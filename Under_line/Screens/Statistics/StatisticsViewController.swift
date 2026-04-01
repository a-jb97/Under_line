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
        heatmapCard.clearSelection()
        viewWillAppearRelay.accept(())
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        showTutorialIfNeeded()
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
            make.width.lessThanOrEqualTo(700)
            make.width.equalTo(scrollView).offset(-48).priority(.high)
            make.centerX.equalTo(scrollView)
        }
    }

    // MARK: - Tutorial

    private func showTutorialIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: "tutorial.statistics") else { return }

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
}

