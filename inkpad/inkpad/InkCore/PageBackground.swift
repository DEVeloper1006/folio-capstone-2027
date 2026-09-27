import SwiftUI

enum PageBackgroundStyle: String, Codable, CaseIterable, Identifiable {
    case blank, lined, grid

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .blank: "Blank"
        case .lined: "Lined"
        case .grid: "Grid"
        }
    }
}

struct PageBackgroundView: View {
    let style: PageBackgroundStyle
    let pageSize: CGSize

    private let lineSpacing: CGFloat = 32
    private let lineColor = Color.gray.opacity(0.3)
    private let topMargin: CGFloat = 80

    var body: some View {
        Canvas { context, size in
            switch style {
            case .blank:
                break
            case .lined:
                drawLines(context: context, size: size)
            case .grid:
                drawGrid(context: context, size: size)
            }
        }
        .frame(width: pageSize.width, height: pageSize.height)
    }

    private func drawLines(context: GraphicsContext, size: CGSize) {
        var y = topMargin
        while y < size.height {
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(path, with: .color(lineColor), lineWidth: 0.5)
            y += lineSpacing
        }
    }

    private func drawGrid(context: GraphicsContext, size: CGSize) {
        var y: CGFloat = 0
        while y < size.height {
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(path, with: .color(lineColor), lineWidth: 0.5)
            y += lineSpacing
        }
        var x: CGFloat = 0
        while x < size.width {
            var path = Path()
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(path, with: .color(lineColor), lineWidth: 0.5)
            x += lineSpacing
        }
    }
}
