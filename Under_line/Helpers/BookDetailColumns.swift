import UIKit

struct BookDetailColumns: Equatable {
    let viewport: CGRect
    let quoteWidth: CGFloat
    let gap: CGFloat

    init?(container: ContainerLayout, usesFullWidth: Bool = false) {
        let inset: CGFloat = 24
        let minimumColumnWidth: CGFloat = 260
        if let hinge = container.reservedRegions.first(where: {
            $0.kind == .division && $0.frame.height > $0.frame.width
        })?.frame {
            let left = container.availableRects.filter {
                $0.maxX <= hinge.minX && $0.width >= minimumColumnWidth + 2 * inset
            }.max { $0.height < $1.height }
            let right = container.availableRects.filter {
                $0.minX >= hinge.maxX && $0.width >= minimumColumnWidth + 2 * inset
            }.max { $0.height < $1.height }
            guard let left, let right else { return nil }
            let top = max(left.minY, right.minY)
            let bottom = min(left.maxY, right.maxY)
            guard bottom > top else { return nil }
            viewport = CGRect(x: left.minX, y: top, width: right.maxX - left.minX, height: bottom - top)
            quoteWidth = left.width - 2 * inset
            gap = right.minX - left.maxX + 2 * inset
        } else {
            var frame = ReadableContentLayout(
                container: container,
                maximumWidth: usesFullWidth ? container.safeBounds.width : 760
            ).frame
            if usesFullWidth {
                let centerX = container.bounds.midX
                let halfWidth = min(centerX - frame.minX, frame.maxX - centerX)
                guard halfWidth > 0 else { return nil }
                frame.origin.x = centerX - halfWidth
                frame.size.width = 2 * halfWidth
            }
            let gap: CGFloat = 24
            let columnWidth = (frame.width - 2 * inset - gap) / 2
            guard container.bounds.width > container.bounds.height,
                  columnWidth >= minimumColumnWidth else { return nil }
            viewport = frame
            quoteWidth = columnWidth
            self.gap = gap
        }
    }
}
