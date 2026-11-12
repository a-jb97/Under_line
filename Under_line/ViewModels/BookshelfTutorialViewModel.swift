import Foundation

@MainActor
final class BookshelfTutorialViewModel {
    private let repository: BookRepositoryProtocol
    private(set) var books: [Book] = []

    init(repository: BookRepositoryProtocol) { self.repository = repository }

    func prepare() async {
        guard let popular = try? await repository.fetchPopularBooks(), !Task.isCancelled else { return }
        books = Array(popular.prefix(9))
        for start in stride(from: 0, to: books.count, by: 3) {
            guard !Task.isCancelled else { return }
            let batch = Array(books[start..<min(start + 3, books.count)])
            let tasks = batch.map { book in
                Task { try? await self.repository.fetchListBookMetadata(isbn13: book.isbn13) }
            }
            for (offset, task) in tasks.enumerated() {
                let metadata = await task.value
                guard !Task.isCancelled else {
                    tasks.forEach { $0.cancel() }
                    return
                }
                if let metadata { books[start + offset] = books[start + offset].mergingListMetadata(from: metadata) }
            }
        }
    }
}
