//
//  ReadingRecordViewController.swift
//  Under_line
//
//  독서 기록 화면 — timerButton 탭 시 push (Node XRB6k)
//

import UIKit
import SnapKit
import RxSwift
import RxCocoa

final class ReadingRecordViewController: AdaptiveViewController {

    var onProgressRecorded: ((ReadingProgress) -> Void)?

    private let book: Book
    private var currentItemPage: Int?
    private var currentPage: Int?
    private let disposeBag = DisposeBag()

    private lazy var viewModel = ReadingRecordViewModel(
        book: book,
        readingSessionRepository: AppContainer.shared.readingSessionRepository
    )
    private let viewDidAppearRelay = PublishRelay<Void>()
    private let tabSelectedRelay   = BehaviorRelay<Int>(value: 0)
    private let timerStoppedRelay  = PublishRelay<Int>()

    init(book: Book, currentItemPage: Int?, initialPage: Int?) {
        self.book = book
        self.currentItemPage = currentItemPage
        currentPage = initialPage
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Chart State

    private var chartWidth: CGFloat = 0
    private var chartPoints: [ChartPoint] = []
    private let chartGridLayers = (0..<4).map { _ in CAShapeLayer() }
    private var yAxisLabels: [UILabel] = []
    private var chartDynamicViews: [UIView] = []

    // 차트 내부 좌표 상수 (chartCard 기준, bounds 불필요)
    private let chartTopY: CGFloat    = 24
    private let chartBottomY: CGFloat = 144  // chartTopY + 40 * 3
    private let chartLeftPad: CGFloat = 54   // Y축 레이블 우측 여백 확보 (레이블 우단 ≈ 50)
    private let chartRightPad: CGFloat = 14

    // MARK: - Scroll

    private let scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.showsVerticalScrollIndicator = false
        return sv
    }()
    private let contentView = UIView()
    private let timerColumn = UIView()
    private let recordsColumn = UIView()
    private var columns: ReadingColumns?

    // MARK: - Header

    // MARK: - Timer Dial

    private let timerDialView = TimerDialView()

    // MARK: - Book Title

    private let bookTitleLabel: UILabel = {
        let l = UILabel()
        l.font          = UIFont(name: "GowunBatang-Bold", size: 20)
            ?? .systemFont(ofSize: 20, weight: .bold)
        l.textColor     = UIColor.accent
        l.textAlignment = .center
        l.numberOfLines = 0
        return l
    }()

    // MARK: - Progress Section

    private let progressSectionView = ProgressSectionView()

    // MARK: - Chart Section

    private let chartTitleLabel: UILabel = {
        let l = UILabel()
        l.text      = "독서 시간"
        l.font      = UIFont(name: "GoyangIlsan R", size: 17) ?? .systemFont(ofSize: 17, weight: .bold)
        l.textColor = UIColor.accent
        return l
    }()

    private lazy var tabDailyButton: UIButton   = makeTabButton(title: "일별", selected: true)
    private lazy var tabWeeklyButton: UIButton  = makeTabButton(title: "주별", selected: false)
    private lazy var tabMonthlyButton: UIButton = makeTabButton(title: "월별", selected: false)

    private lazy var tabSelectorView: UIView = {
        let v = UIView()
        v.backgroundColor    = UIColor(hex: "#E8E0DC")
        v.layer.cornerRadius = 15
        v.layer.shadowColor   = UIColor(hex: "#b5a49e").cgColor
        v.layer.shadowOpacity = 1.0
        v.layer.shadowRadius  = 7
        v.layer.shadowOffset  = CGSize(width: 3, height: 3)
        return v
    }()

    private let chartCard: UIView = {
        let v = UIView()
        v.backgroundColor    = .white
        v.layer.cornerRadius = 16
        v.layer.shadowColor   = UIColor.black.cgColor
        v.layer.shadowOpacity = Float(CGFloat(0x16) / 255)
        v.layer.shadowRadius  = 24
        v.layer.shadowOffset  = CGSize(width: 0, height: 8)
        return v
    }()

