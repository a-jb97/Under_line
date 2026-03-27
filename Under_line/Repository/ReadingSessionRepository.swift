//
//  ReadingSessionRepository.swift
//  Under_line
//
//  독서 세션 로컬 CRUD 저장소
//

import Foundation
import SwiftData
import RxSwift

// MARK: - Protocol

protocol ReadingSessionRepositoryProtocol {
    func saveSession(bookISBN: String, durationSeconds: Int) -> Completable
    func fetchSessions(for bookISBN: String) -> Single<[ReadingSession]>
}

// MARK: - Concrete Implementation

final class ReadingSessionRepository: ReadingSessionRepositoryProtocol {

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func saveSession(bookISBN: String, durationSeconds: Int) -> Completable {
        Completable.create { [weak self] completable in
            guard let self else { completable(.completed); return Disposables.create() }
            do {
                self.modelContext.insert(ReadingSessionRecord(bookISBN: bookISBN, durationSeconds: durationSeconds))
                try self.modelContext.save()
                completable(.completed)
            } catch {
                completable(.error(error))
            }
            return Disposables.create()
        }
    }

    func fetchSessions(for bookISBN: String) -> Single<[ReadingSession]> {
        Single.create { [weak self] single in
            guard let self else { single(.success([])); return Disposables.create() }
            do {
                let descriptor = FetchDescriptor<ReadingSessionRecord>(
                    predicate: #Predicate { $0.bookISBN == bookISBN },
                    sortBy: [SortDescriptor(\ReadingSessionRecord.date, order: .forward)]
                )
                single(.success(try self.modelContext.fetch(descriptor).map { $0.toDomain() }))
            } catch {
                single(.failure(error))
            }
            return Disposables.create()
        }
    }
}
