import UIKit

/// 단일 목록·카드·폼을 위한 연속된 가용 영역. 가려진 영역을 가로질러 콘텐츠를 배치하지 않는다.
struct ReadableContentLayout {
    let frame: CGRect

    init(container: ContainerLayout, maximumWidth: CGFloat = 760, keyboardTop: CGFloat? = nil) {
        let areas = container.availableRects.compactMap { area -> CGRect? in
            var rect = area
            if let keyboardTop { rect.size.height = max(0, min(rect.maxY, keyboardTop) - rect.minY) }
            return rect.isEmpty ? nil : rect
        }
        // 동일한 면적이면 위쪽, 왼쪽을 우선하여 반복 배치 시 위치가 흔들리지 않는다.
        let area = areas.sorted {
            let lhs = min($0.width, maximumWidth) * $0.height
            let rhs = min($1.width, maximumWidth) * $1.height
            if lhs != rhs { return lhs > rhs }
            if $0.minY != $1.minY { return $0.minY < $1.minY }
            return $0.minX < $1.minX
        }.first ?? CGRect(origin: container.safeBounds.origin, size: .zero)
        let width = min(area.width, maximumWidth)
        frame = CGRect(x: area.midX - width / 2, y: area.minY, width: width, height: area.height)
    }
}
