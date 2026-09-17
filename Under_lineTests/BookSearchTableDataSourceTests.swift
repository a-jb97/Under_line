import XCTest
import UIKit
@testable import Under_line

@MainActor
final class BookSearchTableDataSourceTests: XCTestCase {
    func test_append_insertsOnlyNewRowsAndPreservesOffset() {
        let table = RecordingTableView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        table.rowHeight = 80
        let dataSource = BookSearchTableDataSource { _, _, _ in UITableViewCell() }
        table.dataSource = dataSource
        dataSource.apply(.init(books: books(50), change: .replace), to: table)
        table.layoutIfNeeded()
        table.setContentOffset(CGPoint(x: 0, y: 400), animated: false)
        let reloads = table.reloadCount
        dataSource.apply(.init(books: books(100), change: .append(from: 50)), to: table)
        XCTAssertEqual(table.reloadCount, reloads)
        XCTAssertEqual(table.insertedRows.map(\.row), Array(50..<100))
        XCTAssertEqual(table.contentOffset.y, 400)
        XCTAssertEqual(table.numberOfRows(inSection: 0), 100)
    }

    func test_appendWithoutPreviousSnapshot_fallsBackToReplacement() {
        let table = RecordingTableView()
        let dataSource = BookSearchTableDataSource { _, _, _ in UITableViewCell() }
        table.dataSource = dataSource
        dataSource.apply(.init(books: books(100), change: .append(from: 50)), to: table)
        XCTAssertEqual(table.reloadCount, 1)
        XCTAssertTrue(table.insertedRows.isEmpty)
        XCTAssertEqual(dataSource.books.count, 100)
    }

    func test_lastFiveRows_requestOnceUntilLeavingThreshold() {
        var gate = BookSearchPaginationGate()
        XCTAssertFalse(gate.shouldRequest(lastVisibleRow: 44, rowCount: 50, isLoading: false))
        XCTAssertTrue(gate.shouldRequest(lastVisibleRow: 45, rowCount: 50, isLoading: false))
        XCTAssertFalse(gate.shouldRequest(lastVisibleRow: 49, rowCount: 50, isLoading: true))
        XCTAssertFalse(gate.shouldRequest(lastVisibleRow: nil, rowCount: 50, isLoading: false))
        // 실패로 로딩이 끝나도 같은 영역에서는 자동 반복하지 않는다.
        XCTAssertFalse(gate.shouldRequest(lastVisibleRow: 49, rowCount: 50, isLoading: false))
        XCTAssertFalse(gate.shouldRequest(lastVisibleRow: 44, rowCount: 50, isLoading: false))
        XCTAssertTrue(gate.shouldRequest(lastVisibleRow: 45, rowCount: 50, isLoading: false))
    }

    func test_shortListUpdate_canContinueWithoutAnotherScrollEvent() {
        var gate = BookSearchPaginationGate()
        XCTAssertTrue(gate.shouldRequest(lastVisibleRow: 4, rowCount: 5, isLoading: false))
        gate.listDidUpdate()
        XCTAssertFalse(gate.shouldRequest(lastVisibleRow: 8, rowCount: 10, isLoading: true))
        XCTAssertTrue(gate.shouldRequest(lastVisibleRow: 8, rowCount: 10, isLoading: false))
        XCTAssertFalse(gate.shouldRequest(lastVisibleRow: nil, rowCount: 0, isLoading: false))
    }

    private func books(_ count: Int) -> [Book] {
        (0..<count).map { index in
            Book(title: "책", author: "저자", isbn13: "\(index)", coverURL: nil,
                 publisher: "출판사", publishDate: nil, category: nil, bestRank: nil,
                 description: "", itemPage: nil, currentPage: nil)
        }
    }
}

@MainActor
private final class RecordingTableView: UITableView {
    var reloadCount = 0
    var insertedRows: [IndexPath] = []

    override func reloadData() {
        reloadCount += 1
        super.reloadData()
    }

    override func insertRows(at indexPaths: [IndexPath], with animation: UITableView.RowAnimation) {
        insertedRows.append(contentsOf: indexPaths)
        super.insertRows(at: indexPaths, with: animation)
    }
}
