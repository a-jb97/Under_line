import Foundation
import ValidationCore

struct KakaoOptions: Sendable {
    var repetitions = 3
    var timeoutSeconds = 10.0
    var delayMilliseconds = 100
    var outputDirectory = ".build/kakao-book-validation-report"
    var catalogPath: String?
    var reportSummaryPath: String?
    var validateCatalogOnly = false
    var preflightOnly = false
    var help = false

    static func parse(_ arguments: [String]) throws -> KakaoOptions {
        var options = KakaoOptions()
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            func nextValue() throws -> String {
                guard index + 1 < arguments.count else {
                    throw KakaoCLIError("\(argument)에 값이 필요합니다.")
                }
                index += 1
                return arguments[index]
            }
            switch argument {
            case "--repetitions":
                guard let value = Int(try nextValue()), value > 0 else {
                    throw KakaoCLIError("--repetitions는 0보다 큰 정수여야 합니다.")
                }
                options.repetitions = value
            case "--timeout":
                guard let value = Double(try nextValue()), value > 0 else {
                    throw KakaoCLIError("--timeout은 0보다 큰 숫자여야 합니다.")
                }
                options.timeoutSeconds = value
            case "--delay-ms":
                guard let value = Int(try nextValue()), value >= 0 else {
                    throw KakaoCLIError("--delay-ms는 0 이상의 정수여야 합니다.")
                }
                options.delayMilliseconds = value
            case "--output":
                options.outputDirectory = try nextValue()
            case "--catalog":
                options.catalogPath = try nextValue()
            case "--report-from-summary":
                options.reportSummaryPath = try nextValue()
            case "--validate-catalog":
                options.validateCatalogOnly = true
            case "--preflight-only":
                options.preflightOnly = true
            case "--help", "-h":
                options.help = true
            default:
                throw KakaoCLIError("알 수 없는 옵션: \(argument)")
            }
            index += 1
        }
        return options
    }
}

struct KakaoCLIError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

private struct ObservedKakaoSearch {
    let observation: KakaoSearchObservation
    let matchedDocument: KakaoDocument?
}

@main
@MainActor
struct KakaoValidationCommand {
    static func main() async {
        do {
            let options = try KakaoOptions.parse(Array(CommandLine.arguments.dropFirst()))
            if options.help {
                print(kakaoUsage)
                return
            }

            if let reportSummaryPath = options.reportSummaryPath {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let summary = try decoder.decode(
                    KakaoValidationSummary.self,
                    from: Data(contentsOf: URL(fileURLWithPath: reportSummaryPath))
                )
                let outputURL = URL(fileURLWithPath: options.outputDirectory, isDirectory: true)
                try KakaoReportWriter.write(summary: summary, to: outputURL)
                print("리포트 재생성 완료: \(outputURL.standardizedFileURL.path)")
                return
            }

            let books = try loadCatalog(path: options.catalogPath)
            try validateCatalog(books)
            if options.validateCatalogOnly {
                print("카탈로그 검증 성공: \(books.count)권, 최근 2년 \(books.filter { $0.recency == "최근 2년" }.count)권")
                return
            }

            guard let apiKey = ProcessInfo.processInfo.environment["KAKAO_REST_API_KEY"]?
                .trimmingCharacters(in: .whitespacesAndNewlines), !apiKey.isEmpty else {
                throw KakaoCLIError("KAKAO_REST_API_KEY 환경변수가 필요합니다. 키는 인자나 파일로 전달하지 마세요.")
            }

            let client = KakaoBookClient(
                apiKey: apiKey,
                timeout: options.timeoutSeconds,
                delayMilliseconds: options.delayMilliseconds
            )
            do {
                try await client.preflight()
            } catch {
                throw KakaoCLIError("인증키 사전 확인 실패: \(error.localizedDescription) 전체 측정을 시작하지 않았습니다.")
            }
            print("인증키 사전 확인 성공")
            if options.preflightOnly { return }

            var observations: [KakaoBookObservation] = []
            for (index, book) in books.enumerated() {
                print("[\(index + 1)/\(books.count)] \(book.expectedTitle)")
                observations.append(await validate(
                    book: book,
                    client: client,
                    repetitions: options.repetitions
                ))
            }

            let summary = KakaoValidationSummary(
                generatedAt: Date(),
                catalogCount: books.count,
                repetitions: options.repetitions,
                pageSize: 50,
                maximumResults: 200,
                books: observations
            )
            let outputURL = URL(fileURLWithPath: options.outputDirectory, isDirectory: true)
            try KakaoReportWriter.write(summary: summary, to: outputURL)
            try client.writeResponseSamples(to: outputURL.appendingPathComponent("response-samples", isDirectory: true))
            print("완료: \(outputURL.standardizedFileURL.path)")
        } catch {
            FileHandle.standardError.write(Data("오류: \(error.localizedDescription)\n".utf8))
            Foundation.exit(EXIT_FAILURE)
        }
    }

