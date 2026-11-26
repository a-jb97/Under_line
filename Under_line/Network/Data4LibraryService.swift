import Alamofire
import Foundation

protocol Data4LibraryServiceProtocol {
    func fetchPopularBooks() async throws -> [Book]
    func fetchTrendingBooks() async throws -> [Book]
    func fetchBookDetail(isbn13: String) async throws -> BookDetailMetadata?
    func fetchCoLoanBooks(isbn13: String) async throws -> [Book]
}

enum Data4LibraryError: LocalizedError, Equatable {
    case timedOut
    case missingAPIKey
    case invalidISBN
    case invalidDate
    case invalidRequest
    case invalidResponse
    case api(statusCode: Int?, code: String?, message: String?)

    var errorDescription: String? {
        switch self {
        case .timedOut:
            return "도서 목록을 불러오는 데 시간이 오래 걸립니다. 다시 시도해주세요."
        case .missingAPIKey:
            return "도서관 정보나루 API 키가 설정되지 않았습니다."
        case .invalidISBN:
            return "올바른 ISBN13이 아닙니다."
        case .invalidDate:
            return "도서 목록 조회 날짜를 계산할 수 없습니다."
        case .invalidRequest:
            return "도서관 정보나루 요청을 만들 수 없습니다."
        case .invalidResponse:
            return "도서관 정보나루 응답을 처리할 수 없습니다."
        case .api(_, _, let message):
            return message ?? "도서관 정보나루 요청에 실패했습니다."
        }
    }
}

enum Data4LibraryRequestBuilder {
    private static let baseURL = URL(string: "https://data4library.kr/api/")!
    static let popularPageSize = 50

    static func makePopularRequest(
        apiKey: String,
        startDate: String,
        endDate: String
    ) throws -> URLRequest {
        try makeRequest(endpoint: "loanItemSrch", apiKey: apiKey, parameters: [
            URLQueryItem(name: "startDt", value: startDate),
            URLQueryItem(name: "endDt", value: endDate),
            URLQueryItem(name: "pageNo", value: "1"),
            URLQueryItem(name: "pageSize", value: String(popularPageSize))
        ])
    }

    static func makeTrendingRequest(apiKey: String, searchDate: String) throws -> URLRequest {
        try makeRequest(endpoint: "hotTrend", apiKey: apiKey, parameters: [
            URLQueryItem(name: "searchDt", value: searchDate)
        ])
    }

    static func makeDetailRequest(apiKey: String, isbn13: String) throws -> URLRequest {
        return try makeRequest(endpoint: "srchDtlList", apiKey: apiKey, parameters: [
            try isbnParameter(isbn13),
            URLQueryItem(name: "loaninfoYN", value: "N")
        ])
    }

    static func makeUsageRequest(apiKey: String, isbn13: String) throws -> URLRequest {
        try makeRequest(endpoint: "usageAnalysisList", apiKey: apiKey, parameters: [isbnParameter(isbn13)])
    }

    private static func isbnParameter(_ isbn13: String) throws -> URLQueryItem {
        let normalizedISBN = isbn13.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ISBN13Parser.isbn13(in: normalizedISBN) == normalizedISBN else {
            throw Data4LibraryError.invalidISBN
        }
        return URLQueryItem(name: "isbn13", value: normalizedISBN)
    }

