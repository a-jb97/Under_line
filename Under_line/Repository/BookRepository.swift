//
//  BookRepository.swift
//  Under_line
//
//  Repository 프로토콜 및 구현체 — ViewModel은 프로토콜에만 의존
//

import Foundation
import SwiftData
import RxSwift
import RxCocoa

// MARK: - Protocol

protocol BookRepositoryProtocol {
    // Remote
    func fetchPopularBooks() async throws -> [Book]
    func fetchTrendingBooks() async throws -> [Book]
    func searchBooks(query: String, page: Int) async throws -> BookSearchPage
    func fetchListBookMetadata(isbn13: String) async throws -> BookListMetadata?
    func fetchBookSupplement(isbn13: String) async throws -> BookDetailMetadata?

    // Local (BehaviorRelay 스트림 — Observable 유지)
    func fetchSavedBooks() -> Observable<[Book]>
    func registerSearchedBook(_ book: Book) async throws
    func saveBook(_ book: Book) async throws
    func deleteBook(_ book: Book) async throws
    func deleteAllBooks() async throws
    func updateReadingProgress(isbn13: String, itemPage: Int, currentPage: Int) async throws
    func reorderBooks(orderedISBNs: [String]) async throws
}

// MARK: - Concrete Implementation

final class BookRepository: BookRepositoryProtocol {

    private let bookSearchService: BookSearchServiceProtocol
    private let data4LibraryService: Data4LibraryServiceProtocol
    private let modelContext: ModelContext
    private let searchCache: BookSearchCache
    private let metadataCache: BookSearchCache
    private var metadataRequests: [String: Task<Book?, Error>] = [:]
    private var supplementCache: [String: BookDetailMetadata] = [:]
    private var supplementRequests: [String: Task<BookDetailMetadata?, Error>] = [:]
    private let savedBooksRelay = BehaviorRelay<[Book]>(value: [])

    init(
        bookSearchService: BookSearchServiceProtocol,
        data4LibraryService: Data4LibraryServiceProtocol,
        modelContext: ModelContext,
        searchCache: BookSearchCache? = nil,
        metadataCache: BookSearchCache? = nil
    ) {
        self.bookSearchService = bookSearchService
        self.data4LibraryService = data4LibraryService
        self.modelContext = modelContext
        self.searchCache = searchCache ?? BookSearchCache()
        self.metadataCache = metadataCache ?? BookSearchCache(lifetime: 30 * 60, capacity: 100)
        refreshRelay()
    }

    // MARK: Remote

    func fetchPopularBooks() async throws -> [Book] {
        try Task.checkCancellation()
        if let cached = searchCache.result(for: .popular) { return cached.books }
        let books = try await data4LibraryService.fetchPopularBooks()
        try Task.checkCancellation()
        searchCache.insert(
            BookSearchPage(books: books, totalResults: books.count, isEnd: true),
            for: .popular
        )
        return books
    }

    func fetchTrendingBooks() async throws -> [Book] {
        try Task.checkCancellation()
        if let cached = searchCache.result(for: .trending) { return cached.books }
        let books = try await data4LibraryService.fetchTrendingBooks()
        try Task.checkCancellation()
        searchCache.insert(
            BookSearchPage(books: books, totalResults: books.count, isEnd: true),
            for: .trending
        )
        return books
    }

    func searchBooks(query: String, page: Int) async throws -> BookSearchPage {
        try Task.checkCancellation()
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = BookSearchCache.Key.search(query: normalizedQuery, page: page)
        if let cached = searchCache.result(for: key) { return cached }
        let result = try await bookSearchService.searchBooks(query: normalizedQuery, page: page)
        try Task.checkCancellation()
        searchCache.insert(result, for: key)
        return result
    }

    func fetchListBookMetadata(isbn13: String) async throws -> BookListMetadata? {
        try Task.checkCancellation()
        let cacheKey = BookSearchCache.Key.metadata(isbn13: isbn13)
        if let cached = metadataCache.result(for: cacheKey) {
            return cached.books.first.map(BookListMetadata.init(book:))
        }

        let request: Task<Book?, Error>
        if let ongoing = metadataRequests[isbn13] {
            request = ongoing
        } else {
            request = Task { [bookSearchService] in
                try await bookSearchService.fetchBook(isbn13: isbn13)
            }
            metadataRequests[isbn13] = request
        }

        do {
            let book = try await request.value
            metadataCache.insert(
                BookSearchPage(
                    books: book.map { [$0] } ?? [],
                    totalResults: book == nil ? 0 : 1,
                    isEnd: true
                ),
                for: cacheKey
            )
            metadataRequests.removeValue(forKey: isbn13)
            try Task.checkCancellation()
            return book.map(BookListMetadata.init(book:))
        } catch {
            metadataRequests.removeValue(forKey: isbn13)
            throw error
        }
    }

    func fetchBookSupplement(isbn13: String) async throws -> BookDetailMetadata? {
        try Task.checkCancellation()
        if let cached = supplementCache[isbn13] { return cached }

        let request: Task<BookDetailMetadata?, Error>
        if let ongoing = supplementRequests[isbn13] {
            request = ongoing
        } else {
            request = Task { [data4LibraryService] in
                try await data4LibraryService.fetchBookDetail(isbn13: isbn13)
            }
            supplementRequests[isbn13] = request
        }

        do {
            let metadata = try await request.value
            supplementRequests.removeValue(forKey: isbn13)
            if let metadata { supplementCache[isbn13] = metadata }
            try Task.checkCancellation()
            return metadata
        } catch {
            supplementRequests.removeValue(forKey: isbn13)
            throw error
        }
    }

