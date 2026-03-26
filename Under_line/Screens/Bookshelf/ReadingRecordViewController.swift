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

    private let disposeBag = DisposeBag()
    private var gradientLayers: [(view: UIView, layer: CAGradientLayer)] = []
    private var didSetupChart = false

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
        l.text          = "사랑의 기술"
        l.font          = UIFont(name: "GowunBatang-Bold", size: 20)
            ?? .systemFont(ofSize: 20, weight: .bold)
        l.textColor     = UIColor.accent
        l.textAlignment = .center
        l.numberOfLines = 0
        return l
    }()

    // MARK: - Progress Section
    private let progressSection: UIView = {
        let v = UIView()
        v.backgroundColor   = UIColor.background
        v.layer.cornerRadius = 12
        v.layer.shadowColor   = UIColor(hex: "#5d4037").cgColor
        v.layer.shadowOpacity = Float(CGFloat(0x25) / 255)
        v.layer.shadowRadius  = 5
        v.layer.shadowOffset  = CGSize(width: 3, height: 3)
        return v
    }()

    private let progressHeaderLabel: UILabel = {
        let l = UILabel()
        let attrStr = NSMutableAttributedString(
            string: "독서 진행률 : ",
            attributes: [
                .font:            UIFont(name: "GoyangIlsan R", size: 13) ?? .systemFont(ofSize: 13),
                .foregroundColor: UIColor.accent,
            ]
        )
        attrStr.append(NSAttributedString(
            string: "68%",
            attributes: [
                .font:            UIFont(name: "GoyangIlsan R", size: 13) ?? .systemFont(ofSize: 13),
                .foregroundColor: UIColor.primary,
            ]
        ))
        l.attributedText = attrStr
        return l
    }()

    private lazy var editButton: UIButton = {
        let btn = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 10, weight: .regular)
        btn.setImage(UIImage(systemName: "pencil", withConfiguration: cfg), for: .normal)
        btn.setTitle(" 편집", for: .normal)
        btn.titleLabel?.font = UIFont(name: "GoyangIlsan R", size: 12) ?? .systemFont(ofSize: 12)
        btn.tintColor = UIColor.primary.withAlphaComponent(0.7)
        btn.setTitleColor(UIColor.primary.withAlphaComponent(0.7), for: .normal)
        return btn
    }()

    private let progressBarBg: UIView = {
        let v = UIView()
        v.backgroundColor   = UIColor(hex: "#5d4037", alpha: CGFloat(0x20) / 255)
        v.layer.cornerRadius = 6
        v.clipsToBounds      = true
        return v
    }()

    private let progressBarFill: UIView = {
        let v = UIView()
        v.layer.cornerRadius = 4
        v.clipsToBounds      = true
        return v
    }()

    private let progressDetailLabel: UILabel = {
        let l = UILabel()
        l.text      = "187 / 276 페이지"
        l.font      = UIFont(name: "GoyangIlsan R", size: 11) ?? .systemFont(ofSize: 11)
        l.textColor = UIColor.primary.withAlphaComponent(0.45)
        return l
    }()

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
        v.backgroundColor   = UIColor(hex: "#E8E0DC")
        v.layer.cornerRadius = 15
        v.layer.shadowColor   = UIColor(hex: "#b5a49e").cgColor
        v.layer.shadowOpacity = 1.0
        v.layer.shadowRadius  = 7
        v.layer.shadowOffset  = CGSize(width: 3, height: 3)
        return v
    }()

    private let chartCard: UIView = {
        let v = UIView()
        v.backgroundColor   = .white
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
        setupProgressGradient()
        bindActions()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.interactivePopGestureRecognizer?.delegate = nil
        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        for (view, gradient) in gradientLayers {
            gradient.frame = view.bounds
        }
        if chartCard.bounds.width > 0 { drawChart() }
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = UIColor.background

        view.addSubview(scrollView)
        scrollView.addSubview(contentView)

        contentView.addSubview(backButton)
        contentView.addSubview(titleLabel)
        contentView.addSubview(timerDialView)
        contentView.addSubview(bookTitleLabel)

        progressBarBg.addSubview(progressBarFill)
        progressSection.addSubview(progressHeaderLabel)
        progressSection.addSubview(editButton)
        progressSection.addSubview(progressBarBg)
        progressSection.addSubview(progressDetailLabel)
        contentView.addSubview(progressSection)

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

        progressSection.snp.makeConstraints { make in
            make.top.equalTo(bookTitleLabel.snp.bottom).offset(24)
            make.leading.trailing.equalToSuperview().inset(24)
        }
        progressHeaderLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(14)
            make.top.equalToSuperview().inset(12)
        }
        editButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(14)
            make.centerY.equalTo(progressHeaderLabel)
        }
        progressBarBg.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(14)
            make.top.equalTo(progressHeaderLabel.snp.bottom).offset(10)
            make.height.equalTo(24)
        }
        progressBarFill.snp.makeConstraints { make in
            make.leading.top.bottom.equalToSuperview()
            make.width.equalToSuperview().multipliedBy(0.68)
        }
        progressDetailLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(14)
            make.top.equalTo(progressBarBg.snp.bottom).offset(10)
            make.bottom.equalToSuperview().inset(12)
        }

        chartTitleLabel.snp.makeConstraints { make in
            make.top.equalTo(progressSection.snp.bottom).offset(40)
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
            make.height.equalTo(220)
            make.bottom.equalToSuperview().inset(24)
        }
    }

    // MARK: - Chart Drawing

    private func drawChart() {
        guard !didSetupChart else { return }
        didSetupChart = true

        addChartAxisLabels()

        let cardW       = chartCard.bounds.width
        let topPad:  CGFloat = 20
        let leftPad: CGFloat = 30
        let chartH:  CGFloat = 150
        let plotW = cardW - leftPad - 8

        let designXs: [CGFloat] = [24, 74, 124, 174, 224, 274, 324]
        let designRange: CGFloat = 324 - 24
        let xs = designXs.map { leftPad + ($0 - 24) / designRange * plotW }

        let designYs: [CGFloat] = [76, 56, 96, 36, 116, 16, 56]
        let ys = designYs.map { topPad + $0 }

        let linePath = UIBezierPath()
        linePath.move(to: CGPoint(x: xs[0], y: ys[0]))
        for i in 1..<xs.count {
            let prev = CGPoint(x: xs[i-1], y: ys[i-1])
            let curr = CGPoint(x: xs[i], y: ys[i])
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
        let bottomY  = topPad + chartH
        areaPath.addLine(to: CGPoint(x: xs.last!, y: bottomY))
        areaPath.addLine(to: CGPoint(x: xs.first!, y: bottomY))
        areaPath.close()
        chartAreaLayer.path      = areaPath.cgPath
        chartAreaLayer.fillColor = UIColor(hex: "#5d4037", alpha: CGFloat(0x20) / 255).cgColor

        let xLabels = ["월", "화", "수", "목", "금", "토", "일"]
        for i in 0..<xs.count {
            let dot = UIView()
            dot.backgroundColor  = UIColor.primary
            dot.layer.cornerRadius = 4
            dot.layer.borderWidth  = 2
            dot.layer.borderColor  = UIColor.white.cgColor
            dot.frame = CGRect(x: xs[i] - 4, y: ys[i] - 4, width: 8, height: 8)
            chartCard.addSubview(dot)

            let xLabel = UILabel()
            xLabel.text          = xLabels[i]
            xLabel.font          = UIFont(name: "GoyangIlsan R", size: 10) ?? .systemFont(ofSize: 10)
            xLabel.textColor     = UIColor.primary.withAlphaComponent(0.4)
            xLabel.textAlignment = .center
            xLabel.sizeToFit()
            xLabel.center = CGPoint(x: xs[i], y: bottomY + 12)
            chartCard.addSubview(xLabel)
        }
    }

    private func addChartAxisLabels() {
        let yLabels:   [String]  = ["3h", "2h", "1h", "0h"]
        let yPositions: [CGFloat] = [20, 60, 100, 140]
        let cardW = chartCard.bounds.width

        for (i, text) in yLabels.enumerated() {
            let label = UILabel()
            label.text          = text
            label.font          = UIFont(name: "GoyangIlsan R", size: 10) ?? .systemFont(ofSize: 10)
            label.textColor     = UIColor.primary.withAlphaComponent(0.4)
            label.textAlignment = .right
            label.frame         = CGRect(x: 0, y: yPositions[i] - 6, width: 26, height: 12)
            chartCard.addSubview(label)

            let grid = CAShapeLayer()
            let gridPath = UIBezierPath()
            gridPath.move(to: CGPoint(x: 30, y: yPositions[i]))
            gridPath.addLine(to: CGPoint(x: cardW - 8, y: yPositions[i]))
            grid.path        = gridPath.cgPath
            grid.strokeColor = UIColor(hex: "#5d4037", alpha: CGFloat(0x08) / 255).cgColor
            grid.lineWidth   = 1
            chartCard.layer.addSublayer(grid)
        }
    }

    // MARK: - Progress Gradient

    private func setupProgressGradient() {
        let grad = CAGradientLayer()
        grad.colors      = [UIColor.primary.cgColor, UIColor(hex: "#8D6E63").cgColor]
        grad.startPoint  = CGPoint(x: 0, y: 0.5)
        grad.endPoint    = CGPoint(x: 1, y: 0.5)
        grad.cornerRadius = 4
        progressBarFill.layer.addSublayer(grad)
        gradientLayers.append((progressBarFill, grad))
    }

    // MARK: - Bindings

    private func bindActions() {
        backButton.rx.tap
            .subscribe(onNext: { [weak self] in
                self?.navigationController?.popViewController(animated: true)
            })
            .disposed(by: disposeBag)

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
    }

    // MARK: - Helpers

    private func makeTabButton(title: String, selected: Bool) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle(title, for: .normal)
        btn.titleLabel?.font = UIFont(name: "GoyangIlsan R", size: 11) ?? .systemFont(ofSize: 11)
        btn.layer.cornerRadius = 11
        btn.backgroundColor    = selected ? UIColor.primary : .clear
        btn.setTitleColor(selected ? .white : UIColor.primary, for: .normal)
        return btn
    }
}
