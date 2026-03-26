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

    private let disposeBag = DisposeBag()

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
}

// MARK: - HeatmapCardView

final class HeatmapCardView: UIView {

    // 히트맵 더미 데이터: 7행(요일) × 11열(주)
    private static let gridData: [[Int]] = {
        let levels = [0, 1, 2, 3, 4]
        return (0..<7).map { _ in (0..<11).map { _ in levels.randomElement()! } }
    }()

    private var currentYear = 2026
    private var currentMonth = 3

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
        prevButton.addTarget(self, action: #selector(prevMonth), for: .touchUpInside)
        nextButton.addTarget(self, action: #selector(nextMonth), for: .touchUpInside)
        periodLabel.isUserInteractionEnabled = true
        periodLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(periodTapped)))

        heatmapBody.data = Self.gridData

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

    @objc private func prevMonth() {
        currentMonth -= 1
        if currentMonth == 0 { currentMonth = 12; currentYear -= 1 }
        updatePeriodLabel()
    }

    @objc private func nextMonth() {
        currentMonth += 1
        if currentMonth == 13 { currentMonth = 1; currentYear += 1 }
        updatePeriodLabel()
    }

    private func updatePeriodLabel() {
        periodLabel.text = "\(currentYear)년 \(currentMonth)월"
    }

