import XCTest
import SwiftData
import RxSwift
import RxCocoa
@testable import Under_line

@MainActor
final class BookRepositoryTests: XCTestCase {
    func test_repeatedLists_reusesSeparateCachedResults() async throws {
        let fixture = try Fixture()
        let popular = try await fixture.repository.fetchPopularBooks()
        let trending = try await fixture.repository.fetchTrendingBooks()
        fixture.listAPI.books = []
        let cachedPopular = try await fixture.repository.fetchPopularBooks()
        let cachedTrending = try await fixture.repository.fetchTrendingBooks()
        XCTAssertEqual(cachedPopular.map(\.isbn13), popular.map(\.isbn13))
        XCTAssertEqual(cachedTrending.map(\.isbn13), trending.map(\.isbn13))
        XCTAssertEqual(fixture.listAPI.popularCalls, 1)
        XCTAssertEqual(fixture.listAPI.trendingCalls, 1)
    }

    func test_searchWhitespace_reusesBooksAndTotalResults() async throws {
        let fixture = try Fixture()
        fixture.searchAPI.isEnd = true
        let first = try await fixture.repository.searchBooks(query: " \n어린 왕자\t", page: 1)
        fixture.searchAPI.books = []
        fixture.searchAPI.totalResults = 0
        fixture.searchAPI.isEnd = false
        let cached = try await fixture.repository.searchBooks(query: "어린 왕자", page: 1)
        XCTAssertEqual(cached.books.map(\.isbn13), first.books.map(\.isbn13))
        XCTAssertEqual(cached.totalResults, 120)
        XCTAssertTrue(cached.isEnd)
        XCTAssertEqual(fixture.searchAPI.searchQueries.map(\.query), ["어린 왕자"])
    }

    func test_search_usesDedicatedBookSearchServiceOnly() async throws {
        let fixture = try Fixture()

        _ = try await fixture.repository.searchBooks(query: "책", page: 1)

        XCTAssertEqual(fixture.searchAPI.searchQueries.map(\.query), ["책"])
        XCTAssertEqual(fixture.listAPI.popularCalls, 0)
        XCTAssertEqual(fixture.listAPI.trendingCalls, 0)
        XCTAssertEqual(fixture.api.detailCalls, 0)
    }

    func test_queryPageAndListType_doNotShareCache() async throws {
        let fixture = try Fixture()
        for query in ["어린 왕자", "어린  왕자", "다른 책", "Book", "book"] {
            _ = try await fixture.repository.searchBooks(query: query, page: 1)
        }
        _ = try await fixture.repository.searchBooks(query: "어린 왕자", page: 2)
        _ = try await fixture.repository.fetchTrendingBooks()
        _ = try await fixture.repository.fetchTrendingBooks()
        _ = try await fixture.repository.fetchPopularBooks()
        XCTAssertEqual(fixture.searchAPI.searchQueries.count, 6)
        XCTAssertEqual(fixture.searchAPI.searchQueries.map(\.page), [1, 1, 1, 1, 1, 2])
        XCTAssertEqual(fixture.listAPI.trendingCalls, 1)
        XCTAssertEqual(fixture.listAPI.popularCalls, 1)
    }

    func test_emptySuccess_isCached() async throws {
        let fixture = try Fixture()
        fixture.searchAPI.books = []
        fixture.searchAPI.totalResults = 0
        _ = try await fixture.repository.searchBooks(query: "빈 결과", page: 1)
        let result = try await fixture.repository.searchBooks(query: "빈 결과", page: 1)
        XCTAssertTrue(result.books.isEmpty)
        XCTAssertEqual(result.totalResults, 0)
        XCTAssertEqual(fixture.searchAPI.searchQueries.count, 1)
    }

    func test_exactExpiry_requestsAgainWithoutExtendingOnRead() async throws {
        let fixture = try Fixture()
        _ = try await fixture.repository.fetchPopularBooks()
        fixture.clock.time = 299
        _ = try await fixture.repository.fetchPopularBooks()
        XCTAssertEqual(fixture.listAPI.popularCalls, 1)
        fixture.clock.time = 300
        _ = try await fixture.repository.fetchPopularBooks()
        XCTAssertEqual(fixture.listAPI.popularCalls, 2)
    }

    func test_expiry_startsAtResponseCompletion() async throws {
        let fixture = try Fixture()
        fixture.onRequest = { fixture.clock.time = 400 }
        _ = try await fixture.repository.searchBooks(query: "책", page: 1)
        fixture.onRequest = nil
        fixture.clock.time = 699
        _ = try await fixture.repository.searchBooks(query: "책", page: 1)
        XCTAssertEqual(fixture.searchAPI.searchQueries.count, 1)
        fixture.clock.time = 700
        _ = try await fixture.repository.searchBooks(query: "책", page: 1)
        XCTAssertEqual(fixture.searchAPI.searchQueries.count, 2)
    }

