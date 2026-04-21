//
//  AppContainer.swift
//  Under_line
//
//  앱 레벨 의존성 컨테이너 — ModelContainer, Repository 공유 인스턴스 관리
//

import SwiftData

final class AppContainer {
    static let shared = AppContainer()

    let modelContainer: ModelContainer
    let bookRepository: BookRepositoryProtocol
    let sentenceRepository: SentenceRepositoryProtocol
    let readingSessionRepository: ReadingSessionRepositoryProtocol

    func reloadBookRelay() {
        (bookRepository as? BookRepository)?.reloadRelay()
    }

    private init() {
        do {
            modelContainer = try ModelContainer(for: BookRecord.self, SentenceRecord.self, ReadingSessionRecord.self)
        } catch {
            fatalError("SwiftData ModelContainer 초기화 실패 — 스키마 변경 또는 디스크 문제를 확인하세요. 오류: \(error)")
        }
        bookRepository = BookRepository(
            apiService:   AladinAPIService(apiKey: AladinAPIKey.ttbKey),
            modelContext: modelContainer.mainContext
        )
        sentenceRepository = SentenceRepository(modelContext: modelContainer.mainContext)
        readingSessionRepository = ReadingSessionRepository(modelContext: modelContainer.mainContext)
    }
}
