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

final class ReadingRecordViewController: UIViewController {

    var onPageRecorded: ((Int) -> Void)?

    private let book: Book
    private let currentItemPage: Int?
    private let initialPage: Int?
    private let disposeBag = DisposeBag()

    private lazy var viewModel = ReadingRecordViewModel(
        book: book,
        readingSessionRepository: AppContainer.shared.readingSessionRepository,
        bookRepository: AppContainer.shared.bookRepository
    )
    private let viewDidAppearRelay = PublishRelay<Void>()
    private let tabSelectedRelay   = BehaviorRelay<Int>(value: 0)
    private let timerStoppedRelay  = PublishRelay<Int>()
    private let pageRecordedRelay  = PublishRelay<Int>()

    init(book: Book, currentItemPage: Int?, initialPage: Int?) {
        self.book = book
        self.currentItemPage = currentItemPage
        self.initialPage = initialPage
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Chart State

    private var gridReady = false           // 그리드 라인 1회만 추가
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

    // MARK: - Header

    private lazy var backButton: UIButton = {
        let btn = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        btn.setImage(UIImage(systemName: "chevron.left", withConfiguration: cfg), for: .normal)
        btn.tintColor = UIColor.accent
        return btn
    }()

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.text = "독서 기록"
        l.font = UIFont(name: "GowunBatang-Bold", size: 34)
            ?? .systemFont(ofSize: 34, weight: .bold)
        l.textColor = UIColor.accent
        return l
    }()

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

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.interactivePopGestureRecognizer?.delegate = nil
        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // bounds가 확정된 시점에 그리드 1회 추가
        if !gridReady {
            gridReady = true
            setupChartGrid()
        }
        viewDidAppearRelay.accept(())
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = UIColor.background
        bookTitleLabel.text = book.title

        view.addSubview(scrollView)
        scrollView.addSubview(contentView)

        contentView.addSubview(backButton)
        contentView.addSubview(titleLabel)
        contentView.addSubview(timerDialView)
        contentView.addSubview(bookTitleLabel)
        contentView.addSubview(progressSectionView)

