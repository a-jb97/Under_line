//
//  ReadingTimerLiveActivityView.swift
//  UnderLineWidget
//
//  Live Activities + Dynamic Island 뷰
//  Target Membership: UnderLineWidget
//

import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - 색상 상수

private let timerPrimary = Color(red: 0.365, green: 0.251, blue: 0.216)  // #5d4037
private let timerBg      = Color(red: 0.910, green: 0.878, blue: 0.863)  // #E8E0DC

// MARK: - 헬퍼

private func progressFraction(remaining: Int, total: Int) -> CGFloat {
    guard total > 0 else { return 0 }
    return min(1, max(0, CGFloat(remaining) / CGFloat(total)))
}

private func formatSeconds(_ seconds: Int) -> String {
    let m = seconds / 60
    let s = seconds % 60
    return String(format: "%02d:%02d", m, s)
}

// MARK: - Lock Screen 뷰

struct ReadingTimerLockScreenView: View {
    let context: ActivityViewContext<ReadingTimerAttributes>

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            // 프로그레스 링 + 책 아이콘
            ZStack {
                Circle()
                    .stroke(timerPrimary.opacity(0.2), lineWidth: 4)
                    .frame(width: 52, height: 52)
                Circle()
                    .trim(from: 0, to: progressFraction(remaining: context.state.remainingSeconds,
                                                        total: context.attributes.totalSeconds))
                    .stroke(timerPrimary,
                            style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 52, height: 52)
                    .animation(.linear(duration: 1), value: context.state.remainingSeconds)
                Image(systemName: "book.closed.fill")
                    .foregroundStyle(timerPrimary)
                    .font(.system(size: 18))
            }

            // 책 제목 + 카운트다운
            VStack(alignment: .leading, spacing: 4) {
                Text(context.attributes.bookTitle)
                    .font(.custom("GowunBatang-Bold", size: 14))
                    .foregroundStyle(timerPrimary)
                    .lineLimit(1)

                if context.state.isRunning, let end = context.state.timerEndDate {
                    Text(timerInterval: Date.now...max(end, Date.now), countsDown: true)
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .foregroundStyle(timerPrimary)
                        .monospacedDigit()
                } else {
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text(formatSeconds(context.state.remainingSeconds))
                            .font(.system(size: 32, weight: .bold, design: .monospaced))
                            .foregroundStyle(timerPrimary)
                        Text("일시정지")
                            .font(.system(size: 12))
                            .foregroundStyle(timerPrimary.opacity(0.6))
                    }
                }
            }

            Spacer()
        }
        .padding(16)
        .activityBackgroundTint(timerBg)
        .activitySystemActionForegroundColor(timerPrimary)
    }
}

// MARK: - Dynamic Island Compact Leading

struct ReadingTimerCompactLeadingView: View {
    var body: some View {
        Image(systemName: "book.closed.fill")
            .foregroundStyle(timerBg)
            .font(.system(size: 14, weight: .medium))
    }
}

// MARK: - Dynamic Island Compact Trailing

struct ReadingTimerCompactTrailingView: View {
    let context: ActivityViewContext<ReadingTimerAttributes>

    var body: some View {
        Group {
            if context.state.isRunning, let end = context.state.timerEndDate {
                Text(timerInterval: Date.now...max(end, Date.now), countsDown: true)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .frame(minWidth: 44)
            } else {
                Text(formatSeconds(context.state.remainingSeconds))
                    .monospacedDigit()
            }
        }
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(timerBg)
    }
}

// MARK: - Dynamic Island Minimal

struct ReadingTimerMinimalView: View {
    let context: ActivityViewContext<ReadingTimerAttributes>

    var body: some View {
        ZStack {
            Circle()
                .stroke(timerBg.opacity(0.25), lineWidth: 2.5)
                .frame(width: 22, height: 22)
            Circle()
                .trim(from: 0, to: progressFraction(remaining: context.state.remainingSeconds,
                                                    total: context.attributes.totalSeconds))
                .stroke(timerBg,
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 22, height: 22)
                .animation(.linear(duration: 1), value: context.state.remainingSeconds)
            Text("\(context.state.remainingSeconds / 60)")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(timerBg)
        }
    }
}

// MARK: - Dynamic Island Expanded Subviews

private struct ExpandedLeadingView: View {
    let bookTitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "book.closed.fill")
                .foregroundStyle(timerBg)
                .font(.system(size: 16))
            Text(bookTitle)
                .font(.custom("GowunBatang-Bold", size: 12))
                .foregroundStyle(timerBg)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 4)
    }
}

private struct ExpandedTrailingView: View {
    let state: ReadingTimerAttributes.ContentState

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if state.isRunning, let end = state.timerEndDate {
                Text(timerInterval: Date.now...max(end, Date.now), countsDown: true)
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundStyle(timerBg)
                    .monospacedDigit()
            } else {
                Text(formatSeconds(state.remainingSeconds))
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundStyle(timerBg)
            }
            Text(state.isRunning ? "독서 중" : "일시정지")
                .font(.system(size: 10))
                .foregroundStyle(timerBg.opacity(0.6))
        }
        .padding(.trailing, 4)
    }
}

private struct ExpandedBottomView: View {
    let remaining: Int
    let total: Int

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(timerBg.opacity(0.25))
                    .frame(height: 6)
                RoundedRectangle(cornerRadius: 4)
                    .fill(timerBg)
                    .frame(
                        width: geo.size.width * progressFraction(remaining: remaining, total: total),
                        height: 6
                    )
                    .animation(.linear(duration: 1), value: remaining)
            }
        }
        .frame(height: 6)
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
    }
}

// MARK: - Activity Widget Configuration

struct ReadingTimerActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ReadingTimerAttributes.self) { context in
            ReadingTimerLockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ExpandedLeadingView(bookTitle: context.attributes.bookTitle)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ExpandedTrailingView(state: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedBottomView(
                        remaining: context.state.remainingSeconds,
                        total:     context.attributes.totalSeconds
                    )
                }
            } compactLeading: {
                ReadingTimerCompactLeadingView()
            } compactTrailing: {
                ReadingTimerCompactTrailingView(context: context)
            } minimal: {
                ReadingTimerMinimalView(context: context)
            }
        }
    }
}
