//
//  Sentence.swift
//  Under_line
//
//  문장 수집 도메인 모델
//

import Foundation

struct Sentence {
    let id: UUID
    let bookISBN: String
    let sentence: String
    let page: Int
    let emotion: Emotion
    let memo: String?
    let date: Date
    let markedPhotoData: Data?

    init(id: UUID, bookISBN: String, sentence: String, page: Int, emotion: Emotion, memo: String?,
         date: Date, markedPhotoData: Data? = nil) {
        self.id = id
        self.bookISBN = bookISBN
        self.sentence = sentence
        self.page = page
        self.emotion = emotion
        self.memo = memo
        self.date = date
        self.markedPhotoData = markedPhotoData
    }
}
