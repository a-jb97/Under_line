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

final class StatisticsViewController: AdaptiveViewController {

    private let disposeBag  = DisposeBag()
    private let reloadRelay = PublishRelay<Void>()
    private var isViewVisible = false
    private var isDonutDataReady = false
    private var shouldAnimateDonutOnAppearance = false
    private var isStatisticsRequestInFlight = false
    private var latestDonutData: SentenceDonutStatisticsData?
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

    private let allSentencesButton = SystemNavigationStyle.item(
        image: "text.quote", label: "밑줄 모아보기", identifier: "allSentencesButton", priority: .high
    )

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
        SystemNavigationStyle.observeBarPlacement(on: self)
        bindViewModel()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        SystemNavigationStyle.setSectionTitle("통계", leadingInset: 8, on: self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        heatmapCard.clearSelection()
        isViewVisible = true
        isDonutDataReady = latestDonutData != nil
        shouldAnimateDonutOnAppearance = true
        genreCard.prepareForAnimation()
        requestStatisticsData()
        animateDonutIfReady()
        lockTabBarBriefly()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        showTutorialIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isViewVisible = false
    }

    private func animateDonutIfReady() {
        guard isViewVisible, isDonutDataReady, shouldAnimateDonutOnAppearance else { return }
        shouldAnimateDonutOnAppearance = false
        view.layoutIfNeeded()
        genreCard.animateIn()
    }

    func prefetchData() {
        loadViewIfNeeded()
        requestStatisticsData()
    }

    private func requestStatisticsData() {
        guard !isStatisticsRequestInFlight else { return }
        isStatisticsRequestInFlight = true
        reloadRelay.accept(())
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
        SystemNavigationStyle.configure(self, title: "")
        SystemNavigationStyle.setSectionTitle("통계", leadingInset: 8, on: self)
        SystemNavigationStyle.setTrailingItems([allSentencesButton], on: navigationItem)
        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)

        contentStack.addArrangedSubview(heatmapCard)
        contentStack.addArrangedSubview(genreCard)
        contentStack.addArrangedSubview(lineChartCard)
    }

    private func setupConstraints() {
        scrollView.snp.makeConstraints { make in
            make.top.equalTo(view.adaptiveContentLayoutGuide)
            make.leading.trailing.equalTo(view.adaptiveContentLayoutGuide)
            make.bottom.equalTo(view.adaptiveContentLayoutGuide)
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
                targetFrame: .zero,
                message: "날짜 칸을 탭하면 해당 날의\n독서 시간을 확인할 수 있어요",
                targetFrameProvider: { [weak self] in
                    guard let target = self?.heatmapCard else { return .zero }
                    return target.convert(target.bounds, to: nil)
                }
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
            reload: reloadRelay.asObservable()
        ))

        output.allSessions
            .drive(onNext: { [weak self] sessions in
                self?.heatmapCard.configure(with: sessions)
            })
            .disposed(by: disposeBag)

        output.donutData
            .drive(onNext: { [weak self] data in
                guard let self else { return }
                self.isStatisticsRequestInFlight = false
                if self.latestDonutData != data {
                    self.latestDonutData = data
                    self.genreCard.configure(genreData: data.genre, authorData: data.author)
                }
                self.isDonutDataReady = true
                self.animateDonutIfReady()
            })
            .disposed(by: disposeBag)

        output.lineChartData
            .drive(onNext: { [weak self] data in
                self?.lineChartCard.configure(with: data)
            })
            .disposed(by: disposeBag)
    }

}