    func test_moreThanThirtyEntries_evictsLeastRecentlyUsed() async throws {
        let fixture = try Fixture()
        for index in 0..<30 {
            _ = try await fixture.repository.searchBooks(query: "책 \(index)", page: 1)
        }
        _ = try await fixture.repository.searchBooks(query: "책 0", page: 1)
        _ = try await fixture.repository.fetchPopularBooks()
        _ = try await fixture.repository.searchBooks(query: "책 0", page: 1)
        XCTAssertEqual(fixture.searchAPI.searchQueries.count, 30)
        _ = try await fixture.repository.searchBooks(query: "책 1", page: 1)
        XCTAssertEqual(fixture.searchAPI.searchQueries.count, 31)
    }

    func test_expiredEntries_areRemovedBeforeEvictingValidEntry() async throws {
        let fixture = try Fixture()
        for index in 0..<29 {
            _ = try await fixture.repository.searchBooks(query: "책 \(index)", page: 1)
        }
        fixture.clock.time = 100
        _ = try await fixture.repository.fetchPopularBooks()
        fixture.clock.time = 299
        for index in 0..<29 {
            _ = try await fixture.repository.searchBooks(query: "책 \(index)", page: 1)
        }
        fixture.clock.time = 300
        _ = try await fixture.repository.fetchTrendingBooks()
        _ = try await fixture.repository.fetchPopularBooks()
        XCTAssertEqual(fixture.listAPI.popularCalls, 1)
    }

    func test_failedRequests_areNotCached() async throws {
        let fixture = try Fixture()
        for request in fixture.remoteRequests {
            fixture.onRequest = { throw StubError.failed }
            do {
                try await request()
                XCTFail("실패 응답은 호출자에게 전달되어야 함")
            } catch StubError.failed { }
            fixture.onRequest = nil
            try await request()
            try await request()
        }
        XCTAssertEqual(fixture.listAPI.popularCalls, 2)
        XCTAssertEqual(fixture.listAPI.trendingCalls, 2)
        XCTAssertEqual(fixture.searchAPI.searchQueries.count, 2)
    }

    func test_cancelledRequestsReturningSuccess_areNotCached() async throws {
        let fixture = try Fixture()
        for request in fixture.remoteRequests {
            let started = expectation(description: "요청 시작")
            var continuation: CheckedContinuation<Void, Never>?
            fixture.onRequest = {
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
            fixture.onRequest = nil
            try await request()
        }
        XCTAssertEqual(fixture.listAPI.popularCalls, 2)
        XCTAssertEqual(fixture.listAPI.trendingCalls, 2)
        XCTAssertEqual(fixture.searchAPI.searchQueries.count, 2)
    }

    func test_alreadyCancelledTask_doesNotReturnCachedResult() async throws {
        let fixture = try Fixture()
        _ = try await fixture.repository.fetchPopularBooks()
        let task = Task { try await fixture.repository.fetchPopularBooks() }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("캐시 적중이어도 취소를 존중해야 함")
        } catch is CancellationError { }
        XCTAssertEqual(fixture.listAPI.popularCalls, 1)
    }

    func test_newRepository_doesNotReusePreviousInstanceCache() async throws {
        let fixture = try Fixture()
        _ = try await fixture.repository.fetchPopularBooks()
        let another = BookRepository(
            apiService: fixture.api,
            bookSearchService: fixture.searchAPI,
            bookListService: fixture.listAPI,
            modelContext: fixture.container.mainContext
        )
        _ = try await another.fetchPopularBooks()
        XCTAssertEqual(fixture.listAPI.popularCalls, 2)
    }

    func test_bookDetail_remainsUncached() async throws {
        let fixture = try Fixture()
        _ = try await fixture.repository.fetchBookDetail(isbn13: "test")
        _ = try await fixture.repository.fetchBookDetail(isbn13: "test")
        XCTAssertEqual(fixture.api.detailCalls, 2)
    }

    func test_listMetadata_cachesFoundAndMissingResults() async throws {
        let fixture = try Fixture()
        _ = try await fixture.repository.fetchListBookMetadata(isbn13: "found")
        _ = try await fixture.repository.fetchListBookMetadata(isbn13: "found")
        fixture.searchAPI.isbnBook = nil
        _ = try await fixture.repository.fetchListBookMetadata(isbn13: "missing")
        _ = try await fixture.repository.fetchListBookMetadata(isbn13: "missing")

        XCTAssertEqual(fixture.searchAPI.isbnQueries, ["found", "missing"])
    }

    func test_listMetadata_coalescesSameISBNRequest() async throws {
        let fixture = try Fixture()
        let started = expectation(description: "ISBN 요청 시작")
        var continuation: CheckedContinuation<Void, Never>?
        fixture.searchAPI.onISBNRequest = {
            await withCheckedContinuation {
                continuation = $0
                started.fulfill()
            }
        }

        async let first = fixture.repository.fetchListBookMetadata(isbn13: "same")
        await fulfillment(of: [started], timeout: 2)
        async let second = fixture.repository.fetchListBookMetadata(isbn13: "same")
        await Task.yield()
        XCTAssertEqual(fixture.searchAPI.isbnQueries, ["same"])
        continuation?.resume()
        _ = try await (first, second)
    }

