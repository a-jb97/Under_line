//
//  WidgetCacheWriter.swift
//  Under_line
//
//  App Group 컨테이너 파일에 문장 캐시를 기록하고 위젯 타임라인을 갱신
//  Target membership: Under_line only
//

import Foundation
import WidgetKit

final class WidgetCacheWriter {

    static let shared = WidgetCacheWriter()

    private var cacheFileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WidgetSharedConstants.appGroupID)?
            .appendingPathComponent("widgetCache.json")
    }

    private init() {}

    func write(sentence: Sentence, bookTitle: String, bookAuthor: String) {
        let entry = WidgetSentenceEntry(
            sentenceText:     sentence.sentence,
            page:             sentence.page,
            emotionLabel:     sentence.emotion.label,
            emotionImageName: sentence.emotion.assetName,
            bookTitle:        bookTitle,
            bookAuthor:       bookAuthor
        )
        guard
            let data = try? JSONEncoder().encode(entry),
            let url  = cacheFileURL
        else { return }

        try? data.write(to: url, options: .atomic)
        WidgetCenter.shared.reloadTimelines(ofKind: "UnderLineWidget")
    }

    func clear() {
        if let url = cacheFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "UnderLineWidget")
    }
}
