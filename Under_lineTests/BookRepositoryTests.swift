import XCTest
import SwiftData
import RxSwift
import RxCocoa
@testable import Under_line

@MainActor
final class BookRepositoryTests: XCTestCase {
    func test_repeatedLists_reusesSeparateCachedResults() async throws {
        let fixture = try Fixture()
        let bestseller = try await fixture.repository.fetchBestsellers()
        let newSpecial = try await fixture.repository.fetchNewSpecialBooks(page: 1)
        fixture.api.books = []
        let cachedBestseller = try await fixture.repository.fetchBestsellers()
        let cachedNewSpecial = try await fixture.repository.fetchNewSpecialBooks(page: 1)
        XCTAssertEqual(cachedBestseller.map(\.isbn13), bestseller.map(\.isbn13))
        XCTAssertEqual(cachedNewSpecial.map(\.isbn13), newSpecial.map(\.isbn13))
        XCTAssertEqual(fixture.api.bestsellerCalls, 1)
        XCTAssertEqual(fixture.api.newSpecialPages, [1])
    }

    func test_searchWhitespace_reusesBooksAndTotalResults() async throws {
        let fixture = try Fixture()
        let first = try await fixture.repository.searchBooks(query: " \n어린 왕자\t", page: 1)
        fixture.api.books = []
        fixture.api.totalResults = 0
        let cached = try await fixture.repository.searchBooks(query: "어린 왕자", page: 1)
        XCTAssertEqual(cached.books.map(\.isbn13), first.books.map(\.isbn13))
        XCTAssertEqual(cached.totalResults, 120)
        XCTAssertEqual(fixture.api.searchQueries.map(\.query), ["어린 왕자"])
    }

    func test_queryPageAndListType_doNotShareCache() async throws {
        let fixture = try Fixture()
        for query in ["어린 왕자", "어린  왕자", "다른 책", "Book", "book"] {
            _ = try await fixture.repository.searchBooks(query: query, page: 1)
        }
        _ = try await fixture.repository.searchBooks(query: "어린 왕자", page: 2)
        _ = try await fixture.repository.fetchNewSpecialBooks(page: 1)
        _ = try await fixture.repository.fetchNewSpecialBooks(page: 2)
        _ = try await fixture.repository.fetchBestsellers()
        XCTAssertEqual(fixture.api.searchQueries.count, 6)
        XCTAssertEqual(fixture.api.searchQueries.map(\.page), [1, 1, 1, 1, 1, 2])
        XCTAssertEqual(fixture.api.newSpecialPages, [1, 2])
        XCTAssertEqual(fixture.api.bestsellerCalls, 1)
    }

    func test_emptySuccess_isCached() async throws {
        let fixture = try Fixture()
        fixture.api.books = []
        fixture.api.totalResults = 0
        _ = try await fixture.repository.searchBooks(query: "빈 결과", page: 1)
        let result = try await fixture.repository.searchBooks(query: "빈 결과", page: 1)
        XCTAssertTrue(result.books.isEmpty)
        XCTAssertEqual(result.totalResults, 0)
        XCTAssertEqual(fixture.api.searchQueries.count, 1)
    }

    func test_exactExpiry_requestsAgainWithoutExtendingOnRead() async throws {
        let fixture = try Fixture()
        _ = try await fixture.repository.fetchBestsellers()
        fixture.clock.time = 299
        _ = try await fixture.repository.fetchBestsellers()
        XCTAssertEqual(fixture.api.bestsellerCalls, 1)
        fixture.clock.time = 300
        _ = try await fixture.repository.fetchBestsellers()
        XCTAssertEqual(fixture.api.bestsellerCalls, 2)
    }