    private let chartLineLayer = CAShapeLayer()
    private let chartAreaLayer = CAShapeLayer()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupConstraints()
        configureProgress()
        setupYAxisLabels()   // bounds 불필요 — 상수 기반 frame 사용
        bindViewModel()
        bindActions()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        let layout = ReadingColumns(
            container: ContainerLayout(view: view, reservesInactiveDivisions: true),
            usesFullWidth: traitCollection.userInterfaceIdiom == .pad
        )
        guard layout != columns else { return }
        columns = layout
        updateColumnConstraints()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = chartCard.bounds.width
        guard width > 0, width != chartWidth else { return }
        chartWidth = width
        updateChartGrid()
        renderChart(points: chartPoints)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        timerDialView.restoreStateIfNeeded()
        viewDidAppearRelay.accept(())
        showTutorialIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent {
            timerDialView.saveState()
        }
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }

    // MARK: - Setup

    private func setupUI() {
        SystemNavigationStyle.configure(self, title: "독서 기록")
        view.backgroundColor = UIColor.background
        bookTitleLabel.text = book.displayTitle
        timerDialView.persistenceKey = "timer_\(book.isbn13)"

        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        contentView.addSubview(timerColumn)
        contentView.addSubview(recordsColumn)

        timerColumn.addSubview(timerDialView)
        timerColumn.addSubview(bookTitleLabel)
        recordsColumn.addSubview(progressSectionView)

        tabSelectorView.addSubview(tabDailyButton)
        tabSelectorView.addSubview(tabWeeklyButton)
        tabSelectorView.addSubview(tabMonthlyButton)
        recordsColumn.addSubview(chartTitleLabel)
        recordsColumn.addSubview(tabSelectorView)
        chartCard.layer.addSublayer(chartAreaLayer)
        chartCard.layer.addSublayer(chartLineLayer)
        for grid in chartGridLayers {
            grid.strokeColor = UIColor(hex: "#5d4037", alpha: CGFloat(0x08) / 255).cgColor
            grid.lineWidth = 1
            chartCard.layer.insertSublayer(grid, below: chartLineLayer)
        }
        recordsColumn.addSubview(chartCard)
    }

    private func setupConstraints() {
        updateColumnConstraints()

        timerDialView.snp.makeConstraints { make in
            make.leading.trailing.top.equalToSuperview()
        }

        bookTitleLabel.snp.makeConstraints { make in
            make.top.equalTo(timerDialView.snp.bottom).offset(24)
            make.leading.trailing.bottom.equalToSuperview()
        }

        progressSectionView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
        }

        chartTitleLabel.snp.makeConstraints { make in
            make.top.equalTo(progressSectionView.snp.bottom).offset(40)
            make.leading.equalToSuperview()
        }
        tabSelectorView.snp.makeConstraints { make in
            make.trailing.equalToSuperview()
            make.centerY.equalTo(chartTitleLabel)
            make.height.equalTo(40)
        }
        tabDailyButton.snp.makeConstraints { make in
            make.leading.top.bottom.equalToSuperview().inset(4)
            make.width.equalTo(52)
        }
        tabWeeklyButton.snp.makeConstraints { make in
            make.leading.equalTo(tabDailyButton.snp.trailing)
            make.top.bottom.equalToSuperview().inset(4)
            make.width.equalTo(52)
        }
        tabMonthlyButton.snp.makeConstraints { make in
            make.leading.equalTo(tabWeeklyButton.snp.trailing)
            make.trailing.top.bottom.equalToSuperview().inset(4)
            make.width.equalTo(52)
        }

        chartCard.snp.makeConstraints { make in
            make.top.equalTo(tabSelectorView.snp.bottom).offset(16)
            make.leading.trailing.bottom.equalToSuperview()
            make.height.equalTo(194)
        }
    }

    private func updateColumnConstraints() {
        scrollView.snp.remakeConstraints { make in
            if let columns {
                make.left.equalToSuperview().offset(columns.viewport.minX)
                make.top.equalToSuperview().offset(columns.viewport.minY)
                make.width.equalTo(columns.viewport.width)
                make.height.equalTo(columns.viewport.height)
            } else {
                make.edges.equalTo(view.adaptiveContentLayoutGuide)
            }
        }
        contentView.snp.remakeConstraints { make in
            make.edges.equalTo(scrollView.contentLayoutGuide)
            make.width.equalTo(scrollView.frameLayoutGuide)
            if columns != nil {
                make.height.greaterThanOrEqualTo(scrollView.frameLayoutGuide)
                make.height.equalTo(scrollView.frameLayoutGuide).priority(249)
            }
        }
        timerColumn.snp.remakeConstraints { make in
            make.left.equalToSuperview().offset(24)
            if let columns {
                make.width.equalTo(columns.leadingWidth)
                make.centerY.equalToSuperview()
                make.top.greaterThanOrEqualToSuperview().offset(24)
            } else {
                make.right.equalToSuperview().inset(24)
                make.top.equalToSuperview().offset(24)
            }
        }
        recordsColumn.snp.remakeConstraints { make in
            make.right.equalToSuperview().inset(24)
            if let columns {
                make.left.equalTo(timerColumn.snp.right).offset(columns.gap)
                make.centerY.equalToSuperview()
                make.top.greaterThanOrEqualToSuperview().offset(24)
            } else {
                make.left.equalTo(timerColumn)
                make.top.equalTo(timerColumn.snp.bottom).offset(24)
                make.bottom.equalToSuperview().inset(24)
            }
        }
    }

    // MARK: - Y축 레이블 (viewDidLoad에서 생성 — bounds 불필요)

    private func setupYAxisLabels() {
        let step = (chartBottomY - chartTopY) / 3
        let yPositions: [CGFloat] = (0...3).map { chartTopY + CGFloat($0) * step }
        // [28, 68, 108, 148]

        for pos in yPositions {
            let label = UILabel()
            label.font          = UIFont(name: "GoyangIlsan R", size: 10) ?? .systemFont(ofSize: 10)
            label.textColor     = UIColor.appPrimary.withAlphaComponent(0.5)
            label.textAlignment = .right
            label.frame         = CGRect(x: 2, y: pos - 6, width: 48, height: 12)
            chartCard.addSubview(label)
            yAxisLabels.append(label)
        }
        updateYAxisLabels(scale: 3600)  // 초기 텍스트: 1시간/40분/20분/0분
    }

    // MARK: - 그리드 라인

    private func updateChartGrid() {
        let cardW = chartCard.bounds.width
        let step = (chartBottomY - chartTopY) / 3
        let yPositions: [CGFloat] = (0...3).map { chartTopY + CGFloat($0) * step }

        for (grid, pos) in zip(chartGridLayers, yPositions) {
            let path = UIBezierPath()
            path.move(to: CGPoint(x: chartLeftPad - 2, y: pos))
            path.addLine(to: CGPoint(x: cardW - chartRightPad, y: pos))
            grid.path = path.cgPath
        }
    }

    // MARK: - Chart Rendering

    private func renderChart(points: [ChartPoint]) {
        let maxSeconds = points.map(\.seconds).max() ?? 0
        let scale = niceMaxScale(maxSeconds)
        updateYAxisLabels(scale: scale)
        updateChartPaths(points: points, maxScale: scale)
        updateChartDots(points: points, maxScale: scale)
    }

    private func updateYAxisLabels(scale: Int) {
        let values = [scale, scale * 2 / 3, scale / 3, 0]
        for (label, seconds) in zip(yAxisLabels, values) {
            label.text = formatDuration(seconds)
        }
    }

    private func updateChartPaths(points: [ChartPoint], maxScale: Int) {
        guard points.count >= 2, chartCard.bounds.width > 0 else { return }
        let cardW = chartCard.bounds.width
        let plotW = cardW - chartLeftPad - chartRightPad
        let fillY = chartBottomY + 14  // 0분 라인 아래 여유

        let xs: [CGFloat] = points.indices.map { i in
            chartLeftPad + CGFloat(i) / CGFloat(points.count - 1) * plotW
        }
        let ys = points.map { yPos(seconds: $0.seconds, maxScale: maxScale) }

        let linePath = UIBezierPath()
        linePath.move(to: CGPoint(x: xs[0], y: ys[0]))
        for i in 1..<xs.count {
            let prev = CGPoint(x: xs[i-1], y: ys[i-1])
            let curr = CGPoint(x: xs[i],   y: ys[i])
            let cp1  = CGPoint(x: prev.x + (curr.x - prev.x) * 0.5, y: prev.y)
            let cp2  = CGPoint(x: curr.x - (curr.x - prev.x) * 0.5, y: curr.y)
            linePath.addCurve(to: curr, controlPoint1: cp1, controlPoint2: cp2)
        }

        chartLineLayer.path        = linePath.cgPath
        chartLineLayer.fillColor   = UIColor.clear.cgColor
        chartLineLayer.strokeColor = UIColor.appPrimary.cgColor
        chartLineLayer.lineWidth   = 2.5
        chartLineLayer.lineCap     = .round
        chartLineLayer.lineJoin    = .round

        let areaPath = linePath.copy() as! UIBezierPath
        areaPath.addLine(to: CGPoint(x: xs.last!,  y: fillY))
        areaPath.addLine(to: CGPoint(x: xs.first!, y: fillY))
        areaPath.close()
        chartAreaLayer.path      = areaPath.cgPath
        chartAreaLayer.fillColor = UIColor(hex: "#5d4037", alpha: CGFloat(0x18) / 255).cgColor
    }

    private func updateChartDots(points: [ChartPoint], maxScale: Int) {
        chartDynamicViews.forEach { $0.removeFromSuperview() }
        chartDynamicViews.removeAll()
        guard points.count >= 2, chartCard.bounds.width > 0 else { return }

        let cardW = chartCard.bounds.width
        let plotW = cardW - chartLeftPad - chartRightPad

        for (i, point) in points.enumerated() {
            let x = chartLeftPad + CGFloat(i) / CGFloat(points.count - 1) * plotW
            let y = yPos(seconds: point.seconds, maxScale: maxScale)

            let dot = UIView()
            dot.backgroundColor    = UIColor.appPrimary
            dot.layer.cornerRadius = 4
            dot.layer.borderWidth  = 2
            dot.layer.borderColor  = UIColor.white.cgColor
            dot.frame = CGRect(x: x - 4, y: y - 4, width: 8, height: 8)
            chartCard.addSubview(dot)
            chartDynamicViews.append(dot)

            let xLabel = UILabel()
            xLabel.text          = point.label
            xLabel.font          = UIFont(name: "GoyangIlsan R", size: 10) ?? .systemFont(ofSize: 10)
            xLabel.textColor     = UIColor.appPrimary.withAlphaComponent(0.5)
            xLabel.textAlignment = .center
            xLabel.sizeToFit()
            xLabel.center = CGPoint(x: x, y: chartBottomY + 20)
            chartCard.addSubview(xLabel)
            chartDynamicViews.append(xLabel)
        }
    }

    // MARK: - Chart Helpers

    private func yPos(seconds: Int, maxScale: Int) -> CGFloat {
        guard maxScale > 0 else { return chartBottomY }
        let fraction = CGFloat(seconds) / CGFloat(maxScale)
        return chartBottomY - fraction * (chartBottomY - chartTopY)
    }

    private func niceMaxScale(_ maxSeconds: Int) -> Int {
        if maxSeconds <= 0 { return 3600 }
        let halfHours = (maxSeconds + 1799) / 1800
        return halfHours * 1800
    }

    private func formatDuration(_ seconds: Int) -> String {
        if seconds == 0 { return "0분" }
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if m == 0 { return "\(h)시간" }
        if h == 0 { return "\(m)분" }
        return "\(h)시간\(m)분"
    }

    // MARK: - Progress

    private func configureProgress() {
        progressSectionView.configure(itemPage: currentItemPage, currentPage: currentPage)
    }

    // MARK: - ViewModel Binding

    private func bindViewModel() {
        let output = viewModel.transform(input: ReadingRecordViewModel.Input(
            viewDidAppear: viewDidAppearRelay.asObservable(),
            tabSelected:   tabSelectedRelay.asObservable(),
            timerStopped:  timerStoppedRelay.asObservable()
        ))

        output.chartPoints
            .drive(onNext: { [weak self] points in
                guard let self else { return }
                self.chartPoints = points
                self.renderChart(points: points)
            })
            .disposed(by: disposeBag)
    }

    // MARK: - Bindings

    private func bindActions() {

        progressSectionView.editButtonTap
            .subscribe(onNext: { [weak self] in
                guard let self else { return }
                let vc = PageRecordViewController(
                    isbn13: self.book.isbn13,
                    itemPage: self.currentItemPage,
                    currentPage: self.currentPage
                )
                vc.modalPresentationStyle = .pageSheet
                vc.onProgressRecorded = { [weak self] progress in
                    guard let self else { return }
                    self.currentItemPage = progress.itemPage
                    self.currentPage = progress.currentPage
                    self.progressSectionView.configure(
                        itemPage: progress.itemPage,
                        currentPage: progress.currentPage
                    )
                    self.onProgressRecorded?(progress)
                }
                self.present(vc, animated: true)
            })
            .disposed(by: disposeBag)

        timerDialView.onTimerStopped = { [weak self] elapsed in
            self?.timerStoppedRelay.accept(elapsed)
        }

        if #available(iOS 16.2, *) {
            timerDialView.onTimerActivityEvent = { [weak self] event in
                guard let self else { return }
                let mgr = ReadingActivityManager.shared
                switch event {
                case .started(let total, let remaining, let end):
                    mgr.startActivity(bookTitle: self.book.displayTitle, isbn13: self.book.isbn13,
                                      totalSeconds: total, remainingSeconds: remaining,
                                      timerEndDate: end)
                case .paused(let remaining):
                    mgr.updateActivity(remainingSeconds: remaining, isRunning: false, timerEndDate: nil)
                case .resumed(let remaining, let end):
                    mgr.updateActivity(remainingSeconds: remaining, isRunning: true, timerEndDate: end)
                case .ended(let remaining):
                    mgr.endActivity(remainingSeconds: remaining)
                }
            }
        }

        tabDailyButton.rx.tap
            .subscribe(onNext: { [weak self] in self?.selectTab(0) })
            .disposed(by: disposeBag)
        tabWeeklyButton.rx.tap
            .subscribe(onNext: { [weak self] in self?.selectTab(1) })
            .disposed(by: disposeBag)
        tabMonthlyButton.rx.tap
            .subscribe(onNext: { [weak self] in self?.selectTab(2) })
            .disposed(by: disposeBag)
    }

    // MARK: - Tab Switching

    private func selectTab(_ index: Int) {
        let buttons = [tabDailyButton, tabWeeklyButton, tabMonthlyButton]
        for (i, btn) in buttons.enumerated() {
            if i == index {
                btn.backgroundColor = UIColor.appPrimary
                btn.setTitleColor(.white, for: .normal)
            } else {
                btn.backgroundColor = .clear
                btn.setTitleColor(UIColor.appPrimary, for: .normal)
            }
        }
        tabSelectedRelay.accept(index)
    }

    // MARK: - Helpers

    private func makeTabButton(title: String, selected: Bool) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle(title, for: .normal)
        btn.titleLabel?.font = UIFont(name: "GoyangIlsan R", size: 11) ?? .systemFont(ofSize: 11)
        btn.layer.cornerRadius = 11
        btn.backgroundColor    = selected ? UIColor.appPrimary : .clear
        btn.setTitleColor(selected ? .background : UIColor.appPrimary, for: .normal)
        return btn
    }

    // MARK: - Tutorial

    private func showTutorialIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: "tutorial.readingRecord") else { return }

        let steps: [TutorialStep] = [
            TutorialStep(
                targetFrame: .zero,
                message: "다이얼 바깥쪽을 돌려서 시간을 설정한 후\n시작 버튼을 탭해보세요",
                animation: .dialRotation,
                targetFrameProvider: { [weak self] in
                    guard let target = self?.timerDialView else { return .zero }
                    return target.convert(target.bounds, to: nil)
                }
            ),
        ]

        let tutorialVC = TutorialOverlayViewController()
        tutorialVC.steps = steps
        tutorialVC.modalPresentationStyle = .overFullScreen
        tutorialVC.modalTransitionStyle = .crossDissolve
        tutorialVC.onFinished = {
            UserDefaults.standard.set(true, forKey: "tutorial.readingRecord")
        }
        present(tutorialVC, animated: true)
    }
}