    private static func validate(
        book: ValidationBook,
        client: KakaoBookClient,
        repetitions: Int
    ) async -> KakaoBookObservation {
        let generalTitle = await observeSearch(
            client: client, query: book.titleQuery, target: nil,
            kind: .title, mode: .general, book: book, repetitions: repetitions
        )
        let targetedTitle = await observeSearch(
            client: client, query: book.titleQuery, target: "title",
            kind: .title, mode: .targeted, book: book, repetitions: repetitions
        )
        let generalAuthor = await observeSearch(
            client: client, query: book.authorQuery, target: nil,
            kind: .author, mode: .general, book: book, repetitions: repetitions
        )
        let targetedAuthor = await observeSearch(
            client: client, query: book.authorQuery, target: "person",
            kind: .author, mode: .targeted, book: book, repetitions: repetitions
        )
        let generalISBN = await observeSearch(
            client: client, query: book.isbn13, target: nil,
            kind: .isbn, mode: .general, book: book, repetitions: repetitions
        )
        let targetedISBN = await observeSearch(
            client: client, query: book.isbn13, target: "isbn",
            kind: .isbn, mode: .targeted, book: book, repetitions: repetitions
        )

        let representative = targetedISBN.matchedDocument ?? generalISBN.matchedDocument
            ?? targetedTitle.matchedDocument ?? generalTitle.matchedDocument
            ?? targetedAuthor.matchedDocument ?? generalAuthor.matchedDocument
        let cover = await client.inspectCover(urlString: representative?.thumbnail)
        let exactISBNResult = representative.map { KakaoISBN.contains(book.isbn13, in: $0.isbn) } ?? false
        let detailURL = await client.inspectDetailURL(
            urlString: representative?.url,
            exactISBNResult: exactISBNResult
        )

        return KakaoBookObservation(
            book: book,
            generalTitle: generalTitle.observation,
            targetedTitle: targetedTitle.observation,
            generalAuthor: generalAuthor.observation,
            targetedAuthor: targetedAuthor.observation,
            generalISBN: generalISBN.observation,
            targetedISBN: targetedISBN.observation,
            representative: representative,
            metadata: kakaoMetadata(document: representative, book: book),
            cover: cover,
            detailURL: detailURL
        )
    }

