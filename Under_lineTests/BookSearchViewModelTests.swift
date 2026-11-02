import XCTest
import RxSwift
import RxCocoa
@testable import Under_line

@MainActor
final class BookSearchViewModelTests: XCTestCase {
    func test_repeatedBottomEvents_requestOnePageAndEmitAppend() async {
        let h = Harness()
        let first = await requested(h) { h.search("책") }
        await finish(first, .success((makeBooks(0..<50), 120)))
        let second = await requested(h) { h.next.onNext(()) }
        h.next.onNext(())
        h.next.onNext(())
        XCTAssertEqual(h.repository.requests.count, 2)
        XCTAssertTrue(h.loadingMore)
        await finish(second, .success((makeBooks(50..<100), 120)))
        XCTAssertEqual(h.books.count, 100)
        guard case .append(let start) = h.updates.last?.change else { return XCTFail("append가 필요함") }
        XCTAssertEqual(start, 50)
        let third = await requested(h) { h.next.onNext(()) }
        await finish(third, .success((makeBooks(100..<130), 120)))
        XCTAssertEqual(h.books.count, 120)
        h.next.onNext(())
        await drain()
        XCTAssertEqual(h.repository.requests.map(\.page), [1, 2, 3])
    }

    func test_pageFailure_preservesRowsAndRetriesSamePage() async {
        let h = Harness()
        let first = await requested(h) { h.search("책") }
        await finish(first, .success((makeBooks(0..<50), 150)))
        let second = await requested(h) { h.next.onNext(()) }
        let count = h.updates.count
        await finish(second, .failure(StubError.failed))
        XCTAssertEqual(h.books.count, 50)
        XCTAssertEqual(h.updates.count, count)
        XCTAssertFalse(h.loadingMore)
        XCTAssertEqual(h.errors.count, 1)
        let retry = await requested(h) { h.next.onNext(()) }
        XCTAssertEqual(retry.page, 2)
        await finish(retry, .success((makeBooks(50..<100), 150)))
        XCTAssertEqual(h.books.count, 100)
    }

    func test_searchListSearch_ignoresOldSuccessAndErrorEvenForSameQuery() async {
        let h = Harness()
        let oldSearch = await requested(h) { h.search("같은 책") }
        let oldList = await requested(h) { h.list.onNext(.trending) }
        let current = await requested(h) { h.search("같은 책") }
        await finish(oldSearch, .success((makeBooks(900..<901), 1)))
        await finish(oldList, .failure(StubError.failed))
        XCTAssertTrue(oldSearch.wasCancelled)
        XCTAssertTrue(oldList.wasCancelled)
        XCTAssertTrue(h.loading)
        XCTAssertTrue(h.errors.isEmpty)
        XCTAssertTrue(h.books.isEmpty)
        await finish(current, .success((makeBooks(0..<1), 1)))
        XCTAssertEqual(h.books.map(\.isbn13), ["0"])
        XCTAssertFalse(h.loading)
    }

    func test_reselectingList_ignoresPreviousResponse() async {
        let h = Harness()
        let first = await requested(h) { h.list.onNext(.trending) }
        let replacement = await requested(h) { h.list.onNext(.trending) }
        await finish(first, .success((makeBooks(0..<10), 10)))
        XCTAssertTrue(first.wasCancelled)
        XCTAssertTrue(h.books.isEmpty)
        XCTAssertTrue(h.loading)
        XCTAssertFalse(h.loadingMore)
        await finish(replacement, .success((makeBooks(100..<110), 10)))
        XCTAssertEqual(h.books.first?.isbn13, "100")
        guard case .replace = h.updates.last?.change else { return XCTFail("목록을 교체해야 함") }
    }

