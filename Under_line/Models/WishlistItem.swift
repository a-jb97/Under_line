import Foundation

struct WishlistItem: Equatable {
    let isbn13: String
    let title: String
    let author: String
    let publisher: String
    let coverURL: URL?
    let description: String
    let addedAt: Date
}
