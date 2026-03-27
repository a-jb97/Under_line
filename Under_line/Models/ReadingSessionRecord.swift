//
//  ReadingSessionRecord.swift
//  Under_line
//
//  SwiftData 영속 모델 — ReadingSession 도메인 모델의 로컬 저장소
//

import SwiftData
import Foundation

@Model
final class ReadingSessionRecord {
    var id: UUID
    var bookISBN: String
    var date: Date
    var durationSeconds: Int

    init(bookISBN: String, durationSeconds: Int) {
        self.id = UUID()
        self.bookISBN = bookISBN
        self.date = Date()
        self.durationSeconds = durationSeconds
    }

    func toDomain() -> ReadingSession {
        ReadingSession(id: id, bookISBN: bookISBN, date: date, durationSeconds: durationSeconds)
    }
}
