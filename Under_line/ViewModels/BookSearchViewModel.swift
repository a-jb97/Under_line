//
//  BookSearchViewModel.swift
//  Under_line
//

import RxSwift
import RxCocoa
import Foundation

final class BookSearchViewModel {
    enum BookListType: Equatable {
        case bestseller
        case newSpecial
    }

    struct ListUpdate {
        enum Change {
            case replace
            case append(from: Int)
        }

        // 전체 snapshot도 제공해 구독 재연결 시 안전하게 복원할 수 있다.
        let books: [Book]
        let change: Change
    }

    private enum DisplayMode {
        case list(BookListType)
        case search(String)

        var pageSize: Int {
            if case .list(.newSpecial) = self { return 10 }
            return 50
        }

        var maximumCount: Int {
            if case .search = self { return 200 }
            return 50
        }
    }

    struct Input {
        let viewDidLoad: Observable<Void>
        let listSelection: Observable<BookListType>
        let searchQuery: Observable<String>
        let searchTrigger: Observable<Void>
        let loadNextPage: Observable<Void>
        let registerBook: Observable<Book>
    }

    struct Output {
        let books: Driver<[Book]>
        let listUpdates: Driver<ListUpdate>
        let isLoading: Driver<Bool>
        let isLoadingMore: Driver<Bool>
        let errorMessage: Signal<String>
        let registerCompleted: Signal<Void>
    }

    private let repository: BookRepositoryProtocol
    private let disposeBag = DisposeBag()
    private let pageRequest = SerialDisposable()
    private let updates = BehaviorRelay<ListUpdate>(value: .init(books: [], change: .replace))
    private let isLoading = BehaviorRelay<Bool>(value: false)
    private let isLoadingMore = BehaviorRelay<Bool>(value: false)
    private let errorMessage = PublishRelay<String>()
    private let registerCompleted = PublishRelay<Void>()
    private var latestQuery = ""
    private var mode: DisplayMode?
    private var generation = UUID()
    private var currentPage = 0
    private var totalCount = 0
    private var hasMorePages = false

    init(repository: BookRepositoryProtocol) {
        self.repository = repository
        pageRequest.disposed(by: disposeBag)
    }

    func transform(input: Input) -> Output {
        input.searchQuery
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .subscribe(onNext: { [weak self] in self?.latestQuery = $0 })
            .disposed(by: disposeBag)

        Observable.merge(
            input.viewDidLoad.map { DisplayMode.list(.bestseller) },
            input.listSelection.map { DisplayMode.list($0) },
            input.searchTrigger.compactMap { [weak self] _ -> DisplayMode? in
                guard let self, !self.latestQuery.isEmpty else { return nil }
                return .search(self.latestQuery)
            }
        )
        .subscribe(onNext: { [weak self] in self?.start($0) })
        .disposed(by: disposeBag)

        input.loadNextPage
            .subscribe(onNext: { [weak self] in self?.loadNextPage() })
            .disposed(by: disposeBag)

        input.registerBook
            .flatMapLatest { [weak self] book -> Observable<Void> in
                guard let self else { return .empty() }
                return rxAsync { [repository = self.repository] in try await repository.saveBook(book) }
                    .catch { [weak self] error in
                        self?.errorMessage.accept(error.localizedDescription)
                        return .empty()
                    }
            }
            .bind(to: registerCompleted)
            .disposed(by: disposeBag)

        return Output(
            books: updates.map(\.books).asDriver(onErrorJustReturn: []),
            listUpdates: updates.asDriver(),
            isLoading: isLoading.asDriver(),
            isLoadingMore: isLoadingMore.asDriver(),
            errorMessage: errorMessage.asSignal(),
            registerCompleted: registerCompleted.asSignal()
        )
    }

    private func start(_ mode: DisplayMode) {
        // 같은 검색어·같은 탭으로 돌아와도 이전 응답과 구분한다.
        generation = UUID()
        pageRequest.disposable = Disposables.create()
        self.mode = mode
        currentPage = 0
        totalCount = 0
        hasMorePages = false
        isLoading.accept(true)
        isLoadingMore.accept(false)
        request(mode: mode, page: 1, generation: generation)
    }

    private func loadNextPage() {
        guard let mode, !isLoading.value, !isLoadingMore.value, hasMorePages else { return }
        if case .search(let query) = mode, query != latestQuery { return }
        // UI 이벤트가 반복되어도 응답 전에는 한 페이지만 요청한다.
        isLoadingMore.accept(true)
        request(mode: mode, page: currentPage + 1, generation: generation)
    }

    private func request(mode: DisplayMode, page: Int, generation: UUID) {
        let request: Observable<(books: [Book], totalResults: Int)> = rxAsync { [repository] in
            switch mode {
            case .list(.bestseller):
                let books = try await repository.fetchBestsellers()
                return (books, books.count)
            case .list(.newSpecial):
                return (try await repository.fetchNewSpecialBooks(page: page), 50)
            case .search(let query):
                return try await repository.searchBooks(query: query, page: page)
            }
        }
        pageRequest.disposable = request.subscribe(
            onNext: { [weak self] result in
                guard let self, self.generation == generation else { return }
                self.receive(result, mode: mode, page: page)
            },
            onError: { [weak self] error in
                guard let self, self.generation == generation else { return }
                // 실패 시 currentPage와 hasMorePages를 유지해 동일 페이지 재시도를 허용한다.
                if page == 1 {
                    self.updates.accept(.init(books: [], change: .replace))
                }
                self.isLoading.accept(false)
                self.isLoadingMore.accept(false)
                if !(error is CancellationError) {
                    self.errorMessage.accept(error.localizedDescription)
                }
            }
        )
    }

    private func receive(_ result: (books: [Book], totalResults: Int), mode: DisplayMode, page: Int) {
        if page == 1 { totalCount = min(max(result.totalResults, 0), mode.maximumCount) }
        let previous = page == 1 ? [] : updates.value.books
        let combined = Array((previous + result.books).prefix(totalCount))
        currentPage = page
        hasMorePages = !result.books.isEmpty
            && combined.count < totalCount
            && page * mode.pageSize < totalCount
        switch mode {
        case .list(.bestseller):
            hasMorePages = false
        case .list(.newSpecial):
            hasMorePages = hasMorePages && result.books.count >= mode.pageSize
        case .search:
            // 첫 검색은 totalResults를 따른다. 후속 페이지가 짧으면 종료한다.
            hasMorePages = hasMorePages && (page == 1 || result.books.count >= mode.pageSize)
        }
        // 상태 계산과 snapshot 반영 중 발생하는 UI 요청은 로딩 상태로 차단한다.
        if page == 1 {
            updates.accept(.init(books: combined, change: .replace))
        } else if combined.count > previous.count {
            updates.accept(.init(books: combined, change: .append(from: previous.count)))
        }
        isLoading.accept(false)
        isLoadingMore.accept(false)
    }
}
