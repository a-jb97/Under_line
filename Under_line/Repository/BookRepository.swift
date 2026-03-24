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
    func searchBooks(query: String, page: Int) -> Single<[Book]>

    // Local
    func fetchSavedBooks() -> Observable<[Book]>
    func saveBook(_ book: Book) -> Completable
    func deleteBook(_ book: Book) -> Completable
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

    func searchBooks(query: String, page: Int) -> Single<[Book]> {
        apiService.searchBooks(query: query, page: page)
    }

    // MARK: Local

    func fetchSavedBooks() -> Observable<[Book]> {
        savedBooksRelay.asObservable()
    }

    func saveBook(_ book: Book) -> Completable {
        Completable.create { [weak self] (completable: @escaping (CompletableEvent) -> Void) -> Disposable in
            guard let self else { completable(.completed); return Disposables.create() }
            let record = BookRecord(from: book)
            self.modelContext.insert(record)
            do {
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
                let descriptor = FetchDescriptor<BookRecord>(
                    predicate: #Predicate { $0.isbn13 == isbn }
                )
                let records = try self.modelContext.fetch(descriptor)
                records.forEach { self.modelContext.delete($0) }
                try self.modelContext.save()
                self.refreshRelay()
                completable(.completed)
            } catch {
                completable(.error(error))
            }
            return Disposables.create()
        }
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
