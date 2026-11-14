import UIKit

final class BookSearchTableDataSource: NSObject, UITableViewDataSource {
    private(set) var books: [Book] = []
    private let updateCell: (UITableViewCell, IndexPath, Book) -> Void
    private let makeCell: (UITableView, IndexPath, Book) -> UITableViewCell

    init(updateCell: @escaping (UITableViewCell, IndexPath, Book) -> Void = { _, _, _ in },
         makeCell: @escaping (UITableView, IndexPath, Book) -> UITableViewCell) {
        self.updateCell = updateCell
        self.makeCell = makeCell
    }

    func apply(_ update: BookSearchViewModel.ListUpdate, to tableView: UITableView) {
        let previousCount = books.count
        books = update.books
        switch update.change {
        case .append(let start) where start == previousCount && start < books.count:
            let indexPaths = (start..<books.count).map { IndexPath(row: $0, section: 0) }
            let offset = tableView.contentOffset
            UIView.performWithoutAnimation {
                tableView.beginUpdates()
                tableView.insertRows(at: indexPaths, with: .none)
                tableView.endUpdates()
                tableView.setContentOffset(offset, animated: false)
            }
        case .update(let rows):
            for row in Set(rows) where books.indices.contains(row) {
                let indexPath = IndexPath(row: row, section: 0)
                guard let cell = tableView.cellForRow(at: indexPath) else { continue }
                updateCell(cell, indexPath, books[row])
            }
        default:
            // 초기/검색 교체 또는 재구독으로 append 이전 snapshot이 없는 경우.
            tableView.reloadData()
            tableView.setContentOffset(.zero, animated: false)
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        books.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        makeCell(tableView, indexPath, books[indexPath.row])
    }
}
