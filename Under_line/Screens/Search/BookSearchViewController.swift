//
//  BookSearchViewController.swift
//  Under_line
//
//  FAB 탭 시 present되는 도서 등록 검색 시트 (Node 588fl)
//

import UIKit
import SnapKit
import RxSwift
import RxCocoa
import Kingfisher
import Toast

final class BookSearchViewController: UIViewController {

    // MARK: - Properties

    private let disposeBag = DisposeBag()
    private let viewModel = BookSearchViewModel(
        repository: AppContainer.shared.bookRepository,
        wishlistRepository: AppContainer.shared.wishlistRepository
    )
    private let screenAppearedRelay = PublishRelay<Void>()
    private let toggleWishlistRelay = PublishRelay<Book>()
    private var wishlistState = BookSearchViewModel.WishlistState()
    private var registeredISBNs: Set<String> = []
    private let loadNextPageRelay  = PublishRelay<Void>()
    private let registerBookRelay  = PublishRelay<Book>()
    private let descriptionBookRelay = PublishRelay<Book>()
    private let visibleRowsRelay = PublishRelay<[Int]>()
    private let listSelectionRelay = PublishRelay<BookSearchViewModel.BookListType>()

    private let coverPrefetcher = BookCoverPrefetcher()
    private var isScreenVisible = false
    private var isLoadingBooks = false
    private var prefetchUpdateScheduled = false
    private var enrichmentUpdateScheduled = false
    private var paginationUpdateScheduled = false
    private var paginationGate = BookSearchPaginationGate()
    private var isLoadingNextPage = false
    private var expandedRow: Int?
    private var descriptionLoadingISBN: String?
    private lazy var bookDataSource: BookSearchTableDataSource = BookSearchTableDataSource { [weak self] tableView, indexPath, book in
        let cell = tableView.dequeueReusableCell(withIdentifier: BookRowCell.reuseID, for: indexPath) as! BookRowCell
        #if DEBUG
        cell.performanceBatchID = self?.performanceBatchID
        #endif
        cell.configure(
            content: BookRowContent(book: book),
            displayScale: self?.view.traitCollection.displayScale ?? 1,
            descriptionWidth: max(tableView.bounds.width - 48, 1),
            isExpanded: self?.expandedRow == indexPath.row,
            isDescriptionLoading: self?.descriptionLoadingISBN == book.isbn13,
            primaryAction: .registration(isRegistered: self?.registeredISBNs.contains(book.isbn13.trimmingCharacters(in: .whitespacesAndNewlines)) ?? false),
            wishlistAction: self?.wishlistAction(for: book.isbn13) ?? .wishlist(isSaved: false, isEnabled: false)
        )
        cell.onPrimaryAction = { [weak self] isbn13 in
            guard let self, let book = self.bookDataSource.books.first(where: {
                $0.isbn13.trimmingCharacters(in: .whitespacesAndNewlines) == isbn13
            }) else { return }
            self.registerBookRelay.accept(book)
        }
        cell.onToggleWishlist = { [weak self] isbn13 in
            guard let self, let book = self.bookDataSource.books.first(where: {
                $0.isbn13.trimmingCharacters(in: .whitespacesAndNewlines) == isbn13
            }) else { return }
            self.toggleWishlistRelay.accept(book)
        }
        return cell
    }

    #if DEBUG
    private var firstCellDisplaySpan: BookSearchPerformance.Span?
    private var performanceBatchID: UUID?
    private var firstMeasuredRow = 0
    #endif

    // MARK: - UI Components

