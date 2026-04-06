//
//  MainTabBarController.swift
//  Under_line
//

import UIKit
import RxSwift
import RxCocoa

final class MainTabBarController: UITabBarController {

    private let disposeBag             = DisposeBag()
    private let emotionSelectedRelay   = PublishRelay<Emotion>()
    private let viewDidAppearOnceRelay = PublishRelay<Void>()
    private var hasAppeared            = false

    private lazy var randomVM = RandomUnderLineViewModel(
        repository: AppContainer.shared.sentenceRepository
    )

    override func viewDidLoad() {
        super.viewDidLoad()
        setupTabs()
        setupAppearance()
        bindRandomUnderLine()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !hasAppeared else { return }
        hasAppeared = true
        viewDidAppearOnceRelay.accept(())
    }

    private func setupTabs() {
        let booksVC = BookshelfViewController()
        booksVC.tabBarItem = UITabBarItem(
            title: "도서",
            image: UIImage(systemName: "house"),
            selectedImage: UIImage(systemName: "house.fill")
        )
        let booksNav = UINavigationController(rootViewController: booksVC)
        booksNav.setNavigationBarHidden(true, animated: false)
        booksNav.tabBarItem = booksVC.tabBarItem

        let statsVC = StatisticsViewController()
        statsVC.tabBarItem = UITabBarItem(
            title: "통계",
            image: UIImage(systemName: "chart.pie"),
            selectedImage: UIImage(systemName: "chart.pie.fill")
        )
        let statsNav = UINavigationController(rootViewController: statsVC)
        statsNav.setNavigationBarHidden(true, animated: false)
        statsNav.tabBarItem = statsVC.tabBarItem

        let settingsVC = SettingsViewController()
        settingsVC.tabBarItem = UITabBarItem(
            title: "설정",
            image: UIImage(systemName: "gearshape"),
            selectedImage: UIImage(systemName: "gearshape.fill")
        )

        viewControllers = [booksNav, statsNav, settingsVC]
    }

    // MARK: - Random UnderLine

    private func bindRandomUnderLine() {
        let output = randomVM.transform(input: RandomUnderLineViewModel.Input(
            viewDidLoad:     viewDidAppearOnceRelay.asObservable(),
            emotionSelected: emotionSelectedRelay.asObservable()
        ))

        output.shouldPresentEmotionPicker
            .emit(onNext: { [weak self] enabledEmotions in
                guard let self,
                      !enabledEmotions.isEmpty,
                      !UserDefaults.standard.bool(forKey: "randomUnderLine.isDisabled") else { return }
                let vc = RandomUnderLineEmotionViewController(
                    enabledEmotions: enabledEmotions,
                    onEmotionSelected: { [weak self] emotion in
                        self?.emotionSelectedRelay.accept(emotion)
                    }
                )
                vc.modalPresentationStyle = .pageSheet
                self.present(vc, animated: true)
            })
            .disposed(by: disposeBag)

        output.randomSentence
            .emit(onNext: { [weak self] sentence in
                guard let self else { return }
                let vc = RandomUnderLineViewController(sentence: sentence)
                vc.modalPresentationStyle = .overFullScreen
                vc.modalTransitionStyle   = .crossDissolve
                self.present(vc, animated: true)
            })
            .disposed(by: disposeBag)
    }

    private func setupAppearance() {
        let primary = UIColor.appPrimary
        let bg      = UIColor.background

        // 배경색만 Appearance로 지정
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = bg
        tabBar.standardAppearance  = appearance
        tabBar.scrollEdgeAppearance = appearance

        // 아이템 색상은 직접 프로퍼티로 지정 (Appearance보다 신뢰도 높음)
        tabBar.tintColor                = primary   // 선택된 탭
        tabBar.unselectedItemTintColor  = primary   // 비선택 탭
    }
}
