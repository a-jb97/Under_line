import Foundation
import ValidationCore

struct Options: Sendable {
    var repetitions = 3
    var timeoutSeconds = 10.0
    var delayMilliseconds = 100
    var outputDirectory = ".build/validation-report"
    var catalogPath: String?
    var skipLists = false
    var validateCatalogOnly = false
    var preflightOnly = false
    var help = false

    static func parse(_ arguments: [String]) throws -> Options {
        var options = Options()
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            func nextValue() throws -> String {
                guard index + 1 < arguments.count else {
                    throw CLIError("\(argument)에 값이 필요합니다.")
                }
                index += 1
                return arguments[index]
            }
            switch argument {
            case "--repetitions":
                options.repetitions = try positiveInt(nextValue(), name: argument)
            case "--timeout":
                guard let value = Double(try nextValue()), value > 0 else {
                    throw CLIError("--timeout은 0보다 큰 숫자여야 합니다.")
                }
                options.timeoutSeconds = value
            case "--delay-ms":
                guard let value = Int(try nextValue()), value >= 0 else {
                    throw CLIError("--delay-ms는 0 이상의 정수여야 합니다.")
                }
                options.delayMilliseconds = value
            case "--output":
                options.outputDirectory = try nextValue()
            case "--catalog":
                options.catalogPath = try nextValue()
            case "--skip-lists":
                options.skipLists = true
            case "--validate-catalog":
                options.validateCatalogOnly = true
            case "--preflight-only":
                options.preflightOnly = true
            case "--help", "-h":
                options.help = true
            default:
                throw CLIError("알 수 없는 옵션: \(argument)")
            }
            index += 1
        }
        return options
    }

    private static func positiveInt(_ rawValue: String, name: String) throws -> Int {
        guard let value = Int(rawValue), value > 0 else {
            throw CLIError("\(name)은 0보다 큰 정수여야 합니다.")
        }
        return value
    }
}

struct CLIError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

@main
@MainActor
struct ValidationCommand {
    static func main() async {
        do {
            let options = try Options.parse(Array(CommandLine.arguments.dropFirst()))
            if options.help {
                print(usage)
                return
            }
            let books = try loadCatalog(path: options.catalogPath)
            guard books.count == 25 else {
                throw CLIError("기본 검증은 정확히 25권을 요구합니다. 현재 \(books.count)권입니다.")
            }
            let invalidISBNs = books.map(\.isbn13).filter { !ISBN13Validator.isValid($0) }
            guard invalidISBNs.isEmpty else {
                throw CLIError("체크섬이 잘못된 ISBN13: \(invalidISBNs.joined(separator: ", "))")
            }
            if options.validateCatalogOnly {
                print("표본 검증 완료: \(books.count)권, 고유 ISBN13 \(Set(books.map(\.isbn13)).count)개")
                return
            }
            guard let apiKey = ProcessInfo.processInfo.environment["DATA4LIBRARY_API_KEY"]?
                .trimmingCharacters(in: .whitespacesAndNewlines), !apiKey.isEmpty else {
                throw CLIError("DATA4LIBRARY_API_KEY 환경변수가 필요합니다. 키는 인자나 파일로 전달하지 마세요.")
            }

            let client = Data4LibraryClient(
                apiKey: apiKey,
                timeout: options.timeoutSeconds,
                delayMilliseconds: options.delayMilliseconds
            )
            do {
                try await client.preflight()
            } catch {
                throw CLIError("인증키 사전 확인 실패: \(error.localizedDescription) 측정을 시작하지 않았습니다.")
            }
            if options.preflightOnly {
                print("인증키 사전 확인 성공")
                return
            }
            var observations: [BookObservation] = []
            for (index, book) in books.enumerated() {
                print("[\(index + 1)/\(books.count)] \(book.titleQuery)")
                observations.append(try await validate(book: book, client: client, repetitions: options.repetitions))
            }

            let lists = options.skipLists
                ? (popular: Optional<ListObservation>.none, hot: Optional<ListObservation>.none)
                : await validateLists(client: client, repetitions: options.repetitions)
            let summary = ValidationSummary(
                generatedAt: Date(),
                catalogCount: books.count,
                repetitions: options.repetitions,
                books: observations,
                popularBooks: lists.popular,
                hotTrendBooks: lists.hot
            )
            let outputURL = URL(fileURLWithPath: options.outputDirectory, isDirectory: true)
            try write(summary: summary, to: outputURL)
            try client.writeResponseSamples(to: outputURL.appendingPathComponent("response-samples", isDirectory: true))
            print("완료: \(outputURL.standardizedFileURL.path)")
        } catch {
            FileHandle.standardError.write(Data("오류: \(error.localizedDescription)\n".utf8))
            Foundation.exit(EXIT_FAILURE)
        }
    }

