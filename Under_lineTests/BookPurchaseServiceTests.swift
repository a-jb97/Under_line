import XCTest
@testable import Under_line

@MainActor
final class BookPurchaseServiceTests: XCTestCase {
    func test_yes24_returnsISBNSearchDestination() async throws {
        let service = try BookPurchaseService(resolvers: [.yes24: YES24PurchaseResolver()])
        let result = try await service.purchaseDestination(isbn13: "9780132350884", store: .yes24)
        XCTAssertEqual(result.kind, .searchResults)
        XCTAssertEqual(result.store, .yes24)
        let components = URLComponents(url: result.url, resolvingAgainstBaseURL: false)!
        XCTAssertEqual(components.host, "www.yes24.com")
        XCTAssertEqual(components.path, "/Product/Search")
        XCTAssertEqual(components.queryItems, [URLQueryItem(name: "domain", value: "ALL"),
                                               URLQueryItem(name: "query", value: "9780132350884")])
    }

    func test_eachStore_routesNormalizedISBNAndPreservesURL() async throws {
        for store in BookStore.allCases {
            let resolver = StubResolver(store: store)
            let service = try BookPurchaseService(resolvers: [store: resolver])
            let url = try await service.purchaseDestination(isbn13: " 9780132350884\n", store: store)
            XCTAssertEqual(url.url, resolver.url)
            XCTAssertEqual(resolver.inputs, ["9780132350884"])
        }
    }

    func test_invalidISBN_doesNotCallResolver() async throws {
        let resolver = StubResolver(store: .kyobo)
        let service = try BookPurchaseService(resolvers: [.kyobo: resolver])
        for isbn in ["", "9780132350885", "978-0132350884", "0000000000000", "９７８０１３２３５０８８４"] {
            do {
                _ = try await service.purchaseDestination(isbn13: isbn, store: .kyobo)
                XCTFail("Expected invalid ISBN")
            } catch { XCTAssertEqual(error as? BookPurchaseError, .invalidISBN) }
        }
        XCTAssertTrue(resolver.inputs.isEmpty)
    }

    func test_missingResolver_returnsRegistrationError() async throws {
        let service = try BookPurchaseService()
        do {
            _ = try await service.purchaseDestination(isbn13: "9780132350884", store: .yes24)
            XCTFail("Expected missing resolver")
        } catch { XCTAssertEqual(error as? BookPurchaseError, .resolverNotRegistered(.yes24)) }
    }

    func test_mismatchedRegistration_rejectsConfiguration() {
        XCTAssertThrowsError(try BookPurchaseService(resolvers: [.kyobo: StubResolver(store: .aladin)])) {
            XCTAssertEqual($0 as? BookPurchaseError, .resolverStoreMismatch(.kyobo))
        }
    }

    func test_invalidURL_isRejected() async throws {
        let resolver = StubResolver(store: .aladin)
        let service = try BookPurchaseService(resolvers: [.aladin: resolver])
        for raw in ["http://example.com/product", "/product", "https://user:pass@example.com/product"] {
            resolver.url = URL(string: raw)!
            do {
                _ = try await service.purchaseDestination(isbn13: "9780132350884", store: .aladin)
                XCTFail("Expected invalid URL")
            } catch { XCTAssertEqual(error as? BookPurchaseError, .invalidProductURL(.aladin)) }
        }
    }

    func test_failureAndCancellation_arePreservedWithoutFallback() async throws {
        let resolver = StubResolver(store: .kyobo)
        let fallback = StubResolver(store: .yes24)
        let service = try BookPurchaseService(resolvers: [.kyobo: resolver, .yes24: fallback])
        for failure: Error in [BookPurchaseError.productNotFound(.kyobo), CancellationError(), URLError(.timedOut)] {
            resolver.error = failure
            do {
                _ = try await service.purchaseDestination(isbn13: "9780132350884", store: .kyobo)
                XCTFail("Expected failure")
            } catch {
                XCTAssertEqual(String(reflecting: type(of: error)), String(reflecting: type(of: failure)))
            }
        }
        XCTAssertTrue(fallback.inputs.isEmpty)
    }
}

private final class StubResolver: BookStorePurchaseResolver {
    let store: BookStore
    var url = URL(string: "https://example.com/product/123")!
    var inputs: [String] = []
    var error: Error?

    init(store: BookStore) { self.store = store }

    func purchaseDestination(isbn13: String) async throws -> BookPurchaseDestination {
        inputs.append(isbn13)
        if let error { throw error }
        return BookPurchaseDestination(store: store, url: url, kind: .productDetail)
    }
}
