import Foundation
import SwiftData

@Model
final class WishlistRecord {
    @Attribute(.unique) var isbn13: String
    var title: String
    var author: String
    var publisher: String
    var coverURLString: String?
    var bookDescription: String
    var addedAt: Date

    init(from book: Book, isbn13: String, addedAt: Date) {
        self.isbn13 = isbn13
        self.title = book.title
        self.author = book.author
        self.publisher = book.publisher
        self.coverURLString = book.coverURL?.absoluteString
        self.bookDescription = book.description
        self.addedAt = addedAt
    }

    func toDomain() -> WishlistItem {
        WishlistItem(
            isbn13: isbn13,
            title: title,
            author: author,
            publisher: publisher,
            coverURL: coverURLString.flatMap { URL(string: $0) },
            description: bookDescription,
            addedAt: addedAt
        )
    }
}
