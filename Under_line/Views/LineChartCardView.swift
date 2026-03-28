//
//  LineChartCardView.swift
//  Under_line
//

import UIKit
import SnapKit
import RxSwift
import RxCocoa

// MARK: - LineChartCardView

final class LineChartCardView: UIView {

    private let tabSelector  = NeumorphicSegmentView(items: ["주간", "월간", "연간"])
    private var miniCards: [StatMiniCard] = []
    private let statCardsStack = UIStackView()
    private let chartContainer = UIView()
    private let chartView      = LineChartView()
    private var chartData      = ReadingTimeChartData.empty
    private let disposeBag     = DisposeBag()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        backgroundColor = .white
        layer.cornerRadius = 16
        layer.shadowColor   = UIColor.black.cgColor
        layer.shadowOpacity = Float(CGFloat(0x16) / 255)
        layer.shadowRadius  = 24
        layer.shadowOffset  = CGSize(width: 0, height: 8)

        let titleLabel = UILabel()
        titleLabel.text      = "독서 시간 추이"
        titleLabel.font      = UIFont(name: "GoyangIlsan R", size: 17) ?? .systemFont(ofSize: 17, weight: .semibold)
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
        vStack.axis    = .vertical
        vStack.spacing = 16

        addSubview(vStack)
        vStack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(20)
        }

        headerRow.snp.makeConstraints    { $0.height.equalTo(40) }
        tabSelector.snp.makeConstraints  { $0.height.equalTo(40) }
        chartContainer.snp.makeConstraints { $0.height.equalTo(200) }

        tabSelector.selectionChanged
            .subscribe(onNext: { [weak self] index in
                self?.updateChart(for: index)
            })
            .disposed(by: disposeBag)
    }

    private func buildStatCards() {
        statCardsStack.axis         = .horizontal
        statCardsStack.distribution = .fillEqually
        statCardsStack.spacing      = 12

        for title in ["이번 주", "이번 달", "일 평균"] {
            let card = StatMiniCard(title: title)
            miniCards.append(card)
            statCardsStack.addArrangedSubview(card)
        }
    }

    // MARK: - Public

    func configure(with data: ReadingTimeChartData) {
        chartData = data
        updateStats()
        updateChart(for: tabSelector.selectedIndex)
    }

    // MARK: - Private

    private func updateStats() {
        miniCards[safe: 0]?.configure(value: hoursLabel(chartData.thisWeekHours))
        miniCards[safe: 1]?.configure(value: hoursLabel(chartData.thisMonthHours))
        miniCards[safe: 2]?.configure(value: hoursLabel(chartData.dailyAvgHours))
    }

    private func updateChart(for tabIndex: Int) {
        let points: [ReadingTimeChartPoint]
        switch tabIndex {
        case 1:  points = chartData.monthly
        case 2:  points = chartData.yearly
        default: points = chartData.weekly
        }
        chartView.configure(points: points)
    }

    private func hoursLabel(_ hours: Double) -> String {
        guard hours > 0 else { return "-" }
        if hours < 1 { return String(format: "%.0f분", hours * 60) }
        return String(format: "%.1f시간", hours)
    }
}

// MARK: - Array safe subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - StatMiniCard

private final class StatMiniCard: UIView {

    private let valueLabel = UILabel()

    init(title: String) {
        super.init(frame: .zero)
        backgroundColor     = .white
        layer.cornerRadius  = 12
        layer.shadowColor   = UIColor.black.cgColor
        layer.shadowOpacity = Float(CGFloat(0x16) / 255)
        layer.shadowRadius  = 24
        layer.shadowOffset  = CGSize(width: 0, height: 8)

        let titleLabel = UILabel()
        titleLabel.text      = title
        titleLabel.font      = UIFont(name: "GoyangIlsan R", size: 11) ?? .systemFont(ofSize: 11)
        titleLabel.textColor = UIColor.accent.withAlphaComponent(0.5)

        valueLabel.text                 = "-"
        valueLabel.font                 = UIFont(name: "GoyangIlsan R", size: 13) ?? .systemFont(ofSize: 13, weight: .semibold)
        valueLabel.textColor            = .accent
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor   = 0.7

        let vStack = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        vStack.axis    = .vertical
        vStack.spacing = 4

        addSubview(vStack)
        vStack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 16, left: 14, bottom: 16, right: 14))
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(value: String) {
        valueLabel.text = value
    }
}

// MARK: - LineChartView

final class LineChartView: UIView {

    private var dataPoints: [CGFloat] = []
    private var xLabels:    [String]  = []

    private let lineLayer  = CAShapeLayer()
    private let areaLayer  = CAShapeLayer()
    private var dotLayers:   [CALayer]      = []
    private var gridLayers:  [CAShapeLayer] = []
    private var labelViews:  [UILabel]      = []

    private let leftPad:   CGFloat = 54
    private let rightPad:  CGFloat = 14
    private let topPad:    CGFloat = 12
    private let bottomPad: CGFloat = 24

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.addSublayer(areaLayer)
        layer.addSublayer(lineLayer)
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(points: [ReadingTimeChartPoint]) {
        dataPoints = points.map { CGFloat($0.minutes) }
        xLabels    = points.map { $0.label }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0 else { return }
        cleanup()
        guard !dataPoints.isEmpty else { return }
        drawChart()
    }

    // MARK: - Scale helpers

    private func niceMaxScale(_ maxMinutes: CGFloat) -> CGFloat {
        guard maxMinutes > 0 else { return 60 }
        let halfHours = Int(ceil(maxMinutes / 30))
        return CGFloat(max(2, halfHours)) * 30
    }

