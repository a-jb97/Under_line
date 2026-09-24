import XCTest
@testable import NLKISBNValidation
import ValidationCore

final class NLKISBNValidationTests: XCTestCase {
    func test_jsonDocuments_extractsUppercaseISBNRecords() throws {
        let json: [String: Any] = [
            "TOTAL_COUNT": "1",
            "docs": [
                ["TITLE": "데미안", "EA_ISBN": "9788937460449", "PUBLISHER": "민음사"]
            ]
        ]
        let documents = NLKJSON.documents(in: json).map(NLKDocument.init)
        XCTAssertEqual(documents.count, 1)
        XCTAssertEqual(documents.first?.isbn13, "9788937460449")
        XCTAssertEqual(NLKJSON.integer(for: "TOTAL_COUNT", in: json), 1)
    }

    func test_jsonApplicationError_detectsDocumentedError() {
        let json: [String: Any] = ["ERROR_CODE": "013", "ERROR_MESSAGE": "쪽당 출력건수 제한"]
        let error = NLKJSON.applicationError(in: json)
        XCTAssertEqual(error?.code, "013")
    }

    func test_jsonApplicationError_treatsDocumentedSystemError000AsFailure() {
        let json: [String: Any] = ["ERROR_CODE": "000", "ERROR_MESSAGE": "시스템 오류"]
        let error = NLKJSON.applicationError(in: json)
        XCTAssertEqual(error?.code, "000")
    }

    func test_jsonRedaction_removesCertKeyRecursively() {
        let json: [String: Any] = ["cert_key": "secret", "nested": ["CERT_KEY": "secret"]]
        let redacted = NLKJSON.removingSensitiveValues(from: json) as? [String: Any]
        XCTAssertEqual(redacted?["cert_key"] as? String, "[REDACTED]")
        let nested = redacted?["nested"] as? [String: Any]
        XCTAssertEqual(nested?["CERT_KEY"] as? String, "[REDACTED]")
    }

    func test_pageCountParser_parsesCommonSingleNumberForms() {
        XCTAssertEqual(PageCountParser.parse("345").value, 345)
        XCTAssertEqual(PageCountParser.parse("345 p.").value, 345)
        XCTAssertEqual(PageCountParser.parse("345쪽").value, 345)
        XCTAssertEqual(PageCountParser.parse("1,024 p.").value, 1024)
    }

    func test_pageCountParser_rejectsAmbiguousAndMissingValues() {
        XCTAssertEqual(PageCountParser.parse("1권 320쪽, 2권 280쪽").status, "ambiguous")
        XCTAssertEqual(PageCountParser.parse("쪽수 미정").status, "unparseable")
        XCTAssertEqual(PageCountParser.parse(nil).status, "missing")
    }

    func test_sharedPercentile_usesNearestRank() {
        XCTAssertEqual(validationPercentile([10, 20, 30, 40], 0.95), 40)
        XCTAssertEqual(validationMedian([10, 20, 30, 40]), 25)
    }
}
