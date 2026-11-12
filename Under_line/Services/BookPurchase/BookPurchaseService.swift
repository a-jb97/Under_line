import Foundation

enum BookStore: String, CaseIterable {
    case kyobo, aladin, yes24

    var displayName: String {
        switch self {
        case .kyobo: return "교보문고"
        case .aladin: return "알라딘"
        case .yes24: return "YES24"
        }
    }
}

enum BookPurchaseError: Error, Equatable {
    case invalidISBN
    case resolverNotRegistered(BookStore)
    case resolverStoreMismatch(BookStore)
    case productNotFound(BookStore)
    case invalidProductURL(BookStore)
}

protocol BookPurchaseServiceProtocol {
    func purchaseDestination(isbn13: String, store: BookStore) async throws -> BookPurchaseDestination
}

/// 구현체는 상품 상세 페이지와 검색 결과 페이지를 구분해 반환한다.
/// 서점별 오류는 공통 오류로 변환하되, CancellationError는 그대로 전달한다.
protocol BookStorePurchaseResolver {
    var store: BookStore { get }
    func purchaseDestination(isbn13: String) async throws -> BookPurchaseDestination
}

struct BookPurchaseService: BookPurchaseServiceProtocol {
    private let resolvers: [BookStore: any BookStorePurchaseResolver]

    init(resolvers: [BookStore: any BookStorePurchaseResolver] = [:]) throws {
        for (store, resolver) in resolvers where store != resolver.store {
            throw BookPurchaseError.resolverStoreMismatch(store)
        }
        self.resolvers = resolvers
    }

    func purchaseDestination(isbn13: String, store: BookStore) async throws -> BookPurchaseDestination {
        try Task.checkCancellation()
        let isbn = isbn13.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isbn.utf8.count == 13,
              isbn.utf8.allSatisfy({ (48...57).contains($0) }),
              isbn.hasPrefix("978") || isbn.hasPrefix("979"),
              ISBN13Parser.isValidISBN13(isbn) else {
            throw BookPurchaseError.invalidISBN
        }
        guard let resolver = resolvers[store] else {
            throw BookPurchaseError.resolverNotRegistered(store)
        }
        let destination = try await resolver.purchaseDestination(isbn13: isbn)
        try Task.checkCancellation()
        guard destination.store == store else {
            throw BookPurchaseError.resolverStoreMismatch(store)
        }
        let url = destination.url
        guard url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil else {
            throw BookPurchaseError.invalidProductURL(store)
        }
        return destination
    }
}

struct BookPurchaseDestination: Equatable {
    enum Kind { case productDetail, searchResults }
    let store: BookStore
    let url: URL
    let kind: Kind
}

struct YES24PurchaseResolver: BookStorePurchaseResolver {
    let store = BookStore.yes24

    func purchaseDestination(isbn13: String) async throws -> BookPurchaseDestination {
        var components = URLComponents(string: "https://www.yes24.com/Product/Search")!
        components.queryItems = [URLQueryItem(name: "domain", value: "ALL"),
                                 URLQueryItem(name: "query", value: isbn13)]
        guard let url = components.url else { throw BookPurchaseError.invalidProductURL(store) }
        return BookPurchaseDestination(store: store, url: url, kind: .searchResults)
    }
}
