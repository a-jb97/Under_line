//
//  StatisticsViewController.swift
//  Under_line
//
//  통계 탭 — 독서량 히트맵 / 밑줄 장르 도넛 차트 / 독서 시간 라인 차트
//

import UIKit
import SnapKit
import RxSwift
import RxCocoa

// MARK: - StatisticsViewController

final class StatisticsViewController: UIViewController {

    private let disposeBag          = DisposeBag()
    private let viewWillAppearRelay = PublishRelay<Void>()
    private lazy var viewModel = StatisticsViewModel(
        readingSessionRepository: AppContainer.shared.readingSessionRepository,
        bookRepository:           AppContainer.shared.bookRepository,
        sentenceRepository:       AppContainer.shared.sentenceRepository
    )

    // MARK: UI

    private let scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.showsVerticalScrollIndicator = false
        sv.alwaysBounceVertical = true
        return sv
    }()

    private let contentStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .vertical
        sv.spacing = 28
        return sv
    }()

    // 헤더
    private let titleLabel: UILabel = {
        let l = UILabel()
        l.text = "통계"
        l.font = UIFont(name: "GowunBatang-Bold", size: 34) ?? .systemFont(ofSize: 34, weight: .bold)
        l.textColor = .accent
        return l
    }()

    // 히트맵 카드
    private let heatmapCard = HeatmapCardView()

    // 장르/저자 카드
    private let genreCard = GenreAuthorCardView()

    // 라인 차트 카드
    private let lineChartCard = LineChartCardView()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .background
        setupUI()
        setupConstraints()
        bindViewModel()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewWillAppearRelay.accept(())
    }

    // MARK: - Setup

    private func setupUI() {
        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)

        let headerContainer = UIView()
        headerContainer.addSubview(titleLabel)
        headerContainer.snp.makeConstraints { make in
            make.height.equalTo(54)
        }
        titleLabel.snp.makeConstraints { make in
            make.leading.centerY.equalToSuperview()
            make.trailing.lessThanOrEqualToSuperview()
        }

        contentStack.addArrangedSubview(headerContainer)
        contentStack.addArrangedSubview(heatmapCard)
        contentStack.addArrangedSubview(genreCard)
        contentStack.addArrangedSubview(lineChartCard)
    }

    private func setupConstraints() {
        scrollView.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide)
            make.leading.trailing.bottom.equalToSuperview()
        }

        contentStack.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.bottom.equalToSuperview().inset(24)
            make.leading.trailing.equalToSuperview().inset(24)
            make.width.equalTo(scrollView).offset(-48)
        }
    }

    // MARK: - ViewModel Binding

    private func bindViewModel() {
        let output = viewModel.transform(input: StatisticsViewModel.Input(
            viewWillAppear: viewWillAppearRelay.asObservable()
        ))

        output.allSessions
            .drive(onNext: { [weak self] sessions in
                self?.heatmapCard.configure(with: sessions)
            })
            .disposed(by: disposeBag)

        Driver.combineLatest(output.genreData, output.authorData)
            .drive(onNext: { [weak self] genreData, authorData in
                self?.genreCard.configure(genreData: genreData, authorData: authorData)
                self?.genreCard.animateIn()
            })
            .disposed(by: disposeBag)
    }
}

// MARK: - HeatmapCardView

final class HeatmapCardView: UIView {