    private let handleBar: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.walnut.withAlphaComponent(0.25)
        v.layer.cornerRadius = 2.5
        return v
    }()

    private let sheetTitleLabel: UILabel = {
        let l = UILabel()
        l.text = "도서 검색"
        l.font = UIFont(name: "GowunBatang-Bold", size: 22)
            ?? .systemFont(ofSize: 22, weight: .semibold)
        l.textColor = UIColor(hex: "#190e0b")
        return l
    }()

    private let searchBarView = BookSearchBarView()
    private var searchTextField: UITextField { searchBarView.textField }

    private let directRegisterButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.title = "직접 등록"
        config.baseForegroundColor = UIColor.walnut
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UIFont(name: "GoyangIlsan R", size: 14) ?? .systemFont(ofSize: 14)
            return outgoing
        }
        return UIButton(configuration: config)
    }()

    private let tableView: UITableView = {
        let tv = UITableView()
        tv.backgroundColor               = .clear
        tv.separatorStyle                = .none
        tv.showsVerticalScrollIndicator  = false
        tv.clipsToBounds                 = false
        tv.rowHeight                     = UITableView.automaticDimension
        tv.estimatedRowHeight            = 104
        tv.register(BookRowCell.self, forCellReuseIdentifier: BookRowCell.reuseID)
        return tv
    }()

    private let activityIndicator: UIActivityIndicatorView = {
        let ai = UIActivityIndicatorView(style: .medium)
        ai.color = UIColor.walnut
        ai.hidesWhenStopped = true
        return ai
    }()

    private let headerBackground: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.background
        return v
    }()

    private lazy var popularButton = makeListTabButton(title: "인기 대출 도서", selected: true)
    private lazy var trendingButton = makeListTabButton(title: "요즘 뜨는 책", selected: false)

    private lazy var listSegmentContainerView: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor(hex: "#E8E0DC")
        v.layer.cornerRadius = 15
        v.layer.shadowColor = UIColor(hex: "#b5a49e").cgColor
        v.layer.shadowOpacity = 1.0
        v.layer.shadowRadius = 7
        v.layer.shadowOffset = CGSize(width: 3, height: 3)
        return v
    }()

    private let loadMoreIndicator: UIActivityIndicatorView = {
        let ai = UIActivityIndicatorView(style: .medium)
        ai.color = UIColor.walnut
        ai.frame = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 48)
        ai.startAnimating()
        return ai
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupConstraints()
        bindViewModel()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        screenAppearedRelay.accept(())
        isScreenVisible = true
        scheduleCoverPrefetch()
        scheduleEnrichmentWindowUpdate()
        scheduleNextPageIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isScreenVisible = false
        visibleRowsRelay.accept([])
        coverPrefetcher.stop()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        scheduleCoverPrefetch()
        scheduleEnrichmentWindowUpdate()
        scheduleNextPageIfNeeded()
    }

    #if DEBUG
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        firstCellDisplaySpan?.finish(.notDisplayed)
        firstCellDisplaySpan = nil
    }
    #endif

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = UIColor.background

        view.addSubview(tableView)
        view.addSubview(activityIndicator)
        view.addSubview(headerBackground)   // tableView 위, 헤더 뷰 아래 → 오버플로 셀 차단

        view.addSubview(handleBar)
        view.addSubview(sheetTitleLabel)
        view.addSubview(directRegisterButton)

        view.addSubview(searchBarView)
        setupTableHeader()
    }

    private func setupTableHeader() {
        let container = UIView()
        container.backgroundColor = .clear
        listSegmentContainerView.addSubview(popularButton)
        listSegmentContainerView.addSubview(trendingButton)
        container.addSubview(listSegmentContainerView)
        listSegmentContainerView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(8)
            make.top.equalToSuperview().offset(10)
            make.bottom.equalToSuperview().inset(6)
            make.height.equalTo(34)
        }
        popularButton.snp.makeConstraints { make in
            make.leading.top.bottom.equalToSuperview().inset(3)
            make.width.equalTo(94)
        }
        trendingButton.snp.makeConstraints { make in
            make.leading.equalTo(popularButton.snp.trailing)
            make.trailing.top.bottom.equalToSuperview().inset(3)
            make.width.equalTo(popularButton)
        }
        container.frame = CGRect(x: 0, y: 0, width: 0, height: 50)
        tableView.tableHeaderView = container
    }

    private func setupConstraints() {
        handleBar.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(12)
            make.centerX.equalToSuperview()
            make.width.equalTo(36)
            make.height.equalTo(5)
        }

        sheetTitleLabel.snp.makeConstraints { make in
            make.top.equalTo(handleBar.snp.bottom).offset(11)
            make.leading.equalToSuperview().inset(24)
            make.trailing.lessThanOrEqualTo(directRegisterButton.snp.leading).offset(-12)
            make.height.equalTo(52)
        }

        directRegisterButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(24)
            make.centerY.equalTo(sheetTitleLabel)
        }

        searchBarView.snp.makeConstraints { make in
            make.top.equalTo(sheetTitleLabel.snp.bottom)
            make.leading.trailing.equalToSuperview().inset(24)
            make.height.equalTo(48)
        }

        tableView.snp.makeConstraints { make in
            make.top.equalTo(searchBarView.snp.bottom)
            // 카드의 실제 좌우 여백은 24pt로 유지하면서 그림자 공간 8pt를
            // 테이블 내부에 둔다. 행 높이 변경 중 UIKit이 셀 경계를 클리핑해도
            // 그림자가 잘리지 않는다.
            make.leading.trailing.equalToSuperview().inset(16)
            make.bottom.equalTo(view.safeAreaLayoutGuide)
        }

        activityIndicator.snp.makeConstraints { make in
            make.center.equalTo(tableView)
        }

        headerBackground.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.bottom.equalTo(searchBarView.snp.bottom)
        }
    }

    // MARK: - Bindings

    private func bindViewModel() {
        let input = BookSearchViewModel.Input(
            viewDidLoad:   .just(()),
            listSelection: listSelectionRelay.asObservable(),
            searchQuery:   searchTextField.rx.text.orEmpty.asObservable(),
            searchTrigger: searchTextField.rx.controlEvent(.editingDidEndOnExit).asObservable(),
            loadNextPage:  loadNextPageRelay.asObservable(),
            visibleRows: visibleRowsRelay.asObservable(),
            descriptionBook: descriptionBookRelay.asObservable(),
            registerBook: registerBookRelay.asObservable(),
            screenAppeared: screenAppearedRelay.asObservable(),
            toggleWishlist: toggleWishlistRelay.asObservable()
        )

        let output = viewModel.transform(input: input)

        tableView.rx.setDataSource(bookDataSource)
            .disposed(by: disposeBag)

        #if DEBUG
        tableView.rx.willDisplayCell
            .subscribe(onNext: { [weak self] _, indexPath in
                guard let self, indexPath.row >= self.firstMeasuredRow else { return }
                self.firstCellDisplaySpan?.finish(count: self.bookDataSource.books.count)
                self.firstCellDisplaySpan = nil
            })
            .disposed(by: disposeBag)
        #endif

        output.listUpdates
            .drive(onNext: { [weak self] update in
                guard let self else { return }
                #if DEBUG
                switch update.change {
                case .replace:
                    self.firstCellDisplaySpan?.finish(.superseded)
                    let batchID = UUID()
                    self.performanceBatchID = batchID
                    self.firstMeasuredRow = 0
                    self.firstCellDisplaySpan = update.books.isEmpty ? nil : BookSearchPerformance.Span(
                        .firstCellWillDisplay, source: .table, id: batchID
                    )
                case .append(let start):
                    self.firstCellDisplaySpan?.finish(.superseded)
                    let batchID = UUID()
                    self.performanceBatchID = batchID
                    self.firstMeasuredRow = start == self.bookDataSource.books.count && start < update.books.count ? start : 0
                    self.firstCellDisplaySpan = update.books.isEmpty ? nil : BookSearchPerformance.Span(
                        .firstCellWillDisplay, source: .table, id: batchID
                    )
                case .reload:
                    break
                }
                #endif
                if case .replace = update.change {
                    self.expandedRow = nil
                    self.descriptionLoadingISBN = nil
                    self.coverPrefetcher.stop()
                }
                if case .reload = update.change {
                    // ISBN 보완은 페이지 상태를 변경하지 않는다.
                } else {
                    self.paginationGate.listDidUpdate()
                }
                self.bookDataSource.apply(update, to: self.tableView)
                self.scheduleCoverPrefetch()
                self.scheduleEnrichmentWindowUpdate()
                self.scheduleNextPageIfNeeded()
            })
            .disposed(by: disposeBag)

        output.isLoading
            .do(onNext: { [weak self] loading in
                guard let self else { return }
                self.isLoadingBooks = loading
                if loading {
                    self.coverPrefetcher.stop()
                } else {
                    self.scheduleCoverPrefetch()
                    self.scheduleEnrichmentWindowUpdate()
                    self.scheduleNextPageIfNeeded()
                }
            })
            .drive(activityIndicator.rx.isAnimating)
            .disposed(by: disposeBag)

        output.isLoadingMore
            .drive(onNext: { [weak self] loading in
                guard let self else { return }
                self.isLoadingNextPage = loading
                self.tableView.tableFooterView = loading ? self.loadMoreIndicator : UIView()
                if !loading { self.scheduleNextPageIfNeeded() }
            })
            .disposed(by: disposeBag)

        output.registeredISBNs
            .drive(onNext: { [weak self] isbn13s in
                guard let self else { return }
                self.registeredISBNs = isbn13s
                for case let cell as BookRowCell in self.tableView.visibleCells {
                    cell.setPrimaryAction(.registration(isRegistered: cell.isbn13.map { isbn13s.contains($0) } ?? false))
                }
            })
            .disposed(by: disposeBag)

        output.wishlistState
            .drive(onNext: { [weak self] state in
                guard let self else { return }
                self.wishlistState = state
                for case let cell as BookRowCell in self.tableView.visibleCells {
                    cell.setWishlistAction(self.wishlistAction(for: cell.isbn13 ?? ""))
                }
            })
            .disposed(by: disposeBag)

        Signal.merge(output.errorMessage, output.wishlistMessage)
            .emit(onNext: { [weak self] message in
                var style = ToastStyle()
                style.backgroundColor = UIColor.appPrimary.withAlphaComponent(0.9)
                style.messageFont = UIFont(name: "GowunBatang-Regular", size: 14) ?? .systemFont(ofSize: 14)
                self?.view.makeToast(message, duration: 1.2, position: .center, style: style)
            })
            .disposed(by: disposeBag)

        output.descriptionReady
            .emit(onNext: { [weak self] isbn13 in
                guard let self,
                      let row = self.expandedRow,
                      self.bookDataSource.books.indices.contains(row),
                      self.bookDataSource.books[row].isbn13 == isbn13 else { return }
                self.descriptionLoadingISBN = nil
                let indexPath = IndexPath(row: row, section: 0)
                (self.tableView.cellForRow(at: indexPath) as? BookRowCell)?
                    .setDescriptionLoading(false)
                self.tableView.performBatchUpdates(nil)
            })
            .disposed(by: disposeBag)

        output.registerCompleted
            .emit(onNext: { [weak self] in
                self?.dismiss(animated: true)
            })
            .disposed(by: disposeBag)

        popularButton.rx.tap
            .subscribe(onNext: { [weak self] in
                self?.selectListTab(.popular)
                self?.listSelectionRelay.accept(.popular)
            })
            .disposed(by: disposeBag)

        trendingButton.rx.tap
            .subscribe(onNext: { [weak self] in
                self?.selectListTab(.trending)
                self?.listSelectionRelay.accept(.trending)
            })
            .disposed(by: disposeBag)

        tableView.rx.willDisplayCell
            .subscribe(onNext: { [weak self] _, _ in
                self?.scheduleCoverPrefetch()
                self?.scheduleEnrichmentWindowUpdate()
                self?.scheduleNextPageIfNeeded()
            })
            .disposed(by: disposeBag)

        tableView.rx.itemSelected
            .subscribe(onNext: { [weak self] indexPath in
                self?.toggleBookDescription(at: indexPath)
            })
            .disposed(by: disposeBag)

        // 검색 버튼 탭 시 헤더 영구 숨김 (dismiss 전까지 복원 안 함)
        searchTextField.rx.controlEvent(.editingDidEndOnExit)
            .take(1)
            .subscribe(onNext: { [weak self] in
                guard let self, let header = self.tableView.tableHeaderView else { return }
                self.listSegmentContainerView.isHidden = true
                header.frame.size.height = 0
                self.tableView.tableHeaderView = header
            })
            .disposed(by: disposeBag)

        // 검색 시 테이블뷰 최상단으로 스크롤
        searchTextField.rx.controlEvent(.editingDidEndOnExit)
            .subscribe(onNext: { [weak self] in
                self?.tableView.setContentOffset(.zero, animated: false)
            })
            .disposed(by: disposeBag)

        // 스크롤 시 키보드 내리기
        tableView.rx.didScroll
            .subscribe(onNext: { [weak self] in
                self?.view.endEditing(false)
                self?.scheduleCoverPrefetch()
                self?.scheduleEnrichmentWindowUpdate()
                self?.scheduleNextPageIfNeeded()
            })
            .disposed(by: disposeBag)

        // 직접 등록 버튼
        directRegisterButton.rx.tap
            .subscribe(onNext: { [weak self] in
                let vc = DirectRegisterViewController()
                if let sheet = vc.sheetPresentationController {
                    sheet.detents              = [.large()]
                    sheet.prefersGrabberVisible = false
                    sheet.preferredCornerRadius = 24
                }
                self?.present(vc, animated: true)
            })
            .disposed(by: disposeBag)
    }

    private func wishlistAction(for rawISBN: String) -> BookRowAction {
        let isbn13 = rawISBN.trimmingCharacters(in: .whitespacesAndNewlines)
        return .wishlist(
            isSaved: wishlistState.savedISBNs.contains(isbn13),
            isEnabled: wishlistState.isLoaded && !wishlistState.isRefreshing,
            isPending: wishlistState.pendingISBNs.contains(isbn13)
        )
    }

    // MARK: - Book Description

    private func toggleBookDescription(at indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)

        guard indexPath.row < bookDataSource.books.count,
              let selectedCell = tableView.cellForRow(at: indexPath) as? BookRowCell else { return }

        let previousRow = expandedRow
        expandedRow = previousRow == indexPath.row ? nil : indexPath.row
        descriptionLoadingISBN = expandedRow == nil
            ? nil
            : bookDataSource.books[indexPath.row].isbn13

        // reloadRows는 높이 애니메이션 중 셀을 교체하므로 그림자가 임시 행 경계에
        // 잘려 보인다. 기존 셀의 콘텐츠만 바꾸고 테이블에는 높이 재계산만 요청한다.
        if let previousRow, previousRow != indexPath.row {
            let previousIndexPath = IndexPath(row: previousRow, section: indexPath.section)
            (tableView.cellForRow(at: previousIndexPath) as? BookRowCell)?.setExpanded(false)
        }
        if expandedRow == indexPath.row {
            selectedCell.setDescriptionLoading(true)
            descriptionBookRelay.accept(bookDataSource.books[indexPath.row])
        } else {
            selectedCell.setExpanded(false)
        }
        tableView.performBatchUpdates(nil)
    }

    // MARK: - Pagination

    private func scheduleNextPageIfNeeded() {
        guard isScreenVisible, !paginationUpdateScheduled else { return }
        paginationUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.paginationUpdateScheduled = false
            guard self.isScreenVisible else { return }
            let shouldRequest = self.paginationGate.shouldRequest(
                lastVisibleRow: self.tableView.indexPathsForVisibleRows?.map(\.row).max(),
                rowCount: self.bookDataSource.books.count,
                isLoading: self.isLoadingBooks || self.isLoadingNextPage
            )
            if shouldRequest { self.loadNextPageRelay.accept(()) }
        }
    }

    // MARK: - Cover Prefetch

    private func scheduleCoverPrefetch() {
        guard isScreenVisible, !isLoadingBooks, !prefetchUpdateScheduled else { return }
        prefetchUpdateScheduled = true
        // 같은 레이아웃에서 발생한 여러 willDisplay/scroll 이벤트를 한 번으로 합친다.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.prefetchUpdateScheduled = false
            guard self.isScreenVisible, !self.isLoadingBooks else { return }
            guard let lastVisibleRow = self.tableView.indexPathsForVisibleRows?.map(\.row).max() else {
                self.coverPrefetcher.stop()
                return
            }
            self.coverPrefetcher.update(
                books: self.bookDataSource.books, after: lastVisibleRow,
                displayScale: self.view.traitCollection.displayScale
            )
        }
    }

    // MARK: - List Metadata

    private func scheduleEnrichmentWindowUpdate() {
        guard isScreenVisible, !isLoadingBooks, !enrichmentUpdateScheduled else { return }
        enrichmentUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.enrichmentUpdateScheduled = false
            guard self.isScreenVisible, !self.isLoadingBooks else { return }
            self.visibleRowsRelay.accept(self.tableView.indexPathsForVisibleRows?.map(\.row) ?? [])
        }
    }

    // MARK: - List Segment

    private func selectListTab(_ listType: BookSearchViewModel.BookListType) {
        applyListTabStyle(to: popularButton, selected: listType == .popular)
        applyListTabStyle(to: trendingButton, selected: listType == .trending)
    }

    private func makeListTabButton(title: String, selected: Bool) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle(title, for: .normal)
        applyListTabStyle(to: btn, selected: selected)
        return btn
    }

    private func applyListTabStyle(to button: UIButton, selected: Bool) {
        var config = UIButton.Configuration.plain()
        config.title = button.configuration?.title ?? button.title(for: .normal)
        config.baseForegroundColor = selected ? UIColor.background : UIColor.appPrimary
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8)
        config.background.backgroundColor = selected ? UIColor.appPrimary : .clear
        config.background.cornerRadius = 11
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UIFont(name: "GoyangIlsan R", size: 11) ?? .systemFont(ofSize: 11)
            return outgoing
        }
        button.configuration = config
    }
}
