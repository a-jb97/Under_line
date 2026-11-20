//
//  BookshelfViewController.swift
//  Under_line
//
//  메인 화면 — 도서 (책장)
//

import UIKit
import SnapKit
import RxSwift
import RxCocoa
import Kingfisher
import Toast

final class BookshelfViewController: UIViewController {

    private let disposeBag      = DisposeBag()
    private let viewModel       = BookshelfViewModel(repository: AppContainer.shared.bookRepository)
    private let deleteBookRelay = PublishRelay<Book>()
    private let deleteAllRelay  = PublishRelay<Void>()
    private let reorderRelay    = PublishRelay<[String]>()

    private var layoutReady = false
    private let shelfContainerView: ContainerLayoutView = {
        let view = ContainerLayoutView()
        view.reservesInactiveDivisions = true
        return view
    }()
    private var lastContainerLayout: ContainerLayout?
    private var shelfLayout: BookshelfLayout?
    private var shelfPages: [ShelfPageView] = []
    private var displayedBookIDs: [String] = []
    private var isRebuildingShelf = false
    private var isEditMode = false

    // MARK: - Drag & Drop

    private struct DragState {
        var order: BookshelfReorderDraft
        var currentIndex: Int { order.currentIndex }
        let ghostView: UIView
        let touchOffsetInGhost: CGPoint
    }

    private var dragState: DragState?
    private var isDragging = false
    private var bookSlotFrames: [(globalIndex: Int, frameInScrollView: CGRect)] = []

    // 페이지 플립 (가장자리 드래그 → 인접 페이지 전환)
    private var pageFlipTimer: Timer?
    private var pageFlipDirection: Int = 0       // -1 = 왼쪽, 0 = 없음, +1 = 오른쪽
    private let pageFlipZoneWidth: CGFloat = 72  // 가장자리 감지 폭 (pt)
    private let pageFlipDelay: TimeInterval = 0.75

    // MARK: - Saved Books

    private var allBooks: [Book] = []
    private var activeFilterQuery: String?
    private let tutorialLoading = UIActivityIndicatorView(style: .medium)
    private var tutorialDeadlineTask: Task<Void, Never>?
    private var tutorialLoadTask: Task<Void, Never>?
    private var tutorialSession: UUID?
    private var tutorialBooks: [Book] = []

    private var savedBooks: [Book] = [] {
        didSet {
            guard layoutReady, !isRebuildingShelf else { return }
            rebuildShelfPages()
        }
    }

    private func applyFilter() {
        guard !isDragging else { return }
        if let query = activeFilterQuery, !query.isEmpty {
            savedBooks = allBooks.filter {
                $0.title.localizedCaseInsensitiveContains(query) ||
                ($0.author).localizedCaseInsensitiveContains(query)
            }
        } else {
            savedBooks = allBooks
        }
    }

    // MARK: - UI Components

    // 가로 막대에서는 기존 왼쪽 로고, 세로 막대에서는 콘텐츠 로고를 표시한다.
    private static func makeLogoView() -> UIImageView {
        let titleLabel = UILabel()
        titleLabel.text = "밑줄"
        titleLabel.font = UIFont(name: "GowunBatang-Bold", size: 34)
            ?? .systemFont(ofSize: 34, weight: .bold)
        let titleSize = titleLabel.intrinsicContentSize

        let imageView = UIImageView(image: UIImage(named: "Under_line_Logo"))
        imageView.contentMode = .scaleAspectFit
        imageView.snp.makeConstraints { make in
            make.size.equalTo(titleSize)
        }
        imageView.isAccessibilityElement = true
        imageView.accessibilityLabel = "밑줄"
        imageView.accessibilityTraits = [.image, .header]
        return imageView
    }

