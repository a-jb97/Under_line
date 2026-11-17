import UIKit

/// 컨테이너 좌표계의 사용 가능 공간. 기기 종류나 물리 화면 크기를 참조하지 않는다.
struct ContainerLayout: Equatable {
    struct ReservedRegion: Equatable {
        enum Kind: Int {
            case division
            case occlusion
        }

        let kind: Kind
        let frame: CGRect
        var isActive = true
    }

    let bounds: CGRect
    let safeBounds: CGRect
    let horizontalSizeClass: UIUserInterfaceSizeClass
    let verticalSizeClass: UIUserInterfaceSizeClass
    let displayScale: CGFloat
    let reservedRegions: [ReservedRegion]

    /// 서로 겹치지 않는 사각형들로 분해한 공간이며, 각 항목은 예약 영역과 겹치지 않는다.
    /// 최대 크기의 사각형 목록이 아니므로 화면별 배치는 예약 영역의 종류도 함께 고려한다.
    let availableRects: [CGRect]

    init(
        bounds: CGRect,
        safeAreaInsets: UIEdgeInsets = .zero,
        horizontalSizeClass: UIUserInterfaceSizeClass = .unspecified,
        verticalSizeClass: UIUserInterfaceSizeClass = .unspecified,
        displayScale: CGFloat = 1,
        reservedRegions: [ReservedRegion] = [],
        reservesInactiveDivisions: Bool = false
    ) {
        self.bounds = bounds
        self.horizontalSizeClass = horizontalSizeClass
        self.verticalSizeClass = verticalSizeClass
        self.displayScale = displayScale

        // 작은 창에서 inset 합이 너비·높이를 초과해도 가용 영역이 뒤집혀 커지지 않게 한다.
        let left = max(0, safeAreaInsets.left)
        let top = max(0, safeAreaInsets.top)
        let safeBounds = CGRect(
            x: bounds.minX + min(left, bounds.width),
            y: bounds.minY + min(top, bounds.height),
            width: max(0, bounds.width - left - max(0, safeAreaInsets.right)),
            height: max(0, bounds.height - top - max(0, safeAreaInsets.bottom))
        )
        self.safeBounds = safeBounds
        self.reservedRegions = reservedRegions.compactMap { region in
            guard region.isActive || (reservesInactiveDivisions && region.kind == .division) else { return nil }
            let frame = safeBounds.intersection(region.frame)
            guard !frame.isNull, !frame.isEmpty else { return nil }
            return ReservedRegion(kind: region.kind, frame: frame, isActive: region.isActive)
        }.sorted { lhs, rhs in
            let left = [CGFloat(lhs.kind.rawValue), lhs.frame.minY, lhs.frame.minX, lhs.frame.width, lhs.frame.height]
            let right = [CGFloat(rhs.kind.rawValue), rhs.frame.minY, rhs.frame.minX, rhs.frame.width, rhs.frame.height]
            return left.lexicographicallyPrecedes(right)
        }

        availableRects = self.reservedRegions.reduce(safeBounds.isEmpty ? [] : [safeBounds]) { rects, region in
            rects.flatMap { Self.subtract(region.frame, from: $0) }
        }
    }

    /// UIKit의 예약 영역 변경 추적을 위해 updateConstraints()에서 호출한다.
    init(view: UIView, reservesInactiveDivisions: Bool = false) {
        var regions: [ReservedRegion] = []
        if #available(iOS 27.1, *) {
            // frame에 시스템 여백이 이미 포함되어 있으므로 margins를 다시 더하지 않는다.
            regions = view.reservedRegions(kind: .division, options: reservesInactiveDivisions ? .includeInactive : []).map {
                ReservedRegion(kind: .division, frame: $0.frame, isActive: $0.isActive)
            } + view.reservedRegions(kind: .occlusion).map {
                ReservedRegion(kind: .occlusion, frame: $0.frame, isActive: $0.isActive)
            }
        }
        self.init(
            bounds: view.bounds,
            safeAreaInsets: view.safeAreaInsets,
            horizontalSizeClass: view.traitCollection.horizontalSizeClass,
            verticalSizeClass: view.traitCollection.verticalSizeClass,
            displayScale: view.traitCollection.displayScale,
            reservedRegions: regions,
            reservesInactiveDivisions: reservesInactiveDivisions
        )
    }

    private static func subtract(_ exclusion: CGRect, from rect: CGRect) -> [CGRect] {
        let overlap = rect.intersection(exclusion)
        guard !overlap.isNull, !overlap.isEmpty else { return [rect] }
        return [
            CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: overlap.minY - rect.minY),
            CGRect(x: rect.minX, y: overlap.maxY, width: rect.width, height: rect.maxY - overlap.maxY),
            CGRect(x: rect.minX, y: overlap.minY, width: overlap.minX - rect.minX, height: overlap.height),
            CGRect(x: overlap.maxX, y: overlap.minY, width: rect.maxX - overlap.maxX, height: overlap.height)
        ].filter { !$0.isEmpty }
    }
}
