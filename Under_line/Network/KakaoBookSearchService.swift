import Alamofire
import Foundation

enum KakaoBookSearchError: LocalizedError, Equatable {
    case missingAPIKey
    case emptyQuery
    case invalidPage
    case invalidRequest
    case invalidResponse
    case api(statusCode: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "카카오 API 키가 설정되지 않았습니다."
        case .emptyQuery:
            return "검색어를 입력해주세요."
        case .invalidPage:
            return "요청할 수 없는 검색 페이지입니다."
        case .invalidRequest:
            return "카카오 책 검색 요청을 만들 수 없습니다."
        case .invalidResponse:
            return "카카오 책 검색 응답을 처리할 수 없습니다."
        case .api(_, let message):
            return message ?? "카카오 책 검색 요청에 실패했습니다."
        }
    }
}

enum KakaoBookSearchRequestBuilder {
    static let endpoint = URL(string: "https://dapi.kakao.com/v3/search/book")!
    static let pageSize = 50

    static func makeRequest(apiKey: String, query: String, page: Int) throws -> URLRequest {
        let normalizedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedKey.isEmpty else { throw KakaoBookSearchError.missingAPIKey }
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { throw KakaoBookSearchError.emptyQuery }
        guard (1...50).contains(page) else { throw KakaoBookSearchError.invalidPage }

        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "query", value: normalizedQuery),
            URLQueryItem(name: "size", value: String(pageSize)),
            URLQueryItem(name: "sort", value: "accuracy")
        ]
        guard let url = components?.url else { throw KakaoBookSearchError.invalidRequest }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("KakaoAK \(normalizedKey)", forHTTPHeaderField: "Authorization")
        return request
    }
}

final class KakaoBookSearchService: BookSearchServiceProtocol {
    private let apiKey: String
    private let session: Session
    private let decoder: JSONDecoder

    init(apiKey: String, session: Session = .default, decoder: JSONDecoder = JSONDecoder()) {
        self.apiKey = apiKey
        self.session = session
        self.decoder = decoder
    }

    func searchBooks(query: String, page: Int) async throws -> BookSearchPage {
        try Task.checkCancellation()
        let request = try KakaoBookSearchRequestBuilder.makeRequest(
            apiKey: apiKey,
            query: query,
            page: page
        )

        #if DEBUG
        let responseSpan = BookSearchPerformance.Span(.responseDecoded, source: .search)
        defer { responseSpan.finish(Task.isCancelled ? .cancelled : .failed) }
        #endif

        let response = await session.request(request)
            .validate(statusCode: 200..<300)
            .serializingData()
            .response

        try Task.checkCancellation()
        if let statusCode = response.response?.statusCode, !(200..<300).contains(statusCode) {
            let errorResponse = response.data.flatMap {
                try? decoder.decode(KakaoBookErrorResponse.self, from: $0)
            }
            throw KakaoBookSearchError.api(
                statusCode: statusCode,
                message: errorResponse?.message
            )
        }
        if let error = response.error { throw error }
        guard let data = response.data else { throw KakaoBookSearchError.invalidResponse }

        let decoded: KakaoBookSearchResponse
        do {
            decoded = try decoder.decode(KakaoBookSearchResponse.self, from: data)
        } catch {
            throw KakaoBookSearchError.invalidResponse
        }

        #if DEBUG
        responseSpan.finish(count: decoded.documents.count)
        let mappingSpan = BookSearchPerformance.Span(.domainMapping, source: .search, id: responseSpan.id)
        defer { mappingSpan.finish(count: decoded.documents.count) }
        #endif

        return BookSearchPage(
            books: decoded.documents.compactMap { $0.toDomain() },
            totalResults: decoded.meta.pageableCount,
            isEnd: decoded.meta.isEnd
        )
    }
}