    private var currentYear = Calendar.current.component(.year, from: Date())
    private var currentMonth = Calendar.current.component(.month, from: Date())
    private var allSessions: [ReadingSession] = []
    private let disposeBag = DisposeBag()

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.text = "독서량"
        l.font = UIFont(name: "GoyangIlsan R", size: 18)
            ?? .systemFont(ofSize: 18, weight: .semibold)
        l.textColor = .accent
        return l
    }()

    private let prevButton: UIButton = {
        let b = UIButton(type: .system)
        b.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        b.tintColor = UIColor(hex: "#5d4037").withAlphaComponent(0.5)
        return b
    }()

    private let nextButton: UIButton = {
        let b = UIButton(type: .system)
        b.setImage(UIImage(systemName: "chevron.right"), for: .normal)
        b.tintColor = UIColor(hex: "#5d4037").withAlphaComponent(0.5)
        return b
    }()

    private let periodLabel: UILabel = {
        let l = UILabel()
        l.font = UIFont(name: "GoyangIlsan R", size: 13)
            ?? .systemFont(ofSize: 13)
        l.textColor = UIColor(hex: "#5d4037").withAlphaComponent(0.6)
        l.textAlignment = .center
        return l
    }()

    private let heatmapBody = HeatmapBodyView()

    private let legendStack: UIStackView = {
        let s = UIStackView()
        s.axis = .horizontal
        s.spacing = 4
        s.alignment = .center
        return s
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        backgroundColor = .white
        layer.cornerRadius = 16
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = Float(CGFloat(0x16) / 255)
        layer.shadowRadius = 24
        layer.shadowOffset = CGSize(width: 0, height: 8)

        updatePeriodLabel()

        prevButton.rx.tap
            .subscribe(onNext: { [weak self] in
                guard let self else { return }
                self.currentMonth -= 1
                if self.currentMonth == 0 { self.currentMonth = 12; self.currentYear -= 1 }
                self.updatePeriodLabel()
                self.reloadHeatmap()
            })
            .disposed(by: disposeBag)

        nextButton.rx.tap
            .subscribe(onNext: { [weak self] in
                guard let self else { return }
                self.currentMonth += 1
                if self.currentMonth == 13 { self.currentMonth = 1; self.currentYear += 1 }
                self.updatePeriodLabel()
                self.reloadHeatmap()
            })
            .disposed(by: disposeBag)

        let periodTap = UITapGestureRecognizer()
        periodLabel.isUserInteractionEnabled = true
        periodLabel.addGestureRecognizer(periodTap)
        periodTap.rx.event
            .subscribe(onNext: { [weak self] _ in self?.showPeriodPicker() })
            .disposed(by: disposeBag)

        reloadHeatmap()

        // 타이틀 행: 좌측 "독서량", 우측 "< 2026년 X월 >"
        let titleRow = UIView()
        titleRow.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { $0.leading.top.bottom.equalToSuperview() }

        let navStack = UIStackView(arrangedSubviews: [prevButton, periodLabel, nextButton])
        navStack.axis = .horizontal
        navStack.spacing = 6
        navStack.alignment = .center
        prevButton.snp.makeConstraints { $0.size.equalTo(20) }
        nextButton.snp.makeConstraints { $0.size.equalTo(20) }

        titleRow.addSubview(navStack)
        navStack.snp.makeConstraints { make in
            make.trailing.top.bottom.equalToSuperview()
        }

        buildLegend()

        let vStack = UIStackView(arrangedSubviews: [titleRow, heatmapBody, legendStack])
        vStack.axis = .vertical
        vStack.spacing = 16

        addSubview(vStack)
        vStack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(20)
        }
    }

    private func updatePeriodLabel() {
        periodLabel.text = "\(currentYear)년 \(currentMonth)월"
    }

    private func showPeriodPicker() {
        guard let vc = findViewController() else { return }
        let picker = MonthYearPickerViewController(year: currentYear, month: currentMonth)
        picker.onConfirm = { [weak self] year, month in
            self?.currentYear = year
            self?.currentMonth = month
            self?.updatePeriodLabel()
            self?.reloadHeatmap()
        }
        picker.modalPresentationStyle = .pageSheet
        if let sheet = picker.sheetPresentationController {
            sheet.detents = [.custom { _ in 290 }]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 20
        }
        vc.present(picker, animated: true)
    }

    private func findViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let r = responder {
            if let vc = r as? UIViewController { return vc }
            responder = r.next
        }
        return nil
    }

    func configure(with sessions: [ReadingSession]) {
        allSessions = sessions
        reloadHeatmap()
    }

    private func reloadHeatmap() {
        heatmapBody.days = buildGrid()
    }

    private func buildGrid() -> [[HeatmapDay]] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")

        // 날짜별 독서 시간 합산
        var durationByDay: [Date: Int] = [:]
        for session in allSessions {
            let dayStart = calendar.startOfDay(for: session.date)
            durationByDay[dayStart, default: 0] += session.durationSeconds
        }

        // 전월 1일 계산
        var prevMonth = currentMonth - 1
        var prevYear = currentYear
        if prevMonth == 0 { prevMonth = 12; prevYear -= 1 }

        guard let prevMonthFirstDay = calendar.date(
            from: DateComponents(year: prevYear, month: prevMonth, day: 1)
        ) else { return [] }

        // 전월 1일이 속한 주의 월요일 → 그리드 시작일
        // weekday: 1=일, 2=월, 3=화, ... 7=토
        let weekday = calendar.component(.weekday, from: prevMonthFirstDay)
        let mondayOffset = weekday == 1 ? -6 : -(weekday - 2)
        guard let gridStart = calendar.date(
            byAdding: .day, value: mondayOffset, to: prevMonthFirstDay
        ) else { return [] }

        // 7행(요일) × 11열(주) 그리드 생성
        var grid: [[HeatmapDay]] = Array(repeating: [], count: 7)
        for col in 0..<11 {
            for row in 0..<7 {
                let offset = col * 7 + row
                guard let date = calendar.date(byAdding: .day, value: offset, to: gridStart) else { continue }
                let dayStart = calendar.startOfDay(for: date)
                let duration = durationByDay[dayStart] ?? 0
                let intensity = Self.intensityLevel(seconds: duration)
                let comps = calendar.dateComponents([.year, .month], from: date)
                let isCurrentMonth = comps.year == currentYear && comps.month == currentMonth
                grid[row].append(HeatmapDay(date: date, intensity: intensity, isCurrentMonth: isCurrentMonth))
            }
        }
        return grid
    }

    private static func intensityLevel(seconds: Int) -> Int {
        switch seconds {
        case 0:            return 0
        case 1...600:      return 1
        case 601...1800:   return 2
        case 1801...3600:  return 3
        default:           return 4
        }
    }

    private func buildLegend() {
        let lessLabel = UILabel()
        lessLabel.text = "적음"
        lessLabel.font = .systemFont(ofSize: 10)
        lessLabel.textColor = UIColor(hex: "#5d4037", alpha: CGFloat(0x66) / 255)

        let moreLabel = UILabel()
        moreLabel.text = "많음"
        moreLabel.font = .systemFont(ofSize: 10)
        moreLabel.textColor = UIColor(hex: "#5d4037", alpha: CGFloat(0x66) / 255)

        let alphas: [CGFloat] = [
            CGFloat(0x0A) / 255,
            CGFloat(0x30) / 255,
            CGFloat(0x60) / 255,
            CGFloat(0xA0) / 255,
            1.0
        ]

        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        legendStack.addArrangedSubview(spacer)
        legendStack.addArrangedSubview(lessLabel)
        for a in alphas {
            let dot = UIView()
            dot.backgroundColor = UIColor(hex: "#5d4037", alpha: a)
            dot.layer.cornerRadius = 3
            dot.snp.makeConstraints { $0.size.equalTo(12) }
            legendStack.addArrangedSubview(dot)
        }
        legendStack.addArrangedSubview(moreLabel)
    }
}

