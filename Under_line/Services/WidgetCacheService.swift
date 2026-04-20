//
//  WidgetCacheService.swift
//  Under_line
//
//  전체 문장 중 랜덤으로 하나를 선택해 위젯 캐시를 갱신
//  Target membership: Under_line only
//

import Foundation
import RxSwift

final class WidgetCacheService {

    static let shared = WidgetCacheService()

    private init() {}

    func refreshCache() {
        Task {
            guard let sentence = try? await AppContainer.shared.sentenceRepository
                .fetchAllSentences().randomElement() else {
                WidgetCacheWriter.shared.clear()
                return
            }
            AppContainer.shared.bookRepository
                .fetchSavedBooks()
                .take(1)
                .subscribe(onNext: { books in
                    let book = books.first { $0.isbn13 == sentence.bookISBN }
                    WidgetCacheWriter.shared.write(
                        sentence:   sentence,
                        bookTitle:  book?.title ?? "알 수 없음",
                        bookAuthor: book?.author ?? ""
                    )
                })
                .dispose()
        }
    }
}
