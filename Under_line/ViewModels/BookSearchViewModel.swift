//
//  BookSearchViewModel.swift
//  Under_line
//

import RxSwift
import RxCocoa
import Foundation

final class BookSearchViewModel {
    enum BookListType: Equatable {
        case popular
        case trending
    }

    struct ListUpdate {
        enum Change {
            case replace
            case append(from: Int)
            case reload(rows: [Int])
        }

        // 전체 snapshot도 제공해 구독 재연결 시 안전하게 복원할 수 있다.
        let books: [Book]
        let change: Change
    }

    private enum DisplayMode {
        case list(BookListType)
        case search(String)

        var pageSize: Int {
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
        let visibleRows: Observable<[Int]>
        let descriptionBook: Observable<Book>
        let registerBook: Observable<Book>
        let screenAppeared: Observable<Void>
        let toggleWishlist: Observable<Book>
    }

    struct WishlistState: Equatable {
        var savedISBNs: Set<String> = []
        var pendingISBNs: Set<String> = []
        var isLoaded = false
        var isRefreshing = false
    }

    struct Output {
        let books: Driver<[Book]>
        let listUpdates: Driver<ListUpdate>
        let isLoading: Driver<Bool>
        let isLoadingMore: Driver<Bool>
        let errorMessage: Signal<String>
        let descriptionReady: Signal<String>
        let registerCompleted: Signal<Void>
        let wishlistState: Driver<WishlistState>
        let wishlistMessage: Signal<String>
        let registeredISBNs: Driver<Set<String>>
    }

    private let repository: BookRepositoryProtocol
    private let registeredISBNs = BehaviorRelay<Set<String>>(value: [])
    private let wishlistRepository: WishlistRepositoryProtocol
    private let wishlistState = BehaviorRelay<WishlistState>(value: WishlistState())
    private let wishlistMessage = PublishRelay<String>()
    private let wishlistRefresh = SerialDisposable()
    private var wishlistRefreshID = UUID()
    private var needsWishlistRefresh = false
    private let disposeBag = DisposeBag()
    private let pageRequest = SerialDisposable()
    private let maximumConcurrentEnrichments = 4
    private let updates = BehaviorRelay<ListUpdate>(value: .init(books: [], change: .replace))
    private let isLoading = BehaviorRelay<Bool>(value: false)
    private let isLoadingMore = BehaviorRelay<Bool>(value: false)
    private let errorMessage = PublishRelay<String>()
    private let descriptionReady = PublishRelay<String>()
    private let registerCompleted = PublishRelay<Void>()
    private var latestQuery = ""
    private var mode: DisplayMode?
    private var generation = UUID()
    private var currentPage = 0
    private var totalCount = 0
    private var hasMorePages = false
    private var pendingEnrichmentISBNs: [String] = []
    private var attemptedEnrichmentISBNs = Set<String>()
    private var enrichmentTasks: [String: Task<Void, Never>] = [:]
    private var descriptionTask: Task<Void, Never>?

    init(repository: BookRepositoryProtocol, wishlistRepository: WishlistRepositoryProtocol) {
        self.repository = repository
        self.wishlistRepository = wishlistRepository
        pageRequest.disposed(by: disposeBag)
        wishlistRefresh.disposed(by: disposeBag)
    }