    private func formatDuration(_ minutes: Int) -> String {
        if minutes == 0 { return "0분" }
        let h = minutes / 60
        let m = minutes % 60
        if m == 0 { return "\(h)시간" }
        if h == 0 { return "\(m)분" }
        return "\(h)시간\(m)분"
    }

    // MARK: - Drawing

    private func cleanup() {
        dotLayers.forEach  { $0.removeFromSuperlayer() }
        dotLayers.removeAll()
        gridLayers.forEach { $0.removeFromSuperlayer() }
        gridLayers.removeAll()
        labelViews.forEach { $0.removeFromSuperview() }
        labelViews.removeAll()
        lineLayer.path = nil
        areaLayer.path = nil
    }

    private func drawChart() {
        let chartTopY    = topPad
        let chartBottomY = bounds.height - bottomPad
        let plotW        = bounds.width - leftPad - rightPad
        let fillY        = chartBottomY + 14

        let scale = niceMaxScale(dataPoints.max() ?? 0)

        func xPos(_ i: Int) -> CGFloat {
            guard dataPoints.count > 1 else { return leftPad + plotW / 2 }
            return leftPad + CGFloat(i) / CGFloat(dataPoints.count - 1) * plotW
        }
        func yPos(_ v: CGFloat) -> CGFloat {
            chartBottomY - (v / scale) * (chartBottomY - chartTopY)
        }

        // Y-axis: 4 positions (max, 2/3, 1/3, 0)
        let yScaleValues: [CGFloat] = [scale, scale * 2 / 3, scale / 3, 0]
        let yPositions   = yScaleValues.map { yPos($0) }

        // Grid lines
        for pos in yPositions {
            let gl = CAShapeLayer()
            let p  = UIBezierPath()
            p.move(to: CGPoint(x: leftPad - 2, y: pos))
            p.addLine(to: CGPoint(x: bounds.width - rightPad, y: pos))
            gl.path        = p.cgPath
            gl.strokeColor = UIColor(hex: "#5d4037", alpha: CGFloat(0x08) / 255).cgColor
            gl.lineWidth   = 1
            gl.fillColor   = UIColor.clear.cgColor
            layer.insertSublayer(gl, at: 0)
            gridLayers.append(gl)
        }

        guard dataPoints.count >= 2 else { return }

        // Bezier curve line path
        let xs = dataPoints.indices.map { xPos($0) }
        let ys = dataPoints.map { yPos($0) }

        let linePath = UIBezierPath()
        linePath.move(to: CGPoint(x: xs[0], y: ys[0]))
        for i in 1..<xs.count {
            let prev = CGPoint(x: xs[i-1], y: ys[i-1])
            let curr = CGPoint(x: xs[i],   y: ys[i])
            let cp1  = CGPoint(x: prev.x + (curr.x - prev.x) * 0.5, y: prev.y)
            let cp2  = CGPoint(x: curr.x - (curr.x - prev.x) * 0.5, y: curr.y)
            linePath.addCurve(to: curr, controlPoint1: cp1, controlPoint2: cp2)
        }

        lineLayer.path        = linePath.cgPath
        lineLayer.fillColor   = UIColor.clear.cgColor
        lineLayer.strokeColor = UIColor.primary.cgColor
        lineLayer.lineWidth   = 2.5
        lineLayer.lineCap     = .round
        lineLayer.lineJoin    = .round
        lineLayer.frame       = bounds

        // Solid area fill
        let areaPath = linePath.copy() as! UIBezierPath
        areaPath.addLine(to: CGPoint(x: xs.last!,  y: fillY))
        areaPath.addLine(to: CGPoint(x: xs.first!, y: fillY))
        areaPath.close()
        areaLayer.path      = areaPath.cgPath
        areaLayer.fillColor = UIColor(hex: "#5d4037", alpha: CGFloat(0x18) / 255).cgColor
        areaLayer.frame     = bounds

        // Dots
        for (i, val) in dataPoints.enumerated() {
            let dot = CALayer()
            let r: CGFloat = 4
            dot.frame           = CGRect(x: xPos(i) - r, y: yPos(val) - r, width: r * 2, height: r * 2)
            dot.cornerRadius    = r
            dot.backgroundColor = UIColor.primary.cgColor
            dot.borderColor     = UIColor.white.cgColor
            dot.borderWidth     = 2
            layer.addSublayer(dot)
            dotLayers.append(dot)
        }

        // Y-axis labels
        for (i, scaleVal) in yScaleValues.enumerated() {
            let lbl = makeAxisLabel(formatDuration(Int(scaleVal)))
            addSubview(lbl)
            labelViews.append(lbl)
            lbl.sizeToFit()
            lbl.frame.origin = CGPoint(x: 2, y: yPositions[i] - lbl.frame.height / 2)
        }

        // X-axis labels
        for (i, text) in xLabels.enumerated() {
            let lbl = makeAxisLabel(text)
            addSubview(lbl)
            labelViews.append(lbl)
            lbl.sizeToFit()
            lbl.frame.origin = CGPoint(
                x: xPos(i) - lbl.frame.width / 2,
                y: bounds.height - bottomPad + 4
            )
        }
    }

    private func makeAxisLabel(_ text: String) -> UILabel {
        let lbl = UILabel()
        lbl.text      = text
        lbl.font      = UIFont(name: "GoyangIlsan R", size: 10) ?? .systemFont(ofSize: 10)
        lbl.textColor = UIColor.primary.withAlphaComponent(0.5)
        return lbl
    }
}
