import Foundation

/// 손을 놓아 확정하기 전까지 저장하지 않는 책장 순서 초안.
struct BookshelfReorderDraft {
    private(set) var bookIDs: [String]
    private(set) var currentIndex: Int

    init?(bookIDs: [String], index: Int) {
        guard bookIDs.indices.contains(index) else { return nil }
        self.bookIDs = bookIDs
        currentIndex = index
    }

    mutating func move(to index: Int) {
        guard bookIDs.indices.contains(index), index != currentIndex else { return }
        let bookID = bookIDs.remove(at: currentIndex)
        bookIDs.insert(bookID, at: index)
        currentIndex = index
    }

    func finish(commit: Bool, confirmedBookIDs: [String]) -> (bookIDs: [String], shouldSave: Bool) {
        let shouldSave = commit && Set(bookIDs) == Set(confirmedBookIDs)
        return (shouldSave ? bookIDs : confirmedBookIDs, shouldSave)
    }
}
