import UIKit

struct CaptureScreenLayout {
    let previewFrame: CGRect
    let controlsFrame: CGRect
    let usesSideControls: Bool

    init(availableBounds: CGRect) {
        let inset = min(12, availableBounds.width / 2, availableBounds.height / 2)
        let area = availableBounds.insetBy(dx: inset, dy: inset)
        usesSideControls = area.width >= 480 && area.height < 500
        if usesSideControls {
            let width = min(184, area.width)
            let gap = min(16, max(0, area.width - width))
            controlsFrame = CGRect(x: area.maxX - width, y: area.minY, width: width, height: area.height)
            previewFrame = CGRect(x: area.minX, y: area.minY, width: max(0, area.width - width - gap), height: area.height)
        } else {
            let height = min(148, area.height * 0.4)
            let gap = min(12, max(0, area.height - height))
            controlsFrame = CGRect(x: area.minX, y: area.maxY - height, width: area.width, height: height)
            previewFrame = CGRect(x: area.minX, y: area.minY, width: area.width, height: max(0, area.height - height - gap))
        }
    }
}
