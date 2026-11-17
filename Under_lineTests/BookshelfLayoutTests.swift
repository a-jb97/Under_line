import XCTest
import UIKit
@testable import Under_line

@MainActor
final class BookshelfLayoutTests: XCTestCase {
    func test_phoneAndWideContainer_adjustColumnsUsingSpace() {
        let phone = layout(width: 354, height: 620)
        let wide = layout(width: 1000, height: 620)
        XCTAssertEqual(phone.capacity, 9)
        XCTAssertEqual(phone.boards.count, 3)
        XCTAssertEqual(wide.capacity, 24)
        XCTAssertEqual(wide.boards.count, 3)
        XCTAssertTrue(phone.slots.allSatisfy { $0.width == 82 })
        XCTAssertTrue(wide.slots.allSatisfy { $0.width == 82 })
    }

    func test_lowHeight_reducesRowsWithoutClipping() {
        let value = layout(width: 354, height: 300)
        XCTAssertEqual(value.capacity, 3)
        XCTAssertEqual(value.boards.count, 1)
        assertGeometry(value, in: ContainerLayout(bounds: value.bounds))
    }

    func test_verticalFold_balancesColumnsAndKeepsBothSidesClear() {
        let fold = CGRect(x: 490, y: 0, width: 20, height: 620)
        let container = ContainerLayout(bounds: CGRect(x: 0, y: 0, width: 1000, height: 620), reservedRegions: [
            .init(kind: .division, frame: fold)
        ])
        let value = BookshelfLayout(container: container)
        XCTAssertEqual(value.slots.filter { $0.maxX <= fold.minX }.count,
                       value.slots.filter { $0.minX >= fold.maxX }.count)
        XCTAssertEqual(value.capacity, 24)
        assertGeometry(value, in: container)
    }

    func test_horizontalFold_putsRowsAboveAndBelowIt() {
        let fold = CGRect(x: 0, y: 330, width: 800, height: 40)
        let container = ContainerLayout(bounds: CGRect(x: 0, y: 0, width: 800, height: 700), reservedRegions: [
            .init(kind: .division, frame: fold)
        ])
        let value = BookshelfLayout(container: container)
        XCTAssertTrue(value.slots.contains { $0.maxY <= fold.minY })
        XCTAssertTrue(value.slots.contains { $0.minY >= fold.maxY })
        assertGeometry(value, in: container)
    }

    func test_asymmetricSafeAreaAndCamera_excludeUnavailableSpace() {
        let container = ContainerLayout(
            bounds: CGRect(x: 0, y: 0, width: 900, height: 700),
            safeAreaInsets: UIEdgeInsets(top: 10, left: 20, bottom: 15, right: 80),
            reservedRegions: [.init(kind: .occlusion, frame: CGRect(x: 750, y: 0, width: 100, height: 90))]
        )
        assertGeometry(BookshelfLayout(container: container), in: container)
    }