    func test_searchResults_stopAtTwoHundredAndFourPages() async {
        let h = Harness()
        var request = await requested(h) { h.search("책") }
        for page in 1...4 {
            await finish(request, .success((makeBooks(((page - 1) * 50)..<(page * 50)), 999)))
            if page < 4 { request = await requested(h) { h.next.onNext(()) } }
        }
        h.next.onNext(())
        await drain()
        XCTAssertEqual(h.books.count, 200)
        XCTAssertEqual(h.repository.requests.map(\.page), [1, 2, 3, 4])
    }

    func test_trending_usesSingleNonPaginatedResponse() async {
        let h = Harness()
        let request = await requested(h) { h.list.onNext(.trending) }
        await finish(request, .success((makeBooks(0..<15), 15)))
        h.next.onNext(())
        await drain()
        XCTAssertEqual(h.books.count, 15)
        XCTAssertEqual(h.repository.requests.map(\.page), [1])
    }

    func test_listEnrichment_displaysBaseListThenReloadsMatchingRowWithFourRequestLimit() async {
        let h = Harness()
        h.repository.holdsMetadataRequests = true
        let listRequest = await requested(h) { h.list.onNext(.popular) }
        await finish(listRequest, .success((makeBooks(0..<6), 6)))

        XCTAssertEqual(h.books.count, 6)
        XCTAssertTrue(h.books.allSatisfy { $0.coverURL == nil && $0.description.isEmpty })
        XCTAssertEqual(h.repository.metadataRequests.count, 4)

        let first = h.repository.metadataRequests[0]
        await finishMetadata(first, .success(metadataBook(isbn13: first.isbn13)))

        XCTAssertEqual(h.repository.metadataRequests.count, 5)
        let row = Int(first.isbn13)!
        XCTAssertEqual(h.books[row].coverURL?.absoluteString, "https://example.com/\(first.isbn13).jpg")
        XCTAssertEqual(h.books[row].description, "보완 설명")
        XCTAssertEqual(h.books[row].title, "책")
        guard case .reload(let rows) = h.updates.last?.change else {
            return XCTFail("보완된 행만 갱신해야 함")
        }
        XCTAssertEqual(rows, [row])
    }

    func test_listEnrichment_failureContinuesWithNextISBN() async {
        let h = Harness()
        h.repository.holdsMetadataRequests = true
        let listRequest = await requested(h) { h.list.onNext(.trending) }
        await finish(listRequest, .success((makeBooks(0..<5), 5)))
        XCTAssertEqual(h.repository.metadataRequests.count, 4)

        await finishMetadata(h.repository.metadataRequests[0], .failure(StubError.failed))

        XCTAssertEqual(h.repository.metadataRequests.count, 5)
        XCTAssertTrue(h.errors.isEmpty)
        XCTAssertEqual(h.books.count, 5)
    }

    func test_listEnrichment_ignoresResultAfterModeChanges() async {
        let h = Harness()
        h.repository.holdsMetadataRequests = true
        let listRequest = await requested(h) { h.list.onNext(.popular) }
        await finish(listRequest, .success((makeBooks(0..<1), 1)))
        let oldMetadata = h.repository.metadataRequests[0]

        let searchRequest = await requested(h) { h.search("다른 책") }
        await finish(searchRequest, .success((makeBooks(100..<101), 1)))
        await finishMetadata(oldMetadata, .success(metadataBook(isbn13: "0")))

        XCTAssertEqual(h.books.map(\.isbn13), ["100"])
        XCTAssertNil(h.books.first?.coverURL)
    }

    func test_emptyNextPage_finishesWithoutReloadingExistingRows() async {
        let h = Harness()
        let first = await requested(h) { h.search("책") }
        await finish(first, .success((makeBooks(0..<50), 200)))
        let second = await requested(h) { h.next.onNext(()) }
        let count = h.updates.count
        await finish(second, .success(([], 200)))
        h.next.onNext(())
        await drain()
        XCTAssertEqual(h.updates.count, count)
        XCTAssertEqual(h.books.count, 50)
        XCTAssertEqual(h.repository.requests.count, 2)
        XCTAssertFalse(h.loadingMore)
    }

