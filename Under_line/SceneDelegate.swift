//
//  SceneDelegate.swift
//  Under_line
//

import UIKit
import RxSwift

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?
    private var reminderObserver: NSObjectProtocol?
    private let disposeBag = DisposeBag()

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = (scene as? UIWindowScene) else { return }

        window = UIWindow(windowScene: scene)
        window?.rootViewController = MainTabBarController()
        window?.makeKeyAndVisible()

        setupReminderObserver()
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        if let observer = reminderObserver {
            NotificationCenter.default.removeObserver(observer)
            reminderObserver = nil
        }
    }

    func sceneDidBecomeActive(_ scene: UIScene) { }

    func sceneWillResignActive(_ scene: UIScene) { }

    func sceneWillEnterForeground(_ scene: UIScene) {
        WidgetCacheService.shared.refreshCache()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        WidgetCacheService.shared.refreshCache()
    }

    // MARK: - Reminder Notification

    private func setupReminderObserver() {
        reminderObserver = NotificationCenter.default.addObserver(
            forName: .reminderNotificationTapped,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self, let period = notification.object as? String else { return }
            self.handleReminderNotification(period: period)
        }
    }

    private func handleReminderNotification(period: String) {
        let now = Date()
        let cal = Calendar.current
        let targetDate: Date

        switch period {
        case "day":   targetDate = cal.date(byAdding: .day,   value: -1, to: now) ?? now
        case "week":  targetDate = cal.date(byAdding: .day,   value: -7, to: now) ?? now
        case "month": targetDate = cal.date(byAdding: .month, value: -1, to: now) ?? now
        case "year":  targetDate = cal.date(byAdding: .year,  value: -1, to: now) ?? now
        default:      return
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy년 M월 d일"
        let dateLabel = "\(formatter.string(from: targetDate)) 밑줄"

        AppContainer.shared.sentenceRepository
            .fetchSentences(addedOn: targetDate)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] sentences in
                self?.presentReminderVC(sentences: sentences, dateLabel: dateLabel)
            })
            .disposed(by: disposeBag)
    }

    private func presentReminderVC(sentences: [Sentence], dateLabel: String) {
        guard let root = window?.rootViewController else { return }
        var topVC = root
        while let presented = topVC.presentedViewController {
            topVC = presented
        }
        let vc = ReminderSentenceViewController(sentences: sentences, dateLabel: dateLabel)
        vc.modalPresentationStyle = .pageSheet
        if let sheet = vc.sheetPresentationController {
            sheet.detents               = [.large()]
            sheet.preferredCornerRadius = 24
        }
        topVC.present(vc, animated: true)
    }
}
