//
//  ReadingSession.swift
//  Under_line
//
//  독서 세션 도메인 모델
//

import Foundation

struct ReadingSession {
    let id: UUID
    let bookISBN: String
    let date: Date
    let durationSeconds: Int
}
