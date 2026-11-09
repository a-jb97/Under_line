import Foundation

struct BookSearchPage {
    let books: [Book]
    let totalResults: Int
    let isEnd: Bool
}

protocol BookSearchServiceProtocol {
    func searchBooks(query: String, page: Int) async throws -> BookSearchPage
    func fetchBook(isbn13: String) async throws -> Book?
}
