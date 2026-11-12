import Foundation
import RxSwift
import RxCocoa

final class WishlistViewModel {
    struct PurchaseRequest {
        let isbn13: String
        let store: BookStore
    }

    struct Input {
        let screenAppeared: Observable<Void>
        let retry: Observable<Void>
        let searchQuery: Observable<String>
        let deleteISBN: Observable<String>
        var purchase: Observable<PurchaseRequest> = .empty()
        var screenDisappeared: Observable<Void> = .empty()
    }

    struct State: Equatable {
        var allItems: [WishlistItem] = []
        var query = ""
        var isLoading = false
        var hasLoaded = false
        var loadError: String?
        var deletingISBNs: Set<String> = []

        var items: [WishlistItem] {
            guard !query.isEmpty else { return allItems }
            return allItems.filter {
                $0.title.localizedCaseInsensitiveContains(query)
                    || $0.author.localizedCaseInsensitiveContains(query)
            }
        }

        var emptyMessage: String? {
            guard hasLoaded, !isLoading, loadError == nil, items.isEmpty else { return nil }
            return allItems.isEmpty ? "위시리스트에 담은 도서가 없습니다" : "검색 결과가 없습니다"
        }
    }

    struct Output {
        let state: Driver<State>
        let message: Signal<String>
        let destination: Signal<BookPurchaseDestination>
    }

    private let purchaseService: BookPurchaseServiceProtocol
    private let destination = PublishRelay<BookPurchaseDestination>()
    private let purchaseRequest = SerialDisposable()
    private var purchaseID: UUID?
    private let repository: WishlistRepositoryProtocol
    private let state = BehaviorRelay<State>(value: State())
    private let message = PublishRelay<String>()
    private let disposeBag = DisposeBag()
    private let loadRequest = SerialDisposable()
    private var loadID = UUID()
    private var needsReload = false

    init(repository: WishlistRepositoryProtocol, purchaseService: BookPurchaseServiceProtocol = AppContainer.shared.bookPurchaseService) {
        self.purchaseService = purchaseService
        purchaseRequest.disposed(by: disposeBag)
        self.repository = repository
        loadRequest.disposed(by: disposeBag)
    }

    func transform(input: Input) -> Output {
        input.searchQuery
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .distinctUntilChanged()
            .subscribe(onNext: { [weak self] query in
                guard let self else { return }
                var state = self.state.value
                state.query = query
                self.state.accept(state)
            })
            .disposed(by: disposeBag)

        Observable.merge(input.screenAppeared, input.retry)
            .subscribe(onNext: { [weak self] in self?.reload() })
            .disposed(by: disposeBag)

        input.deleteISBN
            .subscribe(onNext: { [weak self] in self?.deleteItem(isbn13: $0) })
            .disposed(by: disposeBag)

        input.purchase.subscribe(onNext: { [weak self] request in
            self?.purchase(request)
        }).disposed(by: disposeBag)
        input.screenDisappeared.subscribe(onNext: { [weak self] in
            self?.purchaseID = nil
            self?.purchaseRequest.disposable = Disposables.create()
        }).disposed(by: disposeBag)

        return Output(state: state.distinctUntilChanged().asDriver(onErrorDriveWith: .empty()),
                      message: message.asSignal(), destination: destination.asSignal())
    }

    private func purchase(_ request: PurchaseRequest) {
        guard purchaseID == nil else { return }
        let id = UUID()
        purchaseID = id
        purchaseRequest.disposable = rxAsync { [purchaseService] in
            try await purchaseService.purchaseDestination(isbn13: request.isbn13, store: request.store)
        }.subscribe(onNext: { [weak self] result in
            guard let self, self.purchaseID == id else { return }
            self.purchaseID = nil
            self.destination.accept(result)
        }, onError: { [weak self] error in
            guard let self, self.purchaseID == id else { return }
            self.purchaseID = nil
            guard !(error is CancellationError) else { return }
            self.message.accept(error as? BookPurchaseError == .invalidISBN
                ? "올바른 ISBN13이 아닙니다." : "구매 페이지를 열 수 없습니다. 다시 시도해주세요.")
        })
    }

    private func reload() {
        guard state.value.deletingISBNs.isEmpty else {
            needsReload = true
            return
        }
        needsReload = false
        let requestID = UUID()
        loadID = requestID
        var value = state.value
        value.isLoading = true
        value.loadError = nil
        state.accept(value)
        loadRequest.disposable = rxAsync { [repository] in
            let items = try await repository.fetchAllItems()
            try Task.checkCancellation()
            return items
        }
        .subscribe(onNext: { [weak self] items in
            guard let self, self.loadID == requestID else { return }
            var value = self.state.value
            value.allItems = items
            value.isLoading = false
            value.hasLoaded = true
            self.state.accept(value)
        }, onError: { [weak self] error in
            guard let self, self.loadID == requestID else { return }
            var value = self.state.value
            value.isLoading = false
            value.loadError = error.localizedDescription
            self.state.accept(value)
            if !value.items.isEmpty { self.message.accept(error.localizedDescription) }
        })
    }

    private func deleteItem(isbn13: String) {
        var value = state.value
        guard value.hasLoaded, !value.isLoading,
              value.allItems.contains(where: { $0.isbn13 == isbn13 }),
              !value.deletingISBNs.contains(isbn13) else { return }
        value.deletingISBNs.insert(isbn13)
        state.accept(value)
        rxAsync { [repository] in try await repository.deleteBook(isbn13: isbn13) }
            .subscribe(onNext: { [weak self] in
                self?.finishDeletion(isbn13: isbn13)
            }, onError: { [weak self] error in
                self?.finishDeletion(isbn13: isbn13, error: error)
            })
            .disposed(by: disposeBag)
    }

    private func finishDeletion(isbn13: String, error: Error? = nil) {
        var value = state.value
        value.deletingISBNs.remove(isbn13)
        if error == nil { value.allItems.removeAll { $0.isbn13 == isbn13 } }
        state.accept(value)
        message.accept(error?.localizedDescription ?? "위시리스트에서 삭제했습니다.")
        if needsReload, value.deletingISBNs.isEmpty { reload() }
    }
}
