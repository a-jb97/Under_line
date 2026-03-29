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

final class BookshelfViewController: UIViewController {

    private let disposeBag  = DisposeBag()
    private let viewModel   = BookshelfViewModel(repository: AppContainer.shared.bookRepository)
    private let deleteBookRelay = PublishRelay<Book>()

    private var layoutReady = false
    private var highlightLayers: [(view: UIView, layer: CAGradientLayer)] = []
    private var isEditMode = false

    // MARK: - Saved Books

    private var allBooks: [Book] = []
    private var activeFilterQuery: String?

    private var savedBooks: [Book] = [] {
        didSet {
            guard layoutReady else { return }
            rebuildShelfPages()
        }
    }

    private func applyFilter() {
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

        applyFabGlassStyle(to: sortButton, cornerRadius: 20)
        applyFabGlassStyle(to: fabButton,    cornerRadius: 26)
        applyFabGlassStyle(to: editButton,   cornerRadius: 26)
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
        let pageCount    = max(1, Int(ceil(Double(savedBooks.count) / Double(booksPerPage))))

        pageControl.numberOfPages = pageCount
        pageControl.isHidden = pageCount <= 1

        bookshelfScrollView.contentSize = CGSize(
            width:  pageWidth * CGFloat(pageCount),
            height: pageHeight
        )

        for pageIdx in 0..<pageCount {
            var rows: [ShelfPageView.RowData] = []
            for rowIdx in 0..<rowsPerPage {
                let start = pageIdx * booksPerPage + rowIdx * booksPerRow
                var rowBooks: [Book?] = start < savedBooks.count
                    ? (start..<min(start + booksPerRow, savedBooks.count)).map { savedBooks[$0] as Book? }
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

    // MARK: - Edit Mode

    private func setEditMode(_ editing: Bool) {
        isEditMode = editing
        if editing {
            editButton.setImage(nil, for: .normal)
            editButton.setTitle("완료", for: .normal)
            editButton.setTitleColor(UIColor.walnut, for: .normal)
            editButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        } else {
            let cfg = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            editButton.setImage(UIImage(systemName: "square.and.pencil", withConfiguration: cfg), for: .normal)
            editButton.setTitle(nil, for: .normal)
        }
        if layoutReady { rebuildShelfPages() }
    }

    private func deleteBook(_ book: Book) {
        let alert = UIAlertController(
            title: "알림",
            message: "도서를 책장에서 꺼내면 수집한 밑줄도 함께 지워집니다.",
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
            deleteBook: deleteBookRelay.asObservable()
        ))

        // 저장된 도서 스트림 → 책장 자동 업데이트
        output.books
            .drive(onNext: { [weak self] books in
                guard let self else { return }
                self.allBooks = books
                self.applyFilter()
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
                    sheet.preferredCornerRadius = 24
                }
                self.present(vc, animated: true)
            })
            .disposed(by: disposeBag)
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
