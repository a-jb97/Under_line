import XCTest
import UIKit
import Vision
@testable import Under_line

@MainActor
final class OCRMarkupViewModelTests: XCTestCase {
    private let lines = [
        CGRect(x: 0.1, y: 0.20, width: 0.8, height: 0.04),
        CGRect(x: 0.1, y: 0.25, width: 0.8, height: 0.04)
    ]

    func test_penAndHighlighterOnNearbyLines_selectUsingTheirOwnVerticalPosition() {
        let pen = stroke(.pen, from: 0.2, to: 0.4, y: 0.255)
        let highlighter = stroke(.highlighter, from: 0.5, to: 0.7, y: 0.255)
        let selection = OCRMarkupViewModel.selectedRanges(in: lines, strokes: [highlighter, pen])

        XCTAssertEqual(Set(selection.keys), [0, 1])
        XCTAssertTrue(selection[0]?.contains(0.3) == true)
        XCTAssertTrue(selection[1]?.contains(0.6) == true)
    }

    func test_highlighterBetweenLines_selectsNothing() {
        let highlighter = stroke(.highlighter, from: 0.2, to: 0.7, y: 0.245)

        XCTAssertTrue(OCRMarkupViewModel.selectedRanges(in: lines, strokes: [highlighter]).isEmpty)
    }

    func test_highlighterInsideOverlappingBounds_selectsClosestLineCenter() {
        let overlappingLines = [lines[0], lines[1].offsetBy(dx: 0, dy: -0.02)]
        let highlighter = stroke(.highlighter, from: 0.2, to: 0.7, y: 0.236)

        let selection = OCRMarkupViewModel.selectedRanges(in: overlappingLines, strokes: [highlighter])

        XCTAssertEqual(Set(selection.keys), [1])
    }

    func test_highlighterAcrossOneWord_extractsOnlyThatWord() throws {
        let text = "Morning sunlight"
        let observations = try recognize(makeImage([text]))
        let observation = try XCTUnwrap(observations.first)
        let candidate = try XCTUnwrap(observation.topCandidates(1).first)
        XCTAssertEqual(candidate.string, text)
        let word = try XCTUnwrap(candidate.string.range(of: "sunlight"))
        let bounds = try XCTUnwrap(candidate.boundingBox(for: word)).boundingBox
        let highlighter = stroke(.highlighter, from: bounds.midX - bounds.width / 4,
                                 to: bounds.midX + bounds.width / 4, y: 1 - observation.boundingBox.midY)

        XCTAssertEqual(OCRMarkupViewModel.selectedText(observations: observations, strokes: [highlighter]), "sunlight")
    }

    func test_markupWithBothTools_resizesClearsAndConfirmsSelection() async throws {
        let suiteName = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let image = makeImage(["Morning sunlight", "Evening breeze"])
        let observations = try recognize(image).sorted { $0.boundingBox.midY > $1.boundingBox.midY }
        XCTAssertEqual(observations.count, 2)
        let firstLine = try XCTUnwrap(observations.first).boundingBox
        let secondLine = try XCTUnwrap(observations.last).boundingBox
        let controller = OCRMarkupViewController(image: image, defaults: defaults)
        let navigation = UINavigationController(rootViewController: controller)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        let host = UIViewController()
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            previousKeyWindow?.makeKey()
        }
        host.present(navigation, animated: false)

        let view = try XCTUnwrap(controller.view)
        let row = try XCTUnwrap(view.subviews.compactMap { $0 as? UIStackView }.first)
        let picker = try XCTUnwrap(row.arrangedSubviews.compactMap { $0 as? UIButton }.first)
        let instructions = try XCTUnwrap(row.arrangedSubviews.compactMap { $0 as? UILabel }.first)
        let status = try XCTUnwrap(view.subviews.compactMap { $0 as? UILabel }.first)
        let photo = try XCTUnwrap(view.subviews.flatMap(\.subviews).compactMap { $0 as? UIImageView }.first)
        let items = controller.navigationItem.trailingItemGroups.flatMap(\.barButtonItems)
        let clear = try XCTUnwrap(items.first { $0.accessibilityIdentifier == "clearOCRButton" })
        let confirm = try XCTUnwrap(items.first { $0.accessibilityIdentifier == "confirmOCRButton" })
        let symbol = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let penIcon = try XCTUnwrap(SystemGlassButtonStyle.icon(UIImage(systemName: "pencil", withConfiguration: symbol)))
        let highlighterIcon = try XCTUnwrap(SystemGlassButtonStyle.icon(UIImage(systemName: "highlighter", withConfiguration: symbol)))

        XCTAssertFalse(picker.isEnabled)
        XCTAssertTrue(picker.showsMenuAsPrimaryAction)
        XCTAssertEqual(picker.accessibilityValue, "기본 펜")
        XCTAssertEqual(picker.configuration?.image, penIcon)
        XCTAssertEqual(instructions.text, "수집할 문장에 밑줄을 그으세요")
        try await waitUntil { picker.isEnabled }
        XCTAssertNil(status.text)
        let originalFrame = view.frame
        for size in [CGSize(width: 320, height: 568), CGSize(width: 744, height: 320)] {
            view.frame.size = size
            view.layoutIfNeeded()
            XCTAssertEqual(picker.bounds.size, CGSize(width: 52, height: 52))
            XCTAssertEqual(instructions.frame.midY, picker.frame.midY, accuracy: 0.5)
            XCTAssertLessThan(instructions.frame.maxX, picker.frame.minX)
            XCTAssertGreaterThanOrEqual(status.frame.minY - row.frame.maxY, 11.5)
        }
        view.frame = originalFrame
        view.layoutIfNeeded()

