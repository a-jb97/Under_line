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
    private var pagesSetup = false
    private var highlightLayers: [(view: UIView, layer: CAGradientLayer)] = []

    // MARK: - Shelf Page Data

    /// 책장 3페이지 데이터 (추후 ViewModel / SwiftData로 교체)
    private let shelfPageData: [[ShelfPageView.RowData]] = [
        [
            .init(books: [.dark,   .medium, .lightOutline]),
            .init(books: [.lightDarkOutline, .dark, .medium]),
            .init(books: [.medium, .lightOutline]),
        ],
        [
            .init(books: [.medium, .dark,  .lightOutline]),
            .init(books: [.dark,   .medium, .dark]),
            .init(books: [.lightOutline, .medium, .dark]),
        ],
        [
            .init(books: [.dark,  .lightOutline, .medium]),
            .init(books: [.medium, .dark]),
            .init(books: [.lightOutline, .dark, .medium]),
        ],
    ]

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
        pc.numberOfPages = 3
        pc.currentPage = 0
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

        guard !pagesSetup, bookshelfScrollView.bounds.width > 0 else { return }
        pagesSetup = true
        setupShelfPages()
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

        applyFabGlassStyle(to: filterButton, cornerRadius: 20)
        applyFabGlassStyle(to: fabButton,    cornerRadius: 26)
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

        pageControl.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.bottom.equalTo(view.safeAreaLayoutGuide).inset(16)
        }

        bookshelfScrollView.snp.makeConstraints { make in
            make.top.equalTo(headerView.snp.bottom).offset(16)
            make.leading.trailing.equalToSuperview().inset(24)
            make.bottom.equalTo(pageControl.snp.top).offset(-12)
        }

        shelfOverlayView.snp.makeConstraints { make in
            make.edges.equalTo(bookshelfScrollView)
        }
    }

    /// 책장 페이지들을 스크롤뷰에 배치 (실제 bounds 확정 후 호출)
    private func setupShelfPages() {
        let pageWidth  = bookshelfScrollView.bounds.width
        let pageHeight = bookshelfScrollView.bounds.height

        bookshelfScrollView.contentSize = CGSize(
            width:  pageWidth * CGFloat(shelfPageData.count),
            height: pageHeight
        )

        for (i, rowData) in shelfPageData.enumerated() {
            let pageView = ShelfPageView(rows: rowData)
            bookshelfScrollView.addSubview(pageView)
            pageView.frame = CGRect(
                x:      pageWidth * CGFloat(i),
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

        for i in 0..<Int(rowCount) {
            let rowMinY  = stackMinY + CGFloat(i) * (rowHeight + spacing)
            // 선반 보드 Y = 행 시작 + top inset(10) + 책 높이(117)
            let shelfY   = rowMinY + 127

            let board = UIView()
            board.backgroundColor = .walnut
            board.layer.cornerRadius = 5
            shelfOverlayView.addSubview(board)
            board.frame = CGRect(
                x:      0,
                y:      shelfY,
                width:  shelfOverlayView.bounds.width,
                height: 22
            )
        }
    }

    // MARK: - FAB Glass (Ffv8R 스펙)

    /// 디자인 스펙 Ffv8R 기준:
    /// fill → #832C11 14% 솔리드 + 상단 화이트 그라데이션 + 하단 워밍 그라데이션
    /// blur → systemUltraThinMaterial (backdrop blur ≈ radius 48)
    /// shadow → black 9% y=6 blur=16
    /// stroke → 그라데이션 테두리 #FFFFFF70→#FFFFFF25→#FFFFFF10 inside 1pt
    private func applyFabGlassStyle(to button: UIButton, cornerRadius: CGFloat) {
        guard let superview = button.superview else { return }

        // 그림자 뷰 — clipsToBounds 없이 cornerRadius만 적용, 배경색 필요 (그림자 렌더링 전제)
        let shadowView = UIView()
        shadowView.isUserInteractionEnabled = false
        shadowView.layer.cornerRadius = cornerRadius
        shadowView.backgroundColor = .white
        shadowView.layer.shadowColor   = UIColor.black.cgColor
        shadowView.layer.shadowOpacity = Float(CGFloat(0x18) / 255)  // ≈ 9.4%
        shadowView.layer.shadowRadius  = 8                            // blur 16 → radius 8
        shadowView.layer.shadowOffset  = CGSize(width: 0, height: 6)
        superview.insertSubview(shadowView, belowSubview: button)
        shadowView.snp.makeConstraints { $0.edges.equalTo(button) }

        // 글래스 컨테이너 — blur + fill 레이어를 clip
        let glassContainer = UIView()
        glassContainer.isUserInteractionEnabled = false
        glassContainer.layer.cornerRadius = cornerRadius
        glassContainer.clipsToBounds = true
        // 그라데이션 테두리 근사: 상단 컬러(#FFFFFF70)로 솔리드 적용
        glassContainer.layer.borderWidth = 1
        glassContainer.layer.borderColor = UIColor(white: 1, alpha: CGFloat(0x70) / 255).cgColor
        superview.insertSubview(glassContainer, belowSubview: button)
        glassContainer.snp.makeConstraints { $0.edges.equalTo(button) }
        superview.insertSubview(shadowView, belowSubview: glassContainer)

        // Blur
        let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
        blurView.isUserInteractionEnabled = false
        glassContainer.addSubview(blurView)
        blurView.snp.makeConstraints { $0.edges.equalToSuperview() }

        // 솔리드 틴트: #832C11 @ 0x24/255 ≈ 14%
        let solidTint = UIView()
        solidTint.isUserInteractionEnabled = false
        solidTint.backgroundColor = UIColor(hex: "#832C11", alpha: CGFloat(0x24) / 255)
        blurView.contentView.addSubview(solidTint)
        solidTint.snp.makeConstraints { $0.edges.equalToSuperview() }

        // 상단 스페큘러 그라데이션: #FFFFFF50 → #FFFFFF10 → clear
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
        topGrad.locations = [0, 0.45, 1.0]
        topGrad.startPoint = CGPoint(x: 0.5, y: 0)
        topGrad.endPoint   = CGPoint(x: 0.5, y: 1)
        topSpecular.layer.addSublayer(topGrad)
        highlightLayers.append((topSpecular, topGrad))

        // 하단 워밍 그라데이션: #832C1120 → #832C110C → clear (아래→위)
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
        bottomGrad.locations = [0, 0.5, 1.0]
        bottomGrad.startPoint = CGPoint(x: 0.5, y: 1)
        bottomGrad.endPoint   = CGPoint(x: 0.5, y: 0)
        bottomWarm.layer.addSublayer(bottomGrad)
        highlightLayers.append((bottomWarm, bottomGrad))

        button.backgroundColor = .clear
    }

    // MARK: - Bindings

    private func bindActions() {
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
                    sheet.detents = [
                        .custom { context in context.maximumDetentValue * 0.78 }
                    ]
                    sheet.prefersGrabberVisible  = false   // 커스텀 핸들바 사용
                    sheet.preferredCornerRadius  = 24
                }
                self.present(vc, animated: true)
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
