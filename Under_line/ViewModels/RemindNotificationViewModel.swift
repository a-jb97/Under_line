//
//  RemindNotificationViewModel.swift
//  Under_line
//
//  리마인드 알림 설정 ViewModel — 주기/시간 선택 + BGAppRefreshTask 등록
//

import Foundation
import RxSwift
import RxCocoa
import UserNotifications
import BackgroundTasks

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

            // 기존 예약 취소 후 새 BGAppRefreshTask 등록
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: AppDelegate.reminderTaskID)

            let fireDate = AppDelegate.nextFireDate(periodIndex: periodIndex, selectedTime: time)
            let request  = BGAppRefreshTaskRequest(identifier: AppDelegate.reminderTaskID)
            request.earliestBeginDate = fireDate

            do {
                try BGTaskScheduler.shared.submit(request)
                DispatchQueue.main.async {
                    UserDefaults.standard.set(periodIndex, forKey: "remind.period")
                    UserDefaults.standard.set(time.timeIntervalSinceReferenceDate, forKey: "remind.time")
                    self.toastSubject.onNext("리마인드 알림이 설정되었습니다.")
                    self.successSubject.onNext(())
                }
            } catch {
                DispatchQueue.main.async {
                    self.toastSubject.onNext("알림 설정에 실패했습니다.")
                }
            }
        }
    }
}
