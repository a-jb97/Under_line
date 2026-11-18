import UIKit

/// 선반, 도서 슬롯, 드래그 위치가 함께 사용하는 한 페이지의 배치.
struct BookshelfLayout: Equatable {
    let bounds: CGRect
    let slots: [CGRect]
    let boards: [CGRect]
    let paginationFrame: CGRect

    var capacity: Int { slots.count }

    init(container: ContainerLayout) {
        bounds = container.bounds
        let paginationBand = CGRect(
            x: container.safeBounds.minX,
            y: max(container.safeBounds.minY, container.safeBounds.maxY - 28),
            width: container.safeBounds.width,
            height: min(28, container.safeBounds.height)
        )
        let paginationArea = container.availableRects.map { $0.intersection(paginationBand) }
            .filter { !$0.isNull && $0.width >= 44 && $0.height >= 24 }
            .max { $0.width < $1.width }
        if let area = paginationArea {
            paginationFrame = CGRect(x: area.midX - min(area.width, 240) / 2,
                                     y: area.midY - 12, width: min(area.width, 240), height: 24)
        } else {
            paginationFrame = .zero
        }

        let contentBounds = CGRect(x: container.safeBounds.minX, y: container.safeBounds.minY,
                                   width: container.safeBounds.width,
                                   height: max(0, container.safeBounds.height - 34))
        let intersections: [CGRect] = container.availableRects.map { $0.intersection(contentBounds) }
        var candidates: [CGRect] = intersections.filter { !$0.isNull && $0.width >= 60 && $0.height >= 72 }
        candidates.sort { lhs, rhs in
            if lhs.minY == rhs.minY { return lhs.minX < rhs.minX }
            return lhs.minY < rhs.minY
        }
        // 카메라 옆의 얇은 조각보다 정상 크기의 표지를 놓을 수 있는 공간을 우선한다.
        let fullSizeAreas = candidates.filter { $0.width >= 98 && $0.height >= 138 }
        let areas = fullSizeAreas.isEmpty ? candidates : fullSizeAreas
        let hasVerticalDivision = container.reservedRegions.contains {
            $0.kind == .division && $0.frame.height > $0.frame.width
        }
        let columns = areas.map { area -> Int in
            let count = max(1, min(8, Int((area.width - 16 + 20) / (82 + 20))))
            return count > 3 && count % 2 != 0 ? count - 1 : count
        }
        let balancedColumns = hasVerticalDivision && areas.count == 2 ? columns.min() : nil
        var rows: [(board: CGRect, slots: [CGRect])] = []
        for (index, area) in areas.enumerated() {
            let columnCount = balancedColumns ?? columns[index]
            let bookWidth = min(82, (area.width - 16 - CGFloat(columnCount - 1) * 20) / CGFloat(columnCount))
            let preferredBookHeight = ceil(bookWidth * 117 / 88)
            var rowCount = 1
            for count in (1...3).reversed() {
                let rowsHeight = CGFloat(count) * (preferredBookHeight + 28)
                let gapsHeight = CGFloat(count + 1) * 16
                if area.height >= rowsHeight + gapsHeight {
                    rowCount = count
                    break
                }
            }
            let gap = min(16, max(0, (area.height - CGFloat(rowCount) * 72) / CGFloat(rowCount + 1)))
            let bookHeight = min(180, (area.height - CGFloat(rowCount + 1) * gap) / CGFloat(rowCount) - 28)
            let rowHeight = bookHeight + 28
            let spacing = (area.height - CGFloat(rowCount) * rowHeight) / CGFloat(rowCount + 1)
            let booksWidth = CGFloat(columnCount) * bookWidth + CGFloat(columnCount - 1) * 20
            let boardWidth = area.width > 600 ? max(booksWidth + 16, area.width * 0.85) : area.width
            for row in 0..<rowCount {
                let top = area.minY + spacing + CGFloat(row) * (rowHeight + spacing) + 6
                let startX = area.midX - booksWidth / 2
                let rowSlots: [CGRect] = (0..<columnCount).map { column in
                    let x = startX + CGFloat(column) * (bookWidth + 20)
                    return CGRect(x: x, y: top, width: bookWidth, height: bookHeight)
                }
                let board = CGRect(x: area.midX - boardWidth / 2, y: top + bookHeight,
                                   width: boardWidth, height: 22)
                rows.append((board, rowSlots))
            }
        }
        rows.sort { $0.board.minY == $1.board.minY ? $0.board.minX < $1.board.minX : $0.board.minY < $1.board.minY }
        if container.reservedRegions.contains(where: { $0.kind == .division && $0.frame.width > $0.frame.height }) {
            rows = Self.evenlySpacedRows(rows, in: areas, contentBounds: contentBounds)
            // 완전히 펼친 세로 화면에서는 도서까지 포함한 책장 묶음을 조금 낮춘다.
            // 비활성 접힘 영역으로 분할 형태는 유지하되, 실제로 가리는 영역과 하단 여백은 침범하지 않는다.
            let divisions = container.reservedRegions.filter { $0.kind == .division }
            if divisions.allSatisfy({ !$0.isActive }) {
                var offset: CGFloat = 48
                for row in rows {
                    let frame = row.slots.reduce(row.board) { $0.union($1) }
                    offset = min(offset, contentBounds.maxY - frame.maxY)
                    for region in container.reservedRegions where region.isActive {
                        if frame.minX < region.frame.maxX, frame.maxX > region.frame.minX,
                           region.frame.minY >= frame.maxY {
                            offset = min(offset, region.frame.minY - frame.maxY)
                        }
                    }
                }
                let shift = max(0, offset)
                rows = rows.map { row in
                    (row.board.offsetBy(dx: 0, dy: shift), row.slots.map { $0.offsetBy(dx: 0, dy: shift) })
                }
            }
        }
        boards = rows.map(\.board)
        slots = rows.flatMap(\.slots)
    }

