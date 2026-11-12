import Foundation

struct BookRowContent {
    let isbn13: String
    let title: String
    let authorText: String
    let publisher: String
    let coverURL: URL?
    let description: String
    let rank: Int?

    init(book: Book) {
        isbn13 = book.isbn13.trimmingCharacters(in: .whitespacesAndNewlines)
        title = book.displayTitle
        authorText = book.searchAuthorText
        publisher = book.publisher
        coverURL = book.coverURL
        description = book.description
        rank = book.bestRank
    }

    init(item: WishlistItem) {
        isbn13 = item.isbn13
        title = item.title
        let author = item.author.trimmingCharacters(in: .whitespacesAndNewlines)
        authorText = "지은이 : \(author.isEmpty ? "알 수 없음" : author)"
        publisher = item.publisher
        coverURL = item.coverURL
        description = item.description
        rank = nil
    }
}

struct BookRowAction {
    let symbolName: String
    let isSelected: Bool
    let isEnabled: Bool
    let accessibilityLabel: String
    let accessibilityValue: String

    static func registration(isRegistered: Bool) -> BookRowAction {
        BookRowAction(
            symbolName: isRegistered ? "books.vertical.fill" : "books.vertical",
            isSelected: isRegistered, isEnabled: !isRegistered,
            accessibilityLabel: isRegistered ? "이미 등록된 도서" : "독서 기록을 위한 도서 등록",
            accessibilityValue: isRegistered ? "등록됨" : "등록 안 됨"
        )
    }

    static func wishlist(isSaved: Bool, isEnabled: Bool, isPending: Bool = false) -> BookRowAction {
        BookRowAction(
            symbolName: isSaved ? "heart.fill" : "heart",
            isSelected: isSaved, isEnabled: isEnabled && !isPending,
            accessibilityLabel: isSaved ? "위시리스트에서 삭제" : "위시리스트에 추가",
            accessibilityValue: isPending ? "처리 중" : isSaved ? "추가됨" : "추가 안 됨"
        )
    }

    static let purchase = BookRowAction(
        symbolName: "cart", isSelected: false, isEnabled: true,
        accessibilityLabel: "도서 구매", accessibilityValue: ""
    )
}
