import SwiftUI

enum PageBackgroundStyle: String, Codable, CaseIterable, Identifiable {
    case dot, grid, lined, blank

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dot: "Dot"
        case .grid: "Grid"
        case .lined: "Lined"
        case .blank: "Blank"
        }
    }
}

struct PageBackgroundView: View {
    let style: PageBackgroundStyle
    let pageSize: CGSize

    var body: some View {
        Canvas { context, size in
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(FolioTheme.paper)
            )
            switch style {
            case .dot:
                drawDots(context: context, size: size)
            case .grid:
                drawGrid(context: context, size: size)
            case .lined:
                drawLines(context: context, size: size)
            case .blank:
                break
            }
        }
        .frame(width: pageSize.width, height: pageSize.height)
    }

    private func drawDots(context: GraphicsContext, size: CGSize) {
        let spacing = FolioTheme.dotSpacing
        let radius = FolioTheme.dotRadius
        let color = FolioTheme.canvasGrid
        var y: CGFloat = spacing
        while y < size.height {
            var x: CGFloat = spacing
            while x < size.width {
                let rect = CGRect(
                    x: x - radius, y: y - radius,
                    width: radius * 2, height: radius * 2
                )
                context.fill(Path(ellipseIn: rect), with: .color(color))
                x += spacing
            }
            y += spacing
        }
    }

    private func drawGrid(context: GraphicsContext, size: CGSize) {
        let spacing: CGFloat = 32
        let color = FolioTheme.canvasGrid.opacity(0.5)
        var y: CGFloat = 0
        while y < size.height {
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(path, with: .color(color), lineWidth: 0.5)
            y += spacing
        }
        var x: CGFloat = 0
        while x < size.width {
            var path = Path()
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(path, with: .color(color), lineWidth: 0.5)
            x += spacing
        }
    }

    private func drawLines(context: GraphicsContext, size: CGSize) {
        let spacing: CGFloat = 32
        let topMargin: CGFloat = 80
        let color = FolioTheme.canvasGrid.opacity(0.5)
        var y = topMargin
        while y < size.height {
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(path, with: .color(color), lineWidth: 0.5)
            y += spacing
        }
    }
}
