//
//  ReadingSessionRepository.swift
//  Under_line
//
//  독서 세션 로컬 CRUD 저장소
//

import Foundation
import SwiftData

// MARK: - Protocol

protocol ReadingSessionRepositoryProtocol {
    func saveSession(bookISBN: String, durationSeconds: Int) async throws
    func fetchSessions(for bookISBN: String) async throws -> [ReadingSession]
    func fetchAllSessions() async throws -> [ReadingSession]
}

// MARK: - Concrete Implementation

final class ReadingSessionRepository: ReadingSessionRepositoryProtocol {

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func saveSession(bookISBN: String, durationSeconds: Int) async throws {
        modelContext.insert(ReadingSessionRecord(bookISBN: bookISBN, durationSeconds: durationSeconds))
        try modelContext.save()
    }

    func fetchSessions(for bookISBN: String) async throws -> [ReadingSession] {
        let descriptor = FetchDescriptor<ReadingSessionRecord>(
            predicate: #Predicate { $0.bookISBN == bookISBN },
            sortBy: [SortDescriptor(\ReadingSessionRecord.date, order: .forward)]
        )
        return try modelContext.fetch(descriptor).map { $0.toDomain() }
    }

    func fetchAllSessions() async throws -> [ReadingSession] {
        let descriptor = FetchDescriptor<ReadingSessionRecord>(
            sortBy: [SortDescriptor(\ReadingSessionRecord.date, order: .forward)]
        )
        return try modelContext.fetch(descriptor).map { $0.toDomain() }
    }
}
