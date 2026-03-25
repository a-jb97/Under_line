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
}
