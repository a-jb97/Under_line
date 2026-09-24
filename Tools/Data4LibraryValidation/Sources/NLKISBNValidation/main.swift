import Foundation
import ValidationCore

struct Options {
    var repetitions = 3
    var delayMilliseconds = 100
    var timeout: TimeInterval = 10
    var outputDirectory = ".build/nlk-isbn-validation-report"
    var catalogPath: String?
    var pageGroundTruthPath: String?
    var preflightOnly = false
    var validateCatalogOnly = false

    init(arguments: [String]) throws {
        var index = 0
        func nextValue() throws -> String {
            index += 1
            guard index < arguments.count else { throw CLIError.missingValue(arguments[index - 1]) }
            return arguments[index]
        }
        while index < arguments.count {
            switch arguments[index] {
            case "--repetitions": repetitions = try positiveInt(nextValue(), name: "--repetitions")
            case "--delay-ms": delayMilliseconds = try nonnegativeInt(nextValue(), name: "--delay-ms")
            case "--timeout": timeout = TimeInterval(try positiveInt(nextValue(), name: "--timeout"))
            case "--output": outputDirectory = try nextValue()
            case "--catalog": catalogPath = try nextValue()
            case "--page-ground-truth": pageGroundTruthPath = try nextValue()
            case "--preflight-only": preflightOnly = true
            case "--validate-catalog": validateCatalogOnly = true
            case "--help", "-h":
                printHelp()
                Foundation.exit(EXIT_SUCCESS)
            default: throw CLIError.unknownArgument(arguments[index])
            }
            index += 1
        }
    }
}

enum CLIError: LocalizedError {
    case missingValue(String)
    case invalidValue(String)
    case unknownArgument(String)
    case missingAPIKey
    case invalidCatalog(String)

    var errorDescription: String? {
        switch self {
        case .missingValue(let value): return "\(value)에 값이 필요합니다."
        case .invalidValue(let value): return "유효하지 않은 옵션 값: \(value)"
        case .unknownArgument(let value): return "알 수 없는 옵션: \(value)"
        case .missingAPIKey: return "NLK_ISBN_API_KEY 환경변수가 없습니다."
        case .invalidCatalog(let value): return "테스트 카탈로그 오류: \(value)"
        }
    }
}

@main
@MainActor
struct NLKISBNValidationMain {
    static func main() async {
        do {
            let options = try Options(arguments: Array(CommandLine.arguments.dropFirst()))
            let books = try loadCatalog(path: options.catalogPath)
            try validateCatalog(books)
            if options.validateCatalogOnly {
                print("카탈로그 검증 성공: \(books.count)권, 최근 2년 \(books.filter { $0.recency == "최근 2년" }.count)권")
                return
            }

            guard let apiKey = ProcessInfo.processInfo.environment["NLK_ISBN_API_KEY"], !apiKey.isEmpty else {
                throw CLIError.missingAPIKey
            }
            let client = NLKISBNClient(
                apiKey: apiKey,
                timeout: options.timeout,
                delayMilliseconds: options.delayMilliseconds
            )
            let acceptedPageSize = try await client.preflight()
            print("인증키 사전 확인 성공, 허용 page_size=\(acceptedPageSize)")
            if options.preflightOnly { return }

            let groundTruth = try loadPageGroundTruth(path: options.pageGroundTruthPath)
            var observations: [NLKBookObservation] = []
            for (index, book) in books.enumerated() {
                print("[\(index + 1)/\(books.count)] \(book.expectedTitle)")
                observations.append(await validate(
                    book: book,
                    client: client,
                    repetitions: options.repetitions,
                    pageSize: acceptedPageSize,
                    pageGroundTruth: groundTruth[book.isbn13]
                ))
            }

            let latest = await validateLatestBooks(
                client: client,
                repetitions: options.repetitions,
                pageSize: min(acceptedPageSize, 50)
            )
            let summary = NLKValidationSummary(
                generatedAt: Date(),
                catalogCount: books.count,
                repetitions: options.repetitions,
                acceptedPageSize: acceptedPageSize,
                books: observations,
                latestBooks: latest
            )
            let outputURL = URL(fileURLWithPath: options.outputDirectory, isDirectory: true)
            try NLKReportWriter.write(summary: summary, to: outputURL)
            try client.writeResponseSamples(to: outputURL.appendingPathComponent("response-samples", isDirectory: true))
            print("완료: \(outputURL.standardizedFileURL.path)")
        } catch {
            FileHandle.standardError.write(Data("오류: \(error.localizedDescription)\n".utf8))
            Foundation.exit(EXIT_FAILURE)
        }
    }

