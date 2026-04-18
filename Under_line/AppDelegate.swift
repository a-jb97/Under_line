//
//  AppDelegate.swift
//  Under_line
//

import UIKit
import UserNotifications
import BackgroundTasks
import SwiftData

extension Notification.Name {
    static let reminderNotificationTapped = Notification.Name("reminderNotificationTapped")
}

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    static let reminderTaskID = "com.jade.UnderLine.reminderCheck"

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        Thread.sleep(forTimeInterval: 1.5)
        UNUserNotificationCenter.current().delegate = self
        registerReminderTask()
        return true
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
    }

    // MARK: - BGAppRefreshTask

    private func registerReminderTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.reminderTaskID, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            refreshTask.expirationHandler = { refreshTask.setTaskCompleted(success: false) }
            DispatchQueue.main.async {
                self.performReminderCheck()
                AppDelegate.scheduleReminderTask()
                refreshTask.setTaskCompleted(success: true)
            }
        }
    }

    // 지정 날짜에 문장이 있을 때만 알림 발송
    private func performReminderCheck() {
        let periodIndex = UserDefaults.standard.integer(forKey: "remind.period")
        guard UserDefaults.standard.double(forKey: "remind.time") > 0 else { return }

        let now = Date()
        let cal = Calendar.current
        let targetDate: Date
        switch periodIndex {
        case 0: targetDate = cal.date(byAdding: .day,   value: -1, to: now) ?? now
        case 1: targetDate = cal.date(byAdding: .day,   value: -7, to: now) ?? now
        case 2: targetDate = cal.date(byAdding: .month, value: -1, to: now) ?? now
        case 3: targetDate = cal.date(byAdding: .year,  value: -1, to: now) ?? now
        default: return
        }

        let start = cal.startOfDay(for: targetDate)
        let end   = cal.date(byAdding: .day, value: 1, to: start)!
        let descriptor = FetchDescriptor<SentenceRecord>(
            predicate: #Predicate { $0.date >= start && $0.date < end }
        )
        let hasSentences = (try? AppContainer.shared.modelContainer.mainContext.fetch(descriptor).isEmpty == false) ?? false
        guard hasSentences else { return }

        let bodies  = ["어제 추가한 밑줄이 있어요.", "일주일 전에 추가한 밑줄이 있어요.", "한 달 전에 추가한 밑줄이 있어요.", "일년 전 오늘 추가한 밑줄이 있어요."]
        let keys    = ["day", "week", "month", "year"]

        let content      = UNMutableNotificationContent()
        content.title    = "밑줄"
        content.body     = bodies[periodIndex]
        content.sound    = .default
        content.userInfo = ["period": keys[periodIndex]]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "remind_fire", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    // 다음 주기의 BGAppRefreshTask 등록
    static func scheduleReminderTask() {
        let periodIndex  = UserDefaults.standard.integer(forKey: "remind.period")
        let timeInterval = UserDefaults.standard.double(forKey: "remind.time")
        guard timeInterval > 0 else { return }

        let selectedTime = Date(timeIntervalSinceReferenceDate: timeInterval)
        let fireDate     = nextFireDate(periodIndex: periodIndex, selectedTime: selectedTime)
        let request      = BGAppRefreshTaskRequest(identifier: reminderTaskID)
        request.earliestBeginDate = fireDate
        try? BGTaskScheduler.shared.submit(request)
    }

    // period + 선택 시간 → 다음 실행 날짜
    static func nextFireDate(periodIndex: Int, selectedTime: Date) -> Date {
        let cal  = Calendar.current
        let now  = Date()
        let tc   = cal.dateComponents([.hour, .minute], from: selectedTime)
        var base = cal.dateComponents([.year, .month, .day], from: now)
        base.hour = tc.hour; base.minute = tc.minute; base.second = 0
        let todayAtTime = cal.date(from: base) ?? now
        switch periodIndex {
        case 0: return cal.date(byAdding: .day,   value: 1, to: todayAtTime) ?? todayAtTime
        case 1: return cal.date(byAdding: .day,   value: 7, to: todayAtTime) ?? todayAtTime
        case 2: return cal.date(byAdding: .month, value: 1, to: todayAtTime) ?? todayAtTime
        case 3: return cal.date(byAdding: .year,  value: 1, to: todayAtTime) ?? todayAtTime
        default: return cal.date(byAdding: .day,  value: 1, to: todayAtTime) ?? todayAtTime
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate: UNUserNotificationCenterDelegate {

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

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
