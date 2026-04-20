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
    func fetchBestsellers() async throws -> [Book]
    func searchBooks(query: String, page: Int) async throws -> (books: [Book], totalResults: Int)
    func fetchBookDetail(isbn13: String) async throws -> Book

    // Local (BehaviorRelay 스트림 — Observable 유지)
    func fetchSavedBooks() -> Observable<[Book]>
    func saveBook(_ book: Book) async throws
    func deleteBook(_ book: Book) async throws
    func deleteAllBooks() async throws
    func updateCurrentPage(isbn13: String, page: Int) async throws
    func reorderBooks(orderedISBNs: [String]) async throws
}

// MARK: - Concrete Implementation

final class BookRepository: BookRepositoryProtocol {

    private let apiService: AladinAPIServiceProtocol
    private let modelContext: ModelContext
    private let savedBooksRelay = BehaviorRelay<[Book]>(value: [])

    init(apiService: AladinAPIServiceProtocol, modelContext: ModelContext) {
        self.apiService   = apiService
        self.modelContext = modelContext
        refreshRelay()
    }

    // MARK: Remote

    func fetchBestsellers() async throws -> [Book] {
        try await apiService.fetchBestsellers()
    }

    func searchBooks(query: String, page: Int) async throws -> (books: [Book], totalResults: Int) {
        try await apiService.searchBooks(query: query, page: page)
    }

    func fetchBookDetail(isbn13: String) async throws -> Book {
        try await apiService.fetchBookDetail(isbn13: isbn13)
    }

    // MARK: Local

    func fetchSavedBooks() -> Observable<[Book]> {
        savedBooksRelay.asObservable()
    }

    func saveBook(_ book: Book) async throws {
        let isbn = book.isbn13
        let duplicateDescriptor = FetchDescriptor<BookRecord>(
            predicate: #Predicate { $0.isbn13 == isbn }
        )
        let existing = try modelContext.fetch(duplicateDescriptor)
        guard existing.isEmpty else {
            throw NSError(
                domain: "BookRepository",
                code: 409,
                userInfo: [NSLocalizedDescriptionKey: "이미 등록된 도서입니다."]
            )
        }
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

    func updateCurrentPage(isbn13: String, page: Int) async throws {
        let descriptor = FetchDescriptor<BookRecord>(
            predicate: #Predicate { $0.isbn13 == isbn13 }
        )
        let records = try modelContext.fetch(descriptor)
        records.first?.currentPage = page
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
            if allRecords.count > 1 && allRecords.allSatisfy({ $0.sortOrder == 0 }) {
                for (index, record) in allRecords.enumerated() {
                    record.sortOrder = index
                }
                try modelContext.save()
            }

            let descriptor = FetchDescriptor<BookRecord>(
                sortBy: [SortDescriptor(\BookRecord.sortOrder, order: .forward)]
            )
            let records = try modelContext.fetch(descriptor)
            savedBooksRelay.accept(records.map { $0.toDomain() })
        } catch { }
    }
}