// MARK: - HeatmapDay

struct HeatmapDay {
    let date: Date
    let intensity: Int        // 0 = 없음, 1–4 = 독서량 단계
    let isCurrentMonth: Bool
}

// MARK: - HeatmapBodyView

final class HeatmapBodyView: UIView {

    private static let cols = 11
    private static let rows = 7
    private static let gap: CGFloat = 4
    private static let labelWidth: CGFloat = 18
    private static let labelGridGap: CGFloat = 6

    private let weekdayLabels = ["월", "화", "수", "목", "금", "토", "일"]
    private let walnut = UIColor(hex: "#5d4037")

    var days: [[HeatmapDay]] = [] { didSet { needsRebuild = true; setNeedsLayout() } }

    private var cellButtons: [[UIButton]] = []
    private var selectedCell: (row: Int, col: Int)?
    private var lastWidth: CGFloat = 0
    private var needsRebuild = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
    }
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: CGSize {
        let w = bounds.width > 0 ? bounds.width : 300
        let gridW = w - Self.labelWidth - Self.labelGridGap
        let cellSize = (gridW - CGFloat(Self.cols - 1) * Self.gap) / CGFloat(Self.cols)
        let h = CGFloat(Self.rows) * cellSize + CGFloat(Self.rows - 1) * Self.gap
        return CGSize(width: UIView.noIntrinsicMetric, height: max(h, 0))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0 else { return }
        if abs(bounds.width - lastWidth) > 0.5 || needsRebuild {
            lastWidth = bounds.width
            needsRebuild = false
            buildCells()
            invalidateIntrinsicContentSize()
        }
    }

    private func buildCells() {
        subviews.forEach { $0.removeFromSuperview() }
        cellButtons = []

        let gridW = bounds.width - Self.labelWidth - Self.labelGridGap
        let cellSize = (gridW - CGFloat(Self.cols - 1) * Self.gap) / CGFloat(Self.cols)
        let gridX = Self.labelWidth + Self.labelGridGap

        let alphas: [CGFloat] = [
            CGFloat(0x0A) / 255,
            CGFloat(0x30) / 255,
            CGFloat(0x60) / 255,
            CGFloat(0xA0) / 255,
            1.0
        ]

        // 요일 레이블 (월 ~ 일)
        for (i, day) in weekdayLabels.enumerated() {
            let lbl = UILabel()
            lbl.text = day
            lbl.font = UIFont(name: "GoyangIlsan R", size: 11) ?? .systemFont(ofSize: 11)
            lbl.textColor = walnut.withAlphaComponent(0.5)
            lbl.textAlignment = .right
            lbl.sizeToFit()
            let cy = CGFloat(i) * (cellSize + Self.gap) + cellSize / 2
            lbl.frame = CGRect(
                x: Self.labelWidth - lbl.frame.width - 2,
                y: cy - lbl.frame.height / 2,
                width: lbl.frame.width,
                height: lbl.frame.height
            )
            addSubview(lbl)
        }

        // 그리드 셀 (정방형)
        for r in 0..<Self.rows {
            var row: [UIButton] = []
            for c in 0..<Self.cols {
                let btn = UIButton()
                let x = gridX + CGFloat(c) * (cellSize + Self.gap)
                let y = CGFloat(r) * (cellSize + Self.gap)
                btn.frame = CGRect(x: x, y: y, width: cellSize, height: cellSize)
                btn.layer.cornerRadius = 5
                btn.tag = r * Self.cols + c
                btn.addTarget(self, action: #selector(cellTapped(_:)), for: .touchUpInside)

                let day = (r < days.count && c < days[r].count) ? days[r][c] : nil
                let level = day?.intensity ?? 0
                let baseAlpha = alphas[min(level, alphas.count - 1)]
                let alpha = (day?.isCurrentMonth ?? true) ? baseAlpha : baseAlpha * 0.35
                btn.backgroundColor = walnut.withAlphaComponent(alpha)

                addSubview(btn)
                row.append(btn)
            }
            cellButtons.append(row)
        }

        applySelection()
    }

    @objc private func cellTapped(_ sender: UIButton) {
        let r = sender.tag / Self.cols
        let c = sender.tag % Self.cols
        selectedCell = (selectedCell?.row == r && selectedCell?.col == c) ? nil : (r, c)
        applySelection()
    }

    private func applySelection() {
        for (r, row) in cellButtons.enumerated() {
            for (c, btn) in row.enumerated() {
                let isSelected = selectedCell?.row == r && selectedCell?.col == c
                btn.layer.borderColor = isSelected ? walnut.cgColor : UIColor.clear.cgColor
                btn.layer.borderWidth = isSelected ? 2 : 0
            }
        }
    }
}

// MARK: - GenreAuthorCardView

final class GenreAuthorCardView: UIView {

    private let segmentControl = NeumorphicSegmentView(items: ["장르별", "저자별"])
    private let donutView      = DonutChartView()
    private let legendStack: UIStackView = {
        let s = UIStackView()
        s.axis = .vertical
        s.spacing = 10
        return s
    }()
    private let disposeBag = DisposeBag()

    private var genreData  = SentenceDonutData.empty
    private var authorData = SentenceDonutData.empty

    private static let palette: [UIColor] = [
        UIColor(hex: "#5d4037"),
        UIColor(hex: "#8D6E63"),
        UIColor(hex: "#BCAAA4"),
        UIColor(hex: "#D7CCC8"),
        UIColor(hex: "#EFEBE9"),
    ]

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(genreData: SentenceDonutData, authorData: SentenceDonutData) {
        self.genreData  = genreData
        self.authorData = authorData
        updateChart(for: segmentControl.selectedIndex)
    }

