import UIKit
import SafariServices
import SnapKit
import RxSwift
import RxCocoa
import Toast

final class WishlistViewController: AdaptiveViewController, UITableViewDataSource, SFSafariViewControllerDelegate {
    override var avoidsKeyboard: Bool { true }

    func safariViewController(_ controller: SFSafariViewController, didCompleteInitialLoad didLoadSuccessfully: Bool) {
        guard !didLoadSuccessfully else { return }
        controller.dismiss(animated: true) { [weak self] in
            self?.view.makeToast("서점 웹페이지를 열 수 없습니다. 네트워크 연결을 확인하거나 다른 서점을 선택해주세요.",
                                 duration: 3, position: .center)
        }
    }

    private let viewModel: WishlistViewModel
    private let disposeBag = DisposeBag()
    private let appeared = PublishRelay<Void>()
    private let purchaseTap = PublishRelay<String>()
    private let purchase = PublishRelay<WishlistViewModel.PurchaseRequest>()
    private let disappeared = PublishRelay<Void>()
    private let deleteISBN = PublishRelay<String>()
    private var state = WishlistViewModel.State()
    private var tutorialExampleTask: Task<Void, Never>?
    private var tutorialActive = false
    private var pendingTutorialState: WishlistViewModel.State?
    private var items: [WishlistItem] = []
    private var expandedISBN: String?
    private var usesTwoColumns = false
    private var lastListWidth: CGFloat = 0
    private var isSynchronizingScroll = false
    private var leadingItemCount: Int { usesTwoColumns ? (items.count + 1) / 2 : items.count }

    private let searchBar = BookSearchBarView()
    private let listContainer = UIView()
    private let tableView = WishlistViewController.makeTableView(identifier: "wishlistTable")
    private let trailingTableView = WishlistViewController.makeTableView(identifier: "wishlistTrailingTable")

