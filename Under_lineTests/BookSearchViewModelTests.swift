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
        let oldList = await requested(h) { h.list.onNext(.newSpecial) }
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

    func test_reselectingList_ignoresPreviousPageResponse() async {
        let h = Harness()
        let first = await requested(h) { h.list.onNext(.newSpecial) }
        await finish(first, .success((makeBooks(0..<10), 50)))
        let oldPage = await requested(h) { h.next.onNext(()) }
        let replacement = await requested(h) { h.list.onNext(.newSpecial) }
        await finish(oldPage, .success((makeBooks(10..<20), 50)))
        XCTAssertTrue(oldPage.wasCancelled)
        XCTAssertEqual(h.books.count, 10)
        XCTAssertTrue(h.loading)
        XCTAssertFalse(h.loadingMore)
        await finish(replacement, .success((makeBooks(100..<110), 50)))
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

    func test_newSpecial_stopsAtFiftyAndFivePages() async {
        let h = Harness()
        var request = await requested(h) { h.list.onNext(.newSpecial) }
        for page in 1...5 {
            await finish(request, .success((makeBooks(((page - 1) * 10)..<(page * 10)), 50)))
            if page < 5 { request = await requested(h) { h.next.onNext(()) } }
        }
        h.next.onNext(())
        await drain()
        XCTAssertEqual(h.books.count, 50)
        XCTAssertEqual(h.repository.requests.map(\.page), [1, 2, 3, 4, 5])
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

    func test_firstPageFailure_clearsPreviousListAndCanSearchAgain() async {
        let h = Harness()
        let first = await requested(h) { h.list.onNext(.bestseller) }
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

    private func finish(_ request: PendingRequest, _ result: Result<([Book], Int), Error>) async {
        let returned = expectation(description: "응답 반환")
        request.onReturned = { returned.fulfill() }
        request.continuation.resume(with: result)
        await fulfillment(of: [returned], timeout: 2)
        await drain()
    }

    private func drain() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
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
    let continuation: CheckedContinuation<([Book], Int), Error>
    var wasCancelled = false
    var onReturned: (() -> Void)?

    init(page: Int, continuation: CheckedContinuation<([Book], Int), Error>) {
        self.page = page
        self.continuation = continuation
    }
}

/// 의도적으로 취소를 무시하고 응답해 ViewModel의 세대 교체를 검증한다.
@MainActor
private final class ControlledRepository: BookRepositoryProtocol {
    var requests: [PendingRequest] = []
    var onRequested: (() -> Void)?

    private func fetch(page: Int) async throws -> ([Book], Int) {
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

    func fetchBestsellers() async throws -> [Book] { try await fetch(page: 1).0 }
    func fetchNewSpecialBooks(page: Int) async throws -> [Book] { try await fetch(page: page).0 }
    func searchBooks(query: String, page: Int) async throws -> (books: [Book], totalResults: Int) {
        try await fetch(page: page)
    }
    func fetchBookDetail(isbn13: String) async throws -> Book { throw StubError.failed }
    func fetchSavedBooks() -> Observable<[Book]> { .just([]) }
    func saveBook(_ book: Book) async throws { }
    func deleteBook(_ book: Book) async throws { }
    func deleteAllBooks() async throws { }
    func updateCurrentPage(isbn13: String, page: Int) async throws { }
    func reorderBooks(orderedISBNs: [String]) async throws { }
}
