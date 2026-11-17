import UIKit

struct QuoteCardEditorLayout {
    static let canvasSize = CGSize(width: 311, height: 311 * 1.586)

    let previewFrame: CGRect
    let previewScale: CGFloat
    let actionsFrame: CGRect
    let actionFrames: [CGRect]
    let actionsContentSize: CGSize

    init(availableBounds: CGRect) {
        let padding = min(16, availableBounds.width / 2, availableBounds.height / 2)
        let area = availableBounds.insetBy(dx: padding, dy: padding)
        let usesSideActions = area.width >= 480 && area.height < 640
        let columns = usesSideActions ? 2 : (area.width >= 304 ? 4 : (area.width >= 144 ? 2 : 1))
        let rows = (4 + columns - 1) / columns
        let contentWidth = CGFloat(columns) * 64 + CGFloat(columns - 1) * 16
        let contentHeight = CGFloat(rows) * 80 + CGFloat(rows - 1) * 16
        actionsContentSize = CGSize(width: contentWidth, height: contentHeight)
        actionFrames = (0..<4).map { index in
            CGRect(x: CGFloat(index % columns) * 80, y: CGFloat(index / columns) * 96, width: 64, height: 80)
        }

        let previewArea: CGRect
        if usesSideActions {
            let height = min(contentHeight, area.height)
            actionsFrame = CGRect(x: area.maxX - contentWidth, y: area.midY - height / 2,
                                  width: contentWidth, height: height)
            previewArea = CGRect(x: area.minX, y: area.minY,
                                 width: max(0, area.width - contentWidth - 24), height: area.height)
        } else {
            let height = min(contentHeight, max(0, area.height * 0.65))
            let width = min(contentWidth, area.width)
            actionsFrame = CGRect(x: area.midX - width / 2, y: area.maxY - height, width: width, height: height)
            previewArea = CGRect(x: area.minX, y: area.minY, width: area.width,
                                 height: max(0, area.height - height - 16))
        }
        previewScale = max(0, min(1, previewArea.width / Self.canvasSize.width,
                                 previewArea.height / Self.canvasSize.height))
        let size = CGSize(width: Self.canvasSize.width * previewScale, height: Self.canvasSize.height * previewScale)
        previewFrame = CGRect(x: previewArea.midX - size.width / 2, y: previewArea.midY - size.height / 2,
                              width: size.width, height: size.height)
    }
}
