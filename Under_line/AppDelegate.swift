//
//  AppDelegate.swift
//  Under_line
//

import UIKit
import UserNotifications

extension Notification.Name {
    static let reminderNotificationTapped = Notification.Name("reminderNotificationTapped")
}

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        Thread.sleep(forTimeInterval: 1.5)
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate: UNUserNotificationCenterDelegate {

    // 알림 탭 → period 파싱 → SceneDelegate에 브로드캐스트
    // nonisolated: UNUserNotificationCenter가 백그라운드 스레드에서 호출
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let period = response.notification.request.content.userInfo["period"] as? String {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .reminderNotificationTapped, object: period)
            }
        }
        completionHandler()
    }

    // 앱 포그라운드 상태에서 알림 수신 시 배너 + 사운드 표시
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
