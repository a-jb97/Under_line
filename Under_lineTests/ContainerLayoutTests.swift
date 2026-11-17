import XCTest
import UIKit
@testable import Under_line

@MainActor
final class ContainerLayoutTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)

    func test_asymmetricSafeArea_insetsEveryEdgeInContainerCoordinates() {
        let layout = ContainerLayout(
            bounds: CGRect(x: 10, y: 20, width: 400, height: 300),
            safeAreaInsets: UIEdgeInsets(top: 12, left: 18, bottom: 24, right: 70)
        )
        XCTAssertEqual(layout.safeBounds, CGRect(x: 28, y: 32, width: 312, height: 264))
        XCTAssertEqual(layout.availableRects, [layout.safeBounds])
    }

    func test_verticalDivision_returnsRegionsOnBothSides() {
        let layout = ContainerLayout(bounds: bounds, reservedRegions: [
            .init(kind: .division, frame: CGRect(x: 390, y: -20, width: 20, height: 640))
        ])
        XCTAssertEqual(layout.availableRects, [
            CGRect(x: 0, y: 0, width: 390, height: 600),
            CGRect(x: 410, y: 0, width: 390, height: 600)
        ])
    }

    func test_horizontalDivision_returnsRegionsAboveAndBelow() {
        let layout = ContainerLayout(bounds: bounds, reservedRegions: [
            .init(kind: .division, frame: CGRect(x: 0, y: 290, width: 800, height: 20))
        ])
        XCTAssertEqual(layout.availableRects, [
            CGRect(x: 0, y: 0, width: 800, height: 290),
            CGRect(x: 0, y: 310, width: 800, height: 290)
        ])
    }

    func test_inactiveAndOutsideRegions_doNotReduceAvailableSpace() {
        let layout = ContainerLayout(bounds: bounds, reservedRegions: [
            .init(kind: .division, frame: CGRect(x: 390, y: 0, width: 20, height: 600), isActive: false),
            .init(kind: .occlusion, frame: CGRect(x: 900, y: 0, width: 40, height: 40))
        ])
        XCTAssertTrue(layout.reservedRegions.isEmpty)
        XCTAssertEqual(layout.availableRects, [bounds])
    }

    func test_preservingInactiveDivision_stillIgnoresInactiveOcclusion() {
        let layout = ContainerLayout(bounds: bounds, reservedRegions: [
            .init(kind: .division, frame: CGRect(x: 390, y: 0, width: 20, height: 600), isActive: false),
            .init(kind: .occlusion, frame: CGRect(x: 0, y: 0, width: 100, height: 100), isActive: false)
        ], reservesInactiveDivisions: true)
        XCTAssertEqual(layout.availableRects, [
            CGRect(x: 0, y: 0, width: 390, height: 600),
            CGRect(x: 410, y: 0, width: 390, height: 600)
        ])
        XCTAssertEqual(layout.reservedRegions.count, 1)
    }

    func test_cameraOverlappingCorner_clipsFrameWithoutAddingMargins() {
        let layout = ContainerLayout(bounds: bounds, reservedRegions: [
            .init(kind: .occlusion, frame: CGRect(x: 760, y: -10, width: 80, height: 60))
        ])
        XCTAssertEqual(layout.reservedRegions.first?.frame, CGRect(x: 760, y: 0, width: 40, height: 50))
        XCTAssertEqual(layout.availableRects, [
            CGRect(x: 0, y: 50, width: 800, height: 550),
            CGRect(x: 0, y: 0, width: 760, height: 50)
        ])
    }

    func test_regionAlreadyOutsideSafeArea_doesNotInsetContentAgain() {
        let layout = ContainerLayout(bounds: bounds, safeAreaInsets: UIEdgeInsets(top: 60, left: 0, bottom: 0, right: 0), reservedRegions: [
            .init(kind: .occlusion, frame: CGRect(x: 760, y: 0, width: 40, height: 50))
        ])
        XCTAssertEqual(layout.availableRects, [CGRect(x: 0, y: 60, width: 800, height: 540)])
    }

    func test_overlappingRegions_excludeTheirUnionWithoutOverlappingResults() {
        let regions: [ContainerLayout.ReservedRegion] = [
            .init(kind: .division, frame: CGRect(x: 390, y: 0, width: 20, height: 600)),
            .init(kind: .occlusion, frame: CGRect(x: 380, y: 0, width: 60, height: 50))
        ]
        let layout = ContainerLayout(bounds: bounds, reservedRegions: regions)
        let area = layout.availableRects.reduce(CGFloat.zero) { $0 + $1.width * $1.height }
        XCTAssertEqual(area, 800 * 600 - 20 * 600 - 40 * 50)
        for (index, rect) in layout.availableRects.enumerated() {
            XCTAssertTrue(bounds.contains(rect))
            for region in regions {
                XCTAssertTrue(rect.intersection(region.frame).isEmpty)
            }
            for other in layout.availableRects.dropFirst(index + 1) {
                XCTAssertTrue(rect.intersection(other).isEmpty)
            }
        }
    }

    func test_regionOrder_changesDoNotChangeLayout() {
        let regions: [ContainerLayout.ReservedRegion] = [
            .init(kind: .occlusion, frame: CGRect(x: 760, y: 0, width: 40, height: 50)),
            .init(kind: .division, frame: CGRect(x: 390, y: 0, width: 20, height: 600))
        ]
        XCTAssertEqual(
            ContainerLayout(bounds: bounds, reservedRegions: regions),
            ContainerLayout(bounds: bounds, reservedRegions: regions.reversed())
        )
    }

    func test_emptyOrFullyReservedContainer_hasNoAvailableRects() {
        XCTAssertTrue(ContainerLayout(bounds: .zero).availableRects.isEmpty)
        XCTAssertTrue(ContainerLayout(bounds: bounds, reservedRegions: [
            .init(kind: .occlusion, frame: bounds)
        ]).availableRects.isEmpty)
        XCTAssertTrue(ContainerLayout(
            bounds: CGRect(x: 0, y: 0, width: 40, height: 30),
            safeAreaInsets: UIEdgeInsets(top: 20, left: 30, bottom: 20, right: 30)
        ).availableRects.isEmpty)
    }

    func test_smallContainer_keepsItsActualSize() {
        let rect = CGRect(x: 0, y: 0, width: 240, height: 120)
        let layout = ContainerLayout(bounds: rect, horizontalSizeClass: .regular, verticalSizeClass: .compact)
        XCTAssertEqual(layout.availableRects, [rect])
        XCTAssertEqual(layout.horizontalSizeClass, .regular)
        XCTAssertEqual(layout.verticalSizeClass, .compact)
    }

    func test_repeatedLayout_notifiesOnlyWhenGeometryChanges() {
        let view = ContainerLayoutView(frame: bounds)
        var layouts: [ContainerLayout] = []
        view.onLayoutChange = { layouts.append($0) }
        view.setNeedsUpdateConstraints()
        view.layoutIfNeeded()
        XCTAssertEqual(layouts.count, 1)
        view.setNeedsUpdateConstraints()
        view.setNeedsLayout()
        view.layoutIfNeeded()
        XCTAssertEqual(layouts.count, 1)

        view.bounds.size = CGSize(width: 320, height: 200)
        view.layoutIfNeeded()
        XCTAssertEqual(layouts.count, 2)
        XCTAssertEqual(layouts.last?.bounds.size, CGSize(width: 320, height: 200))
    }

    func test_safeAreaAndTraitsChange_updateSnapshotWithoutBoundsChange() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let controller = UIViewController()
        let view = ContainerLayoutView(frame: bounds)
        controller.view = view
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        window.layoutIfNeeded()
        let originalBounds = view.bounds
        let originalInsets = view.safeAreaInsets
        controller.additionalSafeAreaInsets = UIEdgeInsets(top: 10, left: 20, bottom: 30, right: 40)
        window.layoutIfNeeded()
        XCTAssertEqual(view.bounds, originalBounds)
        XCTAssertEqual(view.safeAreaInsets.top, originalInsets.top + 10)
        XCTAssertEqual(view.safeAreaInsets.left, originalInsets.left + 20)
        XCTAssertEqual(view.safeAreaInsets.bottom, originalInsets.bottom + 30)
        XCTAssertEqual(view.safeAreaInsets.right, originalInsets.right + 40)
        XCTAssertEqual(view.containerLayout?.safeBounds, view.bounds.inset(by: view.safeAreaInsets))

        controller.traitOverrides.horizontalSizeClass = .regular
        controller.traitOverrides.verticalSizeClass = .compact
        view.updateTraitsIfNeeded()
        view.layoutIfNeeded()
        XCTAssertEqual(view.containerLayout?.horizontalSizeClass, .regular)
        XCTAssertEqual(view.containerLayout?.verticalSizeClass, .compact)
    }
}
