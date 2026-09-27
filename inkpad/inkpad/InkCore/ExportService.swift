import PencilKit
import UIKit

enum ExportService {
    static func renderPNG(drawing: PKDrawing, background: PageBackgroundStyle, size: CGSize, scale: CGFloat = 2.0) -> Data? {
        renderImage(drawing: drawing, background: background, size: size, scale: scale)?.pngData()
    }

    static func renderPDF(drawing: PKDrawing, background: PageBackgroundStyle, size: CGSize) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: size))
        return renderer.pdfData { ctx in
            ctx.beginPage()
            if let cgContext = UIGraphicsGetCurrentContext() {
                drawBackground(background, in: CGRect(origin: .zero, size: size), context: cgContext)
            }
            let image = drawing.image(from: CGRect(origin: .zero, size: size), scale: 2.0)
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private static func renderImage(drawing: PKDrawing, background: PageBackgroundStyle, size: CGSize, scale: CGFloat) -> UIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            UIColor(red: 0.957, green: 0.949, blue: 0.926, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            drawBackground(background, in: CGRect(origin: .zero, size: size), context: ctx.cgContext)
            let drawingImage = drawing.image(from: CGRect(origin: .zero, size: size), scale: scale)
            drawingImage.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private static func drawBackground(_ style: PageBackgroundStyle, in rect: CGRect, context: CGContext) {
        let gridColor = UIColor(red: 0.871, green: 0.851, blue: 0.808, alpha: 1)

        switch style {
        case .blank:
            return
        case .dot:
            let spacing: CGFloat = 28
            let radius: CGFloat = 1.2
            context.setFillColor(gridColor.cgColor)
            var y: CGFloat = spacing
            while y < rect.height {
                var x: CGFloat = spacing
                while x < rect.width {
                    context.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
                    x += spacing
                }
                y += spacing
            }
        case .lined:
            let spacing: CGFloat = 32
            let topMargin: CGFloat = 80
            context.setStrokeColor(gridColor.withAlphaComponent(0.5).cgColor)
            context.setLineWidth(0.5)
            var y = topMargin
            while y < rect.height {
                context.move(to: CGPoint(x: 0, y: y))
                context.addLine(to: CGPoint(x: rect.width, y: y))
                y += spacing
            }
            context.strokePath()
        case .grid:
            let spacing: CGFloat = 32
            context.setStrokeColor(gridColor.withAlphaComponent(0.5).cgColor)
            context.setLineWidth(0.5)
            var y: CGFloat = 0
            while y < rect.height {
                context.move(to: CGPoint(x: 0, y: y))
                context.addLine(to: CGPoint(x: rect.width, y: y))
                y += spacing
            }
            var x: CGFloat = 0
            while x < rect.width {
                context.move(to: CGPoint(x: x, y: 0))
                context.addLine(to: CGPoint(x: x, y: rect.height))
                x += spacing
            }
            context.strokePath()
        }
    }
}
