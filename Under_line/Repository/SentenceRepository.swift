//
//  SentenceRepository.swift
//  Under_line
//
//  Sentence 로컬 CRUD 저장소
//

import Foundation
import SwiftData
import RxSwift

// MARK: - Protocol

protocol SentenceRepositoryProtocol {
    func saveSentence(_ sentence: Sentence) -> Completable
    func updateSentence(_ sentence: Sentence) -> Completable
    func fetchSentences(for bookISBN: String) -> Single<[Sentence]>
    func deleteSentence(_ sentence: Sentence) -> Completable
    func fetchAllSentences() -> Single<[Sentence]>
}

// MARK: - Concrete Implementation

final class SentenceRepository: SentenceRepositoryProtocol {

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func saveSentence(_ sentence: Sentence) -> Completable {
        Completable.create { [weak self] completable in
            guard let self else { completable(.completed); return Disposables.create() }
            do {
                self.modelContext.insert(SentenceRecord(from: sentence))
                try self.modelContext.save()
                completable(.completed)
            } catch {
                completable(.error(error))
            }
            return Disposables.create()
        }
    }

    func updateSentence(_ sentence: Sentence) -> Completable {
        Completable.create { [weak self] completable in
            guard let self else { completable(.completed); return Disposables.create() }
            do {
                let targetID = sentence.id
                let descriptor = FetchDescriptor<SentenceRecord>(
                    predicate: #Predicate { $0.id == targetID }
                )
                if let record = try self.modelContext.fetch(descriptor).first {
                    record.sentence        = sentence.sentence
                    record.page            = sentence.page
                    record.emotionRawValue = sentence.emotion.rawValue
                    record.memo            = sentence.memo
                    try self.modelContext.save()
                }
                completable(.completed)
            } catch {
                completable(.error(error))
            }
            return Disposables.create()
        }
    }

    func deleteSentence(_ sentence: Sentence) -> Completable {
        Completable.create { [weak self] completable in
            guard let self else { completable(.completed); return Disposables.create() }
            do {
                let targetID = sentence.id
                let descriptor = FetchDescriptor<SentenceRecord>(
                    predicate: #Predicate { $0.id == targetID }
                )
                if let record = try self.modelContext.fetch(descriptor).first {
                    self.modelContext.delete(record)
                    try self.modelContext.save()
                }
                completable(.completed)
            } catch {
                completable(.error(error))
            }
            return Disposables.create()
        }
    }

    func fetchSentences(for bookISBN: String) -> Single<[Sentence]> {
        Single.create { [weak self] single in
            guard let self else { single(.success([])); return Disposables.create() }
            do {
                let descriptor = FetchDescriptor<SentenceRecord>(
                    predicate: #Predicate { $0.bookISBN == bookISBN },
                    sortBy: [SortDescriptor(\SentenceRecord.date, order: .reverse)]
                )
                single(.success(try self.modelContext.fetch(descriptor).map { $0.toDomain() }))
            } catch {
                single(.failure(error))
            }
            return Disposables.create()
        }
    }

    func fetchAllSentences() -> Single<[Sentence]> {
        Single.create { [weak self] single in
            guard let self else { single(.success([])); return Disposables.create() }
            do {
                let descriptor = FetchDescriptor<SentenceRecord>(
                    sortBy: [SortDescriptor(\SentenceRecord.date, order: .reverse)]
                )
                single(.success(try self.modelContext.fetch(descriptor).map { $0.toDomain() }))
            } catch {
                single(.failure(error))
            }
            return Disposables.create()
        }
    }

}
