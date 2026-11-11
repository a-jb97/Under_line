import XCTest
import SwiftData
@testable import Under_line

@MainActor
final class WishlistRepositoryTests: XCTestCase {
    private let firstISBN = "9788937460586"
    private let secondISBN = "9788936434267"
    private let thirdISBN = "9788936434120"

    func test_addBook_preservesAllWishlistFields() async throws {
        let container = try makeContainer()
        let date = Date(timeIntervalSince1970: 100)
        let repository = WishlistRepository(modelContainer: container, now: { date })
        let book = makeBook()

        try await repository.addBook(book)

        let items = try await repository.fetchAllItems()
        XCTAssertEqual(items, [WishlistItem(
            isbn13: book.isbn13, title: book.title, author: book.author,
            publisher: book.publisher, coverURL: book.coverURL,
            description: book.description, addedAt: date
        )])
    }

    func test_addBook_acceptsMissingCoverAndEmptyMetadata() async throws {
        let container = try makeContainer()
        let repository = WishlistRepository(modelContainer: container)
        let book = Book(
            title: "도서", author: "", isbn13: firstISBN, coverURL: nil,
            publisher: "", publishDate: nil, category: nil, bestRank: nil,
            description: "", itemPage: nil, currentPage: nil
        )

        try await repository.addBook(book)

        let items = try await repository.fetchAllItems()
        let item = try XCTUnwrap(items.first)
        XCTAssertNil(item.coverURL)
        XCTAssertEqual(item.author, "")
        XCTAssertEqual(item.publisher, "")
        XCTAssertEqual(item.description, "")
    }

    func test_addBook_duplicateISBNPreservesOriginalMetadataAndDate() async throws {
        let container = try makeContainer()
        var date = Date(timeIntervalSince1970: 100)
        let repository = WishlistRepository(modelContainer: container, now: { date })
        try await repository.addBook(makeBook())
        let original = try await repository.fetchAllItems()
        date = Date(timeIntervalSince1970: 200)

        await assertError(.duplicateISBN13) {
            try await repository.addBook(self.makeBook(title: "변경된 제목"))
        }

        let items = try await repository.fetchAllItems()
        XCTAssertEqual(items, original)
    }

    func test_isbnInputs_trimSurroundingWhitespaceAcrossAllOperations() async throws {
        let container = try makeContainer()
        let repository = WishlistRepository(modelContainer: container)
        let paddedISBN = " \n\(firstISBN)\t"

        try await repository.addBook(makeBook(isbn13: paddedISBN))
        let items = try await repository.fetchAllItems()
        XCTAssertEqual(items.map(\.isbn13), [firstISBN])
        let contains = try await repository.containsBook(isbn13: paddedISBN)
        XCTAssertTrue(contains)
        await assertError(.duplicateISBN13) {
            try await repository.addBook(self.makeBook())
        }

        try await repository.deleteBook(isbn13: paddedISBN)
        let remaining = try await repository.fetchAllItems()
        XCTAssertTrue(remaining.isEmpty)
    }

    func test_isbnInputs_rejectInvalidValuesAcrossAllOperations() async throws {
        let container = try makeContainer()
        let repository = WishlistRepository(modelContainer: container)
        let invalidISBNs = [
            "", " \n", "978893746058", "97889374605860", "9788937460587",
            "978893746058A", "978-8937460586", "9788937 460586", "９７８８９３７４６０５８６"
        ]
        for isbn13 in invalidISBNs {
            await assertError(.invalidISBN13) {
                try await repository.addBook(self.makeBook(isbn13: isbn13))
            }
            await assertError(.invalidISBN13) {
                _ = try await repository.containsBook(isbn13: isbn13)
            }
            await assertError(.invalidISBN13) {
                try await repository.deleteBook(isbn13: isbn13)
            }
        }
        let items = try await repository.fetchAllItems()
        XCTAssertTrue(items.isEmpty)
    }

    func test_fetchAllItems_emptyStoreReturnsEmptyList() async throws {
        let container = try makeContainer()
        let repository = WishlistRepository(modelContainer: container)

        let items = try await repository.fetchAllItems()
        let contains = try await repository.containsBook(isbn13: firstISBN)

        XCTAssertEqual(items, [])
        XCTAssertFalse(contains)
    }