    private static func validate(
        book: ValidationBook,
        client: NLKISBNClient,
        repetitions: Int,
        pageSize: Int,
        pageGroundTruth: PageGroundTruth?
    ) async -> NLKBookObservation {
        let title = await observeSearch(
            client: client,
            parameters: ["title": book.titleQuery, "ebook_yn": "N"],
            book: book,
            repetitions: repetitions,
            pageSize: pageSize
        )
        let author = await observeSearch(
            client: client,
            parameters: ["author": book.authorQuery, "ebook_yn": "N"],
            book: book,
            repetitions: repetitions,
            pageSize: pageSize
        )
        let isbn = await observeSearch(
            client: client,
            parameters: ["isbn": book.isbn13, "ebook_yn": "N"],
            book: book,
            repetitions: repetitions,
            pageSize: pageSize
        )
        let representative = isbn.document ?? title.document ?? author.document
        let cover = await client.inspectCover(urlString: representative?.titleURL)
        let introduction = await client.inspectIntroduction(document: representative)
        let parsedPage = PageCountParser.parse(representative?.page)
        let pageCount = PageCountObservation(
            rawValue: representative?.page,
            parsedValue: parsedPage.value,
            parseStatus: parsedPage.status,
            expectedValue: pageGroundTruth?.expectedPageCount,
            matchesExpected: pageGroundTruth.map { $0.expectedPageCount == parsedPage.value },
            groundTruthSource: pageGroundTruth?.source
        )
        return NLKBookObservation(
            book: book,
            titleSearch: title.observation,
            authorSearch: author.observation,
            isbnSearch: isbn.observation,
            representative: representative,
            metadata: metadata(document: representative, book: book),
            cover: cover,
            introduction: introduction,
            pageCount: pageCount
        )
    }

    private static func observeSearch(
        client: NLKISBNClient,
        parameters: [String: String],
        book: ValidationBook,
        repetitions: Int,
        pageSize: Int
    ) async -> (observation: SearchObservation, document: NLKDocument?) {
        var timings: [Double] = []
        var pageTimings: [[Double]] = []
        var repetitionMatches: [Bool] = []
        var errors: [String] = []
        var bestRank: Int?
        var maximumCount = 0
        var maximumTotal: Int?
        var matched: NLKDocument?
        var sawOtherEdition = false

        for _ in 0..<repetitions {
            do {
                let result = try await client.search(
                    parameters: parameters,
                    maximumResults: 200,
                    pageSize: pageSize,
                    sampleName: "SearchApi"
                )
                timings.append(result.elapsedMilliseconds)
                pageTimings.append(result.pageTimingsMilliseconds)
                maximumCount = max(maximumCount, result.documents.count)
                if let total = result.totalCount { maximumTotal = max(maximumTotal ?? total, total) }
                if let index = result.documents.firstIndex(where: { normalizedISBN13($0.isbn13) == book.isbn13 }) {
                    repetitionMatches.append(true)
                    let rank = index + 1
                    bestRank = min(bestRank ?? rank, rank)
                    matched = matched ?? result.documents[index]
                } else {
                    repetitionMatches.append(false)
                    let expected = normalizedBookText(book.expectedTitle)
                    sawOtherEdition = sawOtherEdition || result.documents.contains {
                        let actual = normalizedBookText($0.title)
                        return !actual.isEmpty && (actual.contains(expected) || expected.contains(actual))
                    }
                }
            } catch {
                repetitionMatches.append(false)
                errors.append(error.localizedDescription)
            }
        }
        return (
            SearchObservation(
                success: bestRank != nil,
                targetRank: bestRank,
                resultCount: maximumCount,
                totalCount: maximumTotal,
                timingsMilliseconds: timings,
                pageTimingsMilliseconds: pageTimings,
                repetitionMatches: repetitionMatches,
                otherEditionOnly: bestRank == nil && sawOtherEdition,
                errors: errors
            ),
            matched
        )
    }

