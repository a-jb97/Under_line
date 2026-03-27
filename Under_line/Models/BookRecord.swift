//
//  BookRecord.swift
//  Under_line
//
//  SwiftData 영속 모델 — Book 도메인 모델의 로컬 저장소
//

import SwiftData
import Foundation

@Model
final class BookRecord {
    var title: String
    var author: String
    var isbn13: String
    var coverURLString: String?
    var publisher: String
    var publishDate: String?
    var category: String?
    var bookDescription: String
    var itemPage: Int?
    var currentPage: Int?
    var savedAt: Date

    init(from book: Book) {
        self.title           = book.title
        self.author          = book.author
        self.isbn13          = book.isbn13
        self.coverURLString  = book.coverURL?.absoluteString
        self.publisher       = book.publisher
        self.publishDate     = book.publishDate
        self.category        = book.category
        self.bookDescription = book.description
        self.itemPage        = book.itemPage
        self.currentPage     = book.currentPage
        self.savedAt         = Date()
    }

    func toDomain() -> Book {
        Book(
            title:       title,
            author:      author,
            isbn13:      isbn13,
            coverURL:    coverURLString.flatMap { URL(string: $0) },
            publisher:   publisher,
            publishDate: publishDate,
            category:    category,
            bestRank:    nil,
            description: bookDescription,
            itemPage:    itemPage,
            currentPage: currentPage
        )
    }
}