    private static func observeSearch(
        client: KakaoBookClient,
        query: String,
        target: String?,
        kind: KakaoSearchKind,
        mode: KakaoSearchMode,
        book: ValidationBook,
        repetitions: Int
    ) async -> ObservedKakaoSearch {
        var cumulativeTimings: [Double] = []
        var firstPageTimings: [Double] = []
        var pageTimings: [[Double]] = []
        var repetitionMatches: [Bool] = []
        var errors: [String] = []
        var bestRank: Int?
        var maximumCount = 0
        var maximumTotal: Int?
        var maximumPageable: Int?
        var matched: KakaoDocument?
        var sawOtherEdition = false

        for _ in 0..<repetitions {
            do {
                let result = try await client.search(
                    query: query,
                    target: target,
                    maximumResults: 200,
                    sampleName: "\(mode.rawValue)-\(kind.rawValue)"
                )
                cumulativeTimings.append(result.cumulativeMilliseconds)
                firstPageTimings.append(result.firstPageMilliseconds)
                pageTimings.append(result.pageTimingsMilliseconds)
                maximumCount = max(maximumCount, result.documents.count)
                maximumTotal = max(maximumTotal ?? result.totalCount, result.totalCount)
                maximumPageable = max(maximumPageable ?? result.pageableCount, result.pageableCount)
                if let index = result.documents.firstIndex(where: {
                    KakaoISBN.contains(book.isbn13, in: $0.isbn)
                }) {
                    repetitionMatches.append(true)
                    let rank = index + 1
                    bestRank = min(bestRank ?? rank, rank)
                    matched = matched ?? result.documents[index]
                } else {
                    repetitionMatches.append(false)
                    let expectedTitle = normalizedBookText(book.expectedTitle)
                    sawOtherEdition = sawOtherEdition || result.documents.contains {
                        let actualTitle = normalizedBookText($0.title)
                        return !actualTitle.isEmpty
                            && (actualTitle.contains(expectedTitle) || expectedTitle.contains(actualTitle))
                    }
                }
            } catch {
                repetitionMatches.append(false)
                errors.append(error.localizedDescription)
            }
        }

        return ObservedKakaoSearch(
            observation: KakaoSearchObservation(
                kind: kind,
                mode: mode,
                target: target,
                targetRank: bestRank,
                resultCount: maximumCount,
                totalCount: maximumTotal,
                pageableCount: maximumPageable,
                cumulativeTimingsMilliseconds: cumulativeTimings,
                firstPageTimingsMilliseconds: firstPageTimings,
                pageTimingsMilliseconds: pageTimings,
                repetitionMatches: repetitionMatches,
                otherEditionOnly: bestRank == nil && sawOtherEdition,
                errors: errors
            ),
            matchedDocument: matched
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

    private static func validateCatalog(_ books: [ValidationBook]) throws {
        guard books.count == 25 else { throw KakaoCLIError("25권이어야 하지만 \(books.count)권입니다.") }
        guard Set(books.map(\.isbn13)).count == books.count else { throw KakaoCLIError("ISBN13이 중복됩니다.") }
        let invalidISBNs = books.map(\.isbn13).filter { !ISBN13Validator.isValid($0) }
        guard invalidISBNs.isEmpty else {
            throw KakaoCLIError("체크섬이 잘못된 ISBN13: \(invalidISBNs.joined(separator: ", "))")
        }
        let recentCount = books.filter { $0.recency == "최근 2년" }.count
        guard recentCount == 15 else { throw KakaoCLIError("최근 2년 표본이 15권이어야 하지만 \(recentCount)권입니다.") }
    }
}

func kakaoMetadata(document: KakaoDocument?, book: ValidationBook) -> KakaoMetadataObservation {
    let actualTitle = normalizedBookText(document?.title)
    let expectedTitle = normalizedBookText(book.expectedTitle)
    let actualAuthors = document?.authors.map(normalizedBookText) ?? []
    let actualPublisher = normalizedBookText(document?.publisher)
    let expectedPublisher = normalizedBookText(book.publisher)
    let publicationDate = document.flatMap { kakaoPublicationDate($0.datetime) }
    return KakaoMetadataObservation(
        isbnPresent: !(document.map { KakaoISBN.isbn13s(in: $0.isbn) } ?? []).isEmpty,
        isbnMatches: document.map { KakaoISBN.contains(book.isbn13, in: $0.isbn) } ?? false,
        titlePresent: !actualTitle.isEmpty,
        titleMatches: !actualTitle.isEmpty && (actualTitle.contains(expectedTitle) || expectedTitle.contains(actualTitle)),
        authorPresent: !actualAuthors.isEmpty,
        authorMatches: book.expectedAuthors.contains { expected in
            let normalizedExpected = normalizedBookText(expected)
            return actualAuthors.contains { actual in
                actual.contains(normalizedExpected) || normalizedExpected.contains(actual)
            }
        },
        publisherPresent: !actualPublisher.isEmpty,
        publisherMatches: !actualPublisher.isEmpty
            && (actualPublisher.contains(expectedPublisher) || expectedPublisher.contains(actualPublisher)),
        publicationDatePresent: publicationDate != nil,
        publicationDateMatches: publicationDate == book.publicationDate,
        descriptionPresent: kakaoHasText(document?.contents),
        translatorsPresent: !(document?.translators.isEmpty ?? true),
        statusPresent: kakaoHasText(document?.status),
        detailURLPresent: kakaoHasText(document?.url)
    )
}

let kakaoUsage = """
사용법:
  KAKAO_REST_API_KEY=... swift run kakao-book-validation [옵션]

옵션:
  --repetitions N    검색별 반복 횟수 (기본 3)
  --timeout SEC      요청 타임아웃 초 (기본 10)
  --delay-ms MS      요청 사이 대기 시간 (기본 100)
  --output PATH      결과 디렉터리 (기본 .build/kakao-book-validation-report)
  --catalog PATH     별도 25권 JSON 목록
  --report-from-summary PATH 기존 summary.json으로 리포트 재생성 (API 호출 없음)
  --validate-catalog 네트워크 없이 25권·최근 2년 15권·ISBN 체크섬 검증
  --preflight-only   인증과 기준 ISBN 검색만 확인하고 종료
  --help             도움말
"""
