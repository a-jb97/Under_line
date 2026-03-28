//
//  GenreAuthorCardView.swift
//  Under_line
//

import UIKit
import SnapKit
import RxSwift
import RxCocoa

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
