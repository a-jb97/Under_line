//
//  UnderLineWidget.swift
//  UnderLineWidget
//

import WidgetKit
import SwiftUI
import Foundation
import AppIntents

// MARK: - Shared DTO

struct WidgetSentenceEntry: Codable {
    let sentenceText: String
    let page: Int
    let emotionLabel: String
    let emotionImageName: String
    let bookTitle: String
    let bookAuthor: String
}

// MARK: - Cache Reader

private struct WidgetCacheReader {
    private let appGroupID = "group.com.jade.UnderLine"

    private var cacheFileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("widgetCache.json")
    }

    func loadEntry() -> WidgetSentenceEntry? {
        guard
            let url  = cacheFileURL,
            let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(WidgetSentenceEntry.self, from: data)
    }
}

// MARK: - Timeline Entry

struct UnderLineWidgetTimelineEntry: TimelineEntry {
    let date: Date
    let data: WidgetSentenceEntry?
}

// MARK: - App Intent (정적 위젯용 — 파라미터 없음)

struct UnderLineWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "나의 밑줄"
    static var description = IntentDescription("저장한 문장을 홈 화면에서 확인하세요.")
}

// MARK: - Timeline Provider (async/await)

struct UnderLineTimelineProvider: AppIntentTimelineProvider {
    typealias Entry  = UnderLineWidgetTimelineEntry
    typealias Intent = UnderLineWidgetIntent

    func placeholder(in context: Context) -> UnderLineWidgetTimelineEntry {
        UnderLineWidgetTimelineEntry(date: Date(), data: nil)
    }

    func snapshot(for configuration: UnderLineWidgetIntent, in context: Context) async -> UnderLineWidgetTimelineEntry {
        UnderLineWidgetTimelineEntry(date: Date(), data: WidgetCacheReader().loadEntry())
    }

    func timeline(for configuration: UnderLineWidgetIntent, in context: Context) async -> Timeline<UnderLineWidgetTimelineEntry> {
        let reader  = WidgetCacheReader()
        let cached  = reader.loadEntry()
        let data    = cached ?? WidgetSentenceEntry(
            sentenceText: "앱을 열었다 닫으면 저장한 문장이 표시됩니다.",
            page: 0,
            emotionLabel: "평온",
            emotionImageName: "Calm",
            bookTitle: "밑줄",
            bookAuthor: ""
        )
        let entry = UnderLineWidgetTimelineEntry(date: Date(), data: data)
        return Timeline(entries: [entry], policy: .after(Date(timeIntervalSinceNow: 900)))
    }
}

// MARK: - Widget View

struct UnderLineWidgetView: View {
    let entry: UnderLineWidgetTimelineEntry
    @Environment(\.widgetFamily) private var family

    private let textColor = Color(red: 0.365, green: 0.251, blue: 0.216)
    private let bgColor   = Color(red: 0.965, green: 0.937, blue: 0.933)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let data = entry.data {
                Text(data.sentenceText)
                    .font(.custom("GowunBatang-Regular", size: family == .systemMedium ? 13 : 15))
                    .foregroundStyle(textColor)
                    .lineSpacing(5)
                    .lineLimit(family == .systemMedium ? 4 : 12)
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                Spacer(minLength: 4)

                HStack(alignment: .center, spacing: 5) {
                    Image(data.emotionImageName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                    Text(data.emotionLabel)
                        .font(.custom("GowunBatang-Regular", size: 11))
                        .foregroundStyle(textColor.opacity(0.6))
                    Spacer()
                    Text(data.bookTitle)
                        .font(.custom("GowunBatang-Regular", size: 11))
                        .foregroundStyle(textColor.opacity(0.5))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            } else {
                Spacer()
                VStack(spacing: 6) {
                    Text("📖")
                        .font(.system(size: 28))
                    Text("밑줄을 수집하면\n여기에 표시됩니다")
                        .font(.custom("GowunBatang-Regular", size: 12))
                        .foregroundStyle(textColor.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .unredacted()
        .containerBackground(bgColor, for: .widget)
    }
}

// MARK: - Widget Configuration

struct UnderLineWidget: Widget {
    let kind = "UnderLineWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: UnderLineWidgetIntent.self, provider: UnderLineTimelineProvider()) { entry in
            UnderLineWidgetView(entry: entry)
        }
        .configurationDisplayName("나의 밑줄")
        .description("저장한 문장을 홈 화면에서 확인하세요.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// MARK: - Widget Bundle

@main
struct UnderLineWidgetBundle: WidgetBundle {
    var body: some Widget {
        UnderLineWidget()
        ReadingTimerActivityWidget()
    }
}