    func test_expiry_startsAtResponseCompletion() async throws {
        let fixture = try Fixture()
        fixture.api.onRequest = { fixture.clock.time = 400 }
        _ = try await fixture.repository.searchBooks(query: "책", page: 1)
        fixture.api.onRequest = nil
        fixture.clock.time = 699
        _ = try await fixture.repository.searchBooks(query: "책", page: 1)
        XCTAssertEqual(fixture.api.searchQueries.count, 1)
        fixture.clock.time = 700
        _ = try await fixture.repository.searchBooks(query: "책", page: 1)
        XCTAssertEqual(fixture.api.searchQueries.count, 2)
    }

    func test_moreThanThirtyEntries_evictsLeastRecentlyUsed() async throws {
        let fixture = try Fixture()
        for index in 0..<30 {
            _ = try await fixture.repository.searchBooks(query: "책 \(index)", page: 1)
        }
        _ = try await fixture.repository.searchBooks(query: "책 0", page: 1)
        _ = try await fixture.repository.fetchBestsellers()
        _ = try await fixture.repository.searchBooks(query: "책 0", page: 1)
        XCTAssertEqual(fixture.api.searchQueries.count, 30)
        _ = try await fixture.repository.searchBooks(query: "책 1", page: 1)
        XCTAssertEqual(fixture.api.searchQueries.count, 31)
    }

    func test_expiredEntries_areRemovedBeforeEvictingValidEntry() async throws {
        let fixture = try Fixture()
        for index in 0..<29 {
            _ = try await fixture.repository.searchBooks(query: "책 \(index)", page: 1)
        }
        fixture.clock.time = 100
        _ = try await fixture.repository.fetchBestsellers()
        fixture.clock.time = 299
        for index in 0..<29 {
            _ = try await fixture.repository.searchBooks(query: "책 \(index)", page: 1)
        }
        fixture.clock.time = 300
        _ = try await fixture.repository.fetchNewSpecialBooks(page: 1)
        _ = try await fixture.repository.fetchBestsellers()
        XCTAssertEqual(fixture.api.bestsellerCalls, 1)
    }

    func test_failedRequests_areNotCached() async throws {
        let fixture = try Fixture()
        for request in fixture.remoteRequests {
            fixture.api.onRequest = { throw StubError.failed }
            do {
                try await request()
                XCTFail("실패 응답은 호출자에게 전달되어야 함")
            } catch StubError.failed { }
            fixture.api.onRequest = nil
            try await request()
            try await request()
        }
        XCTAssertEqual(fixture.api.bestsellerCalls, 2)
        XCTAssertEqual(fixture.api.newSpecialPages.count, 2)
        XCTAssertEqual(fixture.api.searchQueries.count, 2)
    }

    func test_cancelledRequestsReturningSuccess_areNotCached() async throws {
        let fixture = try Fixture()
        for request in fixture.remoteRequests {
            let started = expectation(description: "요청 시작")
            var continuation: CheckedContinuation<Void, Never>?
            fixture.api.onRequest = {
                await withCheckedContinuation {
                    continuation = $0
                    started.fulfill()
                }
            }
            let task = Task { try await request() }
            await fulfillment(of: [started], timeout: 2)
            task.cancel()
            continuation?.resume()
            do {
                try await task.value
                XCTFail("취소 후 도착한 성공 응답은 저장되면 안 됨")
            } catch is CancellationError { }
            fixture.api.onRequest = nil
            try await request()
        }
        XCTAssertEqual(fixture.api.bestsellerCalls, 2)
        XCTAssertEqual(fixture.api.newSpecialPages.count, 2)
        XCTAssertEqual(fixture.api.searchQueries.count, 2)
    }

