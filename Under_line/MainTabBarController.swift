//
//  MainTabBarController.swift
//  Under_line
//

import UIKit

final class MainTabBarController: UITabBarController {

    override func viewDidLoad() {
        super.viewDidLoad()
        setupTabs()
        setupAppearance()
    }

    private func setupTabs() {
        let booksVC = BookshelfViewController()
        booksVC.tabBarItem = UITabBarItem(
            title: "도서",
            image: UIImage(systemName: "house"),
            selectedImage: UIImage(systemName: "house.fill")
        )

        let statsVC = UIViewController()
        statsVC.view.backgroundColor = UIColor.background
        statsVC.tabBarItem = UITabBarItem(
            title: "통계",
            image: UIImage(systemName: "chart.pie"),
            selectedImage: UIImage(systemName: "chart.pie.fill")
        )

        let settingsVC = UIViewController()
        settingsVC.view.backgroundColor = UIColor.background
        settingsVC.tabBarItem = UITabBarItem(
            title: "설정",
            image: UIImage(systemName: "gearshape"),
            selectedImage: UIImage(systemName: "gearshape.fill")
        )

        viewControllers = [booksVC, statsVC, settingsVC]
    }

    private func setupAppearance() {
        let primary = UIColor.primary
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