    // MARK: Local

    func fetchSavedBooks() -> Observable<[Book]> {
        savedBooksRelay.asObservable()
    }

    func registerSearchedBook(_ book: Book) async throws {
        try ensureBookIsNotSaved(isbn13: book.isbn13)

        let detail: BookDetailMetadata?
        do {
            detail = try await fetchBookSupplement(isbn13: book.isbn13)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            detail = nil
        }

        try Task.checkCancellation()
        try await saveBook(detail.map { book.mergingDetailMetadata(from: $0) } ?? book)
    }

    func saveBook(_ book: Book) async throws {
        try ensureBookIsNotSaved(isbn13: book.isbn13)
        let allRecords = try modelContext.fetch(FetchDescriptor<BookRecord>())
        let maxOrder = allRecords.map { $0.sortOrder }.max() ?? -1
        let record = BookRecord(from: book)
        record.sortOrder = maxOrder + 1
        modelContext.insert(record)
        try modelContext.save()
        refreshRelay()
    }

    func reorderBooks(orderedISBNs: [String]) async throws {
        let records = try modelContext.fetch(FetchDescriptor<BookRecord>())
        let indexMap = Dictionary(uniqueKeysWithValues: orderedISBNs.enumerated().map { ($1, $0) })
        for record in records {
            if let newOrder = indexMap[record.isbn13] {
                record.sortOrder = newOrder
            }
        }
        try modelContext.save()
        refreshRelay()
    }

    func deleteBook(_ book: Book) async throws {
        let isbn = book.isbn13

        let bookDescriptor = FetchDescriptor<BookRecord>(
            predicate: #Predicate { $0.isbn13 == isbn }
        )
        try modelContext.fetch(bookDescriptor).forEach { modelContext.delete($0) }

        let sentenceDescriptor = FetchDescriptor<SentenceRecord>(
            predicate: #Predicate { $0.bookISBN == isbn }
        )
        try modelContext.fetch(sentenceDescriptor).forEach { modelContext.delete($0) }

        let sessionDescriptor = FetchDescriptor<ReadingSessionRecord>(
            predicate: #Predicate { $0.bookISBN == isbn }
        )
        try modelContext.fetch(sessionDescriptor).forEach { modelContext.delete($0) }

        try modelContext.save()
        refreshRelay()
    }

    func deleteAllBooks() async throws {
        try modelContext.fetch(FetchDescriptor<BookRecord>()).forEach { modelContext.delete($0) }
        try modelContext.fetch(FetchDescriptor<SentenceRecord>()).forEach { modelContext.delete($0) }
        try modelContext.fetch(FetchDescriptor<ReadingSessionRecord>()).forEach { modelContext.delete($0) }
        try modelContext.save()
        refreshRelay()
    }

    func updateReadingProgress(isbn13: String, itemPage: Int, currentPage: Int) async throws {
        let descriptor = FetchDescriptor<BookRecord>(
            predicate: #Predicate { $0.isbn13 == isbn13 }
        )
        guard let record = try modelContext.fetch(descriptor).first else {
            throw NSError(
                domain: "BookRepository",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "등록된 도서를 찾을 수 없습니다."]
            )
        }
        record.itemPage = itemPage
        record.currentPage = currentPage
        try modelContext.save()
        refreshRelay()
    }

    // MARK: Internal

    func reloadRelay() {
        refreshRelay()
    }

    // MARK: Private

    private func refreshRelay() {
        do {
            // Initialize sortOrder for pre-existing records (migration: all sortOrder == 0)
            let allDescriptor = FetchDescriptor<BookRecord>(
                sortBy: [SortDescriptor(\BookRecord.savedAt, order: .reverse)]
            )
            let allRecords = try modelContext.fetch(allDescriptor)
            var needsSave = false
            for record in allRecords where BookGenre.known(record.category) == nil {
                if record.category != BookGenre.unknown {
                    record.category = BookGenre.unknown
                    needsSave = true
                }
            }
            if allRecords.count > 1 && allRecords.allSatisfy({ $0.sortOrder == 0 }) {
                for (index, record) in allRecords.enumerated() {
                    record.sortOrder = index
                }
                needsSave = true
            }
            if needsSave { try modelContext.save() }

            let descriptor = FetchDescriptor<BookRecord>(
                sortBy: [SortDescriptor(\BookRecord.sortOrder, order: .forward)]
            )
            let records = try modelContext.fetch(descriptor)
            savedBooksRelay.accept(records.map { $0.toDomain() })
        } catch {
            print("[BookRepository] refreshRelay 실패:", error)
        }
    }

    private func ensureBookIsNotSaved(isbn13: String) throws {
        let descriptor = FetchDescriptor<BookRecord>(
            predicate: #Predicate { $0.isbn13 == isbn13 }
        )
        guard try modelContext.fetch(descriptor).isEmpty else {
            throw NSError(
                domain: "BookRepository",
                code: 409,
                userInfo: [NSLocalizedDescriptionKey: "이미 등록된 도서입니다."]
            )
        }
    }
}
