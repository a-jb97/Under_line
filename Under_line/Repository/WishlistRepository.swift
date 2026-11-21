import Foundation
import SwiftData

@MainActor
protocol WishlistRepositoryProtocol {
    func addBook(_ book: Book) async throws
    func deleteBook(isbn13: String) async throws
    func containsBook(isbn13: String) async throws -> Bool
    func fetchAllItems() async throws -> [WishlistItem]
}

enum WishlistRepositoryError: LocalizedError, Equatable {
    case invalidISBN13
    case duplicateISBN13

    var errorDescription: String? {
        switch self {
        case .invalidISBN13:
            return "유효한 ISBN13이 필요합니다."
        case .duplicateISBN13:
            return "이미 위시리스트에 추가된 도서입니다."
        }
    }
}

@MainActor
final class WishlistRepository: WishlistRepositoryProtocol {
    private let modelContext: ModelContext
    private let now: () -> Date

    init(modelContainer: ModelContainer, now: @escaping () -> Date = { Date() }) {
        // A dedicated context keeps save/rollback independent of pending bookshelf changes.
        modelContext = ModelContext(modelContainer)
        modelContext.autosaveEnabled = false
        self.now = now
    }

    func addBook(_ book: Book) async throws {
        let isbn13 = try normalizedISBN13(book.isbn13)
        guard try record(for: isbn13) == nil else {
            throw WishlistRepositoryError.duplicateISBN13
        }

        // No suspension between duplicate checking and saving on MainActor.
        modelContext.insert(WishlistRecord(from: book, isbn13: isbn13, addedAt: now()))
        try saveChanges()
    }

    func deleteBook(isbn13: String) async throws {
        let isbn13 = try normalizedISBN13(isbn13)
        guard let record = try record(for: isbn13) else { return }
        modelContext.delete(record)
        try saveChanges()
    }

    func containsBook(isbn13: String) async throws -> Bool {
        let isbn13 = try normalizedISBN13(isbn13)
        return try record(for: isbn13) != nil
    }

    func fetchAllItems() async throws -> [WishlistItem] {
        let descriptor = FetchDescriptor<WishlistRecord>(sortBy: [
            SortDescriptor(\WishlistRecord.addedAt, order: .reverse),
            SortDescriptor(\WishlistRecord.isbn13, order: .forward)
        ])
        return try modelContext.fetch(descriptor).map { $0.toDomain() }
    }

    private func normalizedISBN13(_ value: String) throws -> String {
        let isbn13 = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isbn13.utf8.count == 13,
              isbn13.utf8.allSatisfy({ (48...57).contains($0) }),
              ISBN13Parser.isValidISBN13(isbn13) else {
            throw WishlistRepositoryError.invalidISBN13
        }
        return isbn13
    }

    private func record(for isbn13: String) throws -> WishlistRecord? {
        var descriptor = FetchDescriptor<WishlistRecord>(
            predicate: #Predicate { $0.isbn13 == isbn13 }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func saveChanges() throws {
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }
}