    private static func metadata(document: NLKDocument?, book: ValidationBook) -> MetadataObservation {
        let expectedTitle = normalizedBookText(book.expectedTitle)
        let actualTitle = normalizedBookText(document?.title)
        let actualAuthor = normalizedBookText(document?.author)
        let actualPublisher = normalizedBookText(document?.publisher)
        let expectedPublisher = normalizedBookText(book.publisher)
        let publicationDigits = document?.publishPredate?.filter(\.isNumber)
        let expectedPublicationDigits = book.publicationDate.filter(\.isNumber)
        return MetadataObservation(
            isbnPresent: normalizedISBN13(document?.isbn13) != nil,
            isbnMatches: normalizedISBN13(document?.isbn13) == book.isbn13,
            titlePresent: !actualTitle.isEmpty,
            titleMatches: !actualTitle.isEmpty && (actualTitle.contains(expectedTitle) || expectedTitle.contains(actualTitle)),
            authorPresent: !actualAuthor.isEmpty,
            authorMatches: book.expectedAuthors.contains { actualAuthor.contains(normalizedBookText($0)) },
            publisherPresent: !actualPublisher.isEmpty,
            publisherMatches: !actualPublisher.isEmpty
                && (actualPublisher.contains(expectedPublisher) || expectedPublisher.contains(actualPublisher)),
            publishPredatePresent: !(publicationDigits ?? "").isEmpty,
            publishPredateMatches: publicationDigits == expectedPublicationDigits,
            editionPresent: !(document?.editionStatement?.isEmpty ?? true),
            formPresent: !(document?.form?.isEmpty ?? true),
            inputDatePresent: !(document?.inputDate?.isEmpty ?? true),
            updateDatePresent: !(document?.updateDate?.isEmpty ?? true)
        )
    }

    private static func validateLatestBooks(
        client: NLKISBNClient,
        repetitions: Int,
        pageSize: Int
    ) async -> LatestBooksObservation {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let end = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -29, to: end)!
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyyMMdd"
        let startValue = formatter.string(from: start)
        let endValue = formatter.string(from: end)
        let baseParameters = [
            "start_publish_date": startValue,
            "end_publish_date": endValue,
            "sort": "PUBLISH_PREDATE",
            "order_by": "DESC",
            "ebook_yn": "N"
        ]
        var successfulDocuments: [[NLKDocument]] = []
        var timings: [Double] = []
        var errors: [String] = []
        for _ in 0..<repetitions {
            do {
                let result = try await client.search(parameters: baseParameters, maximumResults: 50, pageSize: pageSize)
                successfulDocuments.append(result.documents)
                timings.append(result.elapsedMilliseconds)
            } catch {
                errors.append(error.localizedDescription)
            }
        }
        let documents = successfulDocuments.first ?? []
        let dateValues = documents.compactMap { $0.publishPredate?.filter(\.isNumber) }.filter { $0.count >= 8 }.map { String($0.prefix(8)) }
        let datesWithinRange = !documents.isEmpty && dateValues.count == documents.count
            && dateValues.allSatisfy { $0 >= startValue && $0 <= endValue }
        let descendingOrder = !dateValues.isEmpty
            && zip(dateValues, dateValues.dropFirst()).allSatisfy { $0 >= $1 }
        let printOnly = !documents.isEmpty && documents.allSatisfy { $0.ebookYN?.uppercased() == "N" }
        let signatures = successfulDocuments.map { $0.map { normalizedISBN13($0.isbn13) ?? normalizedBookText($0.title) } }
        let stable = signatures.count == repetitions && !signatures.isEmpty
            && signatures.dropFirst().allSatisfy { $0 == signatures.first }

