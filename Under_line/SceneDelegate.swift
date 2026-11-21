//
//  SceneDelegate.swift
//  Under_line
//

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = (scene as? UIWindowScene) else { return }

        window = UIWindow(windowScene: scene)
        let launchController = LaunchAnimationViewController()
        launchController.onCompletion = { [weak self, weak launchController] in
            guard let window = self?.window,
                  let launchController,
                  window.rootViewController === launchController else { return }

            let mainController = MainTabBarController()
            mainController.loadViewIfNeeded()

            guard !UIAccessibility.isReduceMotionEnabled,
                  let launchSnapshot = launchController.view.snapshotView(afterScreenUpdates: false) else {
                window.rootViewController = mainController
                return
            }

            // 메인 화면은 제자리에 준비하고, 그 위를 덮은 시작 화면만 걷어냅니다.
            launchSnapshot.frame = window.bounds
            launchSnapshot.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            launchSnapshot.isUserInteractionEnabled = false
            launchSnapshot.accessibilityElementsHidden = true

            window.rootViewController = mainController
            window.layoutIfNeeded()
            window.addSubview(launchSnapshot)

            UIView.animate(
                withDuration: 0.35,
                delay: 0,
                options: .curveEaseOut
            ) {
                launchSnapshot.alpha = 0
            } completion: { _ in
                launchSnapshot.removeFromSuperview()
            }
        }
        window?.rootViewController = launchController
        window?.makeKeyAndVisible()
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        (window?.rootViewController as? LaunchAnimationViewController)?.startIfNeeded()
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        WidgetCacheService.shared.refreshCache()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        (window?.rootViewController as? LaunchAnimationViewController)?.cancelForBackground()
        WidgetCacheService.shared.refreshCache()
    }
}
