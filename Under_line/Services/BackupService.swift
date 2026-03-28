//
//  BackupService.swift
//  Under_line
//
//  전체 SwiftData 데이터를 JSON으로 내보내고 복원하는 서비스
//

import Foundation
import SwiftData
import RxSwift

// MARK: - Codable DTOs

struct BackupPayload: Codable {
    let version: Int
    let exportedAt: Date
    let books: [BookBackup]
    let sentences: [SentenceBackup]
    let sessions: [SessionBackup]
}

struct BookBackup: Codable {
    let title: String
    let author: String
    let isbn13: String
    let coverURLString: String?
    let publisher: String
    let publishDate: String?
    let category: String?
    let bookDescription: String
    let itemPage: Int?
    let currentPage: Int?
    let savedAt: Date
}

struct SentenceBackup: Codable {
    let id: UUID
    let bookISBN: String
    let sentence: String
    let page: Int
    let emotionRawValue: Int
    let memo: String?
    let date: Date
}

struct SessionBackup: Codable {
    let id: UUID
    let bookISBN: String
    let date: Date
    let durationSeconds: Int
}

// MARK: - BackupService

final class BackupService {

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: Export

    func exportToJSON() -> Single<URL> {
        Single.create { [weak self] single in
            guard let self else { single(.failure(BackupError.unknown)); return Disposables.create() }
            do {
                let books = try self.modelContext.fetch(FetchDescriptor<BookRecord>()).map {
                    BookBackup(
                        title:           $0.title,
                        author:          $0.author,
                        isbn13:          $0.isbn13,
                        coverURLString:  $0.coverURLString,
                        publisher:       $0.publisher,
                        publishDate:     $0.publishDate,
                        category:        $0.category,
                        bookDescription: $0.bookDescription,
                        itemPage:        $0.itemPage,
                        currentPage:     $0.currentPage,
                        savedAt:         $0.savedAt
                    )
                }
                let sentences = try self.modelContext.fetch(FetchDescriptor<SentenceRecord>()).map {
                    SentenceBackup(
                        id:               $0.id,
                        bookISBN:         $0.bookISBN,
                        sentence:         $0.sentence,
                        page:             $0.page,
                        emotionRawValue:  $0.emotionRawValue,
                        memo:             $0.memo,
                        date:             $0.date
                    )
                }
                let sessions = try self.modelContext.fetch(FetchDescriptor<ReadingSessionRecord>()).map {
                    SessionBackup(
                        id:              $0.id,
                        bookISBN:        $0.bookISBN,
                        date:            $0.date,
                        durationSeconds: $0.durationSeconds
                    )
                }

                let payload = BackupPayload(
                    version:    1,
                    exportedAt: Date(),
                    books:      books,
                    sentences:  sentences,
                    sessions:   sessions
                )

                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(payload)

                let formatter = DateFormatter()
                formatter.dateFormat = "yyyyMMdd_HHmmss"
                let fileName = "underline_backup_\(formatter.string(from: Date())).json"
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
                try data.write(to: tempURL)

                single(.success(tempURL))
            } catch {
                single(.failure(error))
            }
            return Disposables.create()
        }
    }

    // MARK: Restore

    func restore(from url: URL) -> Completable {
        Completable.create { [weak self] completable in
            guard let self else { completable(.completed); return Disposables.create() }

            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }

            do {
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let payload = try decoder.decode(BackupPayload.self, from: data)

                try self.modelContext.delete(model: BookRecord.self)
                try self.modelContext.delete(model: SentenceRecord.self)
                try self.modelContext.delete(model: ReadingSessionRecord.self)

                for b in payload.books {
                    let book = Book(
                        title:       b.title,
                        author:      b.author,
                        isbn13:      b.isbn13,
                        coverURL:    b.coverURLString.flatMap { URL(string: $0) },
                        publisher:   b.publisher,
                        publishDate: b.publishDate,
                        category:    b.category,
                        bestRank:    nil,
                        description: b.bookDescription,
                        itemPage:    b.itemPage,
                        currentPage: b.currentPage
                    )
                    let record = BookRecord(from: book)
                    record.savedAt = b.savedAt
                    self.modelContext.insert(record)
                }

                for s in payload.sentences {
                    let sentence = Sentence(
                        id:       s.id,
                        bookISBN: s.bookISBN,
                        sentence: s.sentence,
                        page:     s.page,
                        emotion:  Emotion(rawValue: s.emotionRawValue) ?? .calm,
                        memo:     s.memo,
                        date:     s.date
                    )
                    self.modelContext.insert(SentenceRecord(from: sentence))
                }

                for s in payload.sessions {
                    let record = ReadingSessionRecord(bookISBN: s.bookISBN, durationSeconds: s.durationSeconds)
                    record.id   = s.id
                    record.date = s.date
                    self.modelContext.insert(record)
                }

                try self.modelContext.save()
                completable(.completed)
            } catch {
                completable(.error(error))
            }
            return Disposables.create()
        }
    }
}

// MARK: - Error

enum BackupError: LocalizedError {
    case unknown
    var errorDescription: String? { "알 수 없는 오류가 발생했습니다." }
}
