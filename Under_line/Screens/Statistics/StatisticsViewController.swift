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
    private var highlightLayers: [(view: UIView, layer: CAGradientLayer)] = []
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

    private lazy var allSentencesButton: UIButton = {
        let btn = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        btn.setImage(UIImage(systemName: "text.quote", withConfiguration: cfg), for: .normal)
        btn.tintColor = UIColor.walnut
        btn.layer.cornerRadius = 20
        btn.clipsToBounds = true
        return btn
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

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        for (view, gradient) in highlightLayers {
            gradient.frame = view.bounds
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        heatmapCard.clearSelection()
        viewWillAppearRelay.accept(())
        lockTabBarBriefly()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        showTutorialIfNeeded()
    }

    private func lockTabBarBriefly() {
        guard !UserDefaults.standard.bool(forKey: "tutorial.statistics") else { return }
        tabBarController?.tabBar.isUserInteractionEnabled = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.tabBarController?.tabBar.isUserInteractionEnabled = true
        }
    }

    // MARK: - Setup

    private func setupUI() {
        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)

        let headerContainer = UIView()
        headerContainer.addSubview(titleLabel)
        headerContainer.addSubview(allSentencesButton)
        headerContainer.snp.makeConstraints { make in
            make.height.equalTo(54)
        }
        allSentencesButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview()
            make.centerY.equalToSuperview()
            make.size.equalTo(40)
        }
        titleLabel.snp.makeConstraints { make in
            make.leading.centerY.equalToSuperview()
            make.trailing.lessThanOrEqualTo(allSentencesButton.snp.leading).offset(-8)
        }
        applyFabGlassStyle(to: allSentencesButton, cornerRadius: 20)

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
            make.width.lessThanOrEqualTo(700)
            make.width.equalTo(scrollView).offset(-48).priority(.high)
            make.centerX.equalTo(scrollView)
        }
    }

    // MARK: - Tutorial

    private func showTutorialIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: "tutorial.statistics") else { return }

        scrollView.setContentOffset(.zero, animated: false)

        // 튜토리얼 시작 전에 셀 선택 + 툴팁을 미리 표시
        heatmapCard.showDemoSelection()

        let steps: [TutorialStep] = [
            TutorialStep(
                targetFrame: heatmapCard.convert(heatmapCard.bounds, to: nil),
                message: "날짜 칸을 탭하면 해당 날의\n독서 시간을 확인할 수 있어요"
            ),
        ]

        let tutorialVC = TutorialOverlayViewController()
        tutorialVC.steps = steps
        tutorialVC.modalPresentationStyle = .overFullScreen
        tutorialVC.modalTransitionStyle = .crossDissolve
        tutorialVC.onFinished = { [weak self] in
            self?.heatmapCard.hideDemoSelection()
            UserDefaults.standard.set(true, forKey: "tutorial.statistics")
        }
        present(tutorialVC, animated: true)
    }

    // MARK: - ViewModel Binding

    private func bindViewModel() {
        allSentencesButton.rx.tap
            .subscribe(onNext: { [weak self] in
                guard let self else { return }
                self.navigationController?.pushViewController(AllSentenceViewController(), animated: true)
            })
            .disposed(by: disposeBag)

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

        output.lineChartData
            .drive(onNext: { [weak self] data in
                self?.lineChartCard.configure(with: data)
            })
            .disposed(by: disposeBag)
    }

    // MARK: - FAB Glass Style

    private func applyFabGlassStyle(to button: UIButton, cornerRadius: CGFloat) {
        guard let superview = button.superview else { return }

        let shadowView = UIView()
        shadowView.isUserInteractionEnabled = false
        shadowView.layer.cornerRadius = cornerRadius
        shadowView.backgroundColor = .white
        shadowView.layer.shadowColor   = UIColor.black.cgColor
        shadowView.layer.shadowOpacity = Float(CGFloat(0x18) / 255)
        shadowView.layer.shadowRadius  = 8
        shadowView.layer.shadowOffset  = CGSize(width: 0, height: 6)
        superview.insertSubview(shadowView, belowSubview: button)
        shadowView.snp.makeConstraints { $0.edges.equalTo(button) }

        let glassContainer = UIView()
        glassContainer.isUserInteractionEnabled = false
        glassContainer.layer.cornerRadius = cornerRadius
        glassContainer.clipsToBounds = true
        glassContainer.layer.borderWidth = 1
        glassContainer.layer.borderColor = UIColor(white: 1, alpha: CGFloat(0x70) / 255).cgColor
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
        topGrad.colors = [
            UIColor(white: 1, alpha: CGFloat(0x50) / 255).cgColor,
            UIColor(white: 1, alpha: CGFloat(0x10) / 255).cgColor,
            UIColor.clear.cgColor,
        ]
        topGrad.locations  = [0, 0.45, 1.0]
        topGrad.startPoint = CGPoint(x: 0.5, y: 0)
        topGrad.endPoint   = CGPoint(x: 0.5, y: 1)
        topSpecular.layer.addSublayer(topGrad)
        highlightLayers.append((topSpecular, topGrad))

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
        bottomGrad.locations  = [0, 0.5, 1.0]
        bottomGrad.startPoint = CGPoint(x: 0.5, y: 1)
        bottomGrad.endPoint   = CGPoint(x: 0.5, y: 0)
        bottomWarm.layer.addSublayer(bottomGrad)
        highlightLayers.append((bottomWarm, bottomGrad))

        button.backgroundColor = .clear
    }
}