    func animateIn() {
        donutView.animateIn()
    }

    private func setup() {
        backgroundColor = .white
        layer.cornerRadius = 16
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = Float(CGFloat(0x16) / 255)
        layer.shadowRadius = 24
        layer.shadowOffset = CGSize(width: 0, height: 8)

        let titleLabel = UILabel()
        titleLabel.text = "보관한 밑줄"
        titleLabel.font = UIFont(name: "GoyangIlsan R", size: 18)
            ?? .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.textColor = .accent

        let vStack = UIStackView(arrangedSubviews: [titleLabel, segmentControl, donutView, legendStack])
        vStack.axis = .vertical
        vStack.spacing = 16

        addSubview(vStack)
        vStack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(20)
        }

        segmentControl.snp.makeConstraints { $0.height.equalTo(32) }
        donutView.snp.makeConstraints { $0.height.equalTo(180) }

        segmentControl.selectionChanged
            .subscribe(onNext: { [weak self] index in
                self?.updateChart(for: index)
            })
            .disposed(by: disposeBag)
    }

    private func updateChart(for index: Int) {
        let data     = index == 0 ? genreData : authorData
        let segments = makeSegments(from: data)
        donutView.segments = segments
        donutView.setCenterText(count: data.total)
        rebuildLegend(segments: segments, data: data)
    }

    private func makeSegments(from data: SentenceDonutData) -> [DonutChartView.Segment] {
        guard data.total > 0 else { return [] }
        return data.items.enumerated().map { i, item in
            let ratio = CGFloat(item.count) / CGFloat(data.total)
            let color = Self.palette[min(i, Self.palette.count - 1)]
            return DonutChartView.Segment(label: item.label, value: ratio, color: color)
        }
    }

    private func rebuildLegend(segments: [DonutChartView.Segment], data: SentenceDonutData) {
        legendStack.arrangedSubviews.forEach {
            legendStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        for seg in segments {
            let count = data.items.first { $0.label == seg.label }?.count ?? 0
            legendStack.addArrangedSubview(legendItem(segment: seg, count: count))
        }
    }

    private func legendItem(segment: DonutChartView.Segment, count: Int) -> UIView {
        let dot = UIView()
        dot.backgroundColor = segment.color
        dot.layer.cornerRadius = 5
        dot.snp.makeConstraints { $0.size.equalTo(10) }

        let lbl = UILabel()
        lbl.text = "\(segment.label)  \(count)"
        lbl.font = UIFont(name: "GoyangIlsan R", size: 13) ?? .systemFont(ofSize: 13)
        lbl.textColor = .accent

        let row = UIStackView(arrangedSubviews: [dot, lbl])
        row.axis = .horizontal
        row.spacing = 8
        row.alignment = .center
        return row
    }
}

// MARK: - NeumorphicSegmentView

final class NeumorphicSegmentView: UIView {

    private let items: [String]
    var selectedIndex = 0 { didSet { updateSelection() } }

    private var buttons: [UIButton] = []
    private let selector       = UIView()
    private let disposeBag     = DisposeBag()
    private let selectionRelay = PublishRelay<Int>()

    var selectionChanged: Observable<Int> { selectionRelay.asObservable() }

    init(items: [String]) {
        self.items = items
        super.init(frame: .zero)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        backgroundColor = .background
        layer.cornerRadius = 12

        // neumorphic shadow
        layer.shadowColor = UIColor(hex: "#c9c2c1").cgColor
        layer.shadowOpacity = 1
        layer.shadowRadius = 8
        layer.shadowOffset = CGSize(width: 4, height: 4)

        selector.backgroundColor = .primary
        selector.layer.cornerRadius = 8
        selector.layer.shadowColor = UIColor(hex: "#c9c2c1").cgColor
        selector.layer.shadowOpacity = 1
        selector.layer.shadowRadius = 4
        selector.layer.shadowOffset = CGSize(width: -2, height: -2)
        addSubview(selector)

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 4
        addSubview(stack)

        stack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(4)
        }

        for (i, title) in items.enumerated() {
            let btn = UIButton(type: .system)
            btn.setTitle(title, for: .normal)
            btn.titleLabel?.font = UIFont(name: "GoyangIlsan R", size: 13) ?? .systemFont(ofSize: 13)
            btn.layer.cornerRadius = 8
            btn.clipsToBounds = true
            btn.rx.tap
                .map { i }
                .subscribe(onNext: { [weak self] index in
                    self?.selectedIndex = index
                    self?.selectionRelay.accept(index)
                })
                .disposed(by: disposeBag)
            buttons.append(btn)
            stack.addArrangedSubview(btn)
        }

        updateSelection()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateSelectorFrame()
    }

    private func updateSelection() {
        guard !buttons.isEmpty else { return }
        for (i, btn) in buttons.enumerated() {
            let isSelected = i == selectedIndex
            btn.tintColor = isSelected ? .background : UIColor.primary
            btn.backgroundColor = isSelected ? .primary : .clear
        }
        updateSelectorFrame()
    }

    private func updateSelectorFrame() {
        guard !buttons.isEmpty, selectedIndex < buttons.count else { return }
        let btn = buttons[selectedIndex]
        let converted = btn.convert(btn.bounds, to: self)
        selector.frame = converted
    }
}

// MARK: - DonutChartView

final class DonutChartView: UIView {

    struct Segment {
        let label: String
        let value: CGFloat
        let color: UIColor
    }

    var segments: [Segment] = [] { didSet { updateLayers() } }

