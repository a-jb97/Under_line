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

    // MARK: - Timer State
    private var remainingSeconds = 15 * 60
    private var isRunning = false
    private var countdownTimer: Timer?
    private var didSetupDial = false
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
        let cfg = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
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

    // MARK: - Dial
    private let dialContainer: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor(hex: "#E8E0DC")
        v.layer.cornerRadius = 130
        v.layer.shadowColor   = UIColor.black.cgColor
        v.layer.shadowOpacity = Float(CGFloat(0x25) / 255)
        v.layer.shadowRadius  = 8
        v.layer.shadowOffset  = CGSize(width: 4, height: 4)
        return v
    }()

    // 다이얼 외부 웨지 (타이머 진행 표시 — 연한 갈색, 외부 링)
    private let outerWedgeLayer = CAShapeLayer()
    // 다이얼 내부 호 (진한 갈색, 내부 원 위에 오버레이)
    private let innerArcLayer   = CAShapeLayer()

    // 틱마크 & 숫자 레이블을 담는 투명 컨테이너 (innerCircleView 아래 z-order)
    private let markingsView: UIView = {
        let v = UIView()
        v.backgroundColor = .clear
        v.isUserInteractionEnabled = false
        return v
    }()

    private let dialFaceView: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor(hex: "#f6efee")
        v.layer.cornerRadius = 130
        return v
    }()

    private let innerCircleLightShadow: UIView = {
        let v = UIView()
        v.isUserInteractionEnabled = false
        v.backgroundColor = .white
        v.layer.cornerRadius = 83.2
        v.layer.shadowColor   = UIColor.white.cgColor
        v.layer.shadowOpacity = 1.0
        v.layer.shadowRadius  = 12
        v.layer.shadowOffset  = CGSize(width: -6, height: -6)
        return v
    }()

    private let innerCircleView: UIView = {
        let v = UIView()
        v.backgroundColor = .white
        v.layer.cornerRadius = 83.2
        v.layer.shadowColor   = UIColor(hex: "#C5BDB8").cgColor
        v.layer.shadowOpacity = 1.0
        v.layer.shadowRadius  = 12
        v.layer.shadowOffset  = CGSize(width: 6, height: 6)
        return v
    }()

    private let centerKnobView: UIView = {
        let v = UIView()
        v.backgroundColor   = UIColor(hex: "#E8E0DC")
        v.layer.cornerRadius = 15.6
        v.layer.shadowColor   = UIColor.black.cgColor
        v.layer.shadowOpacity = Float(CGFloat(0x22) / 255)
        v.layer.shadowRadius  = 8
        v.layer.shadowOffset  = CGSize(width: 4, height: 4)
        return v
    }()

    // MARK: - Neumorphism Shadow Views

    // ehXZh: 밝은 top-left 그림자 (dialContainer 뒤에 배치)
    private let dialContainerLightShadow: UIView = {
        let v = UIView()
        v.isUserInteractionEnabled = false
        v.backgroundColor = UIColor(hex: "#E8E0DC")
        v.layer.cornerRadius = 130
        v.layer.shadowColor   = UIColor.white.cgColor
        v.layer.shadowOpacity = Float(CGFloat(0x90) / 255)
        v.layer.shadowRadius  = 8
        v.layer.shadowOffset  = CGSize(width: -4, height: -4)
        return v
    }()

    // c9guU: 어두운 bottom-right 그림자
    private let dialFaceDarkShadow: UIView = {
        let v = UIView()
        v.isUserInteractionEnabled = false
        v.backgroundColor = UIColor(hex: "#f6efee")
        v.layer.cornerRadius = 130
        v.layer.shadowColor   = UIColor.black.cgColor
        v.layer.shadowOpacity = Float(CGFloat(0x18) / 255)
        v.layer.shadowRadius  = 6
        v.layer.shadowOffset  = CGSize(width: 3, height: 3)
        return v
    }()

    // c9guU: 밝은 top-left 그림자
    private let dialFaceLightShadow: UIView = {
        let v = UIView()
        v.isUserInteractionEnabled = false
        v.backgroundColor = UIColor(hex: "#f6efee")
        v.layer.cornerRadius = 130
        v.layer.shadowColor   = UIColor.white.cgColor
        v.layer.shadowOpacity = Float(CGFloat(0x80) / 255)
        v.layer.shadowRadius  = 6
        v.layer.shadowOffset  = CGSize(width: -3, height: -3)
        return v
    }()

    // ql0s8: 작은 어두운 그림자 (blur 4)
    private let innerCircleSmallDarkShadow: UIView = {
        let v = UIView()
        v.isUserInteractionEnabled = false
        v.backgroundColor = .white
        v.layer.cornerRadius = 83.2
        v.layer.shadowColor   = UIColor(hex: "#C5BDB8").cgColor
        v.layer.shadowOpacity = Float(CGFloat(0x30) / 255)
        v.layer.shadowRadius  = 4
        v.layer.shadowOffset  = CGSize(width: 2, height: 2)
        return v
    }()

    // ql0s8: 작은 밝은 그림자 (blur 4)
    private let innerCircleSmallLightShadow: UIView = {
        let v = UIView()
        v.isUserInteractionEnabled = false
        v.backgroundColor = .white
        v.layer.cornerRadius = 83.2
        v.layer.shadowColor   = UIColor.white.cgColor
        v.layer.shadowOpacity = Float(CGFloat(0x90) / 255)
        v.layer.shadowRadius  = 4
        v.layer.shadowOffset  = CGSize(width: -2, height: -2)
        return v
    }()

    // qjh5D: 밝은 top-left 그림자 (blur 8)
    private let centerKnobLightShadow: UIView = {
        let v = UIView()
        v.isUserInteractionEnabled = false
        v.backgroundColor = UIColor(hex: "#E8E0DC")
        v.layer.cornerRadius = 15.6
        v.layer.shadowColor   = UIColor.white.cgColor
        v.layer.shadowOpacity = Float(CGFloat(0x90) / 255)
        v.layer.shadowRadius  = 8
        v.layer.shadowOffset  = CGSize(width: -4, height: -4)
        return v
    }()

    // qjh5D: 작은 어두운 그림자 (blur 2)
    private let centerKnobSmallDarkShadow: UIView = {
        let v = UIView()
        v.isUserInteractionEnabled = false
        v.backgroundColor = UIColor(hex: "#E8E0DC")
        v.layer.cornerRadius = 15.6
        v.layer.shadowColor   = UIColor.black.cgColor
        v.layer.shadowOpacity = Float(CGFloat(0x12) / 255)
        v.layer.shadowRadius  = 2
        v.layer.shadowOffset  = CGSize(width: 1, height: 1)
        return v
    }()

    // qjh5D: 작은 밝은 그림자 (blur 2)
    private let centerKnobSmallLightShadow: UIView = {
        let v = UIView()
        v.isUserInteractionEnabled = false
        v.backgroundColor = UIColor(hex: "#E8E0DC")
        v.layer.cornerRadius = 15.6
        v.layer.shadowColor   = UIColor.white.cgColor
        v.layer.shadowOpacity = Float(CGFloat(0x70) / 255)
        v.layer.shadowRadius  = 2
        v.layer.shadowOffset  = CGSize(width: -1, height: -1)
        return v
    }()

    // 노브 위 인디케이터 (Node akjLM — tick-15 / rotation -90°)
    private let knobNeedleView: UIView = {
        let v = UIView()
        v.backgroundColor    = UIColor.primary
        v.layer.cornerRadius = 1
        return v
    }()

    // MARK: - Timer Text
    private let timerLabel: UILabel = {
        let l = UILabel()
        l.text = "15 : 00"
        l.font = UIFont(name: "GoyangIlsan R", size: 24)
            ?? .systemFont(ofSize: 24, weight: .light)
        l.textColor   = UIColor.primary
        l.textAlignment = .center
        return l
    }()

    // MARK: - Controls
    private lazy var resetButton: UIButton = {
        let btn = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        btn.setImage(UIImage(systemName: "arrow.counterclockwise", withConfiguration: cfg), for: .normal)
        btn.tintColor        = UIColor.primary.withAlphaComponent(0.6)
        btn.backgroundColor  = UIColor(hex: "#5d4037", alpha: CGFloat(0x12) / 255)
        btn.layer.cornerRadius = 22
        btn.layer.borderWidth  = 1
        btn.layer.borderColor  = UIColor(hex: "#5d4037", alpha: CGFloat(0x15) / 255).cgColor
        return btn
    }()

    private lazy var playButton: UIButton = {
        let btn = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        btn.setImage(UIImage(systemName: "play.fill", withConfiguration: cfg), for: .normal)
        btn.tintColor          = UIColor.primary
        btn.layer.cornerRadius = 28
        btn.clipsToBounds      = true
        return btn
    }()

    private lazy var stopButton: UIButton = {
        let btn = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        btn.setImage(UIImage(systemName: "stop.fill", withConfiguration: cfg), for: .normal)
        btn.tintColor        = UIColor.primary.withAlphaComponent(0.6)
        btn.backgroundColor  = UIColor(hex: "#5d4037", alpha: CGFloat(0x12) / 255)
        btn.layer.cornerRadius = 22
        btn.layer.borderWidth  = 1
        btn.layer.borderColor  = UIColor(hex: "#5d4037", alpha: CGFloat(0x15) / 255).cgColor
        return btn
    }()

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
        if dialContainer.bounds.width > 0 { drawTimerDial() }
        if chartCard.bounds.width > 0     { drawChart() }
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = UIColor.background

        view.addSubview(scrollView)
        scrollView.addSubview(contentView)

        // Header
        contentView.addSubview(backButton)
        contentView.addSubview(titleLabel)

        // Dial — 레이어/뷰 순서가 z-order를 결정
        dialContainer.addSubview(dialFaceLightShadow)           // -1b. 페이스 밝은 뉴모픽 그림자
        dialContainer.addSubview(dialFaceDarkShadow)            // -1a. 페이스 어두운 뉴모픽 그림자
        dialContainer.addSubview(dialFaceView)                  // 0. 연한 크림색 다이얼 페이스
        dialContainer.layer.addSublayer(outerWedgeLayer)        // 1. 외부 웨지
        dialContainer.addSubview(markingsView)                  // 2. 틱마크 & 숫자
        dialContainer.addSubview(innerCircleSmallLightShadow)   // 2.3. 내부 원 작은 밝은 그림자
        dialContainer.addSubview(innerCircleSmallDarkShadow)    // 2.4. 내부 원 작은 어두운 그림자
        dialContainer.addSubview(innerCircleLightShadow)        // 2.5. 내부 원 밝은 뉴모픽 그림자
        dialContainer.addSubview(innerCircleView)               // 3. 흰 내부 원 (마킹 위를 덮음)
        dialContainer.layer.addSublayer(innerArcLayer)          // 4. 내부 갈색 호 (흰 원 위)
        centerKnobView.addSubview(knobNeedleView)               // 5-1. 노브 인디케이터 (Node akjLM)
        knobNeedleView.transform = CGAffineTransform(rotationAngle: -.pi / 2)
        dialContainer.addSubview(centerKnobSmallDarkShadow)     // 4.7a. 노브 작은 어두운 그림자
        dialContainer.addSubview(centerKnobSmallLightShadow)    // 4.7b. 노브 작은 밝은 그림자
        dialContainer.addSubview(centerKnobLightShadow)         // 4.8. 노브 밝은 그림자
        dialContainer.addSubview(centerKnobView)                // 5. 중앙 노브 (최상단)
        contentView.addSubview(dialContainerLightShadow)        // dialContainer 밝은 그림자 (뒤)
        contentView.addSubview(dialContainer)

        // Timer text & controls
        contentView.addSubview(timerLabel)
        contentView.addSubview(resetButton)
        contentView.addSubview(playButton)
        contentView.addSubview(stopButton)

        // Book title
        contentView.addSubview(bookTitleLabel)

        // Progress
        progressBarBg.addSubview(progressBarFill)
        progressSection.addSubview(progressHeaderLabel)
        progressSection.addSubview(editButton)
        progressSection.addSubview(progressBarBg)
        progressSection.addSubview(progressDetailLabel)
        contentView.addSubview(progressSection)

        // Chart
        tabSelectorView.addSubview(tabDailyButton)
        tabSelectorView.addSubview(tabWeeklyButton)
        tabSelectorView.addSubview(tabMonthlyButton)
        contentView.addSubview(chartTitleLabel)
        contentView.addSubview(tabSelectorView)
        chartCard.layer.addSublayer(chartAreaLayer)
        chartCard.layer.addSublayer(chartLineLayer)
        contentView.addSubview(chartCard)

        applyGlassStyle(to: playButton, cornerRadius: 28)
    }

    private func setupConstraints() {
        scrollView.snp.makeConstraints { make in
            make.edges.equalTo(view.safeAreaLayoutGuide)
        }
        contentView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            make.width.equalTo(scrollView)
        }

        // Header
        backButton.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(24)
            make.top.equalToSuperview().offset(17)
            make.size.equalTo(28)
        }
        titleLabel.snp.makeConstraints { make in
            make.leading.equalTo(backButton.snp.trailing).offset(4)
            make.centerY.equalTo(backButton)
        }

        // Dial (260×260)
        dialContainerLightShadow.snp.makeConstraints { make in
            make.edges.equalTo(dialContainer)
        }
        dialContainer.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(backButton.snp.bottom).offset(32)
            make.size.equalTo(260)
        }
        dialFaceLightShadow.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        dialFaceDarkShadow.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        dialFaceView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        markingsView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        innerCircleSmallLightShadow.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(CGFloat(166.4))
        }
        innerCircleSmallDarkShadow.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(CGFloat(166.4))
        }
        innerCircleLightShadow.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(CGFloat(166.4))
        }
        innerCircleView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(CGFloat(166.4))
        }
        centerKnobSmallDarkShadow.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(CGFloat(31.2))
        }
        centerKnobSmallLightShadow.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(CGFloat(31.2))
        }
        centerKnobLightShadow.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(CGFloat(31.2))
        }
        centerKnobView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(CGFloat(31.2))
        }
        // Node akjLM: 원 중심에 배치 (rotation -90° 적용 시 10.4×1.95 수평 바 → 원 안에 완전히 포함)
        knobNeedleView.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.trailing.equalToSuperview().inset(4)
            make.width.equalTo(CGFloat(1.95))
            make.height.equalTo(CGFloat(10.4))
        }

        // Timer text
        timerLabel.snp.makeConstraints { make in
            make.top.equalTo(dialContainer.snp.bottom).offset(20)
            make.centerX.equalToSuperview()
        }

        // Controls (Reset | Play | Stop) — 수동 배치 (applyGlassStyle 호환)
        playButton.snp.makeConstraints { make in
            make.top.equalTo(timerLabel.snp.bottom).offset(16)
            make.centerX.equalToSuperview()
            make.size.equalTo(56)
        }
        resetButton.snp.makeConstraints { make in
            make.trailing.equalTo(playButton.snp.leading).offset(-16)
            make.centerY.equalTo(playButton)
            make.size.equalTo(44)
        }
        stopButton.snp.makeConstraints { make in
            make.leading.equalTo(playButton.snp.trailing).offset(16)
            make.centerY.equalTo(playButton)
            make.size.equalTo(44)
        }

        // Book title
        bookTitleLabel.snp.makeConstraints { make in
            make.top.equalTo(playButton.snp.bottom).offset(24)
            make.leading.trailing.equalToSuperview().inset(24)
        }

        // Progress Section
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

        // Chart header
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

        // Chart Card
        chartCard.snp.makeConstraints { make in
            make.top.equalTo(tabSelectorView.snp.bottom).offset(16)
            make.leading.trailing.equalToSuperview().inset(24)
            make.height.equalTo(220)
            make.bottom.equalToSuperview().inset(24)
        }
    }

    // MARK: - Dial Drawing

    private func drawTimerDial() {
        guard !didSetupDial else { return }
        didSetupDial = true

        updateDialArc(fraction: 1.0)  // 초기 상태: 15분 전체
        addTickMarks()
        addDialLabels()
    }

    private func updateDialArc(fraction: CGFloat) {
        let center = CGPoint(x: 130, y: 130)
        // 15분 타이머 → 60분 다이얼의 1/4만 사용 (π/2 = 90°)
        let maxSweep: CGFloat = .pi / 2
        let endAngle = -.pi / 2 + fraction * maxSweep

        // 외부 웨지 (radius 122.2)
        let outerPath = UIBezierPath()
        outerPath.move(to: center)
        outerPath.addArc(withCenter: center, radius: 122.2,
                         startAngle: -.pi / 2, endAngle: endAngle, clockwise: true)
        outerPath.close()
        outerWedgeLayer.path      = outerPath.cgPath
        outerWedgeLayer.fillColor = UIColor(hex: "#DDD4CE").withAlphaComponent(0.5).cgColor

        // 내부 호 (radius 83.2, 흰 원 위에 그려짐)
        let innerPath = UIBezierPath()
        innerPath.move(to: center)
        innerPath.addArc(withCenter: center, radius: 83.2,
                         startAngle: -.pi / 2, endAngle: endAngle, clockwise: true)
        innerPath.close()
        innerArcLayer.path      = innerPath.cgPath
        innerArcLayer.fillColor = UIColor.primary.withAlphaComponent(0.9).cgColor
    }

    private func addTickMarks() {
        let center       = CGPoint(x: 130, y: 130)
        let outerRadius: CGFloat = 122.2
        let tickLength:  CGFloat = 10.4
        let tickWidth:   CGFloat = 1.95

        for i in 0..<12 {
            let angle = CGFloat(i) * (.pi * 2 / 12) - .pi / 2
            let outerPt = CGPoint(x: center.x + outerRadius * cos(angle),
                                  y: center.y + outerRadius * sin(angle))
            let innerPt = CGPoint(x: center.x + (outerRadius - tickLength) * cos(angle),
                                  y: center.y + (outerRadius - tickLength) * sin(angle))

            let path = UIBezierPath()
            path.move(to: innerPt)
            path.addLine(to: outerPt)

            let layer = CAShapeLayer()
            layer.path        = path.cgPath
            layer.strokeColor = UIColor.primary.cgColor
            layer.lineWidth   = tickWidth
            layer.lineCap     = .round
            markingsView.layer.addSublayer(layer)
        }
    }

    private func addDialLabels() {
        let center      = CGPoint(x: 130, y: 130)
        let labelRadius: CGFloat = 100
        let minutes = [0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55]

        for (i, minute) in minutes.enumerated() {
            let angle = CGFloat(i) * (.pi * 2 / 12) - .pi / 2
            let x = center.x + labelRadius * cos(angle)
            let y = center.y + labelRadius * sin(angle)

            let label = UILabel()
            label.text          = "\(minute)"
            label.font          = UIFont(name: "GoyangIlsan R", size: 11.7) ?? .systemFont(ofSize: 11.7)
            label.textColor     = UIColor.primary
            label.textAlignment = .center
            label.sizeToFit()
            label.center = CGPoint(x: x, y: y)
            markingsView.addSubview(label)
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
        let plotW = cardW - leftPad - 8  // 오른쪽 여백 8

        // 디자인 x 좌표를 카드 너비에 맞게 비례 변환
        let designXs: [CGFloat] = [24, 74, 124, 174, 224, 274, 324]
        let designRange: CGFloat = 324 - 24
        let xs = designXs.map { leftPad + ($0 - 24) / designRange * plotW }

        // 디자인 y 좌표 (0 = 차트 상단)
        let designYs: [CGFloat] = [76, 56, 96, 36, 116, 16, 56]
        let ys = designYs.map { topPad + $0 }

        // 라인 경로 (부드러운 베지어 곡선)
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

        // 면적 채우기
        let areaPath = linePath.copy() as! UIBezierPath
        let bottomY  = topPad + chartH
        areaPath.addLine(to: CGPoint(x: xs.last!, y: bottomY))
        areaPath.addLine(to: CGPoint(x: xs.first!, y: bottomY))
        areaPath.close()
        chartAreaLayer.path      = areaPath.cgPath
        chartAreaLayer.fillColor = UIColor(hex: "#5d4037", alpha: CGFloat(0x20) / 255).cgColor

        // 데이터 점 & x축 레이블
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

    // MARK: - Play Button Glass Style

    private func applyGlassStyle(to button: UIButton, cornerRadius: CGFloat) {
        guard let superview = button.superview else { return }

        let shadowView = UIView()
        shadowView.isUserInteractionEnabled = false
        shadowView.layer.cornerRadius = cornerRadius
        shadowView.backgroundColor    = .white
        shadowView.layer.shadowColor   = UIColor.black.cgColor
        shadowView.layer.shadowOpacity = Float(CGFloat(0x18) / 255)
        shadowView.layer.shadowRadius  = 8
        shadowView.layer.shadowOffset  = CGSize(width: 0, height: 6)
        superview.insertSubview(shadowView, belowSubview: button)
        shadowView.snp.makeConstraints { $0.edges.equalTo(button) }

        let glassContainer = UIView()
        glassContainer.isUserInteractionEnabled = false
        glassContainer.layer.cornerRadius = cornerRadius
        glassContainer.clipsToBounds      = true
        glassContainer.layer.borderWidth  = 1
        glassContainer.layer.borderColor  = UIColor(white: 1, alpha: CGFloat(0x70) / 255).cgColor
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
        topGrad.colors     = [UIColor(white: 1, alpha: CGFloat(0x50) / 255).cgColor,
                               UIColor(white: 1, alpha: CGFloat(0x10) / 255).cgColor,
                               UIColor.clear.cgColor]
        topGrad.locations  = [0, 0.45, 1.0]
        topGrad.startPoint = CGPoint(x: 0.5, y: 0)
        topGrad.endPoint   = CGPoint(x: 0.5, y: 1)
        topSpecular.layer.addSublayer(topGrad)
        gradientLayers.append((topSpecular, topGrad))

        let bottomWarm = UIView()
        bottomWarm.isUserInteractionEnabled = false
        blurView.contentView.addSubview(bottomWarm)
        bottomWarm.snp.makeConstraints { $0.edges.equalToSuperview() }
        let bottomGrad = CAGradientLayer()
        bottomGrad.colors     = [UIColor(hex: "#832C11", alpha: CGFloat(0x20) / 255).cgColor,
                                  UIColor(hex: "#832C11", alpha: CGFloat(0x0C) / 255).cgColor,
                                  UIColor.clear.cgColor]
        bottomGrad.locations  = [0, 0.5, 1.0]
        bottomGrad.startPoint = CGPoint(x: 0.5, y: 1)
        bottomGrad.endPoint   = CGPoint(x: 0.5, y: 0)
        bottomWarm.layer.addSublayer(bottomGrad)
        gradientLayers.append((bottomWarm, bottomGrad))

        button.backgroundColor = .clear
    }

    // MARK: - Bindings

    private func bindActions() {
        backButton.rx.tap
            .subscribe(onNext: { [weak self] in
                self?.navigationController?.popViewController(animated: true)
            })
            .disposed(by: disposeBag)

        playButton.rx.tap
            .subscribe(onNext: { [weak self] in self?.toggleTimer() })
            .disposed(by: disposeBag)

        resetButton.rx.tap
            .subscribe(onNext: { [weak self] in self?.resetTimer() })
            .disposed(by: disposeBag)

        stopButton.rx.tap
            .subscribe(onNext: { [weak self] in self?.stopTimer() })
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

    // MARK: - Timer Logic

    private func toggleTimer() {
        isRunning ? pauseTimer() : startTimer()
    }

    private func startTimer() {
        isRunning = true
        let cfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        playButton.setImage(UIImage(systemName: "pause.fill", withConfiguration: cfg), for: .normal)
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tickTimer()
        }
    }

    private func pauseTimer() {
        isRunning = false
        let cfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        playButton.setImage(UIImage(systemName: "play.fill", withConfiguration: cfg), for: .normal)
        countdownTimer?.invalidate()
        countdownTimer = nil
    }

    private func stopTimer() {
        pauseTimer()
        // TODO: 독서 시간 기록 저장
    }

    private func resetTimer() {
        pauseTimer()
        remainingSeconds = 15 * 60
        updateTimerDisplay()
        updateDialArc(fraction: 1.0)
    }

    private func tickTimer() {
        guard remainingSeconds > 0 else { stopTimer(); return }
        remainingSeconds -= 1
        updateTimerDisplay()
        let fraction = CGFloat(remainingSeconds) / CGFloat(15 * 60)
        updateDialArc(fraction: fraction)
    }

    private func updateTimerDisplay() {
        let m = remainingSeconds / 60
        let s = remainingSeconds % 60
        timerLabel.text = String(format: "%02d : %02d", m, s)
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