    private static func makeTableView(identifier: String) -> UITableView {
        let table = UITableView()
        table.backgroundColor = .clear
        table.separatorStyle = .none
        table.showsVerticalScrollIndicator = false
        table.clipsToBounds = false
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 120
        table.keyboardDismissMode = .onDrag
        table.alwaysBounceVertical = true
        table.accessibilityIdentifier = identifier
        table.contentInsetAdjustmentBehavior = .never
        table.register(BookRowCell.self, forCellReuseIdentifier: BookRowCell.reuseID)
        return table
    }
    private let loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.color = UIColor.walnut
        indicator.hidesWhenStopped = true
        return indicator
    }()
    private let statusLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont(name: "GoyangIlsan R", size: 15) ?? .systemFont(ofSize: 15)
        label.textColor = UIColor.walnut
        label.numberOfLines = 0
        label.textAlignment = .center
        label.accessibilityIdentifier = "wishlistStatusLabel"
        return label
    }()
    private let retryButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("다시 시도", for: .normal)
        button.tintColor = UIColor.accent
        button.titleLabel?.font = UIFont(name: "GoyangIlsan R", size: 15) ?? .systemFont(ofSize: 15)
        button.accessibilityIdentifier = "wishlistRetryButton"
        return button
    }()
    private lazy var statusStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [statusLabel, retryButton])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        return stack
    }()

    init(repository: WishlistRepositoryProtocol? = nil,
         purchaseService: BookPurchaseServiceProtocol? = nil) {
        viewModel = WishlistViewModel(
            repository: repository ?? AppContainer.shared.wishlistRepository,
            purchaseService: purchaseService
        )
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        bindViewModel()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        appeared.accept(())
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        showWishlistTutorial()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = listContainer.bounds.width
        // 펼친 iPhone의 가용 너비에서만 두 열을 사용한다. 기존 iPad 목록은 유지한다.
        let twoColumns = traitCollection.userInterfaceIdiom == .phone && width >= 568
        guard width > 0 else { return }
        let gap: CGFloat = twoColumns ? 16 : 0
        let columnWidth = twoColumns ? (width - gap) / 2 : width
        tableView.frame = CGRect(x: 0, y: 0, width: columnWidth, height: listContainer.bounds.height)
        trailingTableView.frame = CGRect(x: columnWidth + gap, y: 0,
                                         width: columnWidth, height: listContainer.bounds.height)
        updateCommonScrollRange()
        guard twoColumns != usesTwoColumns || width != lastListWidth else { return }
        let anchor = tableView.indexPathsForVisibleRows?.min().flatMap { indexPath in
            items.indices.contains(indexPath.row) ? items[indexPath.row].isbn13 : nil
        }
        usesTwoColumns = twoColumns
        lastListWidth = width
        trailingTableView.isHidden = !twoColumns
        trailingTableView.scrollsToTop = false
        reloadLists()
        updateCommonScrollRange()
        if let anchor, let index = items.firstIndex(where: { $0.isbn13 == anchor }) {
            let target = index < leadingItemCount ? tableView : trailingTableView
            let row = index < leadingItemCount ? index : index - leadingItemCount
            target.scrollToRow(at: IndexPath(row: row, section: 0), at: .top, animated: false)
        }
    }

    private func reloadLists() {
        tableView.reloadData()
        trailingTableView.reloadData()
    }

    private func updateCommonScrollRange() {
        let height = max(tableView.contentSize.height, trailingTableView.contentSize.height)
        isSynchronizingScroll = true
        defer { isSynchronizingScroll = false }
        for table in [tableView, trailingTableView] {
            // 짧은 열에도 같은 스크롤 범위를 주어 하단에서 두 열이 어긋나지 않게 한다.
            let bottom = usesTwoColumns ? max(0, height - table.contentSize.height) : 0
            if table.contentInset.bottom != bottom {
                table.contentInset.bottom = bottom
            }
        }
        if usesTwoColumns, trailingTableView.contentOffset != tableView.contentOffset {
            trailingTableView.setContentOffset(tableView.contentOffset, animated: false)
        }
    }

    private func synchronizeScroll(from source: UITableView) {
        guard usesTwoColumns, !isSynchronizingScroll else { return }
        let other = source === tableView ? trailingTableView : tableView
        guard other.contentOffset != source.contentOffset else { return }
        isSynchronizingScroll = true
        other.setContentOffset(source.contentOffset, animated: false)
        isSynchronizingScroll = false
    }

    private func showWishlistTutorial() {
        guard !tutorialActive, state.hasLoaded, view.window != nil, presentedViewController == nil,
              !UserDefaults.standard.bool(forKey: "tutorial.wishlist") else { return }
        tutorialActive = true
        if items.isEmpty {
            items = [WishlistItem(isbn13: "9780132350884", title: "튜토리얼 예시 도서", author: "예시", publisher: "", coverURL: nil,
                                  description: "도서 행을 탭하면 책소개를 펼칠 수 있어요", addedAt: Date())]
            reloadLists()
            tutorialExampleTask = Task { [weak self] in
                let model = BookshelfTutorialViewModel(repository: AppContainer.shared.bookRepository)
                await model.prepare()
                guard !Task.isCancelled, let self, self.tutorialActive, let book = model.books.first else { return }
                self.items = [WishlistItem(isbn13: book.isbn13, title: "튜토리얼 예시 · " + book.displayTitle,
                    author: book.author, publisher: book.publisher, coverURL: book.coverURL,
                    description: book.description, addedAt: Date())]
                self.reloadLists()
            }
        }
        tableView.layoutIfNeeded()
        let purchaseMessage: String
        switch AppContainer.shared.bookPurchasePreferenceStore.current {
        case .askEveryTime: purchaseMessage = "구매 버튼에서 서점을 선택해요"
        case .store(let store): purchaseMessage = "구매 버튼을 누르면 \(store.displayName)로 바로 연결돼요"
        }
        let steps = [
            TutorialStep(targetFrame: .zero, message: "제목이나 저자로 위시리스트를 검색해요", targetFrameProvider: { [weak self] in
                guard let bar = self?.searchBar else { return .zero }
                return bar.convert(bar.bounds, to: nil)
            }),
            TutorialStep(targetFrame: .zero, message: "도서를 탭해 책소개를 펼치고\n하트를 다시 눌러 목록에서 삭제할 수 있어요", targetFrameProvider: { [weak self] in
                guard let table = self?.listContainer else { return .zero }
                return table.convert(table.bounds, to: nil)
            }),
            TutorialStep(targetFrame: .zero, message: purchaseMessage + "\n상품 선택과 구매는 서점 웹페이지에서 진행해요", targetFrameProvider: { [weak self] in
                guard let self, let button = TutorialSupport.target(in: self.listContainer, identifier: "purchaseBookButton") else { return .zero }
                return button.convert(button.bounds, to: nil)
            })
        ]
        TutorialSupport.show(on: self, key: "tutorial.wishlist", steps: steps) { [weak self] in
            guard let self else { return }
            self.tutorialExampleTask?.cancel()
            self.tutorialActive = false
            self.items = []
            self.reloadLists()
            let latest = self.pendingTutorialState ?? self.state
            self.pendingTutorialState = nil
            self.apply(latest)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        disappeared.accept(())
    }

    private func setupUI() {
        SystemNavigationStyle.configure(self, title: "도서 위시리스트")
        view.backgroundColor = UIColor.background
        [listContainer, loadingIndicator, statusStack, searchBar].forEach { view.addSubview($0) }
        [tableView, trailingTableView].forEach { listContainer.addSubview($0) }
        trailingTableView.isHidden = true
        searchBar.snp.makeConstraints { make in
            make.top.equalTo(view.adaptiveContentLayoutGuide).offset(8)
            make.leading.trailing.equalTo(view.adaptiveContentLayoutGuide).inset(24)
            make.height.equalTo(48)
        }
        listContainer.snp.makeConstraints { make in
            make.top.equalTo(searchBar.snp.bottom).offset(8)
            make.leading.trailing.equalTo(view.adaptiveContentLayoutGuide).inset(16)
            make.bottom.equalTo(view.adaptiveContentLayoutGuide)
        }
        loadingIndicator.snp.makeConstraints { make in make.center.equalTo(listContainer) }
        statusStack.snp.makeConstraints { make in
            make.center.equalTo(listContainer)
            make.leading.greaterThanOrEqualToSuperview().offset(32)
            make.trailing.lessThanOrEqualToSuperview().inset(32)
        }
        retryButton.snp.makeConstraints { make in make.height.greaterThanOrEqualTo(44) }
    }

    private func bindViewModel() {
        tableView.rx.setDataSource(self).disposed(by: disposeBag)
        trailingTableView.rx.setDataSource(self).disposed(by: disposeBag)
        let output = viewModel.transform(input: .init(
            screenAppeared: appeared.asObservable(), retry: retryButton.rx.tap.asObservable(),
            searchQuery: searchBar.textField.rx.text.orEmpty.asObservable(),
            deleteISBN: deleteISBN.asObservable(), purchaseTap: purchaseTap.asObservable(), purchase: purchase.asObservable(),
            screenDisappeared: disappeared.asObservable()
        ))
        output.selectStore.emit(onNext: { [weak self] in self?.showPurchaseStores(isbn: $0) })
            .disposed(by: disposeBag)
        output.destination.emit(onNext: { [weak self] destination in
            guard let self, let window = self.view.window, self.presentedViewController == nil else { return }
            // 가로 크기 클래스가 regular인 분할 화면도 창 너비로 구분한다.
            let isNarrowWindow = window.bounds.width < window.screen.bounds.width - 1
            let usesMobilePage = self.traitCollection.userInterfaceIdiom == .phone || isNarrowWindow
            let url = usesMobilePage
                ? destination.mobileURL ?? destination.url : destination.url
            let safari = SFSafariViewController(url: url)
            safari.delegate = self
            self.present(safari, animated: true)
        }).disposed(by: disposeBag)
        output.state.drive(onNext: { [weak self] in self?.apply($0) }).disposed(by: disposeBag)
        output.message.emit(onNext: { [weak self] message in
            var style = ToastStyle()
            style.backgroundColor = UIColor.appPrimary.withAlphaComponent(0.9)
            style.messageFont = UIFont(name: "GowunBatang-Regular", size: 14) ?? .systemFont(ofSize: 14)
            self?.view.makeToast(message, duration: 1.2, position: .center, style: style)
        }).disposed(by: disposeBag)
        searchBar.textField.rx.controlEvent(.editingDidEndOnExit).subscribe(onNext: { [weak self] in
            self?.searchBar.textField.resignFirstResponder()
        }).disposed(by: disposeBag)
        for table in [tableView, trailingTableView] {
            table.rx.didScroll.subscribe(onNext: { [weak self, weak table] in
                guard let table else { return }
                self?.synchronizeScroll(from: table)
            }).disposed(by: disposeBag)
            table.rx.willBeginDragging.subscribe(onNext: { [weak self, weak table] in
                guard let self, let table, self.usesTwoColumns else { return }
                let other = table === self.tableView ? self.trailingTableView : self.tableView
                // 반대 열의 감속 중 새 드래그를 시작해도 두 스크롤 애니메이션이 경쟁하지 않게 한다.
                self.isSynchronizingScroll = true
                other.setContentOffset(table.contentOffset, animated: false)
                self.isSynchronizingScroll = false
            }).disposed(by: disposeBag)
            table.rx.observe(CGSize.self, "contentSize")
                .distinctUntilChanged()
                .observe(on: MainScheduler.asyncInstance)
                .subscribe(onNext: { [weak self] _ in self?.updateCommonScrollRange() })
                .disposed(by: disposeBag)
            table.rx.itemSelected.subscribe(onNext: { [weak self, weak table] indexPath in
                guard let table else { return }
                self?.toggleDescription(at: indexPath, in: table)
            }).disposed(by: disposeBag)
        }
    }

    private func apply(_ newState: WishlistViewModel.State) {
        if tutorialActive { pendingTutorialState = newState; return }
        defer { DispatchQueue.main.async { [weak self] in self?.showWishlistTutorial() } }
        let oldItems = items
        let queryChanged = state.query != newState.query
        let offset = tableView.contentOffset
        state = newState
        items = newState.items
        if let expandedISBN, !items.contains(where: { $0.isbn13 == expandedISBN }) {
            self.expandedISBN = nil
        }
        if oldItems != items {
            let remainingISBNs = Set(items.map(\.isbn13))
            let removed = oldItems.indices.filter { !remainingISBNs.contains(oldItems[$0].isbn13) }
            if !usesTwoColumns, !queryChanged, !removed.isEmpty,
               oldItems.filter({ remainingISBNs.contains($0.isbn13) }) == items {
                UIView.performWithoutAnimation {
                    tableView.deleteRows(at: removed.map { IndexPath(row: $0, section: 0) }, with: .none)
                }
            } else {
                reloadLists()
            }
            tableView.layoutIfNeeded()
            trailingTableView.layoutIfNeeded()
            updateCommonScrollRange()
            if !queryChanged {
                let minY = -tableView.adjustedContentInset.top
                let maxY = max(minY, tableView.contentSize.height - tableView.bounds.height + tableView.adjustedContentInset.bottom)
                tableView.setContentOffset(CGPoint(x: offset.x, y: min(max(offset.y, minY), maxY)), animated: false)
            }
        }
        if queryChanged {
            tableView.setContentOffset(.zero, animated: false)
            trailingTableView.setContentOffset(.zero, animated: false)
        }
        for case let cell as BookRowCell in tableView.visibleCells + trailingTableView.visibleCells {
            cell.setWishlistAction(wishlistAction(for: cell.isbn13 ?? ""))
        }
        if newState.isLoading { loadingIndicator.startAnimating() } else { loadingIndicator.stopAnimating() }
        let status = newState.isLoading ? nil : newState.loadError ?? newState.emptyMessage
        statusLabel.text = status
        statusStack.isHidden = status == nil || !items.isEmpty
        retryButton.isHidden = newState.loadError == nil
    }

    private func wishlistAction(for isbn13: String) -> BookRowAction {
        .wishlist(isSaved: true, isEnabled: !state.isLoading, isPending: state.deletingISBNs.contains(isbn13))
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        tableView === trailingTableView ? (usesTwoColumns ? items.count - leadingItemCount : 0) : leadingItemCount
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let index = indexPath.row + (tableView === trailingTableView ? leadingItemCount : 0)
        let item = items[index]
        let cell = tableView.dequeueReusableCell(withIdentifier: BookRowCell.reuseID, for: indexPath) as! BookRowCell
        cell.configure(
            content: BookRowContent(item: item), displayScale: view.traitCollection.displayScale,
            descriptionWidth: max(tableView.bounds.width - 48, 1),
            isExpanded: expandedISBN == item.isbn13, isDescriptionLoading: false,
            primaryAction: .purchase, wishlistAction: wishlistAction(for: item.isbn13)
        )
        cell.onPrimaryAction = { [weak self] isbn in
            self?.purchaseTap.accept(isbn)
        }
        cell.onToggleWishlist = { [weak self] in self?.deleteISBN.accept($0) }
        return cell
    }

    private func showPurchaseStores(isbn: String) {
        guard self.presentedViewController == nil else { return }
        let menu = UIAlertController(title: "구매하기", message: nil, preferredStyle: .alert)
        for store in [BookStore.kyobo, .aladin, .yes24] {
            menu.addAction(UIAlertAction(title: store.displayName, style: .default) { [weak self, weak menu] _ in
                menu?.dismiss(animated: true) {
                    self?.purchase.accept(.init(isbn13: isbn, store: store))
                }
            })
        }
        menu.addAction(UIAlertAction(title: "취소", style: .cancel))
        self.present(menu, animated: true)
    }

    private func toggleDescription(at indexPath: IndexPath, in table: UITableView) {
        table.deselectRow(at: indexPath, animated: false)
        let index = indexPath.row + (table === trailingTableView ? leadingItemCount : 0)
        guard items.indices.contains(index) else { return }
        let isbn13 = items[index].isbn13
        expandedISBN = expandedISBN == isbn13 ? nil : isbn13
        for case let cell as BookRowCell in tableView.visibleCells + trailingTableView.visibleCells {
            cell.setExpanded(cell.isbn13 == expandedISBN)
        }
        tableView.performBatchUpdates(nil)
        trailingTableView.performBatchUpdates(nil)
    }
}
