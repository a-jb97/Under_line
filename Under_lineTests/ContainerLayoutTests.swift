import XCTest
import UIKit
@testable import Under_line

@MainActor
final class ContainerLayoutTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)

    func test_settings_placesRelatedBooksSwitchImmediatelyBelowRandomUnderline() throws {
        let controller = SettingsViewController()
        let view = try XCTUnwrap(controller.view)
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 700)
        view.layoutIfNeeded()

        let scrollView = try XCTUnwrap(view.subviews.compactMap { $0 as? UIScrollView }.first)
        let table = try XCTUnwrap(scrollView.subviews.first)
        let randomUnderlineRow = try XCTUnwrap(table.subviews.first { row in
            row.subviews.contains { ($0 as? UILabel)?.text == "랜덤 밑줄 기능 켜기/끄기" }
        })
        let relatedBooksRow = try XCTUnwrap(table.subviews.first { row in
            row.subviews.contains { ($0 as? UISwitch)?.accessibilityLabel == "이 책과 함께 읽기 좋은 책" }
        })

        XCTAssertEqual(relatedBooksRow.frame.minY, randomUnderlineRow.frame.maxY, accuracy: 0.5)
        XCTAssertGreaterThan(relatedBooksRow.frame.height, 0)
    }

    func test_relatedBooksView_pagesAtFullWidthAndResizesForExpandedDescription() throws {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 310, height: 700))
        let recommendation = RelatedBooksView()
        recommendation.onHeightChange = { [weak host] in host?.setNeedsLayout() }
        recommendation.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(recommendation)
        NSLayoutConstraint.activate([
            recommendation.topAnchor.constraint(equalTo: host.topAnchor),
            recommendation.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            recommendation.trailingAnchor.constraint(equalTo: host.trailingAnchor)
        ])
        let books = (1...3).map { index in
            Book(title: "추천 도서 \(index)", author: "저자", isbn13: "\(index)", coverURL: nil,
                 publisher: "출판사", publishDate: "2026", category: "문학", bestRank: nil,
                 description: String(repeating: "긴 책소개 문장입니다. ", count: 28),
                 itemPage: nil, currentPage: nil)
        }
        recommendation.configure(with: books)
        host.layoutIfNeeded()

        let stack = try XCTUnwrap(recommendation.subviews.first as? UIStackView)
        let title = try XCTUnwrap(stack.arrangedSubviews.compactMap { $0 as? UILabel }.first)
        XCTAssertEqual(title.font.fontName, "GoyangIlsanR-Regular")
        let pager = try XCTUnwrap(stack.arrangedSubviews.compactMap { $0 as? UIScrollView }.first)
        let pageControl = try XCTUnwrap(stack.arrangedSubviews.compactMap { $0 as? UIPageControl }.first)
        let pages = pager.subviews.compactMap { $0 as? BookDetailInfoView }
        XCTAssertEqual(pageControl.numberOfPages, 3)
        XCTAssertEqual(pager.contentSize.width, 930, accuracy: 0.5)
        XCTAssertEqual(pages.map(\.frame.width), [310, 310, 310])
        XCTAssertGreaterThan(pager.bounds.height, 60)
        let collapsedHeight = pager.bounds.height

        pager.contentOffset.x = 310
        pager.delegate?.scrollViewDidEndDecelerating?(pager)
        XCTAssertEqual(pageControl.currentPage, 1)
        let header = try XCTUnwrap(pages[1].subviews.first)
        let moreButton = try XCTUnwrap(header.subviews.compactMap { $0 as? UIButton }.first)
        moreButton.sendActions(for: .touchUpInside)
        host.layoutIfNeeded()
        XCTAssertGreaterThan(pager.bounds.height, collapsedHeight + 50)
        XCTAssertEqual(moreButton.title(for: .normal), "가리기")

        host.frame.size.width = 450
        host.layoutIfNeeded()
        XCTAssertEqual(pageControl.currentPage, 1)
        XCTAssertEqual(pager.contentOffset.x, 450, accuracy: 0.5)
        XCTAssertEqual(pager.contentSize.width, 1350, accuracy: 0.5)

        moreButton.sendActions(for: .touchUpInside)
        host.layoutIfNeeded()
        XCTAssertEqual(pager.bounds.height, collapsedHeight, accuracy: 1)

        recommendation.configure(with: Array(books.prefix(1)))
        host.layoutIfNeeded()
        XCTAssertTrue(pageControl.isHidden)
        XCTAssertFalse(pager.isScrollEnabled)
        XCTAssertEqual(pager.contentOffset.x, 0, accuracy: 0.5)

        recommendation.configure(with: [])
        XCTAssertTrue(recommendation.isHidden)
    }

    func test_bookDetailWhenScrolled_keepsBottomButtonsFixed() throws {
        let book = Book(title: "책", author: "저자", isbn13: "", coverURL: nil,
                        publisher: "", publishDate: nil, category: nil, bestRank: nil,
                        description: "", itemPage: nil, currentPage: nil)

        for size in [CGSize(width: 390, height: 620), bounds.size] {
            let controller = BookDetailViewController(book: book)
            let view = try XCTUnwrap(controller.view)
            view.frame = CGRect(origin: .zero, size: size)
            view.layoutIfNeeded()

            let scrollView = try XCTUnwrap(view.subviews.compactMap { $0 as? UIScrollView }.first)
            let buttons = try ["밑줄 편집", "밑줄 추가"].map { label in
                try XCTUnwrap(view.subviews.first { $0.accessibilityLabel == label } as? UIButton)
            }
            let initialFrames = buttons.map(\.frame)
            for button in buttons {
                XCTAssertEqual(button.frame.maxY, scrollView.frame.maxY - 16, accuracy: 0.5)
            }

            let content = try XCTUnwrap(scrollView.subviews.first { $0.subviews.contains { $0 is UIPageControl } })
            let sections = try XCTUnwrap(content.subviews.compactMap { $0 as? UIStackView }.first)
            let infoSection = try XCTUnwrap(sections.arrangedSubviews.first)
            let relatedSection = try XCTUnwrap(sections.arrangedSubviews.last)
            let infoStack = try XCTUnwrap(infoSection.subviews.compactMap { $0 as? UIStackView }.first)
            let progress = try XCTUnwrap(infoStack.arrangedSubviews.compactMap { $0 as? ProgressSectionView }.first)
            let related = try XCTUnwrap(relatedSection.subviews.compactMap { $0 as? RelatedBooksView }.first)
            XCTAssertTrue(relatedSection.isHidden)
            let heightWithoutRelatedBooks = sections.bounds.height
            controller.configureRelatedBooks([book])
            view.layoutIfNeeded()
            XCTAssertFalse(relatedSection.isHidden)
            XCTAssertEqual(relatedSection.frame.minY, infoSection.frame.maxY + 24, accuracy: 0.5)
            XCTAssertEqual(relatedSection.frame.width, infoSection.frame.width, accuracy: 0.5)
            XCTAssertGreaterThan(related.frame.height, 60)
            progress.configure(itemPage: 300, currentPage: 120)
            view.layoutIfNeeded()
            XCTAssertFalse(relatedSection.isHidden)
            XCTAssertEqual(relatedSection.frame.minY, infoSection.frame.maxY + 24, accuracy: 0.5)
            progress.configure(itemPage: nil, currentPage: nil)
            controller.configureRelatedBooks([])
            view.layoutIfNeeded()
            XCTAssertTrue(relatedSection.isHidden)
            XCTAssertEqual(sections.bounds.height, heightWithoutRelatedBooks, accuracy: 0.5)

            let initialOffset = scrollView.contentOffset.y
            // The offset can exceed the content bounds during a scroll bounce.
            for displacement: CGFloat in [40, -30] {
                scrollView.contentOffset.y = initialOffset + displacement
                view.layoutIfNeeded()

                XCTAssertEqual(scrollView.contentOffset.y, initialOffset + displacement, accuracy: 0.5)
                XCTAssertEqual(buttons.map(\.frame), initialFrames)
            }
        }
    }

    func test_bookDetailInWideLandscape_usesTwoColumnsInsideReadableArea() throws {
        let container = ContainerLayout(bounds: CGRect(x: 0, y: 0, width: 1194, height: 834))
        let columns = try XCTUnwrap(ReadingColumns(container: container))
        XCTAssertEqual(columns.viewport, CGRect(x: 217, y: 0, width: 760, height: 834))
        XCTAssertEqual(columns.leadingWidth, 344)
        XCTAssertEqual(columns.gap, 24)
    }

    func test_bookDetailWhenPortraitOrNarrow_usesSingleColumn() {
        let portrait = ContainerLayout(bounds: CGRect(x: 0, y: 0, width: 834, height: 1194))
        let narrow = ContainerLayout(bounds: CGRect(x: 0, y: 0, width: 560, height: 500))
        XCTAssertNil(ReadingColumns(container: portrait, usesFullWidth: true))
        XCTAssertNil(ReadingColumns(container: narrow, usesFullWidth: true))
    }

    func test_bookDetailInFullWidthLandscape_centersInsideAsymmetricSafeArea() throws {
        let container = ContainerLayout(
            bounds: CGRect(x: 0, y: 0, width: 1194, height: 834),
            safeAreaInsets: UIEdgeInsets(top: 20, left: 16, bottom: 24, right: 24)
        )
        let columns = try XCTUnwrap(ReadingColumns(container: container, usesFullWidth: true))
        XCTAssertEqual(columns.viewport, CGRect(x: 24, y: 20, width: 1146, height: 790))
        XCTAssertEqual(columns.viewport.midX, container.bounds.midX)
        XCTAssertTrue(container.safeBounds.contains(columns.viewport))
        XCTAssertEqual(columns.leadingWidth, 537)
        XCTAssertEqual(columns.gap, 24)
    }

    func test_bookDetailWithInactiveVerticalDivision_keepsColumnsOnOppositeSides() throws {
        let container = ContainerLayout(
            bounds: bounds,
            safeAreaInsets: UIEdgeInsets(top: 20, left: 10, bottom: 30, right: 40),
            reservedRegions: [.init(kind: .division, frame: CGRect(x: 390, y: 0, width: 20, height: 600), isActive: false)],
            reservesInactiveDivisions: true
        )
        let columns = try XCTUnwrap(ReadingColumns(container: container))
        XCTAssertEqual(columns.viewport, CGRect(x: 10, y: 20, width: 750, height: 550))
        XCTAssertEqual(columns.viewport.minX + 24 + columns.leadingWidth, 366)
        XCTAssertEqual(columns.viewport.minX + 24 + columns.leadingWidth + columns.gap, 434)
    }

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

    func test_readableContent_capsWidthAndCentersInsideSafeArea() {
        let container = ContainerLayout(bounds: CGRect(x: 0, y: 0, width: 1200, height: 800),
                                        safeAreaInsets: UIEdgeInsets(top: 40, left: 20, bottom: 30, right: 80))
        let frame = ReadableContentLayout(container: container).frame
        XCTAssertEqual(frame.width, 760)
        XCTAssertEqual(frame.midX, container.safeBounds.midX)
        XCTAssertEqual(frame.minY, 40)
        XCTAssertEqual(frame.maxY, 770)
    }

    func test_readableContent_avoidsFoldAndCameraInBothAxes() {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
        for fold in [CGRect(x: 480, y: 0, width: 40, height: 800),
                     CGRect(x: 0, y: 390, width: 1000, height: 40)] {
            let container = ContainerLayout(bounds: bounds, reservedRegions: [
                .init(kind: .division, frame: fold),
                .init(kind: .occlusion, frame: CGRect(x: 900, y: 0, width: 100, height: 80))
            ])
            let frame = ReadableContentLayout(container: container).frame
            XCTAssertTrue(container.safeBounds.contains(frame))
            XCTAssertGreaterThan(frame.width, 300)
            for region in container.reservedRegions { XCTAssertTrue(frame.intersection(region.frame).isEmpty) }
        }
    }

    func test_readableContent_keyboardSelectsVisibleRegionWithoutCumulativeInsets() {
        let container = ContainerLayout(bounds: CGRect(x: 0, y: 0, width: 800, height: 900), reservedRegions: [
            .init(kind: .division, frame: CGRect(x: 0, y: 390, width: 800, height: 40))
        ])
        let before = ReadableContentLayout(container: container).frame
        let keyboard = ReadableContentLayout(container: container, keyboardTop: 480).frame
        XCTAssertEqual(keyboard.maxY, 390)
        XCTAssertEqual(keyboard, ReadableContentLayout(container: container, keyboardTop: 480).frame)
        XCTAssertEqual(before, ReadableContentLayout(container: container).frame)
    }

    func test_readableContent_smallAndFullyOccludedWindows_doNotExpand() {
        let bounds = CGRect(x: 0, y: 0, width: 260, height: 160)
        XCTAssertEqual(ReadableContentLayout(container: ContainerLayout(bounds: bounds)).frame, bounds)
        let hidden = ContainerLayout(bounds: bounds, reservedRegions: [.init(kind: .occlusion, frame: bounds)])
        XCTAssertTrue(ReadableContentLayout(container: hidden).frame.isEmpty)
    }

    func test_scrollableText_longBodyRemainsReachableAfterResizing() {
        let label = UILabel()
        label.numberOfLines = 0
        label.text = String(repeating: "긴 문장과 메모를 끝까지 읽을 수 있어야 합니다. ", count: 80)
        let scroll = ScrollableTextView(label: label)
        scroll.frame = CGRect(x: 0, y: 0, width: 300, height: 180)
        scroll.layoutIfNeeded()
        XCTAssertGreaterThan(scroll.contentSize.height, scroll.bounds.height)
        scroll.frame.size = CGSize(width: 500, height: 140)
        scroll.layoutIfNeeded()
        XCTAssertGreaterThan(scroll.contentSize.height, scroll.bounds.height)
        XCTAssertEqual(label.text?.count, String(repeating: "긴 문장과 메모를 끝까지 읽을 수 있어야 합니다. ", count: 80).count)
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
