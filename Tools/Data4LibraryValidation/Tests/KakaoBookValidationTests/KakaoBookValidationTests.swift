import XCTest
@testable import KakaoBookValidation
import ValidationCore

final class KakaoBookValidationTests: XCTestCase {
    func test_options_acceptsOfflineReportRegenerationPath() throws {
        let options = try KakaoOptions.parse([
            "--report-from-summary", "result/summary.json", "--output", "result"
        ])
        XCTAssertEqual(options.reportSummaryPath, "result/summary.json")
        XCTAssertEqual(options.outputDirectory, "result")
    }

    func test_responseDecoding_mapsOfficialBookFields() throws {
        let data = Data("""
        {
          "meta": {"total_count": 1, "pageable_count": 1, "is_end": true},
          "documents": [{
            "title": "데미안", "contents": "책소개", "url": "https://example.com/book",
            "isbn": "8937460440 9788937460449", "datetime": "2000-12-20T00:00:00.000+09:00",
            "authors": ["헤르만 헤세"], "publisher": "민음사", "translators": ["전영애"],
            "price": 8000, "sale_price": 7200, "thumbnail": "https://example.com/cover.jpg",
            "status": "정상판매"
          }]
        }
        """.utf8)

        let response = try JSONDecoder().decode(KakaoBookResponse.self, from: data)

        XCTAssertEqual(response.meta.totalCount, 1)
        XCTAssertTrue(response.meta.isEnd)
        XCTAssertEqual(response.documents.first?.salePrice, 7200)
        XCTAssertEqual(response.documents.first?.authors, ["헤르만 헤세"])
    }

    func test_isbnParser_extractsISBN13FromSpaceSeparatedField() {
        XCTAssertEqual(KakaoISBN.tokens(in: "8937460440 9788937460449"), ["8937460440", "9788937460449"])
        XCTAssertEqual(KakaoISBN.isbn13s(in: "8937460440 9788937460449"), ["9788937460449"])
        XCTAssertTrue(KakaoISBN.contains("9788937460449", in: "8937460440 9788937460449"))
        XCTAssertFalse(KakaoISBN.contains("9788937460586", in: "8937460440 9788937460449"))
    }

    func test_requestBuilder_putsKeyOnlyInAuthorizationHeader() throws {
        let request = try KakaoRequestBuilder.searchRequest(
            apiKey: "secret-key", query: "데미안", target: "title",
            page: 1, size: 50, timeout: 10
        )
        let components = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)
        let query = Dictionary(uniqueKeysWithValues: try XCTUnwrap(components?.queryItems).map { ($0.name, $0.value) })

        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "KakaoAK secret-key")
        XCTAssertFalse(try XCTUnwrap(request.url?.absoluteString).contains("secret-key"))
        XCTAssertEqual(query["target"]!, "title")
        XCTAssertEqual(query["size"]!, "50")
        XCTAssertEqual(query["sort"]!, "accuracy")
    }

    func test_generalRequest_omitsTarget() throws {
        let request = try KakaoRequestBuilder.searchRequest(
            apiKey: "key", query: "데미안", target: nil,
            page: 1, size: 50, timeout: 10
        )
        let items = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertFalse(items.contains { $0.name == "target" })
    }

    func test_searchObservation_distinguishesTop50AndTop200() {
        let observation = KakaoSearchObservation(
            kind: .title, mode: .general, target: nil, targetRank: 51,
            resultCount: 200, totalCount: 300, pageableCount: 300,
            cumulativeTimingsMilliseconds: [100], firstPageTimingsMilliseconds: [30],
            pageTimingsMilliseconds: [[30, 20, 20, 30]], repetitionMatches: [true],
            otherEditionOnly: false, errors: []
        )
        XCTAssertFalse(observation.successTop50)
        XCTAssertTrue(observation.successTop200)
    }

    func test_publicationDate_extractsISODatePrefix() {
        XCTAssertEqual(kakaoPublicationDate("2000-12-20T00:00:00.000+09:00"), "2000-12-20")
        XCTAssertNil(kakaoPublicationDate("20001220"))
        XCTAssertNil(kakaoPublicationDate(""))
    }

    func test_metadata_requiresExpectedEditionISBNAndExpectedFields() throws {
        let book = try JSONDecoder().decode(ValidationBook.self, from: Data("""
        {
          "id": "book", "titleQuery": "데미안", "expectedTitle": "데미안",
          "authorQuery": "헤르만 헤세", "expectedAuthors": ["헤르만 헤세"],
          "isbn13": "9788937460449", "publisher": "민음사", "publicationDate": "2000-12-20",
          "category": "해외 번역서", "recency": "10년 초과", "tags": [], "selectionSource": "test"
        }
        """.utf8))
        let document = KakaoDocument(
            title: "데미안", contents: "책소개", url: "https://example.com", isbn: "8937460440 9788937460449",
            datetime: "2000-12-20T00:00:00.000+09:00", authors: ["헤르만 헤세"], publisher: "민음사",
            translators: ["전영애"], price: 8_000, salePrice: 7_200,
            thumbnail: "https://example.com/cover.jpg", status: "정상판매"
        )

        let metadata = kakaoMetadata(document: document, book: book)

        XCTAssertTrue(metadata.isbnMatches)
        XCTAssertTrue(metadata.titleMatches)
        XCTAssertTrue(metadata.authorMatches)
        XCTAssertTrue(metadata.publisherMatches)
        XCTAssertTrue(metadata.publicationDateMatches)
        XCTAssertTrue(metadata.descriptionPresent)
    }

    func test_reportWriter_createsAllExpectedArtifactsWithoutCredentials() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kakao-report-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let summary = KakaoValidationSummary(
            generatedAt: Date(timeIntervalSince1970: 0), catalogCount: 0,
            repetitions: 3, pageSize: 50, maximumResults: 200, books: []
        )

        try KakaoReportWriter.write(summary: summary, to: directory)

        for filename in ["summary.json", "books.csv", "report.md", "comparison.md", "comparison.json"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(filename).path))
        }
        let contents = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
        XCTAssertFalse(contents.contains("KakaoAK"))
        XCTAssertFalse(contents.contains("KAKAO_REST_API_KEY="))
    }
}
