import CoreGraphics

struct OCRMarkupStroke {
    enum Tool: String, CaseIterable {
        case pen
        case highlighter
    }

    let tool: Tool
    var points: [CGPoint]
}