    func test_geometryAcrossBoundarySizes_neverOverlapsOrLeavesBounds() {
        for width in [60, 98, 180, 300, 354, 375, 600, 601, 900, 1200] {
            for height in [106, 180, 300, 478, 620, 900] {
                let container = ContainerLayout(bounds: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
                assertGeometry(BookshelfLayout(container: container), in: container)
            }
        }
    }

    func test_emptyAndFullyReservedSpace_hasZeroCapacityAndOnePage() {
        let empty = layout(width: 0, height: 0)
        XCTAssertEqual(empty.capacity, 0)
        XCTAssertEqual(empty.pageCount(for: 10), 1)
        XCTAssertNil(empty.frame(forBookAt: 0))
        let bounds = CGRect(x: 0, y: 0, width: 500, height: 400)
        let reserved = BookshelfLayout(container: ContainerLayout(bounds: bounds, reservedRegions: [
            .init(kind: .occlusion, frame: bounds)
        ]))
        XCTAssertEqual(reserved.capacity, 0)
    }

    func test_pageBoundaryAndDragFrames_useTheSameSlots() throws {
        let value = layout(width: 354, height: 620)
        XCTAssertEqual(value.pageCount(for: 0), 1)
        XCTAssertEqual(value.pageCount(for: value.capacity), 1)
        XCTAssertEqual(value.pageCount(for: value.capacity + 1), 2)
        XCTAssertEqual(try XCTUnwrap(value.frame(forBookAt: value.capacity)),
                       value.slots[0].offsetBy(dx: 354, dy: 0))
        XCTAssertNil(value.frame(forBookAt: -1))
    }

    func test_resizing_keepsTheAnchorBookVisible() {
        let ids = (0..<50).map(String.init)
        let anchor = BookshelfPageAnchor(bookIDs: ids, page: 3, capacity: 9)
        XCTAssertEqual(anchor.bookID, "27")
        XCTAssertEqual(anchor.page(in: ids, capacity: 24), 1)
        XCTAssertEqual(anchor.page(in: ids, capacity: 3), 9)
    }

    func test_filteredOrRemovedAnchor_usesSurvivingIDOrClampedPosition() {
        let ids = (0..<30).map(String.init)
        let anchor = BookshelfPageAnchor(bookIDs: ids, page: 2, capacity: 9)
        XCTAssertEqual(anchor.page(in: ["12", "18", "22"], capacity: 1), 1)
        XCTAssertEqual(anchor.page(in: ["12", "22"], capacity: 1), 1)
        XCTAssertEqual(anchor.page(in: [], capacity: 9), 0)
        XCTAssertEqual(anchor.page(in: ids, capacity: 0), 0)
    }

    func test_foldDeactivating_reflowsWithoutLosingAnyBook() throws {
        let ids = (0..<70).map(String.init)
        let folded = BookshelfLayout(container: ContainerLayout(
            bounds: CGRect(x: 0, y: 0, width: 800, height: 700),
            reservedRegions: [.init(kind: .division, frame: CGRect(x: 0, y: 330, width: 800, height: 40))]
        ))
        let open = layout(width: 800, height: 700)
        let anchor = BookshelfPageAnchor(bookIDs: ids, page: 2, capacity: folded.capacity)
        let page = anchor.page(in: ids, capacity: open.capacity)
        let visibleRange = page * open.capacity..<min(ids.count, (page + 1) * open.capacity)
        XCTAssertTrue(visibleRange.contains(try XCTUnwrap(anchor.bookID.flatMap { ids.firstIndex(of: $0) })))
        let allIndices = (0..<open.pageCount(for: ids.count)).flatMap { page in
            Array(page * open.capacity..<min(ids.count, (page + 1) * open.capacity))
        }
        XCTAssertEqual(allIndices, Array(ids.indices))
    }

    func test_shelfPages_renderEachBookOnceAndHideOnlyTheDraggedBook() throws {
        let layout = self.layout(width: 354, height: 620)
        let books = (0..<(layout.capacity + 2)).map(book)
        for pageIndex in 0..<layout.pageCount(for: books.count) {
            let page = ShelfPageView(books: books, layout: layout, page: pageIndex,
                                     hiddenBookIndex: 2, isEditing: false, onDelete: { _ in }, onTap: { _ in })
            page.frame = layout.bounds
            page.layoutIfNeeded()
            for index in books.indices {
                let expected = index / layout.capacity == pageIndex && index != 2
                XCTAssertEqual(page.bookView(at: index) != nil, expected)
                if expected {
                    let view = try XCTUnwrap(page.bookView(at: index))
                    XCTAssertEqual(view.frame, layout.slots[index % layout.capacity])
                    let cover = try XCTUnwrap(view.subviews.first)
                    XCTAssertEqual(cover.frame.maxY, view.bounds.height, accuracy: 0.001)
                    XCTAssertLessThanOrEqual(cover.bounds.height, view.bounds.height)
                }
            }
        }
    }

    func test_bookTapAndDeleteButtons_forwardTheConfiguredBook() throws {
        let value = layout(width: 354, height: 620)
        var opened: [String] = []
        var deleted: [String] = []
        for editing in [false, true] {
            let page = ShelfPageView(books: [book(0)], layout: value, page: 0, hiddenBookIndex: nil,
                                     isEditing: editing, onDelete: { deleted.append($0.isbn13) },
                                     onTap: { opened.append($0.isbn13) })
            let open = try XCTUnwrap(TutorialSupport.target(in: page, identifier: "shelfBook.0") as? UIButton)
            let delete = try XCTUnwrap(TutorialSupport.target(in: page, identifier: "deleteShelfBook.0") as? UIButton)
            XCTAssertEqual(open.isHidden, editing)
            XCTAssertEqual(delete.isHidden, !editing)
            (editing ? delete : open).sendActions(for: .touchUpInside)
        }
        XCTAssertEqual(opened, ["0"])
        XCTAssertEqual(deleted, ["0"])
    }

    private func book(_ index: Int) -> Book {
        Book(title: "도서 \(index)", author: "저자", isbn13: String(index), coverURL: nil,
             publisher: "출판사", publishDate: nil, category: nil, bestRank: nil,
             description: "", itemPage: nil, currentPage: nil)
    }

    func test_dragCancelledAfterMove_restoresConfirmedOrderWithoutSaving() throws {
        let confirmed = ["a", "b", "c", "d"]
        var draft = try XCTUnwrap(BookshelfReorderDraft(bookIDs: confirmed, index: 0))
        draft.move(to: 3)
        XCTAssertEqual(draft.bookIDs, ["b", "c", "d", "a"])
        let cancelled = draft.finish(commit: false, confirmedBookIDs: confirmed)
        XCTAssertEqual(cancelled.bookIDs, confirmed)
        XCTAssertFalse(cancelled.shouldSave)
        let committed = draft.finish(commit: true, confirmedBookIDs: confirmed)
        XCTAssertEqual(committed.bookIDs, ["b", "c", "d", "a"])
        XCTAssertTrue(committed.shouldSave)
    }

    func test_libraryChangedDuringDrag_rejectsTheStaleDraft() throws {
        var draft = try XCTUnwrap(BookshelfReorderDraft(bookIDs: ["a", "b", "c"], index: 1))
        draft.move(to: 0)
        for confirmed in [["a", "c"], ["a", "b", "c", "d"]] {
            let result = draft.finish(commit: true, confirmedBookIDs: confirmed)
            XCTAssertEqual(result.bookIDs, confirmed)
            XCTAssertFalse(result.shouldSave)
        }
        draft.move(to: 99)
        XCTAssertEqual(draft.currentIndex, 0)
        XCTAssertNil(BookshelfReorderDraft(bookIDs: [], index: 0))
    }

    private func layout(width: Int, height: Int) -> BookshelfLayout {
        BookshelfLayout(container: ContainerLayout(bounds: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))))
    }

    private func assertGeometry(_ layout: BookshelfLayout, in container: ContainerLayout,
                                file: StaticString = #filePath, line: UInt = #line) {
        for (index, slot) in layout.slots.enumerated() {
            XCTAssertTrue(container.safeBounds.contains(slot), file: file, line: line)
            XCTAssertGreaterThanOrEqual(slot.width, 44, file: file, line: line)
            XCTAssertGreaterThanOrEqual(slot.height, 44, file: file, line: line)
            XCTAssertTrue(layout.boards.contains {
                abs($0.minY - slot.maxY) < 0.001 && $0.minX <= slot.minX && $0.maxX >= slot.maxX
            }, file: file, line: line)
            for other in layout.slots.dropFirst(index + 1) {
                XCTAssertTrue(slot.intersection(other).isEmpty, file: file, line: line)
            }
        }
        for rect in layout.slots + layout.boards + (layout.paginationFrame.isEmpty ? [] : [layout.paginationFrame]) {
            XCTAssertTrue(container.safeBounds.contains(rect), file: file, line: line)
            for region in container.reservedRegions {
                XCTAssertTrue(rect.intersection(region.frame).isEmpty, file: file, line: line)
            }
        }
    }
}