    private static func makeRequest(
        endpoint: String,
        apiKey: String,
        parameters: [URLQueryItem]
    ) throws -> URLRequest {
        let normalizedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedKey.isEmpty else { throw Data4LibraryError.missingAPIKey }

        var components = URLComponents(
            url: baseURL.appendingPathComponent(endpoint),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = parameters + [
            URLQueryItem(name: "authKey", value: normalizedKey),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = components?.url else { throw Data4LibraryError.invalidRequest }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return request
    }
}

final class Data4LibraryService: Data4LibraryServiceProtocol {
    private enum RequestSource {
        case popular, trending, detail, coLoan
    }

    private let listRequestTimeout: TimeInterval
    private let listTotalTimeout: TimeInterval
    private let apiKey: String
    private let session: Session
    private let decoder: JSONDecoder
    private let calendar: Calendar
    private let now: () -> Date

    init(
        apiKey: String,
        session: Session = .default,
        decoder: JSONDecoder = JSONDecoder(),
        calendar: Calendar = Data4LibraryService.koreanCalendar(),
        now: @escaping () -> Date = Date.init,
        listRequestTimeout: TimeInterval = 10,
        listTotalTimeout: TimeInterval = 15
    ) {
        self.listRequestTimeout = listRequestTimeout
        self.listTotalTimeout = listTotalTimeout
        self.apiKey = apiKey
        self.session = session
        self.decoder = decoder
        self.calendar = calendar
        self.now = now
    }

    func fetchPopularBooks() async throws -> [Book] {
        try Task.checkCancellation()
        let dates = try popularDateRange()
        let request = try Data4LibraryRequestBuilder.makePopularRequest(
            apiKey: apiKey,
            startDate: dates.start,
            endDate: dates.end
        )
        let decoded: Data4LibraryPopularResponse = try await execute(
            request,
            source: .popular,
            deadline: ProcessInfo.processInfo.systemUptime + listTotalTimeout
        )

        #if DEBUG
        let mappingSpan = BookSearchPerformance.Span(.domainMapping, source: .popular)
        defer { mappingSpan.finish(count: decoded.response.documents.count) }
        #endif

        return decoded.response.documents.compactMap {
            $0.toDomain(bestRank: $0.sequence ?? $0.ranking)
        }
    }

    func fetchTrendingBooks() async throws -> [Book] {
        try Task.checkCancellation()

        let deadline = ProcessInfo.processInfo.systemUptime + listTotalTimeout
        let referenceDate = now()
        for daysAgo in 1...7 {
            try Task.checkCancellation()
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw Data4LibraryError.timedOut }
            guard let date = calendar.date(byAdding: .day, value: -daysAgo, to: referenceDate) else {
                throw Data4LibraryError.invalidDate
            }
            let request = try Data4LibraryRequestBuilder.makeTrendingRequest(
                apiKey: apiKey,
                searchDate: format(date)
            )
            #if DEBUG
            let attemptSpan = BookSearchPerformance.Span(.trendingAttempt, source: .trending)
            defer { attemptSpan.finish(Task.isCancelled ? .cancelled : .failed, attempt: daysAgo) }
            #endif
            let decoded: Data4LibraryHotTrendResponse = try await execute(
                request,
                source: .trending,
                deadline: deadline
            )
            #if DEBUG
            attemptSpan.finish(count: decoded.response.results.reduce(0) { $0 + $1.documents.count },
                               attempt: daysAgo, responseDays: decoded.response.results.count)
            #endif
            guard decoded.response.results.contains(where: { !$0.documents.isEmpty }) else {
                continue
            }

            #if DEBUG
            let documentCount = decoded.response.results.reduce(0) { $0 + $1.documents.count }
            let mappingSpan = BookSearchPerformance.Span(.domainMapping, source: .trending)
            defer { mappingSpan.finish(count: documentCount) }
            #endif

            return trendingBooks(from: decoded.response.results)
        }

        return []
    }

    func fetchBookDetail(isbn13: String) async throws -> BookDetailMetadata? {
        try Task.checkCancellation()
        let normalizedISBN = isbn13.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = try Data4LibraryRequestBuilder.makeDetailRequest(
            apiKey: apiKey,
            isbn13: normalizedISBN
        )
        let decoded: Data4LibraryBookDetailResponse = try await execute(
            request,
            source: .detail
        )
        return decoded.response.books
            .compactMap { $0.toMetadata() }
            .first { $0.isbn13 == normalizedISBN }
    }

    func fetchCoLoanBooks(isbn13: String) async throws -> [Book] {
        let request = try Data4LibraryRequestBuilder.makeUsageRequest(apiKey: apiKey, isbn13: isbn13)
        let decoded: Data4LibraryUsageResponse = try await execute(
            request,
            source: .coLoan,
            deadline: ProcessInfo.processInfo.systemUptime + listTotalTimeout
        )
        return decoded.response.coLoanBooks.compactMap { $0.toDomain(bestRank: nil) }
    }

    private func popularDateRange() throws -> (start: String, end: String) {
        guard let end = calendar.date(byAdding: .day, value: -1, to: now()),
              let start = calendar.date(byAdding: .day, value: -29, to: end) else {
            throw Data4LibraryError.invalidDate
        }
        return (format(start), format(end))
    }

    private func trendingBooks(from results: [Data4LibraryTrendResult]) -> [Book] {
        var seenISBNs = Set<String>()
        var books: [Book] = []

        for result in results.sorted(by: { $0.date > $1.date }) {
            for document in result.documents {
                guard let isbn13 = ISBN13Parser.isbn13(in: document.isbn13),
                      seenISBNs.insert(isbn13).inserted,
                      let book = document.toDomain(bestRank: nil) else { continue }
                books.append(book)
                if books.count == 15 { return books }
            }
        }
        return books
    }

    private func execute<Response: Decodable>(
        _ request: URLRequest,
        source: RequestSource,
        deadline: TimeInterval? = nil
    ) async throws -> Response {
        try Task.checkCancellation()

        #if DEBUG
        let performanceSource: BookSearchPerformance.Source = switch source {
        case .popular: .popular
        case .trending: .trending
        case .detail: .data4LibraryDetail
        case .coLoan: .coLoan
        }
        let responseSpan = BookSearchPerformance.Span(
            .responseDecoded,
            source: performanceSource
        )
        defer { responseSpan.finish(Task.isCancelled ? .cancelled : .failed) }
        #endif

        var request = request
        let remaining = deadline.map { $0 - ProcessInfo.processInfo.systemUptime }
        if let remaining, remaining <= 0 { throw Data4LibraryError.timedOut }
        let limit = remaining.map { min(listRequestTimeout, $0) }
        if let limit { request.timeoutInterval = limit }
        let dataRequest = session.request(request).validate(statusCode: 200..<300)
        // A hard cap also covers servers that keep the idle timeout alive by sending bytes.
        var timeoutReached = false
        let timeoutTask = limit.map { limit in
            Task {
                do {
                    try await Task.sleep(for: .seconds(limit))
                    timeoutReached = true
                    dataRequest.cancel()
                } catch { }
            }
        }
        defer { timeoutTask?.cancel() }
        #if DEBUG
        let networkSpan = BookSearchPerformance.Span(.responseReceived, source: performanceSource)
        #endif
        let response = await dataRequest.serializingData().response
        #if DEBUG
        networkSpan.finish(Task.isCancelled ? .cancelled : response.error == nil ? .success : .failed)
        #endif

        try Task.checkCancellation()
        if timeoutReached || (limit != nil && (response.error?.underlyingError as? URLError)?.code == .timedOut) {
            throw Data4LibraryError.timedOut
        }
        let embeddedError = response.data.flatMap(Data4LibraryAPIErrorPayload.find)
        let statusCode = response.response?.statusCode
        if let embeddedError {
            throw Data4LibraryError.api(
                statusCode: statusCode,
                code: embeddedError.code,
                message: embeddedError.message
            )
        }
        if let statusCode, !(200..<300).contains(statusCode) {
            throw Data4LibraryError.api(
                statusCode: statusCode,
                code: nil,
                message: nil
            )
        }
        if let error = response.error { throw error }
        guard let data = response.data else { throw Data4LibraryError.invalidResponse }

        #if DEBUG
        let decodingSpan = BookSearchPerformance.Span(.decoding, source: performanceSource)
        defer { decodingSpan.finish(.failed) }
        #endif
        do {
            let decoded = try decoder.decode(Response.self, from: data)
            #if DEBUG
            decodingSpan.finish()
            responseSpan.finish()
            #endif
            return decoded
        } catch {
            throw Data4LibraryError.invalidResponse
        }
    }

    private func format(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func koreanCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }
}

private enum Data4LibraryAPIErrorPayload {
    static func find(in data: Data) -> (code: String?, message: String?)? {
        guard let value = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return find(in: value)
    }

    private static func find(in value: Any) -> (code: String?, message: String?)? {
        if let dictionary = value as? [String: Any] {
            if dictionary["errCode"] != nil {
                return (
                    string(dictionary["errCode"]),
                    string(dictionary["error"]) ?? string(dictionary["message"])
                )
            }
            for child in dictionary.values {
                if let error = find(in: child) { return error }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let error = find(in: child) { return error }
            }
        }
        return nil
    }

    private static func string(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }
}