    @objc private func periodTapped() {
        guard let vc = findViewController() else { return }
        let picker = MonthYearPickerViewController(year: currentYear, month: currentMonth)
        picker.onConfirm = { [weak self] year, month in
            self?.currentYear = year
            self?.currentMonth = month
            self?.updatePeriodLabel()
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

// MARK: - HeatmapBodyView

final class HeatmapBodyView: UIView {

    private static let cols = 11
    private static let rows = 7
    private static let gap: CGFloat = 4
    private static let labelWidth: CGFloat = 18
    private static let labelGridGap: CGFloat = 6

    private let days = ["월", "화", "수", "목", "금", "토", "일"]
    private let walnut = UIColor(hex: "#5d4037")

    var data: [[Int]] = [] { didSet { setNeedsLayout() } }

    private var cellButtons: [[UIButton]] = []
    private var selectedCell: (row: Int, col: Int)?
    private var lastWidth: CGFloat = 0

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
        if abs(bounds.width - lastWidth) > 0.5 {
            lastWidth = bounds.width
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
        for (i, day) in days.enumerated() {
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

                let level = (r < data.count && c < data[r].count) ? data[r][c] : 0
                let alpha = alphas[min(level, alphas.count - 1)]
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

    private let donutView: DonutChartView = {
        let v = DonutChartView()
        v.segments = [
            .init(label: "소설",   value: 0.38, color: UIColor(hex: "#5d4037")),
            .init(label: "인문",   value: 0.22, color: UIColor(hex: "#8D6E63")),
            .init(label: "사회",   value: 0.18, color: UIColor(hex: "#BCAAA4")),
            .init(label: "자기계발", value: 0.14, color: UIColor(hex: "#D7CCC8")),
            .init(label: "기타",   value: 0.08, color: UIColor(hex: "#EFEBE9")),
        ]
        return v
    }()

    private let legendContainer = UIView()

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
        titleLabel.text = "보관한 밑줄"
        titleLabel.font = UIFont(name: "GoyangIlsan R", size: 18)
            ?? .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.textColor = .accent

        buildLegend()

        let vStack = UIStackView(arrangedSubviews: [titleLabel, segmentControl, donutView, legendContainer])
        vStack.axis = .vertical
        vStack.spacing = 16

        addSubview(vStack)
        vStack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(20)
        }

        segmentControl.snp.makeConstraints { $0.height.equalTo(32) }
        donutView.snp.makeConstraints { $0.height.equalTo(180) }
    }

    private func buildLegend() {
        let segments = donutView.segments
        let row1 = legendRowStack(segments: Array(segments.prefix(3)))
        let row2 = legendRowStack(segments: Array(segments.dropFirst(3)))

        let vStack = UIStackView(arrangedSubviews: [row1, row2])
        vStack.axis = .vertical
        vStack.spacing = 10

        legendContainer.addSubview(vStack)
        vStack.snp.makeConstraints { $0.edges.equalToSuperview() }
    }

    private func legendRowStack(segments: [DonutChartView.Segment]) -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 16
        row.alignment = .center

        for seg in segments {
            let dot = UIView()
            dot.backgroundColor = seg.color
            dot.layer.cornerRadius = 5
            dot.snp.makeConstraints { $0.size.equalTo(10) }

            let lbl = UILabel()
            lbl.text = seg.label
            lbl.font = UIFont(name: "GoyangIlsan R", size: 13) ?? .systemFont(ofSize: 13)
            lbl.textColor = .accent

            let item = UIStackView(arrangedSubviews: [dot, lbl])
            item.axis = .horizontal
            item.spacing = 6
            item.alignment = .center
            row.addArrangedSubview(item)
        }

        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(spacer)
        return row
    }
}

// MARK: - NeumorphicSegmentView

final class NeumorphicSegmentView: UIView {

    private let items: [String]
    var selectedIndex = 0 { didSet { updateSelection() } }

    private var buttons: [UIButton] = []
    private let selector = UIView()

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
            btn.tag = i
            btn.addTarget(self, action: #selector(tapped(_:)), for: .touchUpInside)
            buttons.append(btn)
            stack.addArrangedSubview(btn)
        }

        updateSelection()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateSelectorFrame()
    }

    @objc private func tapped(_ sender: UIButton) {
        selectedIndex = sender.tag
    }

    private func updateSelection() {
        guard !buttons.isEmpty else { return }
        for (i, btn) in buttons.enumerated() {
            btn.tintColor = i == selectedIndex ? .accent : UIColor.accent.withAlphaComponent(0.4)
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

    var segments: [Segment] = [] { didSet { setNeedsDisplay() } }

    override func draw(_ rect: CGRect) {
        guard !segments.isEmpty else { return }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerR = min(rect.width, rect.height) / 2 - 8
        let innerR = outerR * 0.55
        var startAngle = -CGFloat.pi / 2

        for seg in segments {
            let endAngle = startAngle + .pi * 2 * seg.value
            let path = UIBezierPath()
            path.move(to: pointOn(center: center, radius: innerR, angle: startAngle))
            path.addArc(withCenter: center, radius: outerR, startAngle: startAngle, endAngle: endAngle, clockwise: true)
            path.addArc(withCenter: center, radius: innerR, startAngle: endAngle, endAngle: startAngle, clockwise: false)
            path.close()
            seg.color.setFill()
            path.fill()
            startAngle = endAngle
        }
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

        let confirmBtn = UIButton(type: .system)
        confirmBtn.setTitle("확인", for: .normal)
        confirmBtn.titleLabel?.font = UIFont(name: "GoyangIlsan R", size: 15)
            ?? .systemFont(ofSize: 15, weight: .semibold)
        confirmBtn.tintColor = .accent
        confirmBtn.addTarget(self, action: #selector(confirm), for: .touchUpInside)

        picker.dataSource = self
        picker.delegate = self

        if let yearIdx = years.firstIndex(of: selectedYear) {
            picker.selectRow(yearIdx, inComponent: 0, animated: false)
        }
        picker.selectRow(selectedMonth - 1, inComponent: 1, animated: false)

        view.addSubview(titleLabel)
        view.addSubview(confirmBtn)
        view.addSubview(picker)

        titleLabel.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.centerX.equalToSuperview()
        }
        confirmBtn.snp.makeConstraints { make in
            make.centerY.equalTo(titleLabel)
            make.trailing.equalToSuperview().inset(24)
        }
        picker.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(-16)
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(view.safeAreaLayoutGuide).inset(8)
        }
    }

    @objc private func confirm() {
        onConfirm?(selectedYear, selectedMonth)
        dismiss(animated: true)
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
