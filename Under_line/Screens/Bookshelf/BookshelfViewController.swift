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

final class BookshelfViewController: UIViewController {

    private let disposeBag      = DisposeBag()
    private let viewModel       = BookshelfViewModel(repository: AppContainer.shared.bookRepository)
    private let deleteBookRelay = PublishRelay<Book>()
    private let deleteAllRelay  = PublishRelay<Void>()
    private let reorderRelay    = PublishRelay<[String]>()

    private var layoutReady = false
    private var highlightLayers: [(view: UIView, layer: CAGradientLayer)] = []
    private var isEditMode = false

    // MARK: - Drag & Drop

    private struct DragState {
        let book: Book
        let fromIndex: Int
        var currentIndex: Int
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
    private var tutorialBooks: [Book] = []

    private var savedBooks: [Book] = [] {
        didSet {
            guard layoutReady else { return }
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

    // 헤더
    private let headerView = UIView()

    private let appTitleLabel: UILabel = {
        let l = UILabel()
        l.text = "밑줄"
        l.font = UIFont(name: "GowunBatang-Bold", size: 34)
            ?? .systemFont(ofSize: 34, weight: .bold)
        l.textColor = UIColor.accent
        return l
    }()

    private lazy var sortButton: UIButton = {
        let btn = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        btn.setImage(UIImage(systemName: "slider.horizontal.3", withConfiguration: cfg), for: .normal)
        btn.tintColor = UIColor.walnut
        btn.layer.cornerRadius = 20
        btn.clipsToBounds = true
        return btn
    }()

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
        btn.tintColor = UIColor.walnut
        btn.layer.cornerRadius = 26
        btn.clipsToBounds = true
        return btn
    }()

    // 편집 버튼
    private lazy var editButton: UIButton = {
        let btn = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        btn.setImage(UIImage(systemName: "square.and.pencil", withConfiguration: cfg), for: .normal)
        btn.tintColor = UIColor.walnut
        btn.layer.cornerRadius = 26
        btn.clipsToBounds = true
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
        btn.setTitleColor(UIColor.walnut, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        btn.layer.cornerRadius = 26
        btn.clipsToBounds = true
        return btn
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupConstraints()
        bindActions()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // 스페큘러 그라데이션 레이어 프레임 갱신
        for (view, gradient) in highlightLayers {
            gradient.frame = view.bounds
        }

        if !layoutReady, bookshelfScrollView.bounds.width > 0 {
            layoutReady = true
            rebuildShelfPages()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        showTutorialIfNeeded()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        layoutReady = false  // viewDidLayoutSubviews가 새 bounds로 rebuildShelfPages() 재실행
    }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = UIColor.background

        view.addSubview(headerView)
        headerView.addSubview(appTitleLabel)
        headerView.addSubview(sortButton)

        view.addSubview(bookshelfScrollView)
        view.addSubview(shelfOverlayView)   // 스크롤뷰 위에 고정 선반 오버레이
        view.addSubview(pageControl)
        view.addSubview(fabButton)

        view.addSubview(editButton)

        view.addSubview(deleteAllButtonContainer)
        deleteAllButtonContainer.addSubview(deleteAllButton)

        applyFabGlassStyle(to: sortButton,      cornerRadius: 20)
        applyFabGlassStyle(to: fabButton,       cornerRadius: 26)
        applyFabGlassStyle(to: editButton,      cornerRadius: 26)
        applyFabGlassStyle(to: deleteAllButton, cornerRadius: 26)
    }

    private func setupConstraints() {
        headerView.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide)
            make.leading.trailing.equalToSuperview().inset(24)
            make.height.equalTo(54)
        }

        appTitleLabel.snp.makeConstraints { make in
            make.leading.centerY.equalToSuperview()
        }

        sortButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview()
            make.centerY.equalToSuperview()
            make.size.equalTo(40)
        }

        fabButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(24)
            make.bottom.equalTo(view.safeAreaLayoutGuide).inset(16)
            make.size.equalTo(52)
        }

