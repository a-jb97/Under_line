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
    let bookRepository: BookRepository
    let sentenceRepository: SentenceRepository

    private init() {
        modelContainer = try! ModelContainer(for: BookRecord.self, SentenceRecord.self)
        bookRepository = BookRepository(
            apiService:   AladinAPIService(apiKey: AladinAPIKey.ttbKey),
            modelContext: modelContainer.mainContext
        )
        sentenceRepository = SentenceRepository(modelContext: modelContainer.mainContext)
    }
}