    private static func loadCatalog(path: String?) throws -> [ValidationBook] {
        let url: URL
        if let path {
            url = URL(fileURLWithPath: path)
        } else {
            url = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .appendingPathComponent("Resources/books.json")
        }
        return try JSONDecoder().decode([ValidationBook].self, from: Data(contentsOf: url))
    }

    private static func validate(
        book: ValidationBook,
        client: Data4LibraryClient,
        repetitions: Int
    ) async throws -> BookObservation {
        let title = await observeSearch(
            client: client, parameters: ["title": book.titleQuery, "exactMatch": "false"],
            isbn13: book.isbn13, repetitions: repetitions
        )
        let exactTitle = await observeSearch(
            client: client, parameters: ["title": book.titleQuery, "exactMatch": "true"],
            isbn13: book.isbn13, repetitions: repetitions
        )
        let author = await observeSearch(
            client: client, parameters: ["author": book.authorQuery, "exactMatch": "false"],
            isbn13: book.isbn13, repetitions: repetitions
        )
        let isbn = await observeSearch(
            client: client, parameters: ["isbn13": book.isbn13, "exactMatch": "true"],
            isbn13: book.isbn13, repetitions: repetitions
        )

        var detailTimings: [Double] = []
        var detailErrors: [String] = []
        var detailDocument: BookDocument?
        for _ in 0..<repetitions {
            do {
                let result = try await client.detail(isbn13: book.isbn13)
                detailTimings.append(result.elapsedMilliseconds)
                if detailDocument == nil {
                    detailDocument = result.documents.first { normalizedISBN($0.isbn13) == book.isbn13 }
                        ?? result.documents.first
                }
            } catch {
                detailErrors.append(error.localizedDescription)
            }
        }

        let representative = detailDocument ?? isbn.document ?? title.document
        let cover = await client.inspectCover(urlString: representative?.coverURL)
        let returnedISBN = normalizedISBN(representative?.isbn13)

        return BookObservation(
            book: book,
            titleSearch: title.observation,
            exactTitleSearch: exactTitle.observation,
            authorSearch: author.observation,
            isbnSearch: isbn.observation,
            detailTimingsMilliseconds: detailTimings,
            detailErrors: detailErrors,
            returnedISBN13: returnedISBN,
            isbnChecksumValid: returnedISBN.map(ISBN13Validator.isValid) ?? false,
            titlePresent: hasText(representative?.title),
            authorPresent: hasText(representative?.authors),
            publisherPresent: hasText(representative?.publisher),
            publicationDatePresent: hasText(representative?.publicationDate),
            descriptionPresent: hasText(representative?.description),
            cover: cover
        )
    }

    private static func observeSearch(
        client: Data4LibraryClient,
        parameters: [String: String],
        isbn13: String,
        repetitions: Int
    ) async -> (observation: EndpointObservation, document: BookDocument?) {
        var timings: [Double] = []
        var errors: [String] = []
        var bestRank: Int?
        var maximumCount = 0
        var matchedDocument: BookDocument?

        for _ in 0..<repetitions {
            do {
                let result = try await client.search(parameters: parameters)
                timings.append(result.elapsedMilliseconds)
                maximumCount = max(maximumCount, result.documents.count)
                if let index = result.documents.firstIndex(where: { normalizedISBN($0.isbn13) == isbn13 }) {
                    let rank = index + 1
                    bestRank = min(bestRank ?? rank, rank)
                    matchedDocument = matchedDocument ?? result.documents[index]
                }
            } catch {
                errors.append(error.localizedDescription)
            }
        }
        return (
            EndpointObservation(
                success: bestRank != nil,
                targetRank: bestRank,
                resultCount: maximumCount,
                timingsMilliseconds: timings,
                errors: errors
            ),
            matchedDocument
        )
    }

