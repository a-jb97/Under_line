//
//  ReadingTimerAttributes.swift
//  Under_line
//
//  Live Activities + Dynamic Island 용 공유 타입
//  Target Membership: Under_line + UnderLineWidget
//

#if canImport(ActivityKit)
import ActivityKit
import Foundation

struct ReadingTimerAttributes: ActivityAttributes {

    // MARK: - Static (Activity 시작 시 고정)
    let bookTitle: String
    let totalSeconds: Int   // 설정된 총 초 — 프로그레스 계산 분모
    let isbn13: String

    // MARK: - Dynamic (update 시 변경)
    struct ContentState: Codable, Hashable {
        var remainingSeconds: Int
        var isRunning: Bool
        var timerEndDate: Date?   // 실행 중일 때만 non-nil — Text(timerInterval:) 카운트다운용
    }
}
#endif