    // MARK: Layer hierarchy (back → front)
    // stroke rim 레이어 제거 → 층 분리 현상 해소
    // 중앙/배경을 흰색으로 통일 → 카드 배경과 자연스럽게 어울림
    private let darkShadowLayer    = CAShapeLayer()    // raised 어두운 그림자
    private let lightShadowLayer   = CAShapeLayer()    // raised 밝은 그림자
    private let bgCircleLayer      = CAShapeLayer()    // 원 배경
    private var segmentLayers      = [CAShapeLayer]()  // 색상 세그먼트 (동적)
    private let ringHighlightLayer = CAGradientLayer() // 링 대각선 하이라이트
    private let ringHighlightMask  = CAShapeLayer()    // annulus 마스크
    private let centerFillLayer        = CALayer()          // 중앙 구멍 (흰색)
    private let innerDarkShadowLayer   = CAShapeLayer()    // inset 어두운 그림자
    private let innerLightShadowLayer  = CAShapeLayer()    // inset 밝은 그림자

    private let neumDark  = UIColor(hex: "#b5a09b")
    private let neumLight = UIColor.white

    private var pendingAnimationDuration: TimeInterval? = nil

    private let centerLabel: UILabel = {
        let l = UILabel()
        l.textAlignment = .center
        l.numberOfLines = 2
        return l
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        setupLayers()
        addSubview(centerLabel)
        centerLabel.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.lessThanOrEqualTo(80)
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setupLayers() {
        // ── 외부 raised 그림자 ──────────────────────────────
        darkShadowLayer.fillColor     = UIColor.clear.cgColor
        darkShadowLayer.shadowColor   = neumDark.cgColor
        darkShadowLayer.shadowOpacity = 0.65
        darkShadowLayer.shadowRadius  = 12
        darkShadowLayer.shadowOffset  = CGSize(width: 7, height: 7)
        layer.addSublayer(darkShadowLayer)

        lightShadowLayer.fillColor     = UIColor.clear.cgColor
        lightShadowLayer.shadowColor   = neumLight.cgColor
        lightShadowLayer.shadowOpacity = 1.0
        lightShadowLayer.shadowRadius  = 12
        lightShadowLayer.shadowOffset  = CGSize(width: -7, height: -7)
        layer.addSublayer(lightShadowLayer)

        // ── 원 배경 (흰색) ───────────────────────────────────
        bgCircleLayer.fillColor = UIColor.white.cgColor
        layer.addSublayer(bgCircleLayer)

        // (세그먼트: updateLayers에서 ringHighlightLayer 아래에 동적 삽입)

        // ── 링 대각선 하이라이트 (evenOdd annulus 마스크로 링 영역만 적용) ─
        ringHighlightLayer.colors     = [
            UIColor.white.withAlphaComponent(0.16).cgColor,
            UIColor.clear.cgColor,
        ]
        ringHighlightLayer.startPoint = CGPoint(x: 0, y: 0)
        ringHighlightLayer.endPoint   = CGPoint(x: 1, y: 1)
        ringHighlightMask.fillRule    = .evenOdd
        ringHighlightLayer.mask       = ringHighlightMask
        layer.addSublayer(ringHighlightLayer)

        // ── 중앙 구멍 (카드 흰색 배경과 동일) ──────────────
        centerFillLayer.backgroundColor = UIColor.white.cgColor
        layer.addSublayer(centerFillLayer)

        // ── 중앙 원 raised 그림자 (링 안쪽으로 퍼지는 바깥 그림자) ─
        // 외부 링과 동일한 광원(좌상단): 어두운 그림자 우하단, 밝은 그림자 좌상단
        innerDarkShadowLayer.fillColor     = UIColor.white.cgColor
        innerDarkShadowLayer.shadowColor   = neumDark.cgColor
        innerDarkShadowLayer.shadowOpacity = 0.55
        innerDarkShadowLayer.shadowRadius  = 8
        innerDarkShadowLayer.shadowOffset  = CGSize(width: 5, height: 5)
        layer.addSublayer(innerDarkShadowLayer)

        innerLightShadowLayer.fillColor     = UIColor.white.cgColor
        innerLightShadowLayer.shadowColor   = neumLight.cgColor
        innerLightShadowLayer.shadowOpacity = 0.9
        innerLightShadowLayer.shadowRadius  = 8
        innerLightShadowLayer.shadowOffset  = CGSize(width: -5, height: -5)
        layer.addSublayer(innerLightShadowLayer)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateLayers()
        if let duration = pendingAnimationDuration, !segmentLayers.isEmpty {
            pendingAnimationDuration = nil
            performAnimation(duration: duration)
        }
    }

    private func updateLayers() {
        guard bounds.width > 0, bounds.height > 0 else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let outerR = min(bounds.width, bounds.height) / 2 - 8
        let innerR = outerR * 0.55

        let outerPath = UIBezierPath(ovalIn: CGRect(
            x: center.x - outerR, y: center.y - outerR,
            width: outerR * 2, height: outerR * 2
        )).cgPath

        // 외부 raised 그림자
        for sl in [darkShadowLayer, lightShadowLayer] {
            sl.frame      = bounds
            sl.shadowPath = outerPath
        }

        // 원 배경
        bgCircleLayer.frame = bounds
        bgCircleLayer.path  = outerPath

        // 세그먼트 재구성
        segmentLayers.forEach { $0.removeFromSuperlayer() }
        segmentLayers = []

        if !segments.isEmpty {
            let midR = (outerR + innerR) / 2
            let lineWidth = outerR - innerR
            var startAngle: CGFloat = -.pi / 2
            for seg in segments {
                let endAngle = startAngle + .pi * 2 * seg.value
                let path = UIBezierPath(arcCenter: center, radius: midR,
                                        startAngle: startAngle, endAngle: endAngle, clockwise: true)

                let sl = CAShapeLayer()
                sl.path        = path.cgPath
                sl.fillColor   = UIColor.clear.cgColor
                sl.strokeColor = seg.color.cgColor
                sl.lineWidth   = lineWidth
                sl.lineCap     = .butt
                sl.strokeEnd   = 1.0
                self.layer.insertSublayer(sl, below: ringHighlightLayer)
                segmentLayers.append(sl)

                startAngle = endAngle
            }
        }

        // 링 하이라이트 — annulus(도넛 링) 영역 마스크
        ringHighlightLayer.frame = bounds
        let annulusPath = UIBezierPath(ovalIn: CGRect(
            x: center.x - outerR, y: center.y - outerR,
            width: outerR * 2, height: outerR * 2
        ))
        annulusPath.append(UIBezierPath(ovalIn: CGRect(
            x: center.x - innerR, y: center.y - innerR,
            width: innerR * 2, height: innerR * 2
        )))
        ringHighlightMask.frame = bounds
        ringHighlightMask.path  = annulusPath.cgPath

        // 중앙 구멍 (흰색)
        let d = innerR * 2
        let innerRect = CGRect(x: center.x - innerR, y: center.y - innerR, width: d, height: d)
        centerFillLayer.frame        = innerRect
        centerFillLayer.cornerRadius = innerR

        // 중앙 원 raised 그림자: 원 자체를 path로 설정 → 그림자가 바깥(링)으로 퍼짐
        let holePath = UIBezierPath(ovalIn: innerRect)
        for sl in [innerDarkShadowLayer, innerLightShadowLayer] {
            sl.frame = bounds
            sl.path  = holePath.cgPath
            sl.mask  = nil
        }
    }

    func animateIn(duration: TimeInterval = 0.5) {
        guard !segments.isEmpty else { return }
        if bounds.width > 0 && !segmentLayers.isEmpty {
            performAnimation(duration: duration)
        } else {
            pendingAnimationDuration = duration
        }
    }

    private func performAnimation(duration: TimeInterval) {
        var elapsedFraction: CGFloat = 0
        for (i, sl) in segmentLayers.enumerated() {
            let segFraction = segments[i].value
            let segDuration = max(duration * Double(segFraction), 0.05)
            let delay = duration * Double(elapsedFraction)

            let anim = CABasicAnimation(keyPath: "strokeEnd")
            anim.fromValue = 0.0
            anim.toValue   = 1.0
            anim.duration  = segDuration
            anim.beginTime = CACurrentMediaTime() + delay
            anim.timingFunction = CAMediaTimingFunction(name: .linear)
            anim.fillMode  = .backwards
            anim.isRemovedOnCompletion = true

            sl.add(anim, forKey: "strokeEndAnim")
            elapsedFraction += segFraction
        }
    }

    func setCenterText(count: Int) {
        let countAttr = NSAttributedString(
            string: "\(count)\n",
            attributes: [
                .font: UIFont(name: "GowunBatang-Bold", size: 22) ?? UIFont.boldSystemFont(ofSize: 22),
                .foregroundColor: UIColor.accent
            ]
        )
        let unitAttr = NSAttributedString(
            string: "밑줄",
            attributes: [
                .font: UIFont(name: "GoyangIlsan R", size: 12) ?? UIFont.systemFont(ofSize: 12),
                .foregroundColor: UIColor.accent.withAlphaComponent(0.6)
            ]
        )
        let combined = NSMutableAttributedString(attributedString: countAttr)
        combined.append(unitAttr)
        centerLabel.attributedText = combined
    }

    private func pointOn(center: CGPoint, radius: CGFloat, angle: CGFloat) -> CGPoint {
        CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
    }
}

// MARK: - LineChartCardView

final class LineChartCardView: UIView {