    private static func validateLists(
        client: Data4LibraryClient,
        repetitions: Int
    ) async -> (popular: ListObservation?, hot: ListObservation?) {
        let calendar = koreaCalendar
        let today = calendar.startOfDay(for: Date())
        let endDate = calendar.date(byAdding: .day, value: -1, to: today)!
        let startDate = calendar.date(byAdding: .day, value: -29, to: endDate)!
        let formatter = dayFormatter
        let start = formatter.string(from: startDate)
        let end = formatter.string(from: endDate)

        var popularResults: [TimedDocuments] = []
        var popularErrors: [String] = []
        for _ in 0..<repetitions {
            do { popularResults.append(try await client.popular(startDate: start, endDate: end)) }
            catch { popularErrors.append(error.localizedDescription) }
        }
        let popularDocuments = popularResults.first?.documents ?? []
        let popular = ListObservation(
            endpoint: "loanItemSrch",
            requestedDateRange: "\(start)...\(end)",
            resultCount: popularDocuments.count,
            uniqueISBNCount: Set(popularDocuments.compactMap { normalizedISBN($0.isbn13) }).count,
            rankingCount: popularDocuments.filter { $0.ranking != nil }.count,
            coverURLCount: popularDocuments.filter { hasText($0.coverURL) }.count,
            timingsMilliseconds: popularResults.map(\.elapsedMilliseconds),
            errors: popularErrors,
            metadata: ["pageSize": "50", "scope": "전국·전체 성별·전체 연령"]
        )

        var resolvedHotDate: String?
        var hotDocuments: [BookDocument] = []
        var hotTimings: [Double] = []
        var hotErrors: [String] = []
        for offset in 1...7 where hotDocuments.isEmpty {
            let candidate = calendar.date(byAdding: .day, value: -offset, to: today)!
            let candidateString = formatter.string(from: candidate)
            do {
                let first = try await client.hotTrend(searchDate: candidateString)
                if !first.documents.isEmpty {
                    resolvedHotDate = candidateString
                    hotDocuments = first.documents
                    hotTimings.append(first.elapsedMilliseconds)
                    if repetitions > 1 {
                        for _ in 1..<repetitions {
                            do { hotTimings.append(try await client.hotTrend(searchDate: candidateString).elapsedMilliseconds) }
                            catch { hotErrors.append(error.localizedDescription) }
                        }
                    }
                }
            } catch {
                hotErrors.append("\(candidateString): \(error.localizedDescription)")
            }
        }
        let hot = ListObservation(
            endpoint: "hotTrend",
            requestedDateRange: resolvedHotDate ?? "전일~7일 전 탐색 실패",
            resultCount: hotDocuments.count,
            uniqueISBNCount: Set(hotDocuments.compactMap { normalizedISBN($0.isbn13) }).count,
            rankingCount: hotDocuments.filter { $0.difference != nil || $0.baseWeekRank != nil || $0.pastWeekRank != nil }.count,
            coverURLCount: hotDocuments.filter { hasText($0.coverURL) }.count,
            timingsMilliseconds: hotTimings,
            errors: hotErrors,
            metadata: ["documentedMaximum": "최근 3일 × 일자별 최대 5권"]
        )
        return (popular, hot)
    }

    private static func write(summary: ValidationSummary, to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(summary).write(to: directory.appendingPathComponent("summary.json"), options: .atomic)
        try Data(csv(summary).utf8).write(to: directory.appendingPathComponent("results.csv"), options: .atomic)
        try Data(markdown(summary).utf8).write(to: directory.appendingPathComponent("report.md"), options: .atomic)
    }

