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

            window.rootViewController = MainTabBarController()
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