    func test_fetchAllItems_sortsNewestFirstThenISBNAscending() async throws {
        let container = try makeContainer()
        var date = Date(timeIntervalSince1970: 100)
        let repository = WishlistRepository(modelContainer: container, now: { date })
        try await repository.addBook(makeBook())
        date = Date(timeIntervalSince1970: 200)
        try await repository.addBook(makeBook(isbn13: secondISBN))
        try await repository.addBook(makeBook(isbn13: thirdISBN))

        let items = try await repository.fetchAllItems()

        XCTAssertEqual(items.map(\.isbn13), [thirdISBN, secondISBN, firstISBN])
    }

    func test_deleteBook_removesOnlyMatchingISBNAndAllowsMissingItem() async throws {
        let container = try makeContainer()
        let repository = WishlistRepository(modelContainer: container)
        try await repository.addBook(makeBook())
        try await repository.addBook(makeBook(isbn13: secondISBN))

        try await repository.deleteBook(isbn13: firstISBN)
        try await repository.deleteBook(isbn13: firstISBN)

        let contains = try await repository.containsBook(isbn13: firstISBN)
        let items = try await repository.fetchAllItems()
        XCTAssertFalse(contains)
        XCTAssertEqual(items.map(\.isbn13), [secondISBN])
    }

    func test_addBook_afterDeletionCreatesNewAddedDate() async throws {
        let container = try makeContainer()
        var date = Date(timeIntervalSince1970: 100)
        let repository = WishlistRepository(modelContainer: container, now: { date })
        try await repository.addBook(makeBook())
        try await repository.deleteBook(isbn13: firstISBN)
        date = Date(timeIntervalSince1970: 200)

        try await repository.addBook(makeBook())

        let items = try await repository.fetchAllItems()
        XCTAssertEqual(items.first?.addedAt, date)
    }

    func test_repositoryRecreation_readsSavedRecordsAndRejectsDuplicates() async throws {
        let container = try makeContainer()
        try await WishlistRepository(modelContainer: container).addBook(makeBook())
        let repository = WishlistRepository(modelContainer: container)

        let items = try await repository.fetchAllItems()
        let contains = try await repository.containsBook(isbn13: firstISBN)
        XCTAssertEqual(items.count, 1)
        XCTAssertTrue(contains)
        await assertError(.duplicateISBN13) {
            try await repository.addBook(self.makeBook())
        }
    }

    func test_wishlistSave_doesNotCommitPendingBookshelfChanges() async throws {
        let container = try makeContainer()
        container.mainContext.autosaveEnabled = false
        container.mainContext.insert(BookRecord(from: makeBook()))
        let repository = WishlistRepository(modelContainer: container)

        try await repository.addBook(makeBook())

        let observer = ModelContext(container)
        let books = try observer.fetch(FetchDescriptor<BookRecord>())
        let wishes = try observer.fetch(FetchDescriptor<WishlistRecord>())
        XCTAssertTrue(books.isEmpty)
        XCTAssertEqual(wishes.count, 1)
        XCTAssertTrue(container.mainContext.hasChanges)
    }

    func test_bookshelfAndWishlist_sameISBNSaveAndDeleteIndependently() async throws {
        let container = try makeContainer()
        let bookshelf = BookRepository(
            bookSearchService: KakaoBookSearchService(apiKey: "unused"),
            data4LibraryService: Data4LibraryService(apiKey: "unused"),
            modelContext: container.mainContext
        )
        let wishlist = WishlistRepository(modelContainer: container)
        let book = makeBook()
        try await bookshelf.saveBook(book)
        try await wishlist.addBook(book)

        try await bookshelf.deleteBook(book)

        let contains = try await wishlist.containsBook(isbn13: firstISBN)
        XCTAssertTrue(contains)
        try await bookshelf.saveBook(book)
        try await wishlist.deleteBook(isbn13: firstISBN)
        let books = try container.mainContext.fetch(FetchDescriptor<BookRecord>())
        XCTAssertEqual(books.map(\.isbn13), [firstISBN])
    }

    func test_diskStore_reopeningPreservesFieldsAndDeletion() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("wishlist.store")
        let expected = try await seedWishlistStore(at: url)

