import XCTest
@testable import Data4LibraryValidation
import ValidationCore

final class ValidationTests: XCTestCase {
    func test_isbn13Validator_acceptsKnownValidISBNs() {
        XCTAssertTrue(ISBN13Validator.isValid("9788937460586"))
        XCTAssertTrue(ISBN13Validator.isValid("9791162245651"))
    }

    func test_isbn13Validator_rejectsInvalidInput() {
        XCTAssertFalse(ISBN13Validator.isValid("9788937460587"))
        XCTAssertFalse(ISBN13Validator.isValid("978-89-3746-058-6"))
        XCTAssertFalse(ISBN13Validator.isValid(""))
    }

    func test_jsonTree_unwrapsDocumentArrays() {
        let json: [String: Any] = [
            "response": [
                "docs": [
                    ["doc": ["bookname": "책", "isbn13": "9788937460586"]]
                ]
            ]
        ]
        let documents = JSONTree.documentDictionaries(in: json, preferredKeys: ["docs", "doc"])
        XCTAssertEqual(documents.count, 1)
        XCTAssertEqual(documents.first?["bookname"] as? String, "책")
    }

    func test_jsonTree_findsApplicationErrorInsideHTTP200Envelope() {
        let json: [String: Any] = [
            "response": ["errCode": "authErr", "error": "인증정보가 일치하지 않습니다."]
        ]
        let error = JSONTree.apiError(in: json)
        XCTAssertEqual(error?.code, "authErr")
    }

    func test_jsonTree_redactsAuthenticationValuesRecursively() {
        let json: [String: Any] = [
            "authKey": "secret",
            "response": ["api_key": "nested-secret", "bookname": "책"]
        ]
        let sanitized = JSONTree.removingSensitiveValues(from: json) as? [String: Any]
        XCTAssertEqual(sanitized?["authKey"] as? String, "[REDACTED]")
        let response = sanitized?["response"] as? [String: Any]
        XCTAssertEqual(response?["api_key"] as? String, "[REDACTED]")
        XCTAssertEqual(response?["bookname"] as? String, "책")
    }

    func test_percentile_usesNearestRank() {
        XCTAssertEqual(percentile([10, 20, 30, 40], 0.95), 40)
        XCTAssertEqual(percentile([], 0.95), 0)
    }
}