        editButton.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(24)
            make.centerY.equalTo(fabButton)
            make.size.equalTo(52)
        }

        deleteAllButtonContainer.snp.makeConstraints { make in
            make.leading.equalTo(editButton.snp.trailing).offset(16)
            make.centerY.equalTo(editButton)
            make.width.equalTo(84)
            make.height.equalTo(52)
        }

        deleteAllButton.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        pageControl.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(shelfOverlayView)   // 초기 플레이스홀더, setupFixedShelfBoards에서 remakeConstraints
        }

        bookshelfScrollView.snp.makeConstraints { make in
            make.top.equalTo(headerView.snp.bottom)
            make.leading.trailing.equalToSuperview().inset(24)
            make.bottom.equalTo(fabButton.snp.top).offset(-16)
        }

        shelfOverlayView.snp.makeConstraints { make in
            make.edges.equalTo(bookshelfScrollView)
        }
    }

    // MARK: - Shelf Pages

    private func rebuildShelfPages() {
        let pageWidth  = bookshelfScrollView.bounds.width
        let pageHeight = bookshelfScrollView.bounds.height
        guard pageWidth > 0 else { return }

        // 기존 페이지 및 선반 오버레이 제거
        bookshelfScrollView.subviews.forEach { $0.removeFromSuperview() }
        shelfOverlayView.subviews.forEach    { $0.removeFromSuperview() }

        let isIPad = UIDevice.current.userInterfaceIdiom == .pad
        let isLandscape = pageWidth > pageHeight
        let booksPerRow: Int = isIPad ? (isLandscape ? 8 : (pageWidth >= 900 ? 5 : 4)) : 3
        let bookWidth: CGFloat = isIPad
            ? (pageWidth - 20.0 * CGFloat(booksPerRow - 1)) / CGFloat(booksPerRow) * 0.652
            : 82
        let bookHeight: CGFloat = min(ceil(bookWidth * 117.0 / 88.0), 180.0)

        let rowsPerPage  = 3
        let booksPerPage = booksPerRow * rowsPerPage
        let displayBooks: [Book] = tutorialBooks.isEmpty ? savedBooks : Array(tutorialBooks.prefix(booksPerPage))
        let pageCount    = max(1, Int(ceil(Double(displayBooks.count) / Double(booksPerPage))))

        pageControl.numberOfPages = pageCount
        pageControl.isHidden = pageCount <= 1

        bookshelfScrollView.contentSize = CGSize(
            width:  pageWidth * CGFloat(pageCount),
            height: pageHeight
        )

        let draggingIndex = dragState?.currentIndex

        for pageIdx in 0..<pageCount {
            var rows: [ShelfPageView.RowData] = []
            for rowIdx in 0..<rowsPerPage {
                let start = pageIdx * booksPerPage + rowIdx * booksPerRow
                var rowBooks: [Book?] = start < displayBooks.count
                    ? (start..<min(start + booksPerRow, displayBooks.count)).map { idx in
                        if let di = draggingIndex, idx == di { return nil }
                        return displayBooks[idx] as Book?
                    }
                    : []
                while rowBooks.count < booksPerRow { rowBooks.append(nil) }
                rows.append(ShelfPageView.RowData(books: rowBooks))
            }
            let pageView = ShelfPageView(rows: rows, bookWidth: bookWidth, isEditing: isEditMode, onDelete: { [weak self] book in
                self?.deleteBook(book)
            }, onTap: { [weak self] book in
                guard let self else { return }
                let vc = BookDetailViewController(book: book)
                self.navigationController?.pushViewController(vc, animated: true)
            })
            bookshelfScrollView.addSubview(pageView)
            pageView.frame = CGRect(
                x:      pageWidth * CGFloat(pageIdx),
                y:      0,
                width:  pageWidth,
                height: pageHeight
            )
        }

        rebuildBookSlotFrames(
            pageWidth: pageWidth, pageHeight: pageHeight,
            bookWidth: bookWidth, bookHeight: bookHeight,
            booksPerRow: booksPerRow, rowsPerPage: rowsPerPage,
            booksPerPage: booksPerPage, pageCount: pageCount,
            booksCount: displayBooks.count
        )

        setupFixedShelfBoards(pageHeight: pageHeight, bookHeight: bookHeight, isIPad: isIPad)
    }

    /// 스크롤과 무관하게 고정되는 선반 보드를 오버레이에 추가
    private func setupFixedShelfBoards(pageHeight: CGFloat, bookHeight: CGFloat, isIPad: Bool = false) {
        let rowHeight: CGFloat = 10 + bookHeight + 22
        let rowCount: CGFloat  = 3
        let rowsHeight = rowHeight * rowCount
        let stackHeight = 0.5 * pageHeight + rowsHeight / 2
        let stackMinY   = (pageHeight - stackHeight) / 2
        let spacing     = rowCount > 1 ? (stackHeight - rowsHeight) / (rowCount - 1) : 0

        var lastShelfMaxY: CGFloat = 0
        for i in 0..<Int(rowCount) {
            let rowMinY  = stackMinY + CGFloat(i) * (rowHeight + spacing)
            // 선반 보드 Y = 행 시작 + top inset(10) + 책 높이
            let shelfY   = rowMinY + 10 + bookHeight

            let shelfWidth = isIPad
                ? shelfOverlayView.bounds.width * 0.85
                : shelfOverlayView.bounds.width
            let shelfX = isIPad
                ? shelfOverlayView.bounds.width * 0.075
                : 0.0
            let boardFrame = CGRect(
                x:      shelfX,
                y:      shelfY,
                width:  shelfWidth,
                height: 22
            )

            // 좌상단 광원 그림자 전용 뷰 (clipsToBounds 없음)
            let shadowView = UIView(frame: boardFrame)
            shadowView.backgroundColor   = .clear
            shadowView.layer.shadowColor   = UIColor.black.cgColor
            shadowView.layer.shadowOpacity = 0.28
            shadowView.layer.shadowRadius  = 4
            shadowView.layer.shadowOffset  = CGSize(width: 2, height: 3)
            shadowView.layer.shadowPath    = UIBezierPath(
                roundedRect: CGRect(origin: .zero, size: boardFrame.size),
                cornerRadius: 5
            ).cgPath
            shelfOverlayView.addSubview(shadowView)

            let board = UIImageView()
            board.image              = UIImage(named: "Bookshelf\(i + 1)")
            board.contentMode        = .scaleToFill
            board.layer.cornerRadius = 5
            board.clipsToBounds      = true
            shelfOverlayView.addSubview(board)
            board.frame = boardFrame
            lastShelfMaxY = shelfY + 22
        }

        // pageControl을 마지막 선반 하단에서 16pt 아래에 배치
        pageControl.snp.remakeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(shelfOverlayView).offset(lastShelfMaxY + 16)
        }
    }

    /// 책 위치 감지를 위한 슬롯 프레임 배열 재계산
    private func rebuildBookSlotFrames(pageWidth: CGFloat, pageHeight: CGFloat, bookWidth: CGFloat, bookHeight: CGFloat, booksPerRow: Int, rowsPerPage: Int, booksPerPage: Int, pageCount: Int, booksCount: Int) {
        var frames: [(globalIndex: Int, frameInScrollView: CGRect)] = []

        // ShelfRowView 실제 높이 = top inset(2) + bookHeight + bottom inset(12)
        let rowHeightActual: CGFloat = bookHeight + 14
        let rowsHeightCalc: CGFloat  = CGFloat(rowsPerPage) * (10 + bookHeight + 22)
        let stackHeight: CGFloat     = 0.5 * pageHeight + rowsHeightCalc / 2
        let stackMinY: CGFloat       = (pageHeight - stackHeight) / 2
        let spacing: CGFloat         = rowsPerPage > 1
            ? (stackHeight - CGFloat(rowsPerPage) * rowHeightActual) / CGFloat(rowsPerPage - 1)
            : 0

        let totalBooksWidth = CGFloat(booksPerRow) * bookWidth + CGFloat(booksPerRow - 1) * 20

        for pageIdx in 0..<pageCount {
            let pageX  = pageWidth * CGFloat(pageIdx)
            let startX = pageX + (pageWidth - totalBooksWidth) / 2

            for rowIdx in 0..<rowsPerPage {
                let rowTop  = stackMinY + CGFloat(rowIdx) * (rowHeightActual + spacing)
                let bookTop = rowTop + 2

                for colIdx in 0..<booksPerRow {
                    let globalIndex = pageIdx * booksPerPage + rowIdx * booksPerRow + colIdx
                    guard globalIndex < booksCount else { continue }
                    let bookX = startX + CGFloat(colIdx) * (bookWidth + 20)
                    frames.append((
                        globalIndex: globalIndex,
                        frameInScrollView: CGRect(x: bookX, y: bookTop, width: bookWidth, height: bookHeight)
                    ))
                }
            }
        }
        bookSlotFrames = frames
    }

    // MARK: - Drag & Drop

    private func dragBegan(_ recognizer: UIGestureRecognizer) {
        guard !isEditMode else { return }
        guard activeFilterQuery == nil || activeFilterQuery!.isEmpty else { return }

        let touchInScrollView = recognizer.location(in: bookshelfScrollView)
        guard let slot = bookSlotFrames.first(where: { $0.frameInScrollView.contains(touchInScrollView) }) else { return }

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
            book: book,
            fromIndex: slot.globalIndex,
            currentIndex: slot.globalIndex,
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
            var books = savedBooks
            let moved = books.remove(at: state.currentIndex)
            books.insert(moved, at: target.globalIndex)
            state.currentIndex = target.globalIndex
            dragState = state
            savedBooks = books   // didSet → rebuildShelfPages (빈 슬롯 + 새 배치)
        } else {
            dragState = state
        }

        // 가장자리 감지 → 페이지 플립 타이머
        let svFrame = bookshelfScrollView.frame
        let ghostX = state.ghostView.center.x
        let pageWidth = bookshelfScrollView.bounds.width
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

    private func dragEnded() {
        cancelPageFlipTimer()
        guard let state = dragState else { return }

        UIView.animate(withDuration: 0.15, animations: {
            state.ghostView.alpha = 0
            state.ghostView.transform = .identity
        }, completion: { _ in
            state.ghostView.removeFromSuperview()
        })

        isDragging = false
        dragState = nil
        bookshelfScrollView.isScrollEnabled = true
        rebuildShelfPages()   // 빈 슬롯 제거

        reorderRelay.accept(savedBooks.map { $0.isbn13 })
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
        imageView.contentMode    = .scaleAspectFill
        imageView.clipsToBounds  = true
        imageView.layer.cornerRadius = 3
        imageView.frame = CGRect(origin: .zero, size: size)
        ghost.addSubview(imageView)
        ghost.bounds = CGRect(origin: .zero, size: size)

        if let url = book.coverURL {
            imageView.kf.setImage(with: url)
        } else {
            imageView.backgroundColor = UIColor.appPrimary
            let label = UILabel()
            label.text          = book.title
            label.font          = UIFont(name: "GowunBatang-Bold", size: 10) ?? .boldSystemFont(ofSize: 10)
            label.textColor     = UIColor.background
            label.textAlignment = .center
            label.numberOfLines = 4
            imageView.addSubview(label)
            label.frame = imageView.bounds.insetBy(dx: 4, dy: 8)
        }
        return ghost
    }

    /// 책장에 마지막으로 배치된 책 wrapper 뷰 반환 (새 도서 등장 애니메이션용)
    /// ShelfPageView → UIStackView(vertical) → ShelfRowView → UIStackView(horizontal) → wrapper
    private func findLastBookView() -> UIView? {
        guard let lastPage = bookshelfScrollView.subviews.last,
              let vStack   = lastPage.subviews.first as? UIStackView else { return nil }
        for rowView in vStack.arrangedSubviews.reversed() {
            guard let hStack = rowView.subviews.first as? UIStackView else { continue }
            for wrapper in hStack.arrangedSubviews.reversed() {
                if wrapper.layer.shadowOpacity > 0 { return wrapper }
            }
        }
        return nil
    }

    // MARK: - Edit Mode

    private func setEditMode(_ editing: Bool) {
        isEditMode = editing
        if editing {
            editButton.setImage(nil, for: .normal)
            editButton.setTitle("완료", for: .normal)
            editButton.setTitleColor(UIColor.walnut, for: .normal)
            editButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
            deleteAllButtonContainer.isHidden = false
        } else {
            let cfg = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            editButton.setImage(UIImage(systemName: "square.and.pencil", withConfiguration: cfg), for: .normal)
            editButton.setTitle(nil, for: .normal)
            deleteAllButtonContainer.isHidden = true
        }
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

    // MARK: - FAB Glass Style

    private func applyFabGlassStyle(to button: UIButton, cornerRadius: CGFloat) {
        guard let superview = button.superview else { return }

        let shadowView = UIView()
        shadowView.isUserInteractionEnabled = false
        shadowView.layer.cornerRadius = cornerRadius
        shadowView.backgroundColor = .white
        shadowView.layer.shadowColor   = UIColor.black.cgColor
        shadowView.layer.shadowOpacity = Float(CGFloat(0x18) / 255)
        shadowView.layer.shadowRadius  = 8
        shadowView.layer.shadowOffset  = CGSize(width: 0, height: 6)
        superview.insertSubview(shadowView, belowSubview: button)
        shadowView.snp.makeConstraints { $0.edges.equalTo(button) }

        let glassContainer = UIView()
        glassContainer.isUserInteractionEnabled = false
        glassContainer.layer.cornerRadius = cornerRadius
        glassContainer.clipsToBounds = true
        glassContainer.layer.borderWidth = 1
        glassContainer.layer.borderColor = UIColor(white: 1, alpha: CGFloat(0x70) / 255).cgColor
        superview.insertSubview(glassContainer, belowSubview: button)
        glassContainer.snp.makeConstraints { $0.edges.equalTo(button) }
        superview.insertSubview(shadowView, belowSubview: glassContainer)

        let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
        blurView.isUserInteractionEnabled = false
        glassContainer.addSubview(blurView)
        blurView.snp.makeConstraints { $0.edges.equalToSuperview() }

        let solidTint = UIView()
        solidTint.isUserInteractionEnabled = false
        solidTint.backgroundColor = UIColor(hex: "#832C11", alpha: CGFloat(0x24) / 255)
        blurView.contentView.addSubview(solidTint)
        solidTint.snp.makeConstraints { $0.edges.equalToSuperview() }

        let topSpecular = UIView()
        topSpecular.isUserInteractionEnabled = false
        blurView.contentView.addSubview(topSpecular)
        topSpecular.snp.makeConstraints { $0.edges.equalToSuperview() }
        let topGrad = CAGradientLayer()
        topGrad.colors = [
            UIColor(white: 1, alpha: CGFloat(0x50) / 255).cgColor,
            UIColor(white: 1, alpha: CGFloat(0x10) / 255).cgColor,
            UIColor.clear.cgColor,
        ]
        topGrad.locations  = [0, 0.45, 1.0]
        topGrad.startPoint = CGPoint(x: 0.5, y: 0)
        topGrad.endPoint   = CGPoint(x: 0.5, y: 1)
        topSpecular.layer.addSublayer(topGrad)
        highlightLayers.append((topSpecular, topGrad))

        let bottomWarm = UIView()
        bottomWarm.isUserInteractionEnabled = false
        blurView.contentView.addSubview(bottomWarm)
        bottomWarm.snp.makeConstraints { $0.edges.equalToSuperview() }
        let bottomGrad = CAGradientLayer()
        bottomGrad.colors = [
            UIColor(hex: "#832C11", alpha: CGFloat(0x20) / 255).cgColor,
            UIColor(hex: "#832C11", alpha: CGFloat(0x0C) / 255).cgColor,
            UIColor.clear.cgColor,
        ]
        bottomGrad.locations  = [0, 0.5, 1.0]
        bottomGrad.startPoint = CGPoint(x: 0.5, y: 1)
        bottomGrad.endPoint   = CGPoint(x: 0.5, y: 0)
        bottomWarm.layer.addSublayer(bottomGrad)
        highlightLayers.append((bottomWarm, bottomGrad))

        button.backgroundColor = .clear
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
                case .ended, .cancelled, .failed: self.dragEnded()
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

        // 스크롤 → 페이지 컨트롤 동기화
        bookshelfScrollView.rx.contentOffset
            .map { [weak self] offset -> Int in
                guard let self else { return 0 }
                let width = self.bookshelfScrollView.bounds.width
                guard width > 0 else { return 0 }
                return Int(round(offset.x / width))
            }
            .distinctUntilChanged()
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] page in
                self?.pageControl.currentPage = page
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
                    sheet.preferredCornerRadius = 24
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

        // 필터 버튼
        sortButton.rx.tap
            .subscribe(onNext: { [weak self] in
                guard let self else { return }
                let vc = BookshelfFilterViewController()
                vc.delegate = self
                vc.modalPresentationStyle = .pageSheet
                if let sheet = vc.sheetPresentationController {
                    sheet.detents               = [.custom { _ in BookshelfFilterViewController.preferredSheetHeight }]
                    sheet.prefersGrabberVisible = true
                    sheet.preferredCornerRadius = 52
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
        guard !UserDefaults.standard.bool(forKey: "tutorial.bookshelf") else { return }

        // 베스트셀러 표지로 책장 미리채우기
        AppContainer.shared.bookRepository
            .fetchBestsellers()
            .observe(on: MainScheduler.instance)
            .subscribe(
                onSuccess: { [weak self] books in
                    guard let self else { return }
                    self.tutorialBooks = books
                    if self.layoutReady { self.rebuildShelfPages() }
                },
                onFailure: { _ in }
            )
            .disposed(by: disposeBag)

        let steps: [TutorialStep] = [
            TutorialStep(
                targetFrame: fabButton.convert(fabButton.bounds, to: nil),
                message: "도서 검색으로 읽고 있는 책을\n책장에 추가해보세요!"
            ),
            TutorialStep(
                targetFrame: sortButton.convert(sortButton.bounds, to: nil),
                message: "정렬·필터로 원하는 책을\n빠르게 찾을 수 있어요"
            ),
        ]

        let tutorialVC = TutorialOverlayViewController()
        tutorialVC.steps = steps
        tutorialVC.modalPresentationStyle = .overFullScreen
        tutorialVC.modalTransitionStyle = .crossDissolve
        tutorialVC.onFinished = { [weak self] in
            UserDefaults.standard.set(true, forKey: "tutorial.bookshelf")
            self?.tutorialBooks = []
            if self?.layoutReady == true { self?.rebuildShelfPages() }
        }
        present(tutorialVC, animated: true)
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