        tabSelectorView.addSubview(tabDailyButton)
        tabSelectorView.addSubview(tabWeeklyButton)
        tabSelectorView.addSubview(tabMonthlyButton)
        contentView.addSubview(chartTitleLabel)
        contentView.addSubview(tabSelectorView)
        chartCard.layer.addSublayer(chartAreaLayer)
        chartCard.layer.addSublayer(chartLineLayer)
        contentView.addSubview(chartCard)
    }

    private func setupConstraints() {
        scrollView.snp.makeConstraints { make in
            make.edges.equalTo(view.safeAreaLayoutGuide)
        }
        contentView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            make.width.equalTo(scrollView)
        }

        backButton.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(24)
            make.top.equalToSuperview().offset(17)
            make.size.equalTo(28)
        }
        titleLabel.snp.makeConstraints { make in
            make.leading.equalTo(backButton.snp.trailing).offset(4)
            make.centerY.equalTo(backButton)
        }

        timerDialView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.top.equalTo(backButton.snp.bottom).offset(32)
        }

        bookTitleLabel.snp.makeConstraints { make in
            make.top.equalTo(timerDialView.snp.bottom).offset(24)
            make.leading.trailing.equalToSuperview().inset(24)
        }

        progressSectionView.snp.makeConstraints { make in
            make.top.equalTo(bookTitleLabel.snp.bottom).offset(24)
            make.leading.trailing.equalToSuperview().inset(24)
        }

        chartTitleLabel.snp.makeConstraints { make in
            make.top.equalTo(progressSectionView.snp.bottom).offset(40)
            make.leading.equalToSuperview().inset(24)
        }
        tabSelectorView.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(24)
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
            make.leading.trailing.equalToSuperview().inset(24)
            make.height.equalTo(194)
            make.bottom.equalToSuperview().inset(24)
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
            label.textColor     = UIColor.primary.withAlphaComponent(0.5)
            label.textAlignment = .right
            label.frame         = CGRect(x: 2, y: pos - 6, width: 48, height: 12)
            chartCard.addSubview(label)
            yAxisLabels.append(label)
        }
        updateYAxisLabels(scale: 3600)  // 초기 텍스트: 1시간/40분/20분/0분
    }

    // MARK: - 그리드 라인 (viewDidAppear에서 생성 — bounds 필요)

    private func setupChartGrid() {
        let cardW = chartCard.bounds.width
        let step = (chartBottomY - chartTopY) / 3
        let yPositions: [CGFloat] = (0...3).map { chartTopY + CGFloat($0) * step }

        for pos in yPositions {
            let grid = CAShapeLayer()
            let path = UIBezierPath()
            path.move(to: CGPoint(x: chartLeftPad - 2, y: pos))
            path.addLine(to: CGPoint(x: cardW - chartRightPad, y: pos))
            grid.path        = path.cgPath
            grid.strokeColor = UIColor(hex: "#5d4037", alpha: CGFloat(0x08) / 255).cgColor
            grid.lineWidth   = 1
            chartCard.layer.insertSublayer(grid, below: chartLineLayer)
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
        chartLineLayer.strokeColor = UIColor.primary.cgColor
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
            dot.backgroundColor    = UIColor.primary
            dot.layer.cornerRadius = 4
            dot.layer.borderWidth  = 2
            dot.layer.borderColor  = UIColor.white.cgColor
            dot.frame = CGRect(x: x - 4, y: y - 4, width: 8, height: 8)
            chartCard.addSubview(dot)
            chartDynamicViews.append(dot)

            let xLabel = UILabel()
            xLabel.text          = point.label
            xLabel.font          = UIFont(name: "GoyangIlsan R", size: 10) ?? .systemFont(ofSize: 10)
            xLabel.textColor     = UIColor.primary.withAlphaComponent(0.5)
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
        guard let itemPage = currentItemPage else { return }
        if let page = initialPage, page > 0 {
            progressSectionView.configure(currentPage: page, itemPage: itemPage)
        } else {
            progressSectionView.showNoProgress(itemPage: itemPage)
        }
    }

    // MARK: - ViewModel Binding

    private func bindViewModel() {
        let output = viewModel.transform(input: ReadingRecordViewModel.Input(
            viewDidAppear: viewDidAppearRelay.asObservable(),
            tabSelected:   tabSelectedRelay.asObservable(),
            timerStopped:  timerStoppedRelay.asObservable(),
            pageRecorded:  pageRecordedRelay.asObservable()
        ))

        output.chartPoints
            .drive(onNext: { [weak self] points in
                self?.renderChart(points: points)
            })
            .disposed(by: disposeBag)
    }

    // MARK: - Bindings

    private func bindActions() {
        backButton.rx.tap
            .subscribe(onNext: { [weak self] in
                self?.navigationController?.popViewController(animated: true)
            })
            .disposed(by: disposeBag)

        progressSectionView.editButtonTap
            .subscribe(onNext: { [weak self] in
                guard let self, let itemPage = self.currentItemPage else { return }
                let vc = PageRecordViewController(itemPage: itemPage)
                vc.modalPresentationStyle = .pageSheet
                vc.onPageRecorded = { [weak self] page in
                    guard let self else { return }
                    self.progressSectionView.configure(currentPage: page, itemPage: itemPage)
                    self.onPageRecorded?(page)
                    self.pageRecordedRelay.accept(page)
                }
                self.present(vc, animated: true)
            })
            .disposed(by: disposeBag)

        timerDialView.onTimerStopped = { [weak self] elapsed in
            self?.timerStoppedRelay.accept(elapsed)
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
                btn.backgroundColor = UIColor.primary
                btn.setTitleColor(.white, for: .normal)
            } else {
                btn.backgroundColor = .clear
                btn.setTitleColor(UIColor.primary, for: .normal)
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
        btn.backgroundColor    = selected ? UIColor.primary : .clear
        btn.setTitleColor(selected ? .background : UIColor.primary, for: .normal)
        return btn
    }
}