    func transform(input: Input) -> Output {
        repository.fetchSavedBooks()
            .map { Set($0.map { $0.isbn13.trimmingCharacters(in: .whitespacesAndNewlines) }) }
            .distinctUntilChanged()
            .bind(to: registeredISBNs)
            .disposed(by: disposeBag)

        input.screenAppeared
            .subscribe(onNext: { [weak self] in self?.refreshWishlist() })
            .disposed(by: disposeBag)

        input.toggleWishlist
            .subscribe(onNext: { [weak self] in self?.toggleWishlist($0) })
            .disposed(by: disposeBag)

        input.searchQuery
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .subscribe(onNext: { [weak self] in self?.latestQuery = $0 })
            .disposed(by: disposeBag)

        Observable.merge(
            input.viewDidLoad.map { DisplayMode.list(.popular) },
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

        input.visibleRows
            .subscribe(onNext: { [weak self] in self?.updateEnrichmentWindow(visibleRows: $0) })
            .disposed(by: disposeBag)

        input.descriptionBook
            .subscribe(onNext: { [weak self] in self?.enrichDescription(for: $0) })
            .disposed(by: disposeBag)

        input.registerBook
            .filter { [weak self] book in
                guard let self else { return false }
                return !self.registeredISBNs.value.contains(
                    book.isbn13.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            .flatMapFirst { [weak self] book -> Observable<Void> in
                guard let self else { return .empty() }
                return rxAsync {
                    [repository = self.repository] in
                    try await repository.registerSearchedBook(book)
                }
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
            descriptionReady: descriptionReady.asSignal(),
            registerCompleted: registerCompleted.asSignal(),
            wishlistState: wishlistState.asDriver(),
            wishlistMessage: wishlistMessage.asSignal(),
            registeredISBNs: registeredISBNs.asDriver()
        )
    }

    private func refreshWishlist() {
        // Re-entry during a mutation must not read a snapshot from before that mutation.
        guard wishlistState.value.pendingISBNs.isEmpty else {
            needsWishlistRefresh = true
            return
        }
        needsWishlistRefresh = false
        let requestID = UUID()
        wishlistRefreshID = requestID
        var state = wishlistState.value
        state.isRefreshing = true
        wishlistState.accept(state)
        wishlistRefresh.disposable = rxAsync { [wishlistRepository] in
            let items = try await wishlistRepository.fetchAllItems()
            try Task.checkCancellation()
            return items
        }
        .subscribe(onNext: { [weak self] items in
            guard let self, self.wishlistRefreshID == requestID else { return }
            var state = self.wishlistState.value
            state.savedISBNs = Set(items.map { $0.isbn13.trimmingCharacters(in: .whitespacesAndNewlines) })
            state.isLoaded = true
            state.isRefreshing = false
            self.wishlistState.accept(state)
        }, onError: { [weak self] error in
            guard let self, self.wishlistRefreshID == requestID else { return }
            var state = self.wishlistState.value
            state.isLoaded = false
            state.isRefreshing = false
            self.wishlistState.accept(state)
            if !(error is CancellationError) {
                self.errorMessage.accept(error.localizedDescription)
            }
        })
    }

    private func toggleWishlist(_ book: Book) {
        let isbn13 = book.isbn13.trimmingCharacters(in: .whitespacesAndNewlines)
        var state = wishlistState.value
        guard state.isLoaded, !state.isRefreshing,
              !state.pendingISBNs.contains(isbn13) else { return }
        let shouldSave = !state.savedISBNs.contains(isbn13)
        state.pendingISBNs.insert(isbn13)
        wishlistState.accept(state)

        rxAsync { [wishlistRepository] in
            if shouldSave {
                try await wishlistRepository.addBook(book)
            } else {
                try await wishlistRepository.deleteBook(isbn13: isbn13)
            }
        }
        .subscribe(onNext: { [weak self] in
            self?.finishWishlistChange(isbn13: isbn13, saved: shouldSave)
        }, onError: { [weak self] error in
            self?.finishWishlistChange(isbn13: isbn13, saved: shouldSave, error: error)
        })
        .disposed(by: disposeBag)
    }

    private func finishWishlistChange(isbn13: String, saved: Bool, error: Error? = nil) {
        var state = wishlistState.value
        state.pendingISBNs.remove(isbn13)
        let isDuplicate = error as? WishlistRepositoryError == .duplicateISBN13
        if error == nil || isDuplicate {
            if saved || isDuplicate {
                state.savedISBNs.insert(isbn13)
            } else {
                state.savedISBNs.remove(isbn13)
            }
        }
        wishlistState.accept(state)
        if let error, !isDuplicate {
            if !(error is CancellationError) { errorMessage.accept(error.localizedDescription) }
        } else {
            wishlistMessage.accept(isDuplicate ? "이미 위시리스트에 추가된 도서입니다."
                : saved ? "위시리스트에 추가했습니다." : "위시리스트에서 삭제했습니다.")
        }
        if needsWishlistRefresh, state.pendingISBNs.isEmpty { refreshWishlist() }
    }

    private func start(_ mode: DisplayMode) {
        // 동일 검색의 첫 페이지·다음 페이지 요청이 진행 중이면 그대로 유지한다.
        if case .search(let query) = mode,
           case .search(let currentQuery) = self.mode,
           query == currentQuery,
           isLoading.value || isLoadingMore.value {
            return
        }

        // 같은 검색어·같은 탭으로 돌아와도 이전 응답과 구분한다.
        generation = UUID()
        cancelEnrichment()
        descriptionTask?.cancel()
        descriptionTask = nil
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
        let request: Observable<BookSearchPage> = rxAsync { [repository] in
            switch mode {
            case .list(.popular):
                let books = try await repository.fetchPopularBooks()
                return BookSearchPage(books: books, totalResults: books.count, isEnd: true)
            case .list(.trending):
                let books = try await repository.fetchTrendingBooks()
                return BookSearchPage(books: books, totalResults: books.count, isEnd: true)
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

    private func receive(_ result: BookSearchPage, mode: DisplayMode, page: Int) {
        if page == 1 { totalCount = min(max(result.totalResults, 0), mode.maximumCount) }
        let previous = page == 1 ? [] : updates.value.books
        let combined = Array((previous + result.books).prefix(totalCount))
        currentPage = page
        hasMorePages = !result.books.isEmpty
            && combined.count < totalCount
            && page * mode.pageSize < totalCount
        switch mode {
        case .list(.popular):
            hasMorePages = false
        case .list(.trending):
            hasMorePages = false
        case .search:
            // ISBN13이 없는 문서가 제외되어 페이지가 짧아져도 카카오의 종료값을 따른다.
            hasMorePages = hasMorePages && !result.isEnd
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

    private func updateEnrichmentWindow(visibleRows: [Int]) {
        guard case .list = mode, !isLoading.value, currentPage > 0 else { return }
        let books = updates.value.books
        let rows = Set(visibleRows.filter { books.indices.contains($0) }).sorted()
        guard let lastRow = rows.last else {
            pendingEnrichmentISBNs.removeAll()
            return
        }

        let nextRows = (lastRow + 1)..<min(lastRow + 6, books.count)
        var seenISBNs = Set<String>()
        // 표시 중인 행을 우선하고, 아직 시작하지 않은 요청은 최신 범위로 교체한다.
        pendingEnrichmentISBNs = (rows + Array(nextRows))
            .map { books[$0].isbn13 }
            .filter { seenISBNs.insert($0).inserted && !attemptedEnrichmentISBNs.contains($0) }
        scheduleEnrichment(generation: generation)
    }

    private func scheduleEnrichment(generation: UUID) {
        guard self.generation == generation else { return }
        while enrichmentTasks.count < maximumConcurrentEnrichments,
              !pendingEnrichmentISBNs.isEmpty {
            let isbn13 = pendingEnrichmentISBNs.removeFirst()
            attemptedEnrichmentISBNs.insert(isbn13)
            let task = Task { [weak self, repository] in
                let metadata = try? await repository.fetchListBookMetadata(isbn13: isbn13)
                guard let self else { return }
                self.finishEnrichment(
                    isbn13: isbn13,
                    metadata: Task.isCancelled ? nil : metadata,
                    generation: generation
                )
            }
            enrichmentTasks[isbn13] = task
        }
    }

    private func finishEnrichment(
        isbn13: String,
        metadata: BookListMetadata?,
        generation: UUID
    ) {
        guard self.generation == generation else { return }
        enrichmentTasks.removeValue(forKey: isbn13)

        if let metadata {
            var books = updates.value.books
            var changedRows: [Int] = []
            for index in books.indices where books[index].isbn13 == isbn13 {
                let original = books[index]
                let enriched = original.mergingListMetadata(from: metadata)
                guard original.coverURL != enriched.coverURL
                        || original.description != enriched.description else { continue }
                books[index] = enriched
                changedRows.append(index)
            }
            if !changedRows.isEmpty {
                updates.accept(.init(books: books, change: .reload(rows: changedRows)))
            }
        }

        scheduleEnrichment(generation: generation)
    }

    private func enrichDescription(for book: Book) {
        let requestGeneration = generation
        descriptionTask?.cancel()
        descriptionTask = Task { [weak self, repository] in
            let metadata: BookDetailMetadata?
            do {
                metadata = try await repository.fetchBookSupplement(isbn13: book.isbn13)
            } catch {
                metadata = nil
            }
            guard !Task.isCancelled,
                  let self,
                  self.generation == requestGeneration else { return }

            if let metadata,
               !metadata.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                var books = self.updates.value.books
                var changedRows: [Int] = []
                for index in books.indices where books[index].isbn13 == book.isbn13 {
                    let enriched = books[index].mergingDetailMetadata(from: metadata)
                    guard books[index].description != enriched.description else { continue }
                    books[index] = enriched
                    changedRows.append(index)
                }
                if !changedRows.isEmpty {
                    self.updates.accept(.init(books: books, change: .reload(rows: changedRows)))
                }
            }
            self.descriptionReady.accept(book.isbn13)
        }
    }

    private func cancelEnrichment() {
        pendingEnrichmentISBNs.removeAll()
        attemptedEnrichmentISBNs.removeAll()
        enrichmentTasks.values.forEach { $0.cancel() }
        enrichmentTasks.removeAll()
    }
}
