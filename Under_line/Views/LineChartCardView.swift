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
