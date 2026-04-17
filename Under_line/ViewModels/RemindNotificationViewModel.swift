//
//  RemindNotificationViewModel.swift
//  Under_line
//
//  리마인드 알림 설정 ViewModel — 주기/시간 선택 + UNCalendarNotificationTrigger 등록
//

import Foundation
import RxSwift
import RxCocoa
import UserNotifications

final class RemindNotificationViewModel {

    struct Input {
        let periodSelected: Observable<Int?>   // 0=하루, 1=일주일, 2=한달, 3=일년 / nil=미선택
        let timePicked: Observable<Date>
        let confirmTap: Observable<Void>
    }

    struct Output {
        let isConfirmEnabled: Driver<Bool>
        let toastMessage: Signal<String>
        let schedulingSucceeded: Signal<Void>
    }

    private let disposeBag     = DisposeBag()
    private let toastSubject   = PublishSubject<String>()
    private let successSubject = PublishSubject<Void>()

    private let periodKeys = ["day", "week", "month", "year"]
    private let periodBodies = [
        "어제 추가한 밑줄이 있어요.",
        "일주일 전에 추가한 밑줄이 있어요.",
        "한 달 전에 추가한 밑줄이 있어요.",
        "일년 전 오늘 추가한 밑줄이 있어요."
    ]

    func transform(input: Input) -> Output {
        let latestPeriod = input.periodSelected.share(replay: 1)
        let latestTime   = input.timePicked.share(replay: 1)

        let isConfirmEnabled = latestPeriod
            .map { $0 != nil }
            .asDriver(onErrorJustReturn: false)

        input.confirmTap
            .withLatestFrom(Observable.combineLatest(latestPeriod, latestTime))
            .subscribe(onNext: { [weak self] period, time in
                guard let self, let period else { return }
                self.scheduleNotification(periodIndex: period, time: time)
            })
            .disposed(by: disposeBag)

        return Output(
            isConfirmEnabled:    isConfirmEnabled,
            toastMessage:        toastSubject.asSignal(onErrorJustReturn: ""),
            schedulingSucceeded: successSubject.asSignal(onErrorSignalWith: .empty())
        )
    }

    // MARK: - Scheduling

    private func scheduleNotification(periodIndex: Int, time: Date) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, _ in
            guard let self else { return }
            guard granted else {
                DispatchQueue.main.async {
                    self.toastSubject.onNext("알림 권한이 필요합니다. 설정에서 허용해주세요.")
                }
                return
            }

            UNUserNotificationCenter.current().removePendingNotificationRequests(
                withIdentifiers: ["remind_notification"]
            )

            let content = UNMutableNotificationContent()
            content.title    = "밑줄"
            content.body     = self.periodBodies[periodIndex]
            content.sound    = .default
            content.userInfo = ["period": self.periodKeys[periodIndex]]

            let cal        = Calendar.current
            var components = cal.dateComponents([.hour, .minute], from: time)

            switch periodIndex {
            case 1: // 일주일 — 완료 탭한 요일마다 반복
                components.weekday = cal.component(.weekday, from: Date())
            case 2: // 한 달 — 완료 탭한 일(day)마다 반복
                components.day = cal.component(.day, from: Date())
            case 3: // 일년 — 완료 탭한 월+일마다 반복
                components.month = cal.component(.month, from: Date())
                components.day   = cal.component(.day, from: Date())
            default: break // 하루 — hour+minute만으로 매일 반복
            }

            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let request  = UNNotificationRequest(
                identifier: "remind_notification",
                content:    content,
                trigger:    trigger
            )

            UNUserNotificationCenter.current().add(request) { [weak self] error in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if error != nil {
                        self.toastSubject.onNext("알림 설정에 실패했습니다.")
                    } else {
                        UserDefaults.standard.set(periodIndex, forKey: "remind.period")
                        UserDefaults.standard.set(
                            time.timeIntervalSinceReferenceDate,
                            forKey: "remind.time"
                        )
                        self.toastSubject.onNext("리마인드 알림이 설정되었습니다.")
                        self.successSubject.onNext(())
                    }
                }
            }
        }
    }
}