    func test_shortNextPage_stopsPagination() async {
        let h = Harness()
        let first = await requested(h) { h.search("책") }
        await finish(first, .success((makeBooks(0..<50), 200)))
        let second = await requested(h) { h.next.onNext(()) }
        await finish(second, .success((makeBooks(50..<53), 200)))
        h.next.onNext(())
        await drain()
        XCTAssertEqual(h.books.count, 53)
        XCTAssertEqual(h.repository.requests.count, 2)
    }

    func test_shortMappedPage_continuesWhenKakaoReportsMoreResults() async {
        let h = Harness()
        let first = await requested(h) { h.search("책") }
        await finish(first, .success((makeBooks(0..<50), 200)))
        let second = await requested(h) { h.next.onNext(()) }
        await finish(second, .success((makeBooks(50..<99), 200)), isEnd: false)

        let third = await requested(h) { h.next.onNext(()) }
        XCTAssertEqual(third.page, 3)
        await finish(third, .success((makeBooks(99..<100), 200)), isEnd: true)

        h.next.onNext(())
        await drain()
        XCTAssertEqual(h.books.count, 100)
        XCTAssertEqual(h.repository.requests.map(\.page), [1, 2, 3])
    }

    func test_firstPageFailure_clearsPreviousListAndCanSearchAgain() async {
        let h = Harness()
        let first = await requested(h) { h.list.onNext(.popular) }
        await finish(first, .success((makeBooks(0..<50), 50)))
        h.next.onNext(())
        await drain()
        XCTAssertEqual(h.repository.requests.count, 1)
        let failed = await requested(h) { h.search("다른 책") }
        await finish(failed, .failure(StubError.failed))
        XCTAssertTrue(h.books.isEmpty)
        XCTAssertFalse(h.loading)
        XCTAssertEqual(h.errors.count, 1)
        let retry = await requested(h) { h.search("다른 책") }
        await finish(retry, .success(([], 0)))
        h.next.onNext(())
        await drain()
        XCTAssertEqual(h.repository.requests.count, 3)
    }

    private func requested(_ h: Harness, action: () -> Void) async -> PendingRequest {
        let started = expectation(description: "요청 시작")
        h.repository.onRequested = { started.fulfill() }
        action()
        await fulfillment(of: [started], timeout: 2)
        h.repository.onRequested = nil
        return h.repository.requests.last!
    }

    private func finish(
        _ request: PendingRequest,
        _ result: Result<([Book], Int), Error>,
        isEnd: Bool? = nil
    ) async {
        let returned = expectation(description: "응답 반환")
        request.onReturned = { returned.fulfill() }
        request.continuation.resume(with: result.map { books, totalResults in
            BookSearchPage(
                books: books,
                totalResults: totalResults,
                isEnd: isEnd ?? (books.isEmpty || books.count < 50 || books.count >= totalResults)
            )
        })
        await fulfillment(of: [returned], timeout: 2)
        await drain()
    }

    private func drain() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    private func finishMetadata(
        _ request: PendingMetadataRequest,
        _ result: Result<BookListMetadata?, Error>
    ) async {
        request.continuation.resume(with: result)
        await drain()
        await drain()
    }

    private func metadataBook(isbn13: String) -> BookListMetadata {
        BookListMetadata(
            isbn13: isbn13,
            coverURL: URL(string: "https://example.com/\(isbn13).jpg"),
            description: "보완 설명"
        )
    }

    private func makeBooks(_ range: Range<Int>) -> [Book] {
        range.map { index in
            Book(title: "책", author: "저자", isbn13: "\(index)", coverURL: nil,
                 publisher: "출판사", publishDate: nil, category: nil, bestRank: nil,
                 description: "", itemPage: nil, currentPage: nil)
        }
    }
}

private enum StubError: Error { case failed }

