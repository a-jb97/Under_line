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
    func productURL(isbn13: String, store: BookStore) async throws -> URL
}

/// 구현체는 검색 결과 페이지가 아닌 상품 상세 페이지 URL을 반환한다.
/// 서점별 오류는 공통 오류로 변환하되, CancellationError는 그대로 전달한다.
protocol BookStoreURLResolver {
    var store: BookStore { get }
    func productURL(isbn13: String) async throws -> URL
}

struct BookPurchaseService: BookPurchaseServiceProtocol {
    private let resolvers: [BookStore: any BookStoreURLResolver]

    init(resolvers: [BookStore: any BookStoreURLResolver] = [:]) throws {
        for (store, resolver) in resolvers where store != resolver.store {
            throw BookPurchaseError.resolverStoreMismatch(store)
        }
        self.resolvers = resolvers
    }

    func productURL(isbn13: String, store: BookStore) async throws -> URL {
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
        let url = try await resolver.productURL(isbn13: isbn)
        try Task.checkCancellation()
        guard url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil else {
            throw BookPurchaseError.invalidProductURL(store)
        }
        return url
    }
}
