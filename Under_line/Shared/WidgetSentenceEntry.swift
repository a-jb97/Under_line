//
//  WidgetSentenceEntry.swift
//  Under_line
//
//  앱 → 위젯으로 전달하는 문장 데이터 DTO
//  Target membership: Under_line + UnderLineWidget
//

import Foundation

struct WidgetSentenceEntry: Codable {
    let sentenceText: String
    let page: Int
    let emotionLabel: String       // 한글 레이블 (기쁨, 평온, ...)
    let emotionImageName: String   // Assets.xcassets 이름 (Happy, Calm, ...)
    let bookTitle: String
    let bookAuthor: String
}
