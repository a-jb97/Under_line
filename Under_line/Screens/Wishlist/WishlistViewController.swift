import UIKit
import SafariServices
import SnapKit
import RxSwift
import RxCocoa
import Toast

final class WishlistViewController: UIViewController, UITableViewDataSource {
    private let viewModel: WishlistViewModel
    private let disposeBag = DisposeBag()
    private let appeared = PublishRelay<Void>()
    private let purchase = PublishRelay<WishlistViewModel.PurchaseRequest>()
    private let disappeared = PublishRelay<Void>()
    private let deleteISBN = PublishRelay<String>()
    private var state = WishlistViewModel.State()
    private var items: [WishlistItem] = []
    private var expandedISBN: String?

    private let headerView = UIView()
    private let backButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        button.tintColor = UIColor.accent
        button.accessibilityLabel = "뒤로가기"
        button.accessibilityIdentifier = "wishlistBackButton"
        return button
    }()
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "도서 위시리스트"
        label.font = UIFont(name: "GowunBatang-Bold", size: 28) ?? .boldSystemFont(ofSize: 28)
        label.textColor = UIColor.accent
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.7
        return label
    }()
    private let searchBar = BookSearchBarView()
    private let tableView: UITableView = {
        let table = UITableView()
        table.backgroundColor = .clear
        table.separatorStyle = .none
        table.showsVerticalScrollIndicator = false
        table.clipsToBounds = false
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 120
        table.keyboardDismissMode = .onDrag
        table.accessibilityIdentifier = "wishlistTable"
        table.register(BookRowCell.self, forCellReuseIdentifier: BookRowCell.reuseID)
        return table
    }()
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

    init(repository: WishlistRepositoryProtocol = AppContainer.shared.wishlistRepository,
         purchaseService: BookPurchaseServiceProtocol = AppContainer.shared.bookPurchaseService) {
        viewModel = WishlistViewModel(repository: repository, purchaseService: purchaseService)
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

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        disappeared.accept(())
    }

    private func setupUI() {
        view.backgroundColor = UIColor.background
        // Add header last so expanding row shadows stay underneath it.
        [tableView, loadingIndicator, statusStack, headerView, searchBar].forEach { view.addSubview($0) }
        headerView.backgroundColor = UIColor.background
        headerView.addSubview(backButton)
        headerView.addSubview(titleLabel)
        headerView.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide)
            make.leading.trailing.equalToSuperview()
            make.height.equalTo(62)
        }
        backButton.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(12)
            make.centerY.equalToSuperview()
            make.size.equalTo(44)
        }
        titleLabel.snp.makeConstraints { make in
            make.leading.equalTo(backButton.snp.trailing).offset(4)
            make.trailing.lessThanOrEqualToSuperview().inset(24)
            make.centerY.equalToSuperview()
        }
        searchBar.snp.makeConstraints { make in
            make.top.equalTo(headerView.snp.bottom)
            make.leading.trailing.equalToSuperview().inset(24)
            make.height.equalTo(48)
        }
        tableView.snp.makeConstraints { make in
            make.top.equalTo(searchBar.snp.bottom).offset(8)
            make.leading.trailing.equalToSuperview().inset(16)
            make.bottom.equalTo(view.keyboardLayoutGuide.snp.top)
        }
        loadingIndicator.snp.makeConstraints { make in make.center.equalTo(tableView) }
        statusStack.snp.makeConstraints { make in
            make.center.equalTo(tableView)
            make.leading.greaterThanOrEqualToSuperview().offset(32)
            make.trailing.lessThanOrEqualToSuperview().inset(32)
        }
        retryButton.snp.makeConstraints { make in make.height.greaterThanOrEqualTo(44) }
    }

    private func bindViewModel() {
        tableView.rx.setDataSource(self).disposed(by: disposeBag)
        let output = viewModel.transform(input: .init(
            screenAppeared: appeared.asObservable(), retry: retryButton.rx.tap.asObservable(),
            searchQuery: searchBar.textField.rx.text.orEmpty.asObservable(),
            deleteISBN: deleteISBN.asObservable(), purchase: purchase.asObservable(),
            screenDisappeared: disappeared.asObservable()
        ))
        output.destination.emit(onNext: { [weak self] destination in
            guard let self, self.view.window != nil, self.presentedViewController == nil else { return }
            self.present(SFSafariViewController(url: destination.url), animated: true)
        }).disposed(by: disposeBag)
        output.state.drive(onNext: { [weak self] in self?.apply($0) }).disposed(by: disposeBag)
        output.message.emit(onNext: { [weak self] message in
            var style = ToastStyle()
            style.backgroundColor = UIColor.appPrimary.withAlphaComponent(0.9)
            style.messageFont = UIFont(name: "GowunBatang-Regular", size: 14) ?? .systemFont(ofSize: 14)
            self?.view.makeToast(message, duration: 1.2, position: .center, style: style)
        }).disposed(by: disposeBag)
        backButton.rx.tap.subscribe(onNext: { [weak self] in
            self?.navigationController?.popViewController(animated: true)
        }).disposed(by: disposeBag)
        searchBar.textField.rx.controlEvent(.editingDidEndOnExit).subscribe(onNext: { [weak self] in
            self?.searchBar.textField.resignFirstResponder()
        }).disposed(by: disposeBag)
        tableView.rx.itemSelected.subscribe(onNext: { [weak self] in self?.toggleDescription(at: $0) })
            .disposed(by: disposeBag)
    }

    private func apply(_ newState: WishlistViewModel.State) {
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
            if !queryChanged, !removed.isEmpty,
               oldItems.filter({ remainingISBNs.contains($0.isbn13) }) == items {
                UIView.performWithoutAnimation {
                    tableView.deleteRows(at: removed.map { IndexPath(row: $0, section: 0) }, with: .none)
                }
            } else {
                tableView.reloadData()
            }
            tableView.layoutIfNeeded()
            if !queryChanged {
                let minY = -tableView.adjustedContentInset.top
                let maxY = max(minY, tableView.contentSize.height - tableView.bounds.height + tableView.adjustedContentInset.bottom)
                tableView.setContentOffset(CGPoint(x: offset.x, y: min(max(offset.y, minY), maxY)), animated: false)
            }
        }
        if queryChanged { tableView.setContentOffset(.zero, animated: false) }
        for case let cell as BookRowCell in tableView.visibleCells {
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

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { items.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = items[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: BookRowCell.reuseID, for: indexPath) as! BookRowCell
        cell.configure(
            content: BookRowContent(item: item), displayScale: view.traitCollection.displayScale,
            descriptionWidth: max(tableView.bounds.width - 48, 1),
            isExpanded: expandedISBN == item.isbn13, isDescriptionLoading: false,
            primaryAction: .purchase, wishlistAction: wishlistAction(for: item.isbn13)
        )
        cell.onPrimaryAction = { [weak self] isbn in
            guard let self, self.presentedViewController == nil else { return }
            let menu = UIAlertController(title: "구매할 서점", message: nil, preferredStyle: .alert)
            menu.addAction(UIAlertAction(title: "YES24에서 검색", style: .default) { [weak self, weak menu] _ in
                menu?.dismiss(animated: true) {
                    self?.purchase.accept(.init(isbn13: isbn, store: .yes24))
                }
            })
            menu.addAction(UIAlertAction(title: "취소", style: .cancel))
            self.present(menu, animated: true)
        }
        cell.onToggleWishlist = { [weak self] in self?.deleteISBN.accept($0) }
        return cell
    }

    private func toggleDescription(at indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        guard items.indices.contains(indexPath.row) else { return }
        let isbn13 = items[indexPath.row].isbn13
        expandedISBN = expandedISBN == isbn13 ? nil : isbn13
        for case let cell as BookRowCell in tableView.visibleCells {
            cell.setExpanded(cell.isbn13 == expandedISBN)
        }
        tableView.performBatchUpdates(nil)
    }
}