    private static func csv(_ summary: ValidationSummary) -> String {
        let header = [
            "id", "title_query", "isbn13", "category", "recency", "title_found", "title_rank",
            "exact_title_found", "author_found", "author_rank", "isbn_found", "returned_isbn13",
            "isbn_checksum_valid", "cover_url", "cover_loaded", "cover_width", "cover_height",
            "cover_quality", "description", "author", "publisher", "publication_date",
            "search_average_ms", "detail_average_ms", "errors"
        ]
        let rows = summary.books.map { observation -> [String] in
            let searchTimings = observation.titleSearch.timingsMilliseconds
                + observation.authorSearch.timingsMilliseconds + observation.isbnSearch.timingsMilliseconds
            let errors = observation.titleSearch.errors + observation.exactTitleSearch.errors
                + observation.authorSearch.errors + observation.isbnSearch.errors + observation.detailErrors
            return [
                observation.book.id, observation.book.titleQuery, observation.book.isbn13,
                observation.book.category, observation.book.recency,
                flag(observation.titleSearch.success), observation.titleSearch.targetRank.map(String.init) ?? "",
                flag(observation.exactTitleSearch.success), flag(observation.authorSearch.success),
                observation.authorSearch.targetRank.map(String.init) ?? "", flag(observation.isbnSearch.success),
                observation.returnedISBN13 ?? "", flag(observation.isbnChecksumValid),
                flag(observation.cover.urlPresent), flag(observation.cover.loaded),
                observation.cover.pixelWidth.map(String.init) ?? "", observation.cover.pixelHeight.map(String.init) ?? "",
                flag(observation.cover.meetsResolution), flag(observation.descriptionPresent),
                flag(observation.authorPresent), flag(observation.publisherPresent),
                flag(observation.publicationDatePresent), format(average(searchTimings)),
                format(average(observation.detailTimingsMilliseconds)), errors.joined(separator: " | ")
            ]
        }
        return ([header] + rows).map { $0.map(csvEscape).joined(separator: ",") }.joined(separator: "\n") + "\n"
    }

    private static func markdown(_ summary: ValidationSummary) -> String {
        let books = summary.books
        let title = rate(books.filter { $0.titleSearch.success }.count, books.count)
        let author = rate(books.filter { $0.authorSearch.success }.count, books.count)
        let isbn = rate(books.filter { $0.isbnSearch.success && $0.isbnChecksumValid }.count, books.count)
        let coversPresent = books.filter { $0.cover.urlPresent }.count
        let coversLoaded = books.filter { $0.cover.loaded }.count
        let coverProvidedRate = rate(coversPresent, books.count)
        let coverLoadRate = rate(coversLoaded, coversPresent)
        let coverQualityRate = rate(books.filter { $0.cover.meetsResolution }.count, coversLoaded)
        let description = rate(books.filter { $0.descriptionPresent }.count, books.count)
        let authorField = rate(books.filter { $0.authorPresent }.count, books.count)
        let publisher = rate(books.filter { $0.publisherPresent }.count, books.count)
        let publicationDate = rate(books.filter { $0.publicationDatePresent }.count, books.count)
        let searchTimings = books.flatMap {
            $0.titleSearch.timingsMilliseconds + $0.authorSearch.timingsMilliseconds + $0.isbnSearch.timingsMilliseconds
        }
        let searchAverage = average(searchTimings)
        let searchP95 = percentile(searchTimings, 0.95)
        let allErrorCount = books.reduce(0) {
            $0 + $1.titleSearch.errors.count + $1.exactTitleSearch.errors.count
                + $1.authorSearch.errors.count + $1.isbnSearch.errors.count + $1.detailErrors.count
        }
        let totalAPITrials = books.count * summary.repetitions * 5
        let errorRate = totalAPITrials == 0 ? 0 : Double(allErrorCount) / Double(totalAPITrials) * 100
        let contentHashes = Dictionary(grouping: books.compactMap { $0.cover.contentHash }, by: { $0 })
        let placeholderCandidates = contentHashes.values.filter { $0.count >= 3 }.reduce(0) { $0 + $1.count }

        let corePass = title.percentage >= 96 && author.percentage >= 96 && isbn.percentage == 100
            && coverProvidedRate.percentage >= 92 && coverLoadRate.percentage >= 95
            && coverQualityRate.percentage >= 90 && description.percentage >= 80
            && authorField.percentage >= 96 && publisher.percentage >= 96 && publicationDate.percentage >= 96
            && searchAverage <= 1_500 && searchP95 <= 3_000 && errorRate < 1
        let decision = corePass
            ? "메인 소스로 조건부 채택 — itemPage 대체 정책과 상세 지연 조회가 필요함"
            : "교체 부적합 — 아래 미달 지표와 개별 실패 사례를 우선 검토해야 함"

        return """
        # 도서관 정보나루 검증 결과

        - 생성 시각: \(ISO8601DateFormatter().string(from: summary.generatedAt))
        - 표본: \(summary.catalogCount)권, API별 \(summary.repetitions)회 반복
        - 판정: **\(decision)**

        ## 핵심 지표

        | 지표 | 결과 | 균형 합격선 |
        |---|---:|---:|
        | 제목 검색 성공률 | \(format(title.percentage))% (\(title.successes)/\(title.total)) | 96% |
        | 저자 검색 성공률 | \(format(author.percentage))% (\(author.successes)/\(author.total)) | 96% |
        | ISBN13 검색·체크섬 | \(format(isbn.percentage))% | 100% |
        | 표지 URL 제공률 | \(format(coverProvidedRate.percentage))% | 92% |
        | 제공 URL 로딩 성공률 | \(format(coverLoadRate.percentage))% | 95% |
        | 로딩 표지 해상도 충족률 | \(format(coverQualityRate.percentage))% | 90% |
        | 책소개 제공률 | \(format(description.percentage))% | 80% |
        | 저자 제공률 | \(format(authorField.percentage))% | 96% |
        | 출판사 제공률 | \(format(publisher.percentage))% | 96% |
        | 정확한 출판일 제공률 | \(format(publicationDate.percentage))% | 96% |
        | 검색 평균 응답시간 | \(format(searchAverage))ms | 1,500ms 이하 |
        | 검색 P95 응답시간 | \(format(searchP95))ms | 3,000ms 이하 |
        | API 오류율 | \(format(errorRate))% | 1% 미만 |

        - 검색 응답시간 최소/최대: \(format(searchTimings.min() ?? 0))ms / \(format(searchTimings.max() ?? 0))ms
        - 동일 이미지 해시 3건 이상 후보: \(placeholderCandidates)건

        ## 목록 API

        \(listMarkdown(summary.popularBooks))

        \(listMarkdown(summary.hotTrendBooks))

        ## 해석 시 주의사항

        - 검색 목록에는 책소개와 정확한 출판일이 없어 ISBN 상세 조회 결과로 평가했습니다.
        - 공식 필드에 전체 페이지 수(itemPage)가 없으므로 현재 페이지 상한 검증은 별도 정책이 필요합니다.
        - 상세 행은 `results.csv`, 원본 구조를 보존한 전체 결과는 `summary.json`에서 확인합니다.
        """
    }

