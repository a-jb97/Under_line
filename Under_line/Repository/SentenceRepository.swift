//
//  SentenceRepository.swift
//  Under_line
//
//  Sentence 로컬 CRUD 저장소
//

import Foundation
import SwiftData

// MARK: - Protocol

protocol SentenceRepositoryProtocol {
    func saveSentence(_ sentence: Sentence) async throws
    func updateSentence(_ sentence: Sentence) async throws
    func fetchSentences(for bookISBN: String) async throws -> [Sentence]
    func deleteSentence(_ sentence: Sentence) async throws
    func fetchAllSentences() async throws -> [Sentence]
}

// MARK: - Concrete Implementation

final class SentenceRepository: SentenceRepositoryProtocol {

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func saveSentence(_ sentence: Sentence) async throws {
        modelContext.insert(SentenceRecord(from: sentence))
        try modelContext.save()
    }

    func updateSentence(_ sentence: Sentence) async throws {
        let targetID = sentence.id
        let descriptor = FetchDescriptor<SentenceRecord>(
            predicate: #Predicate { $0.id == targetID }
        )
        if let record = try modelContext.fetch(descriptor).first {
            record.sentence        = sentence.sentence
            record.page            = sentence.page
            record.emotionRawValue = sentence.emotion.rawValue
            record.memo            = sentence.memo
            try modelContext.save()
        }
    }

    func deleteSentence(_ sentence: Sentence) async throws {
        let targetID = sentence.id
        let descriptor = FetchDescriptor<SentenceRecord>(
            predicate: #Predicate { $0.id == targetID }
        )
        if let record = try modelContext.fetch(descriptor).first {
            modelContext.delete(record)
            try modelContext.save()
        }
    }

    func fetchSentences(for bookISBN: String) async throws -> [Sentence] {
        let descriptor = FetchDescriptor<SentenceRecord>(
            predicate: #Predicate { $0.bookISBN == bookISBN },
            sortBy: [SortDescriptor(\SentenceRecord.date, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).map { $0.toDomain() }
    }

    func fetchAllSentences() async throws -> [Sentence] {
        let descriptor = FetchDescriptor<SentenceRecord>(
            sortBy: [SortDescriptor(\SentenceRecord.date, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).map { $0.toDomain() }
    }
}