    func test_alreadyCancelledTask_doesNotReturnCachedResult() async throws {
        let fixture = try Fixture()
        _ = try await fixture.repository.fetchBestsellers()
        let task = Task { try await fixture.repository.fetchBestsellers() }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("캐시 적중이어도 취소를 존중해야 함")
        } catch is CancellationError { }
        XCTAssertEqual(fixture.api.bestsellerCalls, 1)
    }

    func test_newRepository_doesNotReusePreviousInstanceCache() async throws {
        let fixture = try Fixture()
        _ = try await fixture.repository.fetchBestsellers()
        let another = BookRepository(apiService: fixture.api, modelContext: fixture.container.mainContext)
        _ = try await another.fetchBestsellers()
        XCTAssertEqual(fixture.api.bestsellerCalls, 2)
    }

    func test_bookDetail_remainsUncached() async throws {
        let fixture = try Fixture()
        _ = try await fixture.repository.fetchBookDetail(isbn13: "test")
        _ = try await fixture.repository.fetchBookDetail(isbn13: "test")
        XCTAssertEqual(fixture.api.detailCalls, 2)
    }

    func test_viewModelPagination_usesSameNormalizedQuery() async throws {
        let fixture = try Fixture()
        let viewModel = BookSearchViewModel(repository: fixture.repository)
        let query = PublishSubject<String>()
        let search = PublishSubject<Void>()
        let nextPage = PublishSubject<Void>()
        let firstPage = expectation(description: "첫 페이지")
        let secondPage = expectation(description: "다음 페이지")
        let output = viewModel.transform(input: .init(
            viewDidLoad: .never(), listSelection: .never(), searchQuery: query,
            searchTrigger: search, loadNextPage: nextPage, registerBook: .never()
        ))
        let subscription = output.books.drive(onNext: { books in
            if books.count == 1 { firstPage.fulfill() }
            if books.count == 2 { secondPage.fulfill() }
        })
        defer { subscription.dispose() }
        query.onNext(" \n어린 왕자\t")
        search.onNext(())
        await fulfillment(of: [firstPage], timeout: 2)
        query.onNext("어린 왕자 \n")
        nextPage.onNext(())
        await fulfillment(of: [secondPage], timeout: 2)
        XCTAssertEqual(fixture.api.searchQueries.map(\.query), ["어린 왕자", "어린 왕자"])
        XCTAssertEqual(fixture.api.searchQueries.map(\.page), [1, 2])
    }
}

private enum StubError: Error {
    case failed
}

@MainActor
private final class TestClock {
    var time: TimeInterval = 0
}

@MainActor
private final class Fixture {
    let clock = TestClock()
    let api = StubAladinAPIService()
    let container: ModelContainer
    let repository: BookRepository

    init() throws {
        container = try ModelContainer(
            for: BookRecord.self, SentenceRecord.self, ReadingSessionRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let clock = clock
        repository = BookRepository(
            apiService: api, modelContext: container.mainContext,
            searchCache: BookSearchCache(now: { clock.time })
        )
    }

    var remoteRequests: [() async throws -> Void] {
        [
            { _ = try await self.repository.fetchBestsellers() },
            { _ = try await self.repository.fetchNewSpecialBooks(page: 1) },
            { _ = try await self.repository.searchBooks(query: "책", page: 1) }
        ]
    }
}

@MainActor
private final class StubAladinAPIService: AladinAPIServiceProtocol {
    var bestsellerCalls = 0
    var newSpecialPages: [Int] = []
    var searchQueries: [(query: String, page: Int)] = []
    var detailCalls = 0
    var totalResults = 120
    var onRequest: (() async throws -> Void)?
    var books = [Book(
        title: "테스트 도서", author: "저자", isbn13: "test", coverURL: nil,
        publisher: "출판사", publishDate: nil, category: nil, bestRank: nil,
        description: "설명", itemPage: nil, currentPage: nil
    )]

    func fetchBestsellers() async throws -> [Book] {
        bestsellerCalls += 1
        try await onRequest?()
        return books
    }

    func fetchNewSpecialBooks(page: Int) async throws -> [Book] {
        newSpecialPages.append(page)
        try await onRequest?()
        return books
    }

    func searchBooks(query: String, page: Int) async throws -> (books: [Book], totalResults: Int) {
        searchQueries.append((query, page))
        try await onRequest?()
        return (books, totalResults)
    }

    func fetchBookDetail(isbn13: String) async throws -> Book {
        detailCalls += 1
        return books[0]
    }
}
