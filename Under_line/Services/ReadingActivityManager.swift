//
//  ReadingActivityManager.swift
//  Under_line
//
//  독서 타이머 Live Activity 생명주기 관리
//  Target Membership: Under_line만
//

import Foundation

#if canImport(ActivityKit)
import ActivityKit

@available(iOS 16.2, *)
final class ReadingActivityManager {

    static let shared = ReadingActivityManager()
    private init() {}

    private var currentActivity: Activity<ReadingTimerAttributes>?

    // MARK: - Start

    func startActivity(bookTitle: String,
                       isbn13: String,
                       totalSeconds: Int,
                       remainingSeconds: Int,
                       timerEndDate: Date) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // 이미 실행 중인 Activity가 있으면 즉시 종료 후 재시작
        if let existing = currentActivity {
            Task { await existing.end(nil, dismissalPolicy: .immediate) }
            currentActivity = nil
        }

        let attributes = ReadingTimerAttributes(
            bookTitle:    bookTitle,
            totalSeconds: totalSeconds,
            isbn13:       isbn13
        )
        let initialState = ReadingTimerAttributes.ContentState(
            remainingSeconds: remainingSeconds,
            isRunning:        true,
            timerEndDate:     timerEndDate
        )

        do {
            currentActivity = try Activity<ReadingTimerAttributes>.request(
                attributes: attributes,
                content: .init(
                    state:     initialState,
                    staleDate: timerEndDate.addingTimeInterval(60)
                ),
                pushType: nil
            )
        } catch {
            // .unsupported, .denied 등 — 조용히 무시
        }
    }

    // MARK: - Update (일시정지 / 재개)

    func updateActivity(remainingSeconds: Int,
                        isRunning: Bool,
                        timerEndDate: Date?) {
        guard let activity = currentActivity else { return }

        let newState = ReadingTimerAttributes.ContentState(
            remainingSeconds: remainingSeconds,
            isRunning:        isRunning,
            timerEndDate:     timerEndDate
        )
        let staleDate = timerEndDate?.addingTimeInterval(60)
            ?? Date(timeIntervalSinceNow: 300)

        Task {
            await activity.update(.init(state: newState, staleDate: staleDate))
        }
    }

    // MARK: - End

    func endActivity(remainingSeconds: Int) {
        guard let activity = currentActivity else { return }

        let finalState = ReadingTimerAttributes.ContentState(
            remainingSeconds: remainingSeconds,
            isRunning:        false,
            timerEndDate:     nil
        )
        Task {
            // 4초 후 자동 해제 — 완료 상태를 잠깐 보여줌
            await activity.end(
                .init(state: finalState, staleDate: nil),
                dismissalPolicy: .after(Date(timeIntervalSinceNow: 4))
            )
        }
        currentActivity = nil
    }

    // MARK: - End All (앱 종료 시 정리용)

    func endAllActivities() {
        Task {
            for activity in Activity<ReadingTimerAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        currentActivity = nil
    }
}
#endif