    /// 가로 접힘 위아래를 따로 채우면 가운데 선반이 치우친다.
    /// 각 행이 속한 영역을 유지하면서 모든 선반에 같은 간격과 표지 높이를 적용한다.
    private static func evenlySpacedRows(
        _ rows: [(board: CGRect, slots: [CGRect])],
        in areas: [CGRect],
        contentBounds: CGRect
    ) -> [(board: CGRect, slots: [CGRect])] {
        guard rows.count >= 3,
              let bookHeight = rows.compactMap({ $0.slots.first?.height }).min(),
              let first = rows.first,
              rows.allSatisfy({ $0.board.minX == first.board.minX && $0.board.width == first.board.width }) else { return rows }
        let rowAreas = rows.compactMap { row in
            areas.first { $0.contains(row.board) }
        }
        guard rowAreas.count == rows.count else { return rows }
        let minimumPitch = bookHeight + 28 + 16
        let maximumPitch = (contentBounds.height - bookHeight - 28) / CGFloat(rows.count - 1)
        guard maximumPitch >= minimumPitch else { return rows }
        // 가장 넓은 균등 간격부터 찾되, 모든 표지와 선반이 원래 가용 영역 안에 있어야 한다.
        for pitch in stride(from: maximumPitch, through: minimumPitch, by: -1) {
            var lower = -CGFloat.infinity
            var upper = CGFloat.infinity
            for (index, area) in rowAreas.enumerated() {
                let offset = CGFloat(index) * pitch
                lower = max(lower, area.minY + 6 + bookHeight - offset)
                upper = min(upper, area.maxY - 22 - offset)
            }
            guard lower <= upper else { continue }
            let centered = contentBounds.midY - 11 - CGFloat(rows.count - 1) * pitch / 2
            let firstBoardY = min(upper, max(lower, centered))
            return rows.enumerated().map { index, row in
                let boardY = firstBoardY + CGFloat(index) * pitch
                let board = CGRect(x: row.board.minX, y: boardY, width: row.board.width, height: 22)
                let slots = row.slots.map {
                    CGRect(x: $0.minX, y: boardY - bookHeight, width: $0.width, height: bookHeight)
                }
                return (board, slots)
            }
        }
        return rows
    }

    func pageCount(for bookCount: Int) -> Int {
        guard capacity > 0 else { return 1 }
        return max(1, (bookCount + capacity - 1) / capacity)
    }

    func frame(forBookAt index: Int) -> CGRect? {
        guard index >= 0, capacity > 0 else { return nil }
        return slots[index % capacity].offsetBy(dx: CGFloat(index / capacity) * bounds.width, dy: 0)
    }
}

struct BookshelfPageAnchor {
    let bookID: String?
    let fallbackIndex: Int

    init(bookIDs: [String], page: Int, capacity: Int) {
        fallbackIndex = max(0, page) * max(0, capacity)
        bookID = bookIDs.indices.contains(fallbackIndex) ? bookIDs[fallbackIndex] : nil
    }

    func page(in bookIDs: [String], capacity: Int) -> Int {
        guard capacity > 0, !bookIDs.isEmpty else { return 0 }
        let index = bookID.flatMap { bookIDs.firstIndex(of: $0) } ?? min(fallbackIndex, bookIDs.count - 1)
        return index / capacity
    }
}
