import Alamofire
import XCTest
@testable import Under_line

@MainActor
final class KakaoBookSearchServiceTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    func test_requestBuilder_setsGeneralSearchQueryAndAuthorizationHeader() throws {
        let request = try KakaoBookSearchRequestBuilder.makeRequest(
            apiKey: " test-key ",
            query: " 어린 왕자 ",
            page: 2
        )
        let components = try XCTUnwrap(
            URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)
        )
        let parameters = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map {
            ($0.name, $0.value)
        })

        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "KakaoAK test-key")
        XCTAssertFalse(try XCTUnwrap(request.url?.absoluteString).contains("test-key"))
        XCTAssertEqual(parameters["query"]!, "어린 왕자")
        XCTAssertEqual(parameters["page"]!, "2")
        XCTAssertEqual(parameters["size"]!, "50")
        XCTAssertEqual(parameters["sort"]!, "accuracy")
        XCTAssertNil(parameters["target"] ?? nil)
    }

    func test_requestBuilder_rejectsInvalidInputs() {
        XCTAssertThrowsError(try KakaoBookSearchRequestBuilder.makeRequest(
            apiKey: "", query: "책", page: 1
        )) { XCTAssertEqual($0 as? KakaoBookSearchError, .missingAPIKey) }
        XCTAssertThrowsError(try KakaoBookSearchRequestBuilder.makeRequest(
            apiKey: "key", query: " \n ", page: 1
        )) { XCTAssertEqual($0 as? KakaoBookSearchError, .emptyQuery) }
        XCTAssertThrowsError(try KakaoBookSearchRequestBuilder.makeRequest(
            apiKey: "key", query: "책", page: 51
        )) { XCTAssertEqual($0 as? KakaoBookSearchError, .invalidPage) }
    }

    func test_responseDecodingAndMapping_usesExpectedISBN13AndBookFields() throws {
        let response = try JSONDecoder().decode(KakaoBookSearchResponse.self, from: responseData)
        let document = try XCTUnwrap(response.documents.first)
        let book = try XCTUnwrap(document.toDomain())

        XCTAssertEqual(response.meta.totalCount, 120)
        XCTAssertEqual(response.meta.pageableCount, 100)
        XCTAssertFalse(response.meta.isEnd)
        XCTAssertEqual(book.title, "어린 왕자 & 여우")
        XCTAssertEqual(book.author, "앙투안 드 생텍쥐페리, 번역자")
        XCTAssertEqual(book.isbn13, "9788937460586")
        XCTAssertEqual(book.coverURL?.absoluteString, "https://example.com/cover.jpg")
        XCTAssertEqual(book.publisher, "테스트 출판사")
        XCTAssertEqual(book.publishDate, "2026-09-17")
        XCTAssertEqual(book.description, "중요한 것은 \"눈\"에 보이지 않아")
        XCTAssertNil(book.category)
        XCTAssertNil(book.bestRank)
        XCTAssertNil(book.itemPage)
        XCTAssertNil(book.currentPage)
    }

    func test_mapping_rejectsMissingOrInvalidISBN13() throws {
        let missing = try decodeDocument(isbn: "8937460588")
        let invalid = try decodeDocument(isbn: "8937460588 9788937460587")

        XCTAssertNil(missing.toDomain())
        XCTAssertNil(invalid.toDomain())
    }

    func test_service_returnsMappedPageUsingPageableCount() async throws {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url), statusCode: 200,
                httpVersion: nil, headerFields: ["Content-Type": "application/json"]
            )!
            return (response, self.responseData)
        }
        let service = makeService()

        let result = try await service.searchBooks(query: "어린 왕자", page: 1)

        XCTAssertEqual(result.books.map(\.isbn13), ["9788937460586"])
        XCTAssertEqual(result.totalResults, 100)
        XCTAssertFalse(result.isEnd)
    }

    func test_service_mapsKakaoHTTPErrorMessage() async throws {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url), statusCode: 401,
                httpVersion: nil, headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(#"{"errorType":"AccessDeniedError","message":"인증 실패"}"#.utf8))
        }

        do {
            _ = try await makeService().searchBooks(query: "책", page: 1)
            XCTFail("HTTP 오류가 호출자에게 전달되어야 합니다.")
        } catch let error as KakaoBookSearchError {
            XCTAssertEqual(error, .api(statusCode: 401, message: "인증 실패"))
            XCTAssertEqual(error.localizedDescription, "인증 실패")
        }
    }

    func test_service_mapsMalformedPayloadToInvalidResponse() async throws {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url), statusCode: 200,
                httpVersion: nil, headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(#"{"unexpected":true}"#.utf8))
        }

        do {
            _ = try await makeService().searchBooks(query: "책", page: 1)
            XCTFail("디코딩 오류가 호출자에게 전달되어야 합니다.")
        } catch let error as KakaoBookSearchError {
            XCTAssertEqual(error, .invalidResponse)
        }
    }

    func test_service_respectsAlreadyCancelledTask() async {
        let task = Task { try await makeService().searchBooks(query: "책", page: 1) }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("취소된 요청은 실행되지 않아야 합니다.")
        } catch is CancellationError { }
        catch { XCTFail("예상하지 못한 오류: \(error)") }
    }

    private var responseData: Data {
        Data(#"""
        {
          "meta": {"total_count": 120, "pageable_count": 100, "is_end": false},
          "documents": [{
            "title": "어린 왕자 &amp; 여우",
            "contents": "중요한 것은 &quot;눈&quot;에 보이지 않아",
            "url": "https://example.com/book",
            "isbn": "8937460588 9788937460586",
            "datetime": "2026-09-17T00:00:00.000+09:00",
            "authors": ["앙투안 드 생텍쥐페리", "번역자"],
            "publisher": "테스트 출판사",
            "translators": [],
            "price": 10000,
            "sale_price": 9000,
            "thumbnail": "https://example.com/cover.jpg",
            "status": "정상판매"
          }]
        }
        """#.utf8)
    }

    private func decodeDocument(isbn: String) throws -> KakaoBookDocument {
        try JSONDecoder().decode(KakaoBookDocument.self, from: Data(#"""
        {
          "title": "책", "contents": "설명", "isbn": "\#(isbn)",
          "datetime": "2026-09-17T00:00:00.000+09:00",
          "authors": ["저자"], "publisher": "출판사", "thumbnail": ""
        }
        """#.utf8))
    }

    private func makeService() -> KakaoBookSearchService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return KakaoBookSearchService(
            apiKey: "test-key",
            session: Session(configuration: configuration)
        )
    }
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: KakaoBookSearchError.invalidResponse)
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() { }
}
