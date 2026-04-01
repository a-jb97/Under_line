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
    func fetchBestsellers() -> Single<[Book]>
    func searchBooks(query: String, page: Int) -> Single<(books: [Book], totalResults: Int)>
    func fetchBookDetail(isbn13: String) -> Single<Book>

    // Local
    func fetchSavedBooks() -> Observable<[Book]>
    func saveBook(_ book: Book) -> Completable
    func deleteBook(_ book: Book) -> Completable
    func deleteAllBooks() -> Completable
    func updateCurrentPage(isbn13: String, page: Int) -> Completable
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

    func fetchBestsellers() -> Single<[Book]> {
        apiService.fetchBestsellers()
    }

    func searchBooks(query: String, page: Int) -> Single<(books: [Book], totalResults: Int)> {
        apiService.searchBooks(query: query, page: page)
    }

    func fetchBookDetail(isbn13: String) -> Single<Book> {
        apiService.fetchBookDetail(isbn13: isbn13)
    }

    // MARK: Local

    func fetchSavedBooks() -> Observable<[Book]> {
        savedBooksRelay.asObservable()
    }

    func saveBook(_ book: Book) -> Completable {
        Completable.create { [weak self] (completable: @escaping (CompletableEvent) -> Void) -> Disposable in
            guard let self else { completable(.completed); return Disposables.create() }
            do {
                let isbn = book.isbn13
                let duplicateDescriptor = FetchDescriptor<BookRecord>(
                    predicate: #Predicate { $0.isbn13 == isbn }
                )
                let existing = try self.modelContext.fetch(duplicateDescriptor)
                guard existing.isEmpty else {
                    completable(.error(NSError(
                        domain: "BookRepository",
                        code: 409,
                        userInfo: [NSLocalizedDescriptionKey: "이미 등록된 도서입니다."]
                    )))
                    return Disposables.create()
                }
                let record = BookRecord(from: book)
                self.modelContext.insert(record)
                try self.modelContext.save()
                self.refreshRelay()
                completable(.completed)
            } catch {
                completable(.error(error))
            }
            return Disposables.create()
        }
    }

    func deleteBook(_ book: Book) -> Completable {
        Completable.create { [weak self] (completable: @escaping (CompletableEvent) -> Void) -> Disposable in
            guard let self else { completable(.completed); return Disposables.create() }
            do {
                let isbn = book.isbn13

                let bookDescriptor = FetchDescriptor<BookRecord>(
                    predicate: #Predicate { $0.isbn13 == isbn }
                )
                try self.modelContext.fetch(bookDescriptor).forEach { self.modelContext.delete($0) }

                let sentenceDescriptor = FetchDescriptor<SentenceRecord>(
                    predicate: #Predicate { $0.bookISBN == isbn }
                )
                try self.modelContext.fetch(sentenceDescriptor).forEach { self.modelContext.delete($0) }

                let sessionDescriptor = FetchDescriptor<ReadingSessionRecord>(
                    predicate: #Predicate { $0.bookISBN == isbn }
                )
                try self.modelContext.fetch(sessionDescriptor).forEach { self.modelContext.delete($0) }

                try self.modelContext.save()
                self.refreshRelay()
                completable(.completed)
            } catch {
                completable(.error(error))
            }
            return Disposables.create()
        }
    }

    func deleteAllBooks() -> Completable {
        Completable.create { [weak self] (completable: @escaping (CompletableEvent) -> Void) -> Disposable in
            guard let self else { completable(.completed); return Disposables.create() }
            do {
                try self.modelContext.fetch(FetchDescriptor<BookRecord>()).forEach { self.modelContext.delete($0) }
                try self.modelContext.fetch(FetchDescriptor<SentenceRecord>()).forEach { self.modelContext.delete($0) }
                try self.modelContext.fetch(FetchDescriptor<ReadingSessionRecord>()).forEach { self.modelContext.delete($0) }
                try self.modelContext.save()
                self.refreshRelay()
                completable(.completed)
            } catch {
                completable(.error(error))
            }
            return Disposables.create()
        }
    }

    func updateCurrentPage(isbn13: String, page: Int) -> Completable {
        Completable.create { [weak self] (completable: @escaping (CompletableEvent) -> Void) -> Disposable in
            guard let self else { completable(.completed); return Disposables.create() }
            do {
                let descriptor = FetchDescriptor<BookRecord>(
                    predicate: #Predicate { $0.isbn13 == isbn13 }
                )
                let records = try self.modelContext.fetch(descriptor)
                records.first?.currentPage = page
                try self.modelContext.save()
                self.refreshRelay()
                completable(.completed)
            } catch {
                completable(.error(error))
            }
            return Disposables.create()
        }
    }

    // MARK: Internal

    func reloadRelay() {
        refreshRelay()
    }

    // MARK: Private

    private func refreshRelay() {
        do {
            let descriptor = FetchDescriptor<BookRecord>(
                sortBy: [SortDescriptor(\BookRecord.savedAt, order: .reverse)]
            )
            let records = try modelContext.fetch(descriptor)
            savedBooksRelay.accept(records.map { $0.toDomain() })
        } catch { }
    }
}
