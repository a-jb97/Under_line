import UIKit

struct QuoteCardEditorLayout {
    static let canvasSize = CGSize(width: 311, height: 311 * 1.586)

    let previewFrame: CGRect
    let previewScale: CGFloat
    let actionsFrame: CGRect
    let actionFrames: [CGRect]
    let actionsContentSize: CGSize

    init(availableBounds: CGRect, containerSize: CGSize? = nil, containerBounds: CGRect? = nil,
         usesFoldableLayout: Bool = false, showsColorSync: Bool = false) {
        let size = containerSize ?? containerBounds?.size ?? availableBounds.size
        let isLandscape = usesFoldableLayout && size.width > size.height
        let isCompactPortrait = usesFoldableLayout && size.width <= size.height && size.width < 600
        // 가로 펼침과 접힌 화면은 Safe Area 여백까지 포함한 전체 화면을 기준으로 정렬한다.
        let layoutBounds = (isLandscape || isCompactPortrait) ? (containerBounds ?? availableBounds) : availableBounds
        let padding = min(16, layoutBounds.width / 2, layoutBounds.height / 2)
        let area = layoutBounds.insetBy(dx: padding, dy: padding)
        let visibleActions = showsColorSync ? [0, 1, 2, 3] : [0, 1, 3]
        let cellSize = CGSize(width: 64, height: 80)
        var frames = [CGRect](repeating: .zero, count: 4)
        let fitScale: (CGFloat, CGFloat) -> CGFloat = { width, height in
            max(0, min(1, width / Self.canvasSize.width, height / Self.canvasSize.height))
        }

        if isCompactPortrait {
            let contentHeight = CGFloat(visibleActions.count) * cellSize.height + CGFloat(visibleActions.count - 1) * 12
            actionsContentSize = CGSize(width: cellSize.width, height: contentHeight)
            let width = min(cellSize.width, area.width)
            let height = min(contentHeight, area.height)
            actionsFrame = CGRect(x: area.maxX - width - min(2, area.width - width),
                                  y: area.maxY - height, width: width, height: height)
            for (position, index) in visibleActions.enumerated() {
                frames[index] = CGRect(x: 0, y: CGFloat(position) * 92, width: 64, height: 80)
            }

            // 카드는 전체 화면의 중앙을 유지한다. 오른쪽 아래 버튼과 겹치지 않는 최대 크기를 선택한다.
            let horizontalRoom = max(0, 2 * (actionsFrame.minX - 12 - layoutBounds.midX))
            let verticalRoom = max(0, 2 * (actionsFrame.minY - 12 - layoutBounds.midY))
            previewScale = max(fitScale(min(area.width, horizontalRoom), area.height),
                               fitScale(area.width, min(area.height, verticalRoom)))
            let previewSize = CGSize(width: Self.canvasSize.width * previewScale,
                                     height: Self.canvasSize.height * previewScale)
            previewFrame = CGRect(x: layoutBounds.midX - previewSize.width / 2,
                                  y: layoutBounds.midY - previewSize.height / 2,
                                  width: previewSize.width, height: previewSize.height)
        } else if isLandscape {
            let contentWidth = CGFloat(visibleActions.count) * cellSize.width
            actionsContentSize = CGSize(width: contentWidth, height: cellSize.height)
            let toolbarSize = CGSize(width: min(contentWidth, area.width), height: min(cellSize.height, area.height))
            let gap = min(16, max(0, area.width - toolbarSize.width) / 2)
            previewScale = fitScale(max(0, area.width - toolbarSize.width - gap), area.height)
            let previewSize = CGSize(width: Self.canvasSize.width * previewScale,
                                     height: Self.canvasSize.height * previewScale)
            let groupSize = CGSize(width: previewSize.width + gap + toolbarSize.width,
                                   height: max(previewSize.height, toolbarSize.height))
            let group = CGRect(x: area.midX - groupSize.width / 2, y: area.midY - groupSize.height / 2,
                               width: groupSize.width, height: groupSize.height)
            // 카드 오른쪽에 버튼을 한 줄로 두고, 하단을 맞춘 전체 묶음을 중앙에 배치한다.
            previewFrame = CGRect(x: group.minX, y: group.maxY - previewSize.height,
                                  width: previewSize.width, height: previewSize.height)
            actionsFrame = CGRect(x: previewFrame.maxX + gap, y: group.maxY - toolbarSize.height,
                                  width: toolbarSize.width, height: toolbarSize.height)
            for (position, index) in visibleActions.enumerated() {
                frames[index] = CGRect(x: CGFloat(position) * 64, y: 0, width: 64, height: 80)
            }
        } else {
            let contentWidth = max(CGFloat(visibleActions.count) * cellSize.width, area.width - 4)
            actionsContentSize = CGSize(width: contentWidth, height: cellSize.height)
            let toolbarSize = CGSize(width: min(contentWidth, area.width), height: min(cellSize.height, area.height))
            actionsFrame = CGRect(x: area.midX - toolbarSize.width / 2, y: area.maxY - toolbarSize.height,
                                  width: toolbarSize.width, height: toolbarSize.height)
            let previewArea = CGRect(x: area.minX, y: area.minY, width: area.width,
                                     height: max(0, area.height - toolbarSize.height - 12))
            previewScale = fitScale(previewArea.width, previewArea.height)
            let previewSize = CGSize(width: Self.canvasSize.width * previewScale,
                                     height: Self.canvasSize.height * previewScale)
            previewFrame = CGRect(x: previewArea.midX - previewSize.width / 2,
                                  y: previewArea.midY - previewSize.height / 2,
                                  width: previewSize.width, height: previewSize.height)
            for (position, index) in visibleActions.enumerated() {
                // 64pt 셀 안의 52pt 버튼 사이에 기존 12pt 간격을 유지한다.
                frames[index] = CGRect(x: index == 3 ? contentWidth - 64 : CGFloat(position) * 64,
                                       y: 0, width: 64, height: 80)
            }
        }
        actionFrames = frames
    }
}
