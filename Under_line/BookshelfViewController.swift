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

    private let disposeBag = DisposeBag()
    private var layoutReady = false
    private var highlightLayers: [(view: UIView, layer: CAGradientLayer)] = []
    private var isEditMode = false

    // MARK: - Saved Books

    private var savedBooks: [Book] = [] {
        didSet {
            guard layoutReady else { return }
            rebuildShelfPages()
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

    private lazy var filterButton: UIButton = {
        let btn = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
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
        pc.currentPageIndicatorTintColor = UIColor.primary
        pc.pageIndicatorTintColor        = UIColor.primary.withAlphaComponent(0.3)
        pc.transform = CGAffineTransform(scaleX: 0.75, y: 0.75)
        return pc
    }()

    // FAB (+) 버튼
    private lazy var fabButton: UIButton = {
        let btn = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        btn.setImage(UIImage(systemName: "plus", withConfiguration: cfg), for: .normal)
        btn.tintColor = UIColor.walnut
        btn.layer.cornerRadius = 26
        btn.clipsToBounds = true
        return btn
    }()

    // 편집 버튼
    private lazy var editButton: UIButton = {
        let btn = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
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

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = UIColor.background

        view.addSubview(headerView)
        headerView.addSubview(appTitleLabel)
        headerView.addSubview(filterButton)

        view.addSubview(bookshelfScrollView)
        view.addSubview(shelfOverlayView)   // 스크롤뷰 위에 고정 선반 오버레이
        view.addSubview(pageControl)
        view.addSubview(fabButton)

        view.addSubview(editButton)

        applyFabGlassStyle(to: filterButton, cornerRadius: 20)
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

        filterButton.snp.makeConstraints { make in
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
            make.top.equalTo(headerView.snp.bottom).offset(16)
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

        let booksPerRow  = 3
        let rowsPerPage  = 3
        let booksPerPage = booksPerRow * rowsPerPage
        let pageCount    = max(1, Int(ceil(Double(savedBooks.count) / Double(booksPerPage))))

        pageControl.numberOfPages = pageCount

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
            let pageView = ShelfPageView(rows: rows, isEditing: isEditMode, onDelete: { [weak self] book in
                self?.deleteBook(book)
            })
            bookshelfScrollView.addSubview(pageView)
            pageView.frame = CGRect(
                x:      pageWidth * CGFloat(pageIdx),
                y:      0,
                width:  pageWidth,
                height: pageHeight
            )
        }

        setupFixedShelfBoards(pageHeight: pageHeight)
    }

    /// 스크롤과 무관하게 고정되는 선반 보드를 오버레이에 추가
    private func setupFixedShelfBoards(pageHeight: CGFloat) {
        // ShelfRowView 높이: top inset(10) + 책 높이(117) + 선반 높이(22) = 149
        let rowHeight: CGFloat = 149
        let rowCount: CGFloat  = 3
        let rowsHeight = rowHeight * rowCount                                // 447
        let stackHeight = 0.5 * pageHeight + rowsHeight / 2
        let stackMinY   = (pageHeight - stackHeight) / 2
        let spacing     = rowCount > 1 ? (stackHeight - rowsHeight) / (rowCount - 1) : 0

        var lastShelfMaxY: CGFloat = 0
        for i in 0..<Int(rowCount) {
            let rowMinY  = stackMinY + CGFloat(i) * (rowHeight + spacing)
            // 선반 보드 Y = 행 시작 + top inset(10) + 책 높이(117)
            let shelfY   = rowMinY + 127

            let board = UIView()
            board.backgroundColor    = .walnut
            board.layer.cornerRadius = 5
            shelfOverlayView.addSubview(board)
            board.frame = CGRect(
                x:      0,
                y:      shelfY,
                width:  shelfOverlayView.bounds.width,
                height: 22
            )
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
            editButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        } else {
            let cfg = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
            editButton.setImage(UIImage(systemName: "square.and.pencil", withConfiguration: cfg), for: .normal)
            editButton.setTitle(nil, for: .normal)
        }
        if layoutReady { rebuildShelfPages() }
    }

    private func deleteBook(_ book: Book) {
        AppContainer.shared.bookRepository.deleteBook(book)
            .observe(on: MainScheduler.instance)
            .subscribe(onCompleted: { }, onError: { error in
                print("삭제 실패: \(error)")
            })
            .disposed(by: disposeBag)
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
        // 저장된 도서 스트림 구독 → 책장 자동 업데이트
        AppContainer.shared.bookRepository.fetchSavedBooks()
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] books in
                self?.savedBooks = books
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

        // 책장 탭 → 상세 화면 push (편집 모드일 때는 비활성)
        let bookTap = UITapGestureRecognizer()
        bookshelfScrollView.addGestureRecognizer(bookTap)
        bookTap.rx.event
            .subscribe(onNext: { [weak self] _ in
                guard let self, !self.isEditMode else { return }
                let vc = BookDetailViewController()
                self.navigationController?.pushViewController(vc, animated: true)
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
        filterButton.rx.tap
            .subscribe(onNext: { [weak self] in
                // TODO: 정렬/필터 시트 present
                print("필터 탭")
            })
            .disposed(by: disposeBag)
    }
}
