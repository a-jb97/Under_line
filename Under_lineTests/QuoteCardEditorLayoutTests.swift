import XCTest
import UIKit
@testable import Under_line

@MainActor
final class QuoteCardEditorLayoutTests: XCTestCase {
    func test_duoHierarchy_compactEditorReceivesHingeAndUsesVerticalActions() async throws {
        guard #available(iOS 27.1, *),
              ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"]?.contains("Duo") == true else {
            throw XCTSkip("Duo 시뮬레이터에서 힌지 전달을 검증합니다.")
        }
        let defaults = UserDefaults.standard
        let tutorial = defaults.object(forKey: "tutorial.cardEditor")
        defaults.set(true, forKey: "tutorial.cardEditor")
        defer { defaults.set(tutorial, forKey: "tutorial.cardEditor") }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let host = UIViewController()
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        let controller = makeEditor()
        host.addChild(controller)
        host.view.addSubview(controller.view)
        controller.didMove(toParent: host)
        let receivedHinge = expectation(description: "Duo의 힌지 정보 전달")
        receivedHinge.assertForOverFulfill = false
        controller.view.addInteraction(UIHingeInteraction { _, update in
            if update.hinge != nil { receivedHinge.fulfill() }
        })
        await fulfillment(of: [receivedHinge], timeout: 3)
        resize(controller, to: CGSize(width: 375, height: 812))
        let logo = controller.removeLogoButton.convert(controller.removeLogoButton.bounds, to: controller.view)
        let background = controller.backgroundButton.convert(controller.backgroundButton.bounds, to: controller.view)
        let share = controller.saveButton.convert(controller.saveButton.bounds, to: controller.view)
        XCTAssertEqual(logo.midX, background.midX, accuracy: 0.001)
        XCTAssertEqual(background.midX, share.midX, accuracy: 0.001)
        XCTAssertGreaterThan(background.minY, logo.maxY)
        XCTAssertGreaterThan(share.minY, background.maxY)
    }

    func test_previewFitsNarrowLowAndWideWindows_withoutUpscaling() {
        for size in [CGSize(width: 375, height: 650), CGSize(width: 300, height: 260),
                     CGSize(width: 760, height: 300), CGSize(width: 760, height: 1000),
                     CGSize(width: 240, height: 200)] {
            let bounds = CGRect(origin: CGPoint(x: 25, y: 40), size: size)
            let layout = QuoteCardEditorLayout(availableBounds: bounds)
            XCTAssertTrue(bounds.contains(layout.previewFrame))
            XCTAssertTrue(bounds.contains(layout.actionsFrame))
            XCTAssertTrue(layout.previewFrame.intersection(layout.actionsFrame).isEmpty)
            XCTAssertGreaterThan(layout.previewScale, 0)
            XCTAssertLessThanOrEqual(layout.previewScale, 1)
            XCTAssertEqual(layout.previewFrame.height / layout.previewFrame.width, 1.586, accuracy: 0.001)
        }
    }

    func test_regularPhone_keepsBottomHorizontalActionsInBothOrientations() {
        for size in [CGSize(width: 375, height: 667), CGSize(width: 393, height: 852),
                     CGSize(width: 440, height: 956), CGSize(width: 852, height: 393)] {
            let bounds = CGRect(origin: .zero, size: size)
            let safeBounds = bounds.inset(by: UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0))
            for showsColorSync in [false, true] {
                let layout = QuoteCardEditorLayout(availableBounds: safeBounds, containerBounds: bounds,
                                                   showsColorSync: showsColorSync)
                XCTAssertEqual(layout.actionFrames[0].minY, layout.actionFrames[1].minY)
                XCTAssertEqual(layout.actionFrames[1].minY, layout.actionFrames[3].minY)
                XCTAssertEqual(layout.actionFrames[1].minX - layout.actionFrames[0].minX, 64)
                XCTAssertEqual(layout.actionsFrame.minX + 6, safeBounds.minX + 24)
                XCTAssertEqual(layout.actionsFrame.minX + layout.actionFrames[3].maxX - 6, safeBounds.maxX - 24)
                XCTAssertEqual(layout.actionsFrame.maxY, safeBounds.maxY - 16)
                XCTAssertTrue(layout.previewFrame.intersection(layout.actionsFrame).isEmpty)
                XCTAssertEqual(layout.actionFrames[2].isEmpty, !showsColorSync)
            }
        }
    }

    func test_landscape_centersCardAndRightAlignedActionGroup() {
        let bounds = CGRect(x: 0, y: 0, width: 760, height: 600)
        let safeBounds = CGRect(x: 0, y: 20, width: 660, height: 550)
        let layout = QuoteCardEditorLayout(availableBounds: safeBounds, containerBounds: bounds, usesFoldableLayout: true)
        XCTAssertGreaterThan(layout.actionsFrame.minX, layout.previewFrame.maxX)
        XCTAssertEqual(layout.actionsFrame.maxY, layout.previewFrame.maxY, accuracy: 0.001)
        let group = layout.previewFrame.union(layout.actionsFrame)
        XCTAssertEqual(group.midX, bounds.midX, accuracy: 0.001)
        XCTAssertEqual(group.midY, bounds.midY, accuracy: 0.001)
        XCTAssertEqual(layout.actionFrames[0].minY, layout.actionFrames[1].minY)
        XCTAssertEqual(layout.actionFrames[0].minY, layout.actionFrames[3].minY)
        XCTAssertEqual(layout.actionFrames[1].minX - layout.actionFrames[0].minX, 64)
        XCTAssertEqual(layout.actionFrames[3].minX - layout.actionFrames[1].minX, 64)
        XCTAssertTrue(layout.actionFrames[2].isEmpty)
    }

    func test_tinyWindow_keepsEveryActionInScrollableContent() {
        let layout = QuoteCardEditorLayout(availableBounds: CGRect(x: 0, y: 0, width: 200, height: 240), usesFoldableLayout: true, showsColorSync: true)
        let content = CGRect(origin: .zero, size: layout.actionsContentSize)
        XCTAssertGreaterThan(content.height, layout.actionsFrame.height)
        for frame in layout.actionFrames {
            XCTAssertTrue(content.contains(frame))
            XCTAssertGreaterThanOrEqual(frame.width, 52)
        }
    }

    func test_compactPortrait_placesActionsAtBottomRightAndCentersCard() {
        let bounds = CGRect(x: 0, y: 0, width: 375, height: 812)
        let safeBounds = CGRect(x: 0, y: 62, width: 280, height: 716)
        let layout = QuoteCardEditorLayout(availableBounds: safeBounds, containerBounds: bounds, usesFoldableLayout: true)
        XCTAssertEqual(layout.actionsFrame.height, layout.actionsContentSize.height)
        XCTAssertEqual(layout.actionsFrame.maxX - 6, bounds.maxX - 24)
        XCTAssertEqual(layout.actionFrames[0].minX, layout.actionFrames[1].minX)
        XCTAssertEqual(layout.actionFrames[1].minX, layout.actionFrames[3].minX)
        XCTAssertGreaterThan(layout.actionFrames[1].minY, layout.actionFrames[0].maxY)
        XCTAssertGreaterThan(layout.actionFrames[3].minY, layout.actionFrames[1].maxY)
        XCTAssertEqual(layout.previewFrame.midX, bounds.midX, accuracy: 0.001)
        XCTAssertEqual(layout.previewFrame.midY, bounds.midY, accuracy: 0.001)
        XCTAssertEqual(layout.actionsFrame.maxY, bounds.maxY - 16)
        XCTAssertGreaterThan(layout.actionsFrame.minX, safeBounds.maxX)
        XCTAssertGreaterThan(layout.actionsFrame.minX, layout.previewFrame.maxX)
    }

    func test_unfoldedPortrait_keepsOriginalGapBetweenLogoAndBackground() {
        let bounds = CGRect(x: 0, y: 0, width: 650, height: 900)
        let layout = QuoteCardEditorLayout(availableBounds: bounds)
        XCTAssertEqual(layout.actionFrames[1].minX - layout.actionFrames[0].minX - 52, 12)
        XCTAssertEqual(layout.actionsFrame.minX + 6, bounds.minX + 24)
        XCTAssertEqual(layout.actionsFrame.minX + layout.actionFrames[3].maxX - 6, bounds.maxX - 24)
    }

    func test_colorSyncVisibility_addsActionWithoutLeavingAnEmptySlot() {
        for bounds in [CGRect(x: 0, y: 0, width: 375, height: 750),
                       CGRect(x: 0, y: 0, width: 760, height: 300)] {
            let hidden = QuoteCardEditorLayout(availableBounds: bounds, usesFoldableLayout: true)
            let visible = QuoteCardEditorLayout(availableBounds: bounds, usesFoldableLayout: true, showsColorSync: true)
            XCTAssertTrue(hidden.actionFrames[2].isEmpty)
            XCTAssertFalse(visible.actionFrames[2].isEmpty)
            XCTAssertGreaterThan(visible.actionsContentSize.width * visible.actionsContentSize.height,
                                 hidden.actionsContentSize.width * hidden.actionsContentSize.height)
        }
    }

    func test_foldAndCamera_keepPreviewAndActionsInOneUsableArea() {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
        for fold in [CGRect(x: 480, y: 0, width: 40, height: 800),
                     CGRect(x: 0, y: 380, width: 1000, height: 40)] {
            let container = ContainerLayout(bounds: bounds, reservedRegions: [
                .init(kind: .division, frame: fold),
                .init(kind: .occlusion, frame: CGRect(x: 900, y: 0, width: 100, height: 80))
            ])
            let area = ReadableContentLayout(container: container).frame
            let layout = QuoteCardEditorLayout(availableBounds: area, containerSize: bounds.size)
            for frame in [layout.previewFrame, layout.actionsFrame] {
                XCTAssertTrue(area.contains(frame))
                for region in container.reservedRegions { XCTAssertTrue(frame.intersection(region.frame).isEmpty) }
            }
        }
    }

    func test_resizingPreview_keepsCanvasAndExportDimensions() throws {
        let controller = makeEditor()
        controller.cardView.traitOverrides.displayScale = 2
        controller.cardView.updateTraitsIfNeeded()
        resize(controller, to: CGSize(width: 375, height: 812))
        let before = controller.renderedCardImage()
        resize(controller, to: CGSize(width: 760, height: 300))
        let after = controller.renderedCardImage()
        XCTAssertEqual(controller.cardView.bounds.width, QuoteCardEditorLayout.canvasSize.width)
        XCTAssertEqual(controller.cardView.bounds.height, QuoteCardEditorLayout.canvasSize.height, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(before.cgImage).width, 622)
        XCTAssertEqual(before.size, after.size)
        XCTAssertEqual(before.scale, after.scale)
        XCTAssertEqual(before.cgImage?.width, after.cgImage?.width)
        XCTAssertEqual(before.cgImage?.height, after.cgImage?.height)
        // 미리보기 컨테이너만 축소하며 실제 출력 뷰의 transform은 변하지 않는다.
        XCTAssertEqual(controller.cardView.transform, .identity)
        XCTAssertLessThan(try XCTUnwrap(controller.cardView.superview).transform.a, 1)
    }

    func test_logoBackgroundColorAndMasks_surviveRepeatedResizing() throws {
        let controller = makeEditor()
        resize(controller, to: CGSize(width: 375, height: 812))
        let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 60)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 60))
        }
        controller.applyBackgroundImage(image, dominantColor: .red)
        controller.removeLogoButton.sendActions(for: .touchUpInside)
        controller.colorSyncButton.sendActions(for: .touchUpInside)
        controller.view.layoutIfNeeded()
        let blurs = controller.cardView.subviews.compactMap { $0 as? UIVisualEffectView }
        XCTAssertEqual(blurs.count, 2)
        let masks = try blurs.map { try XCTUnwrap($0.layer.mask) }
        let labelFrames = controller.cardView.subviews.compactMap { $0 as? UIStackView }.map(\.frame)
        for size in [CGSize(width: 760, height: 300), CGSize(width: 320, height: 480), CGSize(width: 375, height: 812)] {
            resize(controller, to: size)
            XCTAssertTrue(controller.logoImageView.isHidden)
            XCTAssertTrue(controller.backgroundImageView.image === image)
            XCTAssertFalse(controller.backgroundImageView.isHidden)
            XCTAssertEqual(controller.colorSyncButton.accessibilityValue, "켜짐")
            XCTAssertEqual(controller.cardView.subviews.compactMap { $0 as? UIStackView }.map(\.frame), labelFrames)
            for (blur, mask) in zip(blurs, masks) { XCTAssertTrue(blur.layer.mask === mask) }
        }
    }

    func test_exportUsesCurrentDisplayScale_andPopoverAnchorsCurrentShareButton() {
        let controller = makeEditor()
        for scale: CGFloat in [2, 3] {
            controller.cardView.traitOverrides.displayScale = scale
            controller.cardView.updateTraitsIfNeeded()
            resize(controller, to: CGSize(width: 760, height: 300))
            XCTAssertEqual(controller.renderedCardImage().cgImage?.width, Int(311 * scale))
        }
        let activity = controller.makeShareController()
        XCTAssertTrue(activity.popoverPresentationController?.sourceView === controller.saveButton)
        XCTAssertEqual(activity.popoverPresentationController?.sourceRect, controller.saveButton.bounds)
    }

    func test_scaledPreview_keepsRenderedPixelsAtFullResolution() throws {
        let defaults = UserDefaults.standard
        let tutorial = defaults.object(forKey: "tutorial.cardEditor")
        defaults.set(true, forKey: "tutorial.cardEditor")
        defer { defaults.set(tutorial, forKey: "tutorial.cardEditor") }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let host = UIViewController()
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        let controller = makeEditor()
        host.addChild(controller)
        host.view.addSubview(controller.view)
        controller.didMove(toParent: host)
        resize(controller, to: CGSize(width: 375, height: 750))
        let before = controller.renderedCardImage()
        resize(controller, to: CGSize(width: 375, height: 350))
        let after = controller.renderedCardImage()
        XCTAssertEqual(before.pngData(), after.pngData())
        for (name, image) in [("원본 미리보기 출력", before), ("축소 미리보기 출력", after)] {
            let attachment = XCTAttachment(image: image)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        for (name, size) in [("세로 편집 화면", CGSize(width: 375, height: 750)),
                             ("펼친 세로 편집 화면", CGSize(width: 650, height: 900)),
                             ("낮은 가로 편집 화면", CGSize(width: 760, height: 300)),
                             ("좁은 편집 화면", CGSize(width: 260, height: 400))] {
            resize(controller, to: size)
            let image = UIGraphicsImageRenderer(size: size).image { _ in
                controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        resize(controller, to: CGSize(width: 200, height: 240))
        let toolbar = try XCTUnwrap(controller.view.subviews.compactMap { $0 as? UIScrollView }.first)
        toolbar.contentOffset.y = 80
        resize(controller, to: CGSize(width: 760, height: 300))
        XCTAssertEqual(toolbar.contentOffset, .zero)
    }

    private func makeEditor() -> QuoteCardEditorViewController {
        let sentence = Sentence(id: UUID(), bookISBN: "test", sentence: "매일 한 줄씩 모아 나만의 책장을 채웁니다.",
                                page: 42, emotion: .joy, memo: nil, date: Date())
        let controller = QuoteCardEditorViewController(sentence: sentence, bookTitle: "테스트 도서")
        controller.loadViewIfNeeded()
        return controller
    }

    private func resize(_ controller: QuoteCardEditorViewController, to size: CGSize) {
        controller.view.frame = CGRect(origin: .zero, size: size)
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        controller.viewDidLayoutSubviews()
    }
}
