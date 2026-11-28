import CoreGraphics

struct OCRMarkupStroke {
    enum Tool: CaseIterable {
        case pen
        case highlighter
    }

    let tool: Tool
    var points: [CGPoint]
}
