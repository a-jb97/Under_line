import Alamofire
import XCTest
@testable import Under_line

@MainActor
final class Data4LibraryServiceTests: XCTestCase {
    override func tearDown() {
        Data4LibraryStubURLProtocol.handler = nil
        super.tearDown()
    }

    func test_popularRequest_usesThirtyDayKoreanDateRangeAndExpectedParameters() async throws {
        Data4LibraryStubURLProtocol.handler = { request in
            let components = try XCTUnwrap(
                URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)
            )
            let parameters = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map {
                ($0.name, $0.value)
            })

            XCTAssertEqual(request.url?.path, "/api/loanItemSrch")
            XCTAssertEqual(parameters["startDt"]!, "2026-10-01")
            XCTAssertEqual(parameters["endDt"]!, "2026-10-30")
            XCTAssertEqual(parameters["pageNo"]!, "1")
            XCTAssertEqual(parameters["pageSize"]!, "50")
            XCTAssertEqual(parameters["format"]!, "json")
            XCTAssertEqual(parameters["authKey"]!, "test-key")
            XCTAssertNil(parameters["gender"] ?? nil)
            XCTAssertNil(parameters["age"] ?? nil)
            return (Self.response(for: request), Self.popularResponse)
        }

        let books = try await makeService().fetchPopularBooks()

        let book = try XCTUnwrap(books.first)
        XCTAssertEqual(book.title, "어린 왕자 & 여우")
        XCTAssertEqual(book.author, "생텍쥐페리")
        XCTAssertEqual(book.isbn13, "9788937460586")
        XCTAssertEqual(book.publisher, "테스트 출판사")
        XCTAssertEqual(book.publishDate, "2026")
        XCTAssertEqual(book.category, "문학")
        XCTAssertEqual(book.bestRank, 1)
        XCTAssertEqual(books.map(\.bestRank), [1, 2], "공동 순위 대신 응답 순서를 표시한다.")
        XCTAssertNil(book.coverURL, "정보나루 표지는 이용 정책상 앱 도메인으로 전달하지 않는다.")
        XCTAssertEqual(book.description, "")
        XCTAssertNil(book.itemPage)
    }

    func test_trendingRequest_retriesEmptyDateThenCombinesNewestFirstAndDeduplicatesISBN() async throws {
        var requestedDates: [String] = []
        Data4LibraryStubURLProtocol.handler = { request in
            let date = try XCTUnwrap(Self.queryValue("searchDt", in: request))
            requestedDates.append(date)
            let data = date == "2026-10-30" ? Self.emptyTrendingResponse : Self.trendingResponse
            return (Self.response(for: request), data)
        }

        let books = try await makeService().fetchTrendingBooks()

        XCTAssertEqual(requestedDates, ["2026-10-30", "2026-10-29"])
        XCTAssertEqual(books.map(\.isbn13), [
            "9788937460586",
            "9791162245651",
            "9788936439996"
        ])
        XCTAssertTrue(books.allSatisfy { $0.bestRank == nil })
        XCTAssertTrue(books.allSatisfy { $0.coverURL == nil })
    }

    func test_trendingResponse_limitsCombinedBooksToFifteen() async throws {
        let documents = (0..<16).map { index in
            Self.documentJSON(isbn13: Self.validISBN(seed: index), sequence: index + 1)
        }.joined(separator: ",")
        let data = Data(#"{"response":{"results":[{"result":{"date":"20261030","docs":[\#(documents)]}}]}}"#.utf8)
        Data4LibraryStubURLProtocol.handler = { request in
            (Self.response(for: request), data)
        }

        let books = try await makeService().fetchTrendingBooks()

        XCTAssertEqual(books.count, 15)
        XCTAssertEqual(books.first?.isbn13, Self.validISBN(seed: 0))
        XCTAssertEqual(books.last?.isbn13, Self.validISBN(seed: 14))
    }

    func test_trendingResponse_returnsEmptyAfterSevenEmptyDates() async throws {
        var requestCount = 0
        Data4LibraryStubURLProtocol.handler = { request in
            requestCount += 1
            return (Self.response(for: request), Self.emptyTrendingResponse)
        }

        let books = try await makeService().fetchTrendingBooks()

        XCTAssertTrue(books.isEmpty)
        XCTAssertEqual(requestCount, 7)
    }

    func test_detailRequest_usesExactISBNAndMapsBookMetadata() async throws {
        Data4LibraryStubURLProtocol.handler = { request in
            let components = try XCTUnwrap(
                URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)
            )
            let parameters = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map {
                ($0.name, $0.value)
            })

            XCTAssertEqual(request.url?.path, "/api/srchDtlList")
            XCTAssertEqual(parameters["isbn13"]!, "9788937460586")
            XCTAssertEqual(parameters["loaninfoYN"]!, "N")
            XCTAssertEqual(parameters["format"]!, "json")
            XCTAssertEqual(parameters["authKey"]!, "test-key")
            return (Self.response(for: request), Self.detailResponse)
        }

        let response = try await makeService().fetchBookDetail(isbn13: " 9788937460586\n")
        let detail = try XCTUnwrap(response)

        XCTAssertEqual(detail.isbn13, "9788937460586")
        XCTAssertEqual(detail.title, "어린 왕자 & 여우")
        XCTAssertEqual(detail.author, "생텍쥐페리")
        XCTAssertEqual(detail.publisher, "테스트 출판사")
        XCTAssertEqual(detail.publishDate, "2026-10-01")
        XCTAssertEqual(detail.coverURL?.absoluteString, "https://example.com/detail-cover.jpg")
        XCTAssertEqual(detail.description, "완전한 \"책소개\" & 설명")
    }

    func test_detailResponse_returnsNilWhenExactISBNIsMissing() async throws {
        Data4LibraryStubURLProtocol.handler = { request in
            (Self.response(for: request), Self.otherEditionDetailResponse)
        }

        let detail = try await makeService().fetchBookDetail(isbn13: "9788937460586")

        XCTAssertNil(detail)
    }

    func test_service_mapsEmbeddedAPIErrorReturnedWithHTTP200() async throws {
        Data4LibraryStubURLProtocol.handler = { request in
            let data = Data(#"{"response":{"error":"인증키가 유효하지 않습니다.","errCode":"E01"}}"#.utf8)
            return (Self.response(for: request), data)
        }

        do {
            _ = try await makeService().fetchPopularBooks()
            XCTFail("HTTP 200 내부 API 오류가 호출자에게 전달되어야 합니다.")
        } catch let error as Data4LibraryError {
            XCTAssertEqual(error, .api(
                statusCode: 200,
                code: "E01",
                message: "인증키가 유효하지 않습니다."
            ))
        }
    }

    func test_service_mapsHTTPErrorStatus() async throws {
        Data4LibraryStubURLProtocol.handler = { request in
            (Self.response(for: request, statusCode: 503), Data())
        }

        do {
            _ = try await makeService().fetchPopularBooks()
            XCTFail("HTTP 오류 상태가 호출자에게 전달되어야 합니다.")
        } catch let error as Data4LibraryError {
            XCTAssertEqual(error, .api(statusCode: 503, code: nil, message: nil))
        }
    }

    func test_trendingDTO_preservesMovementMetrics() throws {
        let decoded = try JSONDecoder().decode(
            Data4LibraryHotTrendResponse.self,
            from: Self.trendingResponse
        )
        let newest = try XCTUnwrap(
            decoded.response.results.first(where: { $0.date == "20261029" })
        )
        let document = try XCTUnwrap(newest.documents.first)

        XCTAssertEqual(document.sequence, 1)
        XCTAssertEqual(document.difference, 10)
        XCTAssertEqual(document.baseWeekRank, 8)
        XCTAssertEqual(document.pastWeekRank, 18)
        XCTAssertNil(document.ranking, "급상승 응답에는 전역 순위를 만들어 넣지 않는다.")
    }

    func test_service_mapsMalformedPayloadToInvalidResponse() async throws {
        Data4LibraryStubURLProtocol.handler = { request in
            (Self.response(for: request), Data(#"{"unexpected":true}"#.utf8))
        }

        do {
            _ = try await makeService().fetchPopularBooks()
            XCTFail("잘못된 응답은 invalidResponse여야 합니다.")
        } catch let error as Data4LibraryError {
            XCTAssertEqual(error, .invalidResponse)
        }
    }

    func test_requestBuilder_rejectsMissingAPIKey() {
        XCTAssertThrowsError(try Data4LibraryRequestBuilder.makePopularRequest(
            apiKey: " \n ",
        startDate: "2026-10-01",
        endDate: "2026-10-30"
        )) {
            XCTAssertEqual($0 as? Data4LibraryError, .missingAPIKey)
        }
        XCTAssertThrowsError(try Data4LibraryRequestBuilder.makeDetailRequest(
            apiKey: "test-key",
            isbn13: "invalid"
        )) {
            XCTAssertEqual($0 as? Data4LibraryError, .invalidISBN)
        }
    }

    func test_service_respectsAlreadyCancelledTask() async {
        let task = Task { try await makeService().fetchPopularBooks() }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("취소된 요청은 실행되지 않아야 합니다.")
        } catch is CancellationError { }
        catch { XCTFail("예상하지 못한 오류: \(error)") }
    }

    private func makeService() -> Data4LibraryService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Data4LibraryStubURLProtocol.self]
        return Data4LibraryService(
            apiKey: "test-key",
            session: Session(configuration: configuration),
            calendar: Self.koreanCalendar,
            now: { Self.fixedNow }
        )
    }

    private static var koreanCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }

    private static var fixedNow: Date {
        koreanCalendar.date(from: DateComponents(
            year: 2026, month: 10, day: 31, hour: 12
        ))!
    }

    private static func response(for request: URLRequest, statusCode: Int = 200) -> HTTPURLResponse {
        HTTPURLResponse(
            url: request.url!, statusCode: statusCode,
            httpVersion: nil, headerFields: ["Content-Type": "application/json"]
        )!
    }

    private static func queryValue(_ name: String, in request: URLRequest) -> String? {
        URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == name })?.value
    }

    private static let popularResponse = Data(#"""
    {
      "response": {
        "resultNum": "2",
        "numFound": 2,
        "docs": [{
          "doc": {
            "no": 1,
            "ranking": "1",
            "bookname": "어린 왕자 &amp; 여우",
            "authors": "생텍쥐페리",
            "publisher": "테스트 출판사",
            "publication_year": 2026,
            "isbn13": "9788937460586",
            "class_nm": "문학",
            "bookImageURL": "https://example.com/data4library-cover.jpg",
            "bookDtlUrl": "https://example.com/detail",
            "loan_count": "100"
          }
        }, {
          "doc": {
            "no": 2,
            "ranking": "1",
            "bookname": "공동 순위 도서",
            "authors": "다른 저자",
            "publisher": "테스트 출판사",
            "publication_year": 2025,
            "isbn13": "9791162245651",
            "loan_count": "100"
          }
        }]
      }
    }
    """#.utf8)

    private static let emptyTrendingResponse = Data(#"{"response":{"results":[]}}"#.utf8)

    private static let detailResponse = Data(#"""
    {
      "response": {
        "detail": [{
          "book": {
            "bookname": "다른 판본",
            "authors": "다른 저자",
            "publisher": "다른 출판사",
            "publication_date": "2025-01-01",
            "isbn13": "9791162245651",
            "description": "다른 설명"
          }
        }, {
          "book": {
            "bookname": "어린 왕자 &amp; 여우",
            "authors": "생텍쥐페리",
            "publisher": "테스트 출판사",
            "publication_date": "2026-10-01",
            "isbn13": "9788937460586",
            "bookImageURL": "https://example.com/detail-cover.jpg",
            "description": "완전한 &quot;책소개&quot; &amp; 설명"
          }
        }]
      }
    }
    """#.utf8)

    private static let otherEditionDetailResponse = Data(#"""
    {"response":{"detail":{"book":{
      "bookname":"다른 판본","authors":"저자","publisher":"출판사",
      "publication_date":"2025-01-01","isbn13":"9791162245651",
      "description":"설명"
    }}}}
    """#.utf8)

    private static let trendingResponse = Data(#"""
    {
      "response": {
        "results": [
          {"result": {"date": "20261027", "docs": [
            {"doc": {"no": 1, "difference": 5, "baseWeekRank": 20, "pastWeekRank": 25,
              "bookname": "오래된 중복", "authors": "저자", "publisher": "출판사",
              "publication_year": "2026", "isbn13": "9788937460586"}},
            {"doc": {"no": 2, "bookname": "세 번째 책", "authors": "저자", "publisher": "출판사",
              "publication_year": "2025", "isbn13": "9788936439996"}}
          ]}},
          {"result": {"date": "20261029", "docs": [
            {"doc": {"no": 1, "difference": 10, "baseWeekRank": 8, "pastWeekRank": 18,
              "bookname": "최신 중복", "authors": "저자", "publisher": "출판사",
              "publication_year": "2026", "isbn13": "9788937460586"}},
            {"doc": {"no": 2, "bookname": "두 번째 책", "authors": "저자", "publisher": "출판사",
              "publication_year": "2026", "isbn13": "9791162245651"}},
            {"doc": {"no": 3, "bookname": "잘못된 ISBN", "authors": "저자", "publisher": "출판사",
              "publication_year": "2026", "isbn13": "9788937460587"}}
          ]}}
        ]
      }
    }
    """#.utf8)

    private static func documentJSON(isbn13: String, sequence: Int) -> String {
        #"{"doc":{"no":\#(sequence),"bookname":"책 \#(sequence)","authors":"저자","publisher":"출판사","publication_year":"2026","isbn13":"\#(isbn13)"}}"#
    }

    private static func validISBN(seed: Int) -> String {
        let prefix = String(format: "97800000%04d", seed)
        let digits = prefix.compactMap(\.wholeNumberValue)
        let sum = digits.enumerated().reduce(0) { partial, pair in
            partial + pair.element * (pair.offset.isMultiple(of: 2) ? 1 : 3)
        }
        return prefix + String((10 - sum % 10) % 10)
    }
}

private final class Data4LibraryStubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: Data4LibraryError.invalidResponse)
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