    private let tabSelector = NeumorphicSegmentView(items: ["주간", "월간", "연간"])
    private let statCardsStack = UIStackView()
    private let chartContainer = UIView()
    private let chartView = LineChartView()

    // 더미 stat 데이터
    private let stats: [(String, String)] = [
        ("이번 주", "12.5"),
        ("이번 달", "38.2"),
        ("일 평균", "1.8"),
    ]

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        backgroundColor = .white
        layer.cornerRadius = 16
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = Float(CGFloat(0x16) / 255)
        layer.shadowRadius = 24
        layer.shadowOffset = CGSize(width: 0, height: 8)

        let titleLabel = UILabel()
        titleLabel.text = "독서 시간 추이"
        titleLabel.font = UIFont(name: "GoyangIlsan R", size: 17) ?? .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .accent

        let headerRow = UIView()
        headerRow.addSubview(titleLabel)
        headerRow.addSubview(tabSelector)
        titleLabel.snp.makeConstraints { make in
            make.leading.centerY.equalToSuperview()
        }
        tabSelector.snp.makeConstraints { make in
            make.trailing.top.bottom.equalToSuperview()
            make.width.equalTo(160)
        }

        buildStatCards()

        chartContainer.addSubview(chartView)
        chartView.snp.makeConstraints { $0.edges.equalToSuperview() }

        let vStack = UIStackView(arrangedSubviews: [headerRow, statCardsStack, chartContainer])
        vStack.axis = .vertical
        vStack.spacing = 16

        addSubview(vStack)
        vStack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(20)
        }

        headerRow.snp.makeConstraints { $0.height.equalTo(40) }
        tabSelector.snp.makeConstraints { $0.height.equalTo(40) }
        chartContainer.snp.makeConstraints { $0.height.equalTo(200) }
    }

    private func buildStatCards() {
        statCardsStack.axis = .horizontal
        statCardsStack.distribution = .fillEqually
        statCardsStack.spacing = 12

        for (title, value) in stats {
            let card = StatMiniCard(title: title, value: value)
            statCardsStack.addArrangedSubview(card)
        }
    }
}

