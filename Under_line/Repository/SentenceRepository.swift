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
        let record = SentenceRecord(from: sentence)
        modelContext.insert(record)
        do {
            try modelContext.save()
        } catch {
            modelContext.delete(record)
            throw error
        }
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
        // 통계, 랜덤 밑줄, 위젯에서 모든 사진 데이터를 읽지 않도록 한다.
        return try modelContext.fetch(descriptor).map { $0.toDomain(includesMarkedPhoto: false) }
    }
}
