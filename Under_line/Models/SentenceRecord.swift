//
//  SentenceRecord.swift
//  Under_line
//
//  SwiftData 영속 모델 — Sentence 도메인 모델의 로컬 저장소
//

import SwiftData
import Foundation

@Model
final class SentenceRecord {
    var id: UUID
    var bookISBN: String
    var sentence: String
    var page: Int
    var emotionRawValue: Int
    var memo: String?
    var date: Date

    init(from sentence: Sentence) {
        self.id               = sentence.id
        self.bookISBN         = sentence.bookISBN
        self.sentence         = sentence.sentence
        self.page             = sentence.page
        self.emotionRawValue  = sentence.emotion.rawValue
        self.memo             = sentence.memo
        self.date             = sentence.date
    }

    func toDomain() -> Sentence {
        Sentence(
            id:       id,
            bookISBN: bookISBN,
            sentence: sentence,
            page:     page,
            emotion:  Emotion(rawValue: emotionRawValue) ?? .calm,
            memo:     memo,
            date:     date
        )
    }
}