    func test_listMetadata_doesNotCacheFailure() async throws {
        let fixture = try Fixture()
        fixture.searchAPI.onISBNRequest = { throw StubError.failed }
        do {
            _ = try await fixture.repository.fetchListBookMetadata(isbn13: "retry")
            XCTFail("오류는 호출자에게 전달되어야 함")
        } catch StubError.failed { }
        fixture.searchAPI.onISBNRequest = nil
        _ = try await fixture.repository.fetchListBookMetadata(isbn13: "retry")
        XCTAssertEqual(fixture.searchAPI.isbnQueries, ["retry", "retry"])
    }

    func test_listMetadataCache_expiresAfterThirtyMinutes() async throws {
        let fixture = try Fixture()
        _ = try await fixture.repository.fetchListBookMetadata(isbn13: "found")
        fixture.clock.time = 1_799
        _ = try await fixture.repository.fetchListBookMetadata(isbn13: "found")
        XCTAssertEqual(fixture.searchAPI.isbnQueries, ["found"])

        fixture.clock.time = 1_800
        _ = try await fixture.repository.fetchListBookMetadata(isbn13: "found")
        XCTAssertEqual(fixture.searchAPI.isbnQueries, ["found", "found"])
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
        XCTAssertEqual(fixture.searchAPI.searchQueries.map(\.query), ["어린 왕자", "어린 왕자"])
        XCTAssertEqual(fixture.searchAPI.searchQueries.map(\.page), [1, 2])
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
    let searchAPI = StubBookSearchService()
    let listAPI = StubData4LibraryBookListService()
    let container: ModelContainer
    let repository: BookRepository

    init() throws {
        container = try ModelContainer(
            for: BookRecord.self, SentenceRecord.self, ReadingSessionRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let clock = clock
        repository = BookRepository(
            apiService: api,
            bookSearchService: searchAPI,
            bookListService: listAPI,
            modelContext: container.mainContext,
            searchCache: BookSearchCache(now: { clock.time }),
            metadataCache: BookSearchCache(
                lifetime: 30 * 60,
                capacity: 100,
                now: { clock.time }
            )
        )
    }

    var onRequest: (() async throws -> Void)? {
        get { searchAPI.onRequest }
        set {
            searchAPI.onRequest = newValue
            listAPI.onRequest = newValue
        }
    }

    var remoteRequests: [() async throws -> Void] {
        [
            { _ = try await self.repository.fetchPopularBooks() },
            { _ = try await self.repository.fetchTrendingBooks() },
            { _ = try await self.repository.searchBooks(query: "책", page: 1) }
        ]
    }
}

@MainActor
private final class StubData4LibraryBookListService: Data4LibraryBookListServiceProtocol {
    var popularCalls = 0
    var trendingCalls = 0
    var onRequest: (() async throws -> Void)?
    var books = [Book(
        title: "테스트 도서", author: "저자", isbn13: "test", coverURL: nil,
        publisher: "출판사", publishDate: nil, category: nil, bestRank: nil,
        description: "설명", itemPage: nil, currentPage: nil
    )]

    func fetchPopularBooks() async throws -> [Book] {
        popularCalls += 1
        try await onRequest?()
        return books
    }

    func fetchTrendingBooks() async throws -> [Book] {
        trendingCalls += 1
        try await onRequest?()
        return books
    }
}

@MainActor
private final class StubAladinAPIService: AladinAPIServiceProtocol {
    var detailCalls = 0
    var books = [Book(
        title: "테스트 도서", author: "저자", isbn13: "test", coverURL: nil,
        publisher: "출판사", publishDate: nil, category: nil, bestRank: nil,
        description: "설명", itemPage: nil, currentPage: nil
    )]

    func fetchBookDetail(isbn13: String) async throws -> Book {
        detailCalls += 1
        return books[0]
    }
}

@MainActor
private final class StubBookSearchService: BookSearchServiceProtocol {
    var searchQueries: [(query: String, page: Int)] = []
    var totalResults = 120
    var isEnd = false
    var onRequest: (() async throws -> Void)?
    var onISBNRequest: (() async throws -> Void)?
    var isbnQueries: [String] = []
    var books = [Book(
        title: "테스트 도서", author: "저자", isbn13: "test", coverURL: nil,
        publisher: "출판사", publishDate: nil, category: nil, bestRank: nil,
        description: "설명", itemPage: nil, currentPage: nil
    )]
    var isbnBook: Book? {
        get { books.first }
        set { books = newValue.map { [$0] } ?? [] }
    }

    func searchBooks(query: String, page: Int) async throws -> BookSearchPage {
        searchQueries.append((query, page))
        try await onRequest?()
        return BookSearchPage(books: books, totalResults: totalResults, isEnd: isEnd)
    }

    func fetchBook(isbn13: String) async throws -> Book? {
        isbnQueries.append(isbn13)
        try await onISBNRequest?()
        return isbnBook
    }
}