    private static func listMarkdown(_ observation: ListObservation?) -> String {
        guard let observation else { return "- 실행 생략" }
        return "- `\(observation.endpoint)`: \(observation.resultCount)건, ISBN 고유 \(observation.uniqueISBNCount)건, 순위/지표 \(observation.rankingCount)건, 표지 URL \(observation.coverURLCount)건, 오류 \(observation.errors.count)건, 평균 \(format(average(observation.timingsMilliseconds)))ms (\(observation.requestedDateRange))"
    }
}

func normalizedISBN(_ value: String?) -> String? {
    guard let value else { return nil }
    let normalized = value.filter(\.isNumber)
    return normalized.isEmpty ? nil : normalized
}

func hasText(_ value: String?) -> Bool {
    !(value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
}

func average(_ values: [Double]) -> Double {
    values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
}

func percentile(_ values: [Double], _ quantile: Double) -> Double {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    let index = Int(ceil(Double(sorted.count) * quantile)) - 1
    return sorted[max(0, min(index, sorted.count - 1))]
}

func rate(_ successes: Int, _ total: Int) -> RateSummary {
    RateSummary(successes: successes, total: total)
}

func format(_ value: Double) -> String { String(format: "%.2f", value) }
func flag(_ value: Bool) -> String { value ? "Y" : "N" }

func csvEscape(_ value: String) -> String {
    if value.contains(",") || value.contains("\"") || value.contains("\n") {
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
    return value
}

var koreaCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
    return calendar
}

var dayFormatter: DateFormatter {
    let formatter = DateFormatter()
    formatter.calendar = koreaCalendar
    formatter.timeZone = koreaCalendar.timeZone
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
}

let usage = """
사용법:
  DATA4LIBRARY_API_KEY=... swift run data4library-validation [옵션]

옵션:
  --repetitions N   API별 반복 횟수 (기본 3)
  --timeout SEC     요청 타임아웃 초 (기본 10)
  --delay-ms MS     요청 사이 대기 시간 (기본 100)
  --output PATH     결과 디렉터리 (기본 .build/validation-report)
  --catalog PATH    별도 25권 JSON 목록
  --validate-catalog 네트워크 호출 없이 표본 개수·ISBN 체크섬 검증
  --preflight-only  인증 요청 한 번만 확인하고 종료
  --skip-lists      인기대출·급상승 검증 생략
  --help            도움말
"""