    private let appLogoView = BookshelfViewController.makeLogoView()
    private let contentLogoView = BookshelfViewController.makeLogoView()
    private let logoHeaderView = UIView()
    private var logoHeaderHeight: Constraint?
    private var usesContentLogo: Bool?
    private lazy var logoBarItem: UIBarButtonItem = {
        let item = UIBarButtonItem(customView: appLogoView)
        if #available(iOS 26.0, *) {
            item.hidesSharedBackground = true
        }
        return item
    }()

    private let sortButton = SystemNavigationStyle.item(
        image: "slider.horizontal.3", label: "정렬·필터", identifier: "sortButton"
    )

    private let wishlistButton = SystemNavigationStyle.item(
        image: "heart", label: "도서 위시리스트", identifier: "openWishlistButton", priority: .high
    )

    // 책장 수평 페이징 스크롤뷰
    private let bookshelfScrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.isPagingEnabled = true
        sv.showsHorizontalScrollIndicator = false
        sv.bounces = true
        return sv
    }()

    // 고정 선반 보드 오버레이 (스크롤되지 않는 나무 선반)
    private let shelfOverlayView: UIView = {
        let v = UIView()
        v.isUserInteractionEnabled = false
        v.backgroundColor = .clear
        return v
    }()

    // 페이지 컨트롤 (점 인디케이터)
    private let pageControl: UIPageControl = {
        let pc = UIPageControl()
        pc.numberOfPages = 1
        pc.currentPage   = 0
        pc.currentPageIndicatorTintColor = UIColor.appPrimary
        pc.pageIndicatorTintColor        = UIColor.appPrimary.withAlphaComponent(0.3)
        pc.transform = CGAffineTransform(scaleX: 0.75, y: 0.75)
        return pc
    }()

    // FAB (+) 버튼
    private lazy var fabButton: UIButton = {
        let btn = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        btn.setImage(UIImage(systemName: "plus", withConfiguration: cfg), for: .normal)
        btn.tintColor = UIColor.appPrimary
        return btn
    }()

    // 편집 버튼
    private lazy var editButton: UIButton = {
        let btn = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        btn.setImage(UIImage(systemName: "square.and.pencil", withConfiguration: cfg), for: .normal)
        btn.tintColor = UIColor.appPrimary
        return btn
    }()

    // 전부 삭제 버튼 컨테이너 (편집 모드일 때만 표시)
    private let deleteAllButtonContainer: UIView = {
        let v = UIView()
        v.isHidden = true
        return v
    }()

    private lazy var deleteAllButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle("전부 꺼내기", for: .normal)
        btn.setTitleColor(UIColor.systemRed, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        return btn
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupConstraints()
        updateLogoPlacement()
        SystemNavigationStyle.observeBarPlacement(on: self)
        shelfContainerView.onLayoutChange = { [weak self] _ in
            self?.view.setNeedsLayout()
        }
        bindActions()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        updateLogoPlacement()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        shelfContainerView.layoutIfNeeded()
        guard let container = shelfContainerView.containerLayout,
              container.bounds.width > 0, container.bounds.height > 0 else { return }
        guard !layoutReady || container != lastContainerLayout else { return }
        finishDrag(commit: false, rebuild: false)
        lastContainerLayout = container
        layoutReady = true
        rebuildShelfPages(layout: BookshelfLayout(container: container))
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        showTutorialIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        finishDrag(commit: false)
        guard !(presentedViewController is TutorialOverlayViewController) else { return }
        tutorialSession = nil
        tutorialLoadTask?.cancel()
        tutorialDeadlineTask?.cancel()
        tutorialLoading.removeFromSuperview()
        tutorialBooks = []
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        finishDrag(commit: false, rebuild: false)
        layoutReady = false
    }

    // MARK: - Setup

    private func setupUI() {
        SystemNavigationStyle.configure(self, title: "")
        SystemNavigationStyle.setTrailingItems([wishlistButton, sortButton], on: navigationItem)
        view.backgroundColor = UIColor.background

        view.addSubview(logoHeaderView)
        logoHeaderView.addSubview(contentLogoView)
        view.addSubview(shelfContainerView)
        shelfContainerView.addSubview(bookshelfScrollView)
        shelfContainerView.addSubview(shelfOverlayView)
        shelfContainerView.addSubview(pageControl)
        view.addSubview(fabButton)

        view.addSubview(editButton)

        view.addSubview(deleteAllButtonContainer)
        deleteAllButtonContainer.addSubview(deleteAllButton)

        SystemGlassButtonStyle.apply(to: fabButton, accessibilityLabel: "도서 추가")
        SystemGlassButtonStyle.apply(to: editButton, accessibilityLabel: "책장 편집")
        SystemGlassButtonStyle.apply(to: deleteAllButton, accessibilityLabel: "전부 꺼내기")
    }

    private func setupConstraints() {
        logoHeaderView.snp.makeConstraints { make in
            make.top.leading.trailing.equalTo(view.safeAreaLayoutGuide)
            logoHeaderHeight = make.height.equalTo(0).constraint
        }
        contentLogoView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(24)
            make.centerY.equalToSuperview()
        }

        fabButton.snp.makeConstraints { make in
            make.trailing.equalTo(view.safeAreaLayoutGuide).inset(24)
            make.bottom.equalTo(view.safeAreaLayoutGuide).inset(16)
            make.size.equalTo(52)
        }

        editButton.snp.makeConstraints { make in
            make.leading.equalTo(view.safeAreaLayoutGuide).offset(24)
            make.centerY.equalTo(fabButton)
            make.size.equalTo(52)
        }

        deleteAllButtonContainer.snp.makeConstraints { make in
            make.leading.equalTo(editButton.snp.trailing).offset(12)
            make.centerY.equalTo(editButton)
            make.trailing.lessThanOrEqualTo(fabButton.snp.leading).offset(-12)
            make.height.equalTo(52)
        }

        deleteAllButton.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        shelfContainerView.snp.makeConstraints { make in
            make.top.equalTo(logoHeaderView.snp.bottom)
            make.leading.trailing.equalTo(view.safeAreaLayoutGuide).inset(24)
            make.bottom.equalTo(fabButton.snp.top).offset(-16)
        }
        bookshelfScrollView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        shelfOverlayView.snp.makeConstraints { make in
            make.edges.equalTo(bookshelfScrollView)
        }
    }

    private func updateLogoPlacement() {
        let usesContentLogo = SystemNavigationStyle.usesVerticalBar(on: self)
        guard self.usesContentLogo != usesContentLogo else { return }
        self.usesContentLogo = usesContentLogo
        navigationItem.leftBarButtonItem = usesContentLogo ? nil : logoBarItem
        logoHeaderView.isHidden = !usesContentLogo
        let logoHeight = contentLogoView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).height
        logoHeaderHeight?.update(offset: usesContentLogo ? logoHeight + 16 : 0)
    }

    // MARK: - Shelf Pages

    private func rebuildShelfPages(layout newLayout: BookshelfLayout? = nil) {
        guard let layout = newLayout ?? shelfLayout else { return }
        let anchor = BookshelfPageAnchor(bookIDs: displayedBookIDs, page: pageControl.currentPage,
                                         capacity: shelfLayout?.capacity ?? 0)
        isRebuildingShelf = true
        defer { isRebuildingShelf = false }
        shelfLayout = layout
        let displayBooks = tutorialBooks.isEmpty ? savedBooks : Array(tutorialBooks.prefix(layout.capacity))
        let ids = displayBooks.map(\.isbn13)
        let pageCount = layout.pageCount(for: displayBooks.count)
        let page = isDragging
            ? min(pageControl.currentPage, pageCount - 1)
            : anchor.page(in: ids, capacity: layout.capacity)
        displayedBookIDs = ids
        pageControl.numberOfPages = pageCount
        pageControl.currentPage = page
        pageControl.isHidden = pageCount <= 1 || layout.paginationFrame.isEmpty
        pageControl.bounds.size = layout.paginationFrame.size
        pageControl.center = CGPoint(x: layout.paginationFrame.midX, y: layout.paginationFrame.midY)

        shelfPages.forEach { $0.removeFromSuperview() }
        shelfPages = []
        shelfOverlayView.subviews.forEach { $0.removeFromSuperview() }
        bookshelfScrollView.layer.removeAllAnimations()
        bookshelfScrollView.contentSize = CGSize(width: layout.bounds.width * CGFloat(pageCount), height: layout.bounds.height)
        bookshelfScrollView.setContentOffset(CGPoint(x: layout.bounds.width * CGFloat(page), y: 0), animated: false)
        guard layout.capacity > 0 else {
            bookSlotFrames = []
            return
        }
        for pageIndex in 0..<pageCount {
            let pageView = ShelfPageView(books: displayBooks, layout: layout, page: pageIndex,
                                         hiddenBookIndex: dragState?.currentIndex, isEditing: isEditMode,
                                         onDelete: { [weak self] book in self?.deleteBook(book) },
                                         onTap: { [weak self] book in
                self?.navigationController?.pushViewController(BookDetailViewController(book: book), animated: true)
            })
            pageView.frame = CGRect(x: layout.bounds.width * CGFloat(pageIndex), y: 0,
                                    width: layout.bounds.width, height: layout.bounds.height)
            bookshelfScrollView.addSubview(pageView)
            shelfPages.append(pageView)
        }
        bookSlotFrames = displayBooks.indices.compactMap { index in
            layout.frame(forBookAt: index).map { (globalIndex: index, frameInScrollView: $0) }
        }
        setupFixedShelfBoards(layout: layout)
    }

    /// 페이지 이동과 무관하게 고정하는 선반. 도서와 동일한 계산 결과를 사용한다.
    private func setupFixedShelfBoards(layout: BookshelfLayout) {
        for (index, boardFrame) in layout.boards.enumerated() {
            let shadowView = UIView(frame: boardFrame)
            shadowView.backgroundColor = .clear
            shadowView.layer.shadowColor = UIColor.black.cgColor
            shadowView.layer.shadowOpacity = 0.28
            shadowView.layer.shadowRadius = 4
            shadowView.layer.shadowOffset = CGSize(width: 2, height: 3)
            shadowView.layer.shadowPath = UIBezierPath(roundedRect: CGRect(origin: .zero, size: boardFrame.size), cornerRadius: 5).cgPath
            shelfOverlayView.addSubview(shadowView)
            let board = UIImageView(frame: boardFrame)
            board.image = UIImage(named: "Bookshelf\(index % 3 + 1)")
            board.contentMode = .scaleToFill
            board.layer.cornerRadius = 5
            board.clipsToBounds = true
            shelfOverlayView.addSubview(board)
        }
    }

    // MARK: - Drag & Drop

    private func dragBegan(_ recognizer: UIGestureRecognizer) {
        guard !isEditMode, tutorialBooks.isEmpty else { return }
        guard activeFilterQuery == nil || activeFilterQuery!.isEmpty else { return }

        let touchInScrollView = recognizer.location(in: bookshelfScrollView)
        guard let slot = bookSlotFrames.first(where: { $0.frameInScrollView.contains(touchInScrollView) }) else { return }

        guard savedBooks.indices.contains(slot.globalIndex),
              let order = BookshelfReorderDraft(bookIDs: savedBooks.map(\.isbn13), index: slot.globalIndex) else { return }
        let book = savedBooks[slot.globalIndex]
        let slotFrameInView = bookshelfScrollView.convert(slot.frameInScrollView, to: view)

        let ghost = makeGhostView(book: book, size: slot.frameInScrollView.size)
        ghost.frame = slotFrameInView
        view.addSubview(ghost)

        let touchInView = recognizer.location(in: view)
        let touchOffset = CGPoint(
            x: touchInView.x - slotFrameInView.midX,
            y: touchInView.y - slotFrameInView.midY
        )

        isDragging = true
        dragState = DragState(
            order: order,
            ghostView: ghost,
            touchOffsetInGhost: touchOffset
        )

        bookshelfScrollView.isScrollEnabled = false
        rebuildShelfPages()   // 빈 슬롯 표시

        UIView.animate(withDuration: 0.2, delay: 0,
                       usingSpringWithDamping: 0.7, initialSpringVelocity: 0,
                       options: [], animations: {
            ghost.transform = CGAffineTransform(scaleX: 1.12, y: 1.12)
            ghost.alpha = 0.88
        })
    }

    private func dragMoved(_ recognizer: UIGestureRecognizer) {
        guard var state = dragState else { return }

        let touchInView = recognizer.location(in: view)
        let ghostCenter = CGPoint(
            x: touchInView.x - state.touchOffsetInGhost.x,
            y: touchInView.y - state.touchOffsetInGhost.y
        )
        state.ghostView.center = ghostCenter

        // 현재 손가락이 어느 슬롯 위에 있는지 계산
        let ghostInScrollView = view.convert(ghostCenter, to: bookshelfScrollView)
        if let target = bookSlotFrames.first(where: { $0.frameInScrollView.contains(ghostInScrollView) }),
           target.globalIndex != state.currentIndex {
            state.order.move(to: target.globalIndex)
            let booksByID = savedBooks.reduce(into: [String: Book]()) { $0[$1.isbn13] = $1 }
            dragState = state
            savedBooks = state.order.bookIDs.compactMap { booksByID[$0] }
        } else {
            dragState = state
        }

        // 가장자리 감지 → 페이지 플립 타이머
        let svFrame = bookshelfScrollView.convert(bookshelfScrollView.bounds, to: view)
        let ghostX = state.ghostView.center.x
        let pageWidth = bookshelfScrollView.bounds.width
        guard pageWidth > 0 else { return }
        let currentPage = Int(round(bookshelfScrollView.contentOffset.x / pageWidth))
        let totalPages = pageControl.numberOfPages

        if ghostX < svFrame.minX + pageFlipZoneWidth, currentPage > 0 {
            startPageFlipTimer(direction: -1)
        } else if ghostX > svFrame.maxX - pageFlipZoneWidth, currentPage < totalPages - 1 {
            startPageFlipTimer(direction: +1)
        } else {
            cancelPageFlipTimer()
        }
    }

    private func finishDrag(commit: Bool, rebuild: Bool = true) {
        cancelPageFlipTimer()
        guard let state = dragState else { return }
        state.ghostView.removeFromSuperview()
        isDragging = false
        dragState = nil
        bookshelfScrollView.isScrollEnabled = true
        // 드래그 중 도서가 추가·삭제됐다면 마지막 확정 목록을 다시 표시한다.
        let result = state.order.finish(commit: commit, confirmedBookIDs: allBooks.map(\.isbn13))
        if !result.shouldSave {
            let wasReady = layoutReady
            layoutReady = false
            applyFilter()
            layoutReady = wasReady
        }
        if rebuild { rebuildShelfPages() }
        if result.shouldSave { reorderRelay.accept(result.bookIDs) }
    }

    private func startPageFlipTimer(direction: Int) {
        guard pageFlipDirection != direction || pageFlipTimer == nil else { return }
        cancelPageFlipTimer()
        pageFlipDirection = direction
        pageFlipTimer = Timer.scheduledTimer(withTimeInterval: pageFlipDelay, repeats: false) { [weak self] _ in
            self?.flipPage(direction: direction)
        }
    }

    private func cancelPageFlipTimer() {
        pageFlipTimer?.invalidate()
        pageFlipTimer = nil
        pageFlipDirection = 0
    }

    private func flipPage(direction: Int) {
        cancelPageFlipTimer()
        let pageWidth = bookshelfScrollView.bounds.width
        guard pageWidth > 0 else { return }
        let currentPage = Int(round(bookshelfScrollView.contentOffset.x / pageWidth))
        let targetPage = currentPage + direction
        guard targetPage >= 0, targetPage < pageControl.numberOfPages else { return }

        let targetOffset = CGPoint(x: pageWidth * CGFloat(targetPage), y: 0)
        UIView.animate(withDuration: 0.35, delay: 0, options: .curveEaseInOut) {
            self.bookshelfScrollView.contentOffset = targetOffset
        }
    }

    private func makeGhostView(book: Book, size: CGSize) -> UIView {
        let ghost = UIView()
        ghost.layer.cornerRadius = 3
        ghost.clipsToBounds = false
        ghost.layer.shadowColor   = UIColor.black.cgColor
        ghost.layer.shadowOpacity = 0.45
        ghost.layer.shadowRadius  = 12
        ghost.layer.shadowOffset  = CGSize(width: 0, height: 8)

        let imageView = UIImageView()
        imageView.contentMode    = .scaleAspectFit
        imageView.clipsToBounds  = true
        imageView.layer.cornerRadius = 3
        ghost.addSubview(imageView)
        ghost.bounds = CGRect(origin: .zero, size: size)

        let fitCover: (CGSize) -> Void = { [weak ghost, weak imageView] imageSize in
            guard imageSize.width > 0, imageSize.height > 0 else { return }
            let scale = min(size.width / imageSize.width, size.height / imageSize.height)
            let coverSize = CGSize(width: floor(imageSize.width * scale), height: floor(imageSize.height * scale))
            let coverFrame = CGRect(x: (size.width - coverSize.width) / 2,
                                    y: size.height - coverSize.height,
                                    width: coverSize.width, height: coverSize.height)
            imageView?.frame = coverFrame
            ghost?.layer.shadowPath = UIBezierPath(roundedRect: coverFrame, cornerRadius: 3).cgPath
        }
        fitCover(CGSize(width: 88, height: 117))

        if let url = book.coverURL {
            let request = ShelfCoverImageSource.request(for: url)
            imageView.kf.setImage(with: request.url, options: request.options) { result in
                guard case .success(let value) = result else { return }
                fitCover(value.image.size)
            }
        } else {
            imageView.backgroundColor = UIColor.appPrimary
            let label = UILabel()
            label.text          = book.displayTitle
            label.font          = UIFont(name: "GowunBatang-Bold", size: 10) ?? .boldSystemFont(ofSize: 10)
            label.textColor     = UIColor.background
            label.textAlignment = .center
            label.numberOfLines = 4
            imageView.addSubview(label)
            label.frame = imageView.bounds.insetBy(dx: 4, dy: 8)
        }
        return ghost
    }

    /// 신규 도서 등장 애니메이션에 사용할 실제 도서 뷰.
    private func findLastBookView() -> UIView? {
        guard !displayedBookIDs.isEmpty else { return nil }
        return shelfPages.last?.bookView(at: displayedBookIDs.count - 1)
    }

    // MARK: - Edit Mode

    private func setEditMode(_ editing: Bool) {
        isEditMode = editing
        SystemGlassButtonStyle.setEditing(editing, on: editButton, accessibilityLabel: "책장 편집")
        deleteAllButtonContainer.isHidden = !editing
        if layoutReady { rebuildShelfPages() }
    }

    func showRestoreCompleteAlert() {
        let alert = UIAlertController(
            title: nil,
            message: "내 밑줄 기록 불러오기가 완료되었습니다.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "확인", style: .default))
        present(alert, animated: true)
    }

    private func deleteBook(_ book: Book) {
        let alert = UIAlertController(
            title: "알림",
            message: "도서를 책장에서 꺼내면 수집한 밑줄과 독서 데이터도 함께 삭제됩니다.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "그대로 두기", style: .cancel))
        alert.addAction(UIAlertAction(title: "꺼내기", style: .destructive) { [weak self] _ in
            self?.deleteBookRelay.accept(book)
        })
        present(alert, animated: true)
    }

    // MARK: - Bindings

    private func bindActions() {
        let output = viewModel.transform(input: BookshelfViewModel.Input(
            deleteBook:   deleteBookRelay.asObservable(),
            deleteAll:    deleteAllRelay.asObservable(),
            reorderBooks: reorderRelay.asObservable()
        ))

        // 길게 탭 → 드래그 & 드롭 재정렬
        let longPress = UILongPressGestureRecognizer()
        longPress.minimumPressDuration = 0.45
        bookshelfScrollView.addGestureRecognizer(longPress)
        longPress.rx.event
            .subscribe(onNext: { [weak self] recognizer in
                guard let self else { return }
                switch recognizer.state {
                case .began:                      self.dragBegan(recognizer)
                case .changed:                    self.dragMoved(recognizer)
                case .ended:                      self.finishDrag(commit: true)
                case .cancelled, .failed:          self.finishDrag(commit: false)
                default: break
                }
            })
            .disposed(by: disposeBag)

        // 저장된 도서 스트림 → 책장 자동 업데이트
        output.books
            .drive(onNext: { [weak self] books in
                guard let self else { return }
                let previousCount     = self.allBooks.count
                let previousSavedCount = self.savedBooks.count
                self.allBooks = books
                self.applyFilter()

                // 새 도서 추가 시: 페이지 이동 후 책 등장 애니메이션
                let newBookAdded = previousCount > 0
                    && books.count > previousCount
                    && self.savedBooks.count > previousSavedCount
                    && self.layoutReady
                guard newBookAdded else { return }

                let lastPage  = self.pageControl.numberOfPages - 1
                let pageWidth = self.bookshelfScrollView.bounds.width
                let targetOffset = CGPoint(x: pageWidth * CGFloat(lastPage), y: 0)

                // 신규 도서 뷰를 미리 숨겨두기 (레이아웃 먼저 확정)
                self.bookshelfScrollView.layoutIfNeeded()
                let newBookView = self.findLastBookView()
                newBookView?.alpha     = 0
                newBookView?.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)

                let showNewBook = {
                    UIView.animate(withDuration: 0.3, delay: 0.05,
                                   usingSpringWithDamping: 0.65, initialSpringVelocity: 0.5,
                                   options: [], animations: {
                        newBookView?.alpha     = 1
                        newBookView?.transform = .identity
                    })
                }

                if lastPage > 0 {
                    UIView.animate(withDuration: 0.4, delay: 0, options: .curveEaseInOut, animations: {
                        self.bookshelfScrollView.contentOffset = targetOffset
                    }, completion: { _ in showNewBook() })
                } else {
                    showNewBook()
                }
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

        // 리사이즈 중의 임시 offset은 페이지 앵커에 반영하지 않는다.
        bookshelfScrollView.rx.contentOffset
            .subscribe(onNext: { [weak self] offset in
                guard let self, !self.isRebuildingShelf, let layout = self.shelfLayout,
                      layout.bounds.width > 0,
                      layout.bounds.width == self.bookshelfScrollView.bounds.width else { return }
                let page = Int(round(offset.x / layout.bounds.width))
                self.pageControl.currentPage = min(max(0, page), self.pageControl.numberOfPages - 1)
            })
            .disposed(by: disposeBag)

        // FAB → 도서 등록 검색 시트
        fabButton.rx.tap
            .subscribe(onNext: { [weak self] in
                guard let self else { return }
                let vc = BookSearchViewController()
                vc.modalPresentationStyle = .pageSheet
                if let sheet = vc.sheetPresentationController {
                    sheet.detents               = [.large()]
                    sheet.prefersGrabberVisible = false   // 커스텀 핸들바 사용
                }
                self.present(vc, animated: true)
            })
            .disposed(by: disposeBag)

        // 편집 버튼
        editButton.rx.tap
            .subscribe(onNext: { [weak self] in
                guard let self else { return }
                self.setEditMode(!self.isEditMode)
            })
            .disposed(by: disposeBag)

        // 전부 삭제 버튼
        deleteAllButton.rx.tap
            .subscribe(onNext: { [weak self] in
                guard let self else { return }
                let alert = UIAlertController(
                    title: "알림",
                    message: "책장의 모든 도서와 밑줄, 독서 데이터가 삭제됩니다.",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "취소", style: .cancel))
                alert.addAction(UIAlertAction(title: "삭제", style: .destructive) { [weak self] _ in
                    self?.deleteAllRelay.accept(())
                    self?.setEditMode(false)
                })
                self.present(alert, animated: true)
            })
            .disposed(by: disposeBag)

        wishlistButton.rx.tap
            .subscribe(onNext: { [weak self] in
                self?.navigationController?.pushViewController(WishlistViewController(), animated: true)
            })
            .disposed(by: disposeBag)

        // 필터 버튼
        sortButton.rx.tap
            .subscribe(onNext: { [weak self] in
                guard let self else { return }
                let vc = BookshelfFilterViewController()
                vc.delegate = self
                vc.modalPresentationStyle = .pageSheet
                if let sheet = vc.sheetPresentationController {
                    sheet.detents               = [.custom { min(BookshelfFilterViewController.preferredSheetHeight, $0.maximumDetentValue) }]
                    sheet.prefersScrollingExpandsWhenScrolledToEdge = false
                    sheet.prefersGrabberVisible = false
                }
                self.present(vc, animated: true)
            })
            .disposed(by: disposeBag)
    }
}

// MARK: - BookshelfFilterDelegate

// MARK: - Tutorial

extension BookshelfViewController {
    private func showTutorialIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: "tutorial.bookshelf") else {
            var steps: [TutorialStep] = []
            var keys: [String] = []
            if !UserDefaults.standard.bool(forKey: "tutorial.bookshelfWishlist") {
                steps.append(TutorialSupport.barButtonStep(item: wishlistButton, on: self, message: "하트 아이콘에서 위시리스트를 열고\n읽고 싶은 책을 관리해보세요"))
                keys.append("tutorial.bookshelfWishlist")
            }
            if !UserDefaults.standard.bool(forKey: "tutorial.bookshelfDrag") {
                steps.append(bookshelfDragTutorialStep())
                keys.append("tutorial.bookshelfDrag")
            }
            guard let key = keys.first else { return }
            TutorialSupport.show(on: self, key: key, steps: steps) {
                keys.forEach { UserDefaults.standard.set(true, forKey: $0) }
            }
            return
        }
        guard presentedViewController == nil else { return }

        guard tutorialSession == nil else { return }
        let session = UUID()
        tutorialSession = session
        let model = BookshelfTutorialViewModel(repository: AppContainer.shared.bookRepository)
        view.addSubview(tutorialLoading)
        tutorialLoading.center = view.center
        tutorialLoading.startAnimating()
        tutorialLoadTask = Task { [weak self] in
            await model.prepare()
            guard !Task.isCancelled else { return }
            self?.presentBookshelfTutorial(session: session, books: model.books)
        }
        tutorialDeadlineTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.presentBookshelfTutorial(session: session, books: model.books)
        }
    }

    private func presentBookshelfTutorial(session: UUID, books: [Book]) {
        guard tutorialSession == session, view.window != nil, presentedViewController == nil else { return }
        tutorialDeadlineTask?.cancel()
        tutorialLoadTask?.cancel()
        tutorialLoading.stopAnimating()
        tutorialLoading.removeFromSuperview()
        tutorialBooks = books
        if layoutReady { rebuildShelfPages() }
        let steps: [TutorialStep] = [
            TutorialSupport.barButtonStep(item: wishlistButton, on: self, message: "하트 아이콘에서 위시리스트를 열 수 있어요"),
            TutorialSupport.barButtonStep(item: sortButton, on: self, message: "조절 아이콘에서 정렬·필터로\n원하는 책을 빠르게 찾을 수 있어요"),
            bookshelfDragTutorialStep(),
            TutorialStep(
                targetFrame: .zero,
                message: "도서 검색으로 읽고 있는 책을\n책장에 추가해보세요!",
                targetFrameProvider: { [weak self] in
                    guard let target = self?.fabButton else { return .zero }
                    return target.convert(target.bounds, to: nil)
                }
            ),
        ]

        let tutorialVC = TutorialOverlayViewController()
        tutorialVC.steps = steps
        tutorialVC.modalPresentationStyle = .overFullScreen
        tutorialVC.modalTransitionStyle = .crossDissolve
        tutorialVC.onFinished = { [weak self] in
            UserDefaults.standard.set(true, forKey: "tutorial.bookshelf")
            UserDefaults.standard.set(true, forKey: "tutorial.bookshelfWishlist")
            UserDefaults.standard.set(true, forKey: "tutorial.bookshelfDrag")
            self?.tutorialSession = nil
            self?.tutorialLoadTask?.cancel()
            self?.tutorialBooks = []
            if self?.layoutReady == true { self?.rebuildShelfPages() }
        }
        present(tutorialVC, animated: true)
    }

    private func bookshelfDragTutorialStep() -> TutorialStep {
        TutorialStep(
            targetFrame: .zero,
            message: "책을 꾹 누른 채 원하는 위치로 옮겨\n책장의 순서를 바꿀 수 있어요",
            targetFrameProvider: { [weak self] in
                guard let self else { return .zero }
                let page = self.pageControl.currentPage
                if self.shelfPages.indices.contains(page), let layout = self.shelfLayout,
                   let bookView = self.shelfPages[page].bookView(at: page * layout.capacity) {
                    return bookView.convert(bookView.bounds, to: nil)
                }
                return self.bookshelfScrollView.convert(self.bookshelfScrollView.bounds, to: nil)
            }
        )
    }
}

// MARK: - BookshelfFilterDelegate

extension BookshelfViewController: BookshelfFilterDelegate {
    func bookshelfFilter(didSearch query: String) {
        activeFilterQuery = query
        applyFilter()
        dismiss(animated: true)
    }

    func bookshelfFilterDidRequestShowAll() {
        activeFilterQuery = nil
        applyFilter()
        dismiss(animated: true)
    }
}