        let container = try makeContainer(url: url)
        let repository = WishlistRepository(modelContainer: container)
        let items = try await repository.fetchAllItems()
        XCTAssertEqual(items, expected)
    }

    func test_existingStore_addingWishlistSchemaPreservesBooksSentencesAndSessions() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("legacy.store")
        let date = Date(timeIntervalSince1970: 100)
        let sentenceID = UUID()
        let sessionID = UUID()
        try seedLegacyStore(at: url, date: date, sentenceID: sentenceID, sessionID: sessionID)

        let container = try makeContainer(url: url)
        let context = container.mainContext
        let books = try context.fetch(FetchDescriptor<BookRecord>())
        let sentences = try context.fetch(FetchDescriptor<SentenceRecord>())
        let sessions = try context.fetch(FetchDescriptor<ReadingSessionRecord>())
        XCTAssertEqual(books.count, 1)
        let book = try XCTUnwrap(books.first)
        XCTAssertEqual(book.isbn13, firstISBN)
        XCTAssertEqual(book.title, "테스트 도서")
        XCTAssertEqual(book.author, "저자")
        XCTAssertEqual(book.publisher, "출판사")
        XCTAssertEqual(book.coverURLString, "https://example.com/cover.jpg")
        XCTAssertEqual(book.bookDescription, "책소개")
        XCTAssertEqual(book.itemPage, 300)
        XCTAssertEqual(book.currentPage, 100)
        XCTAssertEqual(book.savedAt, date)
        XCTAssertEqual(book.sortOrder, 7)
        XCTAssertEqual(sentences.map(\.id), [sentenceID])
        XCTAssertEqual(sentences.first?.bookISBN, firstISBN)
        XCTAssertEqual(sentences.first?.sentence, "기존 문장")
        XCTAssertEqual(sentences.first?.date, date)
        XCTAssertEqual(sessions.map(\.id), [sessionID])
        XCTAssertEqual(sessions.first?.bookISBN, firstISBN)
        XCTAssertEqual(sessions.first?.durationSeconds, 120)
        XCTAssertEqual(sessions.first?.date, date)

        let repository = WishlistRepository(modelContainer: container)
        let initial = try await repository.fetchAllItems()
        XCTAssertTrue(initial.isEmpty)
        try await repository.addBook(makeBook())
        let items = try await repository.fetchAllItems()
        XCTAssertEqual(items.count, 1)
    }

    private func makeBook(isbn13: String = "9788937460586", title: String = "테스트 도서") -> Book {
        Book(
            title: title, author: "저자", isbn13: isbn13,
            coverURL: URL(string: "https://example.com/cover.jpg"),
            publisher: "출판사", publishDate: "2026-01-01", category: "문학", bestRank: nil,
            description: "책소개", itemPage: 300, currentPage: 100
        )
    }

    private func makeContainer(url: URL? = nil) throws -> ModelContainer {
        let schema = Schema([
            BookRecord.self, SentenceRecord.self, ReadingSessionRecord.self, WishlistRecord.self
        ])
        let configuration: ModelConfiguration
        if let url {
            configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        } else {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        }
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func seedWishlistStore(at url: URL) async throws -> [WishlistItem] {
        let container = try makeContainer(url: url)
        let repository = WishlistRepository(
            modelContainer: container, now: { Date(timeIntervalSince1970: 100) }
        )
        try await repository.addBook(makeBook())
        try await repository.addBook(makeBook(isbn13: secondISBN))
        try await repository.deleteBook(isbn13: secondISBN)
        return try await repository.fetchAllItems()
    }

    private func seedLegacyStore(
        at url: URL, date: Date, sentenceID: UUID, sessionID: UUID
    ) throws {
        try autoreleasepool {
            let schema = Schema([BookRecord.self, SentenceRecord.self, ReadingSessionRecord.self])
            let container = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)]
            )
            let context = ModelContext(container)
            context.autosaveEnabled = false
            let book = BookRecord(from: makeBook())
            book.savedAt = date
            book.sortOrder = 7
            context.insert(book)
            context.insert(SentenceRecord(from: Sentence(
                id: sentenceID, bookISBN: firstISBN, sentence: "기존 문장", page: 10,
                emotion: .calm, memo: "메모", date: date
            )))
            let session = ReadingSessionRecord(bookISBN: firstISBN, durationSeconds: 120)
            session.id = sessionID
            session.date = date
            context.insert(session)
            try context.save()
        }
    }

    private func assertError(
        _ expected: WishlistRepositoryError,
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail("예상한 오류가 발생하지 않았습니다: \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? WishlistRepositoryError, expected, file: file, line: line)
        }
    }
}