// MARK: - StatMiniCard

private final class StatMiniCard: UIView {

    init(title: String, value: String) {
        super.init(frame: .zero)
        backgroundColor = .white
        layer.cornerRadius = 12
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = Float(CGFloat(0x16) / 255)
        layer.shadowRadius = 24
        layer.shadowOffset = CGSize(width: 0, height: 8)

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = UIFont(name: "GoyangIlsan R", size: 11) ?? .systemFont(ofSize: 11)
        titleLabel.textColor = UIColor.accent.withAlphaComponent(0.5)

        let valueLabel = UILabel()
        valueLabel.text = value
        valueLabel.font = UIFont(name: "GoyangIlsan R", size: 13) ?? .systemFont(ofSize: 13, weight: .semibold)
        valueLabel.textColor = .accent
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.7

        let vStack = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        vStack.axis = .vertical
        vStack.spacing = 4

        addSubview(vStack)
        vStack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 16, left: 14, bottom: 16, right: 14))
        }
    }
    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - LineChartView

final class LineChartView: UIView {

    // 더미 데이터: 분 단위
    private let dataPoints: [CGFloat] = [80, 140, 60, 180, 110, 155, 90]
    private let xLabels  = ["15", "16", "17", "18", "19", "20", "21"]

    private let lineLayer   = CAShapeLayer()
    private let gradLayer   = CAGradientLayer()
    private let gradMaskLayer = CAShapeLayer()
    private let avgLineLayer  = CAShapeLayer()
    private var dotLayers: [CALayer] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.addSublayer(gradLayer)
        layer.addSublayer(avgLineLayer)
        layer.addSublayer(lineLayer)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0 else { return }
        dotLayers.forEach { $0.removeFromSuperlayer() }
        dotLayers.removeAll()
        drawChart()
    }

    private func drawChart() {
        let primary  = UIColor.primary
        let walnut   = UIColor(hex: "#5d4037")
        let leftPad: CGFloat  = 32
        let bottomPad: CGFloat = 24
        let topPad: CGFloat   = 12

        let chartW = bounds.width - leftPad
        let chartH = bounds.height - bottomPad - topPad
        let maxVal: CGFloat = 200

        func xPos(_ i: Int) -> CGFloat { leftPad + CGFloat(i) / CGFloat(dataPoints.count - 1) * chartW }
        func yPos(_ v: CGFloat) -> CGFloat { topPad + (1 - v / maxVal) * chartH }

        // Grid lines
        [180, 120, 60, 0].enumerated().forEach { _, val in
            let y = yPos(CGFloat(val))
            let gl = CAShapeLayer()
            let p = UIBezierPath()
            p.move(to: CGPoint(x: leftPad, y: y))
            p.addLine(to: CGPoint(x: bounds.width, y: y))
            gl.path = p.cgPath
            gl.strokeColor = UIColor(hex: "#5d4037", alpha: CGFloat(0x08) / 255).cgColor
            gl.lineWidth = 1
            gl.fillColor = UIColor.clear.cgColor
            layer.insertSublayer(gl, at: 0)
        }

        // Average line
        let avg = dataPoints.reduce(0, +) / CGFloat(dataPoints.count)
        let avgY = yPos(avg)
        let avgPath = UIBezierPath()
        avgPath.move(to: CGPoint(x: leftPad, y: avgY))
        avgPath.addLine(to: CGPoint(x: bounds.width, y: avgY))
        avgLineLayer.path = avgPath.cgPath
        avgLineLayer.strokeColor = UIColor(hex: "#8D6E63", alpha: 0.4).cgColor
        avgLineLayer.lineWidth = 1
        avgLineLayer.lineDashPattern = [4, 4]
        avgLineLayer.fillColor = UIColor.clear.cgColor
        avgLineLayer.frame = bounds

        // Line path
        let linePath = UIBezierPath()
        for (i, val) in dataPoints.enumerated() {
            let pt = CGPoint(x: xPos(i), y: yPos(val))
            if i == 0 { linePath.move(to: pt) } else { linePath.addLine(to: pt) }
        }
        lineLayer.path = linePath.cgPath
        lineLayer.strokeColor = primary.cgColor
        lineLayer.lineWidth = 2.5
        lineLayer.fillColor = UIColor.clear.cgColor
        lineLayer.lineCap = .round
        lineLayer.lineJoin = .round
        lineLayer.frame = bounds

        // Gradient fill
        let fillPath = linePath.copy() as! UIBezierPath
        fillPath.addLine(to: CGPoint(x: xPos(dataPoints.count - 1), y: topPad + chartH))
        fillPath.addLine(to: CGPoint(x: leftPad, y: topPad + chartH))
        fillPath.close()
        gradMaskLayer.path = fillPath.cgPath
        gradMaskLayer.fillColor = UIColor.white.cgColor
        gradLayer.colors = [
            walnut.withAlphaComponent(0.12).cgColor,
            walnut.withAlphaComponent(0.0).cgColor,
        ]
        gradLayer.startPoint = CGPoint(x: 0.5, y: 0)
        gradLayer.endPoint   = CGPoint(x: 0.5, y: 1)
        gradLayer.frame = bounds
        gradLayer.mask = gradMaskLayer

        // Dots
        for (i, val) in dataPoints.enumerated() {
            let dot = CALayer()
            let r: CGFloat = 4
            dot.frame = CGRect(x: xPos(i) - r, y: yPos(val) - r, width: r * 2, height: r * 2)
            dot.cornerRadius = r
            dot.backgroundColor = primary.cgColor
            dot.borderColor = UIColor.white.cgColor
            dot.borderWidth = 2
            layer.addSublayer(dot)
            dotLayers.append(dot)
        }

        // Y-axis labels
        zip([180, 120, 60, 0], ["3h", "2h", "1h", "0h"]).forEach { val, text in
            let lbl = UILabel()
            lbl.text = text
            lbl.font = UIFont(name: "GoyangIlsan R", size: 10) ?? .systemFont(ofSize: 10)
            lbl.textColor = UIColor.primary.withAlphaComponent(0.4)
            addSubview(lbl)
            lbl.sizeToFit()
            lbl.frame.origin = CGPoint(x: 0, y: yPos(CGFloat(val)) - lbl.frame.height / 2)
        }

        // X-axis labels
        for (i, text) in xLabels.enumerated() {
            let lbl = UILabel()
            lbl.text = text
            lbl.font = UIFont(name: "GoyangIlsan R", size: 10) ?? .systemFont(ofSize: 10)
            lbl.textColor = UIColor.primary.withAlphaComponent(0.4)
            addSubview(lbl)
            lbl.sizeToFit()
            lbl.frame.origin = CGPoint(
                x: xPos(i) - lbl.frame.width / 2,
                y: bounds.height - bottomPad + 4
            )
        }
    }
}