        var formFilteredCount: Int?
        do {
            var parameters = baseParameters
            parameters["form"] = "종이책"
            formFilteredCount = try await client.search(parameters: parameters, maximumResults: 50, pageSize: pageSize).documents.count
        } catch { errors.append("form=종이책: \(error.localizedDescription)") }

        var depositedCount: Int?
        do {
            var parameters = baseParameters
            parameters["deposit_yn"] = "Y"
            depositedCount = try await client.search(parameters: parameters, maximumResults: 50, pageSize: pageSize).documents.count
        } catch { errors.append("deposit_yn=Y: \(error.localizedDescription)") }

        return LatestBooksObservation(
            requestedDateRange: "\(startValue)...\(endValue)",
            resultCount: documents.count,
            uniqueISBNCount: Set(documents.compactMap { normalizedISBN13($0.isbn13) }).count,
            datesWithinRange: datesWithinRange,
            descendingOrder: descendingOrder,
            printOnly: printOnly,
            repetitionsStable: stable,
            formFilteredCount: formFilteredCount,
            depositedCount: depositedCount,
            timingsMilliseconds: timings,
            errors: errors
        )
    }

    private static func loadCatalog(path: String?) throws -> [ValidationBook] {
        let url: URL
        if let path {
            url = URL(fileURLWithPath: path)
        } else {
            url = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Data4LibraryValidation/Resources/books.json")
        }
        return try JSONDecoder().decode([ValidationBook].self, from: Data(contentsOf: url))
    }

    private static func loadPageGroundTruth(path: String?) throws -> [String: PageGroundTruth] {
        guard let path else { return [:] }
        let values = try JSONDecoder().decode([PageGroundTruth].self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        return Dictionary(uniqueKeysWithValues: values.map { ($0.isbn13, $0) })
    }

    private static func validateCatalog(_ books: [ValidationBook]) throws {
        guard books.count == 25 else { throw CLIError.invalidCatalog("25권이어야 하지만 \(books.count)권입니다.") }
        guard Set(books.map(\.isbn13)).count == books.count else { throw CLIError.invalidCatalog("ISBN13이 중복됩니다.") }
        let invalid = books.map(\.isbn13).filter { !ISBN13Validator.isValid($0) }
        guard invalid.isEmpty else { throw CLIError.invalidCatalog("체크섬 오류: \(invalid.joined(separator: ", "))") }
        let recentCount = books.filter { $0.recency == "최근 2년" }.count
        guard recentCount == 15 else { throw CLIError.invalidCatalog("최근 2년 표본이 15권이어야 하지만 \(recentCount)권입니다.") }
    }
}

private func positiveInt(_ value: String, name: String) throws -> Int {
    guard let number = Int(value), number > 0 else { throw CLIError.invalidValue("\(name)=\(value)") }
    return number
}

private func nonnegativeInt(_ value: String, name: String) throws -> Int {
    guard let number = Int(value), number >= 0 else { throw CLIError.invalidValue("\(name)=\(value)") }
    return number
}

private func printHelp() {
    print("""
    Usage: swift run nlk-isbn-validation [options]
      --repetitions N          API별 반복 횟수 (기본 3)
      --delay-ms N             요청 사이 지연 ms (기본 100)
      --timeout N              요청 timeout 초 (기본 10)
      --output PATH            결과 디렉터리
      --catalog PATH           25권 JSON 경로
      --page-ground-truth PATH ISBN별 독립 페이지 수 기준 JSON
      --preflight-only         인증·응답·page_size만 확인
      --validate-catalog       API 호출 없이 카탈로그만 확인
    """)
}
