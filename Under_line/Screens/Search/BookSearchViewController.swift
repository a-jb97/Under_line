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
    private let viewModel  = BookSearchViewModel(repository: AppContainer.shared.bookRepository)
    private let loadNextPageRelay  = PublishRelay<Void>()
    private let registerBookRelay  = PublishRelay<Book>()
    private let listSelectionRelay = PublishRelay<BookSearchViewModel.BookListType>()

    private let coverPrefetcher = BookCoverPrefetcher()
    private var isScreenVisible = false
    private var isLoadingBooks = false
    private var prefetchUpdateScheduled = false
    private var paginationUpdateScheduled = false
    private var paginationGate = BookSearchPaginationGate()
    private var isLoadingNextPage = false
    private lazy var bookDataSource = BookSearchTableDataSource { [weak self] tableView, indexPath, book in
        let cell = tableView.dequeueReusableCell(withIdentifier: BookRowCell.reuseID, for: indexPath) as! BookRowCell
        #if DEBUG
        cell.performanceBatchID = self?.performanceBatchID
        #endif
        cell.configure(book: book, displayScale: self?.view.traitCollection.displayScale ?? 1)
        cell.onRegister = { [weak self] in self?.registerBookRelay.accept($0) }
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

    private let searchBarView: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.background
        v.layer.cornerRadius = 10
        v.layer.borderWidth  = 1
        v.layer.borderColor  = UIColor.walnut.cgColor
        return v
    }()

    private let searchIconView: UIImageView = {
        let iv = UIImageView()
        let cfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        iv.image = UIImage(systemName: "magnifyingglass", withConfiguration: cfg)
        iv.tintColor    = UIColor.walnut
        iv.contentMode  = .scaleAspectFit
        return iv
    }()

    private let searchTextField: UITextField = {
        let tf = UITextField()
        let placeholderFont = UIFont(name: "GoyangIlsan R", size: 14)
            ?? .systemFont(ofSize: 14)
        tf.attributedPlaceholder = NSAttributedString(
            string: "책 제목 또는 저자를 검색하세요",
            attributes: [
                .font:            placeholderFont,
                .foregroundColor: UIColor(hex: "#190e0b").withAlphaComponent(0.5),
            ]
        )
        tf.font            = placeholderFont
        tf.textColor       = UIColor(hex: "#190e0b")
        tf.backgroundColor = .clear
        tf.returnKeyType   = .search
        return tf
    }()

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

    private lazy var bestsellerButton = makeListTabButton(title: "베스트셀러 50", selected: true)
    private lazy var newSpecialButton = makeListTabButton(title: "추천 신간", selected: false)

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
        isScreenVisible = true
        scheduleCoverPrefetch()
        scheduleNextPageIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isScreenVisible = false
        coverPrefetcher.stop()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        scheduleCoverPrefetch()
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

        searchBarView.addSubview(searchIconView)
        searchBarView.addSubview(searchTextField)
        view.addSubview(searchBarView)
        setupTableHeader()
    }

    private func setupTableHeader() {
        let container = UIView()
        container.backgroundColor = .clear
        listSegmentContainerView.addSubview(bestsellerButton)
        listSegmentContainerView.addSubview(newSpecialButton)
        container.addSubview(listSegmentContainerView)
        listSegmentContainerView.snp.makeConstraints { make in
            make.leading.equalToSuperview()
            make.top.equalToSuperview().offset(10)
            make.bottom.equalToSuperview().inset(6)
            make.height.equalTo(34)
        }
        bestsellerButton.snp.makeConstraints { make in
            make.leading.top.bottom.equalToSuperview().inset(3)
            make.width.equalTo(94)
        }
        newSpecialButton.snp.makeConstraints { make in
            make.leading.equalTo(bestsellerButton.snp.trailing)
            make.trailing.top.bottom.equalToSuperview().inset(3)
            make.width.equalTo(bestsellerButton)
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

        searchIconView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(16)
            make.centerY.equalToSuperview()
            make.size.equalTo(18)
        }

        searchTextField.snp.makeConstraints { make in
            make.leading.equalTo(searchIconView.snp.trailing).offset(10)
            make.trailing.equalToSuperview().inset(16)
            make.centerY.equalToSuperview()
        }

        tableView.snp.makeConstraints { make in
            make.top.equalTo(searchBarView.snp.bottom)
            make.leading.trailing.equalToSuperview().inset(24)
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
            registerBook:  registerBookRelay.asObservable()
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
                self.firstCellDisplaySpan?.finish(.superseded)
                let batchID = UUID()
                self.performanceBatchID = batchID
                switch update.change {
                case .replace: self.firstMeasuredRow = 0
                case .append(let start):
                    self.firstMeasuredRow = start == self.bookDataSource.books.count && start < update.books.count ? start : 0
                }
                self.firstCellDisplaySpan = update.books.isEmpty ? nil : BookSearchPerformance.Span(
                    .firstCellWillDisplay, source: .table, id: batchID
                )
                #endif
                if case .replace = update.change { self.coverPrefetcher.stop() }
                self.paginationGate.listDidUpdate()
                self.bookDataSource.apply(update, to: self.tableView)
                self.scheduleCoverPrefetch()
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

        output.errorMessage
            .emit(onNext: { [weak self] message in
                var style = ToastStyle()
                style.backgroundColor = UIColor.appPrimary.withAlphaComponent(0.9)
                style.messageFont = UIFont(name: "GowunBatang-Regular", size: 14) ?? .systemFont(ofSize: 14)
                self?.view.makeToast(message, duration: 1.2, position: .center, style: style)
            })
            .disposed(by: disposeBag)

        output.registerCompleted
            .emit(onNext: { [weak self] in
                self?.dismiss(animated: true)
            })
            .disposed(by: disposeBag)

        bestsellerButton.rx.tap
            .subscribe(onNext: { [weak self] in
                self?.selectListTab(.bestseller)
                self?.listSelectionRelay.accept(.bestseller)
            })
            .disposed(by: disposeBag)

        newSpecialButton.rx.tap
            .subscribe(onNext: { [weak self] in
                self?.selectListTab(.newSpecial)
                self?.listSelectionRelay.accept(.newSpecial)
            })
            .disposed(by: disposeBag)

        tableView.rx.willDisplayCell
            .subscribe(onNext: { [weak self] _, _ in
                self?.scheduleCoverPrefetch()
                self?.scheduleNextPageIfNeeded()
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

    // MARK: - List Segment

    private func selectListTab(_ listType: BookSearchViewModel.BookListType) {
        applyListTabStyle(to: bestsellerButton, selected: listType == .bestseller)
        applyListTabStyle(to: newSpecialButton, selected: listType == .newSpecial)
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

// MARK: - BookRowCell

private final class BookRowCell: UITableViewCell {

    static let reuseID = "BookRowCell"

    // MARK: - UI

    private let cardView: UIView = {
        let v = UIView()
        v.backgroundColor     = UIColor.background
        v.layer.cornerRadius  = 16
        v.layer.masksToBounds = false
        v.layer.shadowColor   = UIColor(hex: "#5d4037").cgColor
        v.layer.shadowOpacity = Float(CGFloat(0x30) / 255)
        v.layer.shadowRadius  = 4
        v.layer.shadowOffset  = CGSize(width: 4, height: 4)
        return v
    }()

    private let rankLabel: UILabel = {
        let l = UILabel()
        l.font          = UIFont(name: "GoyangIlsan L", size: 18) ?? .boldSystemFont(ofSize: 18)
        l.textColor     = UIColor(hex: "#190e0b")
        l.textAlignment = .center
        l.setContentHuggingPriority(.required, for: .horizontal)
        return l
    }()

    private let thumbnailImageView: UIImageView = {
        let iv = UIImageView()
        iv.backgroundColor    = UIColor.walnut
        iv.layer.cornerRadius = 3
        iv.clipsToBounds      = true
        iv.contentMode        = .scaleAspectFill
        return iv
    }()

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.font          = UIFont(name: "GowunBatang-Regular", size: 16)
            ?? .systemFont(ofSize: 16, weight: .medium)
        l.textColor     = UIColor(hex: "#190e0b")
        l.numberOfLines = 2
        return l
    }()

    private let authorLabel: UILabel = {
        let l = UILabel()
        l.font      = UIFont(name: "GowunBatang-Regular", size: 13)
            ?? .systemFont(ofSize: 13)
        l.textColor = UIColor.walnut
        return l
    }()

    private let registerButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.title = "등록"
        config.baseForegroundColor = UIColor.walnut
        config.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 14, bottom: 7, trailing: 14)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UIFont(name: "GoyangIlsan R", size: 13) ?? .systemFont(ofSize: 13, weight: .medium)
            return outgoing
        }
        let btn = UIButton(configuration: config)
        btn.layer.cornerRadius = 7
        btn.layer.borderWidth  = 1
        btn.layer.borderColor  = UIColor.walnut.cgColor
        btn.setContentHuggingPriority(.required, for: .horizontal)
        btn.setContentCompressionResistancePriority(.required, for: .horizontal)
        return btn
    }()

    #if DEBUG
    var performanceBatchID: UUID?
    #endif

    var onRegister: ((Book) -> Void)?
    private var currentBook: Book?
    private let disposeBag = DisposeBag()

    private var rankVisible = true
    private var rankedLeading: Constraint?
    private var unrankedLeading: Constraint?
    private var lastShadowBounds: CGRect = .null

    // MARK: - Init

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupCell()
        registerButton.rx.tap
            .subscribe(onNext: { [weak self] in
                guard let self, let book = self.currentBook else { return }
                self.onRegister?(book)
            })
            .disposed(by: disposeBag)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        thumbnailImageView.kf.cancelDownloadTask()
        // 취소할 DownloadTask가 없는 디스크 캐시 조회도 이전 요청으로 처리되도록 초기화한다.
        thumbnailImageView.kf.setImage(with: Optional<URL>.none)
        currentBook = nil
        onRegister = nil
        rankLabel.text = nil
        titleLabel.text = nil
        authorLabel.text = nil
        #if DEBUG
        performanceBatchID = nil
        #endif
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let bounds = cardView.bounds
        guard bounds != lastShadowBounds else { return }
        lastShadowBounds = bounds
        cardView.layer.shadowPath = UIBezierPath(
            roundedRect: bounds, cornerRadius: cardView.layer.cornerRadius
        ).cgPath
    }

    // MARK: - Setup

    private func setupCell() {
        selectionStyle              = .none
        backgroundColor             = .clear
        contentView.backgroundColor = .clear
        contentView.clipsToBounds   = false

        contentView.addSubview(cardView)

        let textStack = UIStackView(arrangedSubviews: [titleLabel, authorLabel])
        textStack.axis    = .vertical
        textStack.spacing = 3

        [rankLabel, thumbnailImageView, textStack, registerButton].forEach {
            cardView.addSubview($0)
        }

        cardView.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(6)
            make.bottom.equalToSuperview().inset(6)
            make.leading.trailing.equalToSuperview()
            make.height.greaterThanOrEqualTo(80)
        }

        rankLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(16)
            make.centerY.equalToSuperview()
            make.width.equalTo(20)
        }

        thumbnailImageView.snp.prepareConstraints { make in
            unrankedLeading = make.leading.equalToSuperview().offset(16).constraint
        }
        thumbnailImageView.snp.makeConstraints { make in
            rankedLeading = make.leading.equalTo(rankLabel.snp.trailing).offset(14).constraint
            make.centerY.equalToSuperview()
            make.size.equalTo(BookCoverImageOptions.size)
        }

        textStack.snp.makeConstraints { make in
            make.leading.equalTo(thumbnailImageView.snp.trailing).offset(14)
            make.trailing.lessThanOrEqualTo(registerButton.snp.leading).offset(-14)
            make.centerY.equalToSuperview()
        }

        registerButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(16)
            make.centerY.equalToSuperview()
        }

    }

    // MARK: - Configure

    func configure(book: Book, displayScale: CGFloat) {
        thumbnailImageView.kf.cancelDownloadTask()
        let imageOptions = BookCoverImageOptions.make(displayScale: displayScale)
        currentBook      = book
        rankLabel.text   = book.bestRank.map { "\($0)" }
        titleLabel.text  = book.title
        authorLabel.text = book.author
        #if DEBUG
        let coverSpan = BookSearchPerformance.Span(.coverLoaded, source: .table, id: performanceBatchID ?? UUID())
        thumbnailImageView.kf.setImage(with: book.coverURL, options: imageOptions) { result in
            switch result {
            case .success(let value):
                let cache: BookSearchPerformance.Cache
                switch value.cacheType {
                case .none: cache = .none
                case .memory: cache = .memory
                case .disk: cache = .disk
                }
                coverSpan.finish(cache: cache)
            case .failure(let error):
                if book.coverURL == nil {
                    coverSpan.finish(.noURL)
                } else if error.isTaskCancelled {
                    coverSpan.finish(.cancelled)
                } else if error.isNotCurrentTask {
                    coverSpan.finish(.superseded)
                } else {
                    coverSpan.finish(.failed)
                }
            }
        }
        #else
        thumbnailImageView.kf.setImage(with: book.coverURL, options: imageOptions)
        #endif

        let showRank = book.bestRank != nil
        guard showRank != rankVisible else { return }
        rankVisible        = showRank
        rankLabel.isHidden = !showRank
        updateThumbnailLeading(showRank: showRank)
    }

    private func updateThumbnailLeading(showRank: Bool) {
        if showRank {
            unrankedLeading?.deactivate()
            rankedLeading?.activate()
        } else {
            rankedLeading?.deactivate()
            unrankedLeading?.activate()
        }
    }
}