// MARK: - MonthYearPickerViewController

private final class MonthYearPickerViewController: UIViewController,
                                                    UIPickerViewDataSource,
                                                    UIPickerViewDelegate {

    var onConfirm: ((Int, Int) -> Void)?

    private let years: [Int]
    private let monthNames = (1...12).map { "\($0)월" }
    private var selectedYear: Int
    private var selectedMonth: Int
    private let nowYear: Int
    private let nowMonth: Int

    private let picker = UIPickerView()
    private let confirmButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle("확인", for: .normal)
        btn.titleLabel?.font = UIFont(name: "GoyangIlsan R", size: 15)
            ?? .systemFont(ofSize: 15, weight: .semibold)
        btn.tintColor = .accent
        return btn
    }()
    private let disposeBag = DisposeBag()

    init(year: Int, month: Int) {
        let cal = Calendar.current
        let today = Date()
        nowYear  = cal.component(.year,  from: today)
        nowMonth = cal.component(.month, from: today)
        self.years = Array((nowYear - 10)...nowYear)
        self.selectedYear  = min(year, nowYear)
        self.selectedMonth = (year == nowYear) ? min(month, nowMonth) : month
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .background

        let titleLabel = UILabel()
        titleLabel.text = "날짜 선택"
        titleLabel.font = UIFont(name: "GoyangIlsan R", size: 17)
            ?? .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .accent

        confirmButton.rx.tap
            .subscribe(onNext: { [weak self] in
                guard let self else { return }
                self.onConfirm?(self.selectedYear, self.selectedMonth)
                self.dismiss(animated: true)
            })
            .disposed(by: disposeBag)

        picker.dataSource = self
        picker.delegate = self

        if let yearIdx = years.firstIndex(of: selectedYear) {
            picker.selectRow(yearIdx, inComponent: 0, animated: false)
        }
        picker.selectRow(selectedMonth - 1, inComponent: 1, animated: false)

        view.addSubview(titleLabel)
        view.addSubview(confirmButton)
        view.addSubview(picker)

        titleLabel.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.centerX.equalToSuperview()
        }
        confirmButton.snp.makeConstraints { make in
            make.centerY.equalTo(titleLabel)
            make.trailing.equalToSuperview().inset(24)
        }
        picker.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(-16)
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(view.safeAreaLayoutGuide).inset(8)
        }
    }

    // MARK: UIPickerViewDataSource

    func numberOfComponents(in pickerView: UIPickerView) -> Int { 2 }

    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        component == 0 ? years.count : 12
    }

    // MARK: UIPickerViewDelegate

    func pickerView(_ pickerView: UIPickerView, viewForRow row: Int, forComponent component: Int, reusing view: UIView?) -> UIView {
        let lbl = (view as? UILabel) ?? {
            let l = UILabel()
            l.textAlignment = .center
            l.font = UIFont(name: "GoyangIlsan R", size: 16) ?? .systemFont(ofSize: 16)
            l.isUserInteractionEnabled = false
            return l
        }()
        lbl.text = component == 0 ? "\(years[row])년" : monthNames[row]
        let isFuture: Bool
        if component == 0 {
            isFuture = years[row] > nowYear
        } else {
            isFuture = selectedYear == nowYear && (row + 1) > nowMonth
        }
        lbl.textColor = isFuture ? .tertiaryLabel : .primary
        return lbl
    }

    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        if component == 0 {
            selectedYear = years[row]
            // 미래 연도 선택 차단: 현재 연도로 되돌림
            if selectedYear > nowYear {
                selectedYear = nowYear
                picker.selectRow(years.firstIndex(of: nowYear) ?? row, inComponent: 0, animated: true)
            }
            // 연도 변경 시 월 색상 업데이트
            picker.reloadComponent(1)
            // 선택된 월이 현재 연도에서 미래 월이면 이번 달로 조정
            if selectedYear == nowYear && selectedMonth > nowMonth {
                selectedMonth = nowMonth
                picker.selectRow(selectedMonth - 1, inComponent: 1, animated: true)
            }
        } else {
            let month = row + 1
            // 미래 월 선택 차단
            if selectedYear == nowYear && month > nowMonth {
                selectedMonth = nowMonth
                picker.selectRow(selectedMonth - 1, inComponent: 1, animated: true)
            } else {
                selectedMonth = month
            }
        }
    }
}