@MainActor
private final class Harness {
    let repository = ControlledRepository()
    let query = PublishSubject<String>()
    let trigger = PublishSubject<Void>()
    let list = PublishSubject<BookSearchViewModel.BookListType>()
    let next = PublishSubject<Void>()
    let bag = DisposeBag()
    let viewModel: BookSearchViewModel
    var updates: [BookSearchViewModel.ListUpdate] = []
    var errors: [String] = []
    var loading = false
    var loadingMore = false
    var books: [Book] { updates.last?.books ?? [] }

    init() {
        viewModel = BookSearchViewModel(repository: repository)
        let output = viewModel.transform(input: .init(
            viewDidLoad: .never(), listSelection: list, searchQuery: query,
            searchTrigger: trigger, loadNextPage: next, registerBook: .never()
        ))
        output.listUpdates.drive(onNext: { [weak self] in self?.updates.append($0) }).disposed(by: bag)
        output.isLoading.drive(onNext: { [weak self] in self?.loading = $0 }).disposed(by: bag)
        output.isLoadingMore.drive(onNext: { [weak self] in self?.loadingMore = $0 }).disposed(by: bag)
        output.errorMessage.emit(onNext: { [weak self] in self?.errors.append($0) }).disposed(by: bag)
    }

    func search(_ text: String) {
        query.onNext(text)
        trigger.onNext(())
    }
}

@MainActor
private final class PendingRequest {
    let page: Int
    let continuation: CheckedContinuation<BookSearchPage, Error>
    var wasCancelled = false
    var onReturned: (() -> Void)?

    init(page: Int, continuation: CheckedContinuation<BookSearchPage, Error>) {
        self.page = page
        self.continuation = continuation
    }
}

@MainActor
private final class PendingMetadataRequest {
    let isbn13: String
    let continuation: CheckedContinuation<BookListMetadata?, Error>

    init(isbn13: String, continuation: CheckedContinuation<BookListMetadata?, Error>) {
        self.isbn13 = isbn13
        self.continuation = continuation
    }
}

/// 의도적으로 취소를 무시하고 응답해 ViewModel의 세대 교체를 검증한다.
@MainActor
private final class ControlledRepository: BookRepositoryProtocol {
    var requests: [PendingRequest] = []
    var metadataRequests: [PendingMetadataRequest] = []
    var onRequested: (() -> Void)?
    var holdsMetadataRequests = false

    private func fetch(page: Int) async throws -> BookSearchPage {
        var pending: PendingRequest?
        defer {
            pending?.wasCancelled = Task.isCancelled
            pending?.onReturned?()
        }
        return try await withCheckedThrowingContinuation { continuation in
            let request = PendingRequest(page: page, continuation: continuation)
            pending = request
            requests.append(request)
            onRequested?()
        }
    }

    func fetchPopularBooks() async throws -> [Book] { try await fetch(page: 1).books }
    func fetchTrendingBooks() async throws -> [Book] { try await fetch(page: 1).books }
    func searchBooks(query: String, page: Int) async throws -> BookSearchPage {
        try await fetch(page: page)
    }
    func fetchListBookMetadata(isbn13: String) async throws -> BookListMetadata? {
        guard holdsMetadataRequests else { return nil }
        return try await withCheckedThrowingContinuation { continuation in
            metadataRequests.append(PendingMetadataRequest(
                isbn13: isbn13,
                continuation: continuation
            ))
        }
    }
    func fetchBookDetail(isbn13: String) async throws -> Book { throw StubError.failed }
    func fetchSavedBooks() -> Observable<[Book]> { .just([]) }
    func saveBook(_ book: Book) async throws { }
    func deleteBook(_ book: Book) async throws { }
    func deleteAllBooks() async throws { }
    func updateCurrentPage(isbn13: String, page: Int) async throws { }
    func reorderBooks(orderedISBNs: [String]) async throws { }
}