        try draw(on: photo, in: view, across: firstLine, y: 1 - firstLine.minY + firstLine.height * 0.25)
        XCTAssertTrue(confirm.isEnabled)
        let menuActions = try XCTUnwrap(picker.menu?.children.compactMap { $0 as? UIAction })
        XCTAssertEqual(menuActions.map(\.state), [.on, .off])
        let highlighter = try XCTUnwrap(menuActions.first { $0.title == "형광펜" })
        UIButton(configuration: .plain(), primaryAction: highlighter).sendActions(for: .primaryActionTriggered)
        XCTAssertEqual(picker.accessibilityValue, "형광펜")
        XCTAssertEqual(picker.configuration?.image, highlighterIcon)
        XCTAssertEqual(instructions.text, "수집할 문장 위로 형광펜을 그으세요")
        XCTAssertEqual(picker.menu?.children.compactMap { ($0 as? UIAction)?.state }, [.off, .on])
        try draw(on: photo, in: view, across: secondLine, y: 1 - secondLine.midY)

        view.frame.size = CGSize(width: 744, height: 320)
        view.layoutIfNeeded()
        XCTAssertTrue(confirm.isEnabled)
        try tap(clear)
        XCTAssertFalse(clear.isEnabled)
        XCTAssertFalse(confirm.isEnabled)
        XCTAssertEqual(picker.accessibilityValue, "형광펜")

        try draw(on: photo, in: view, across: secondLine, y: 1 - secondLine.midY)
        var confirmedText: String?
        controller.onConfirm = { confirmedText = $0 }
        try tap(confirm)
        try await waitUntil { confirmedText != nil }
        XCTAssertEqual(confirmedText, "Evening breeze")

        let reopenedDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let reopened = OCRMarkupViewController(image: image, defaults: reopenedDefaults)
        let reopenedRow = try XCTUnwrap(reopened.view.subviews.compactMap { $0 as? UIStackView }.first)
        let reopenedPicker = try XCTUnwrap(reopenedRow.arrangedSubviews.compactMap { $0 as? UIButton }.first)
        let reopenedInstructions = try XCTUnwrap(reopenedRow.arrangedSubviews.compactMap { $0 as? UILabel }.first)
        XCTAssertEqual(reopenedPicker.accessibilityValue, "형광펜")
        XCTAssertEqual(reopenedPicker.configuration?.image, highlighterIcon)
        XCTAssertEqual(reopenedInstructions.text, "수집할 문장 위로 형광펜을 그으세요")
        XCTAssertEqual(reopenedPicker.menu?.children.compactMap { ($0 as? UIAction)?.state }, [.off, .on])

        let pen = try XCTUnwrap(reopenedPicker.menu?.children.first as? UIAction)
        UIButton(configuration: .plain(), primaryAction: pen).sendActions(for: .primaryActionTriggered)
        XCTAssertEqual(reopenedPicker.accessibilityValue, "기본 펜")
        XCTAssertEqual(reopenedPicker.configuration?.image, penIcon)
    }

    private func makeImage(_ lines: [String]) -> UIImage {
        let size = CGSize(width: 560, height: 40 + 100 * lines.count)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            for (index, text) in lines.enumerated() {
                (text as NSString).draw(at: CGPoint(x: 24, y: 34 + 100 * index), withAttributes: [
                    .font: UIFont.systemFont(ofSize: 52), .foregroundColor: UIColor.black
                ])
            }
        }
    }

    private func recognize(_ image: UIImage) throws -> [VNRecognizedTextObservation] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: XCTUnwrap(image.cgImage)).perform([request])
        return try XCTUnwrap(request.results)
    }

    private func draw(on photo: UIImageView, in view: UIView, across line: CGRect, y: CGFloat) throws {
        let point = CGPoint(x: line.minX * photo.bounds.width, y: y * photo.bounds.height)
        let overlay = try XCTUnwrap(view.hitTest(photo.convert(point, to: view), with: nil))
        let touch = TestTouch()
        touch.point = photo.convert(point, to: overlay)
        overlay.touchesBegan([touch], with: nil)
        touch.point = photo.convert(CGPoint(x: line.maxX * photo.bounds.width, y: point.y), to: overlay)
        overlay.touchesMoved([touch], with: nil)
        overlay.touchesEnded([touch], with: nil)
    }

    private func tap(_ item: UIBarButtonItem) throws {
        let action = try XCTUnwrap(item.action)
        XCTAssertTrue(UIApplication.shared.sendAction(action, to: item.target, from: item, for: nil))
    }

    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTFail("Timed out waiting for the markup screen", file: file, line: line)
    }

    private func stroke(_ tool: OCRMarkupStroke.Tool, from start: CGFloat, to end: CGFloat, y: CGFloat) -> OCRMarkupStroke {
        OCRMarkupStroke(tool: tool, points: [CGPoint(x: start, y: y), CGPoint(x: end, y: y)])
    }
}

private final class TestTouch: UITouch {
    var point = CGPoint.zero

    override func location(in view: UIView?) -> CGPoint { point }
}
