import PencilKit
import UIKit

nonisolated struct CanvasExportItem: Sendable {
    let rect: CGRect
    let png: Data
    let isCurrent: Bool
}

enum ExportService {
    static func renderPNG(drawing: PKDrawing, background: PageBackgroundStyle, size: CGSize, scale: CGFloat = 2.0, results: [CanvasExportItem] = []) -> Data? {
        renderImage(drawing: drawing, background: background, size: size, scale: scale, results: results)?.pngData()
    }

    static func renderPDF(drawing: PKDrawing, background: PageBackgroundStyle, size: CGSize, results: [CanvasExportItem] = []) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: size))
        var data = Data()
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
        data = renderer.pdfData { ctx in
            ctx.beginPage()
            if let cgContext = UIGraphicsGetCurrentContext() {
                drawBackground(background, in: CGRect(origin: .zero, size: size), context: cgContext)
            }
            let image = drawing.image(from: CGRect(origin: .zero, size: size), scale: 2.0)
            image.draw(in: CGRect(origin: .zero, size: size))
            drawResults(results)
        }
        }
        return data
    }

    private static func renderImage(drawing: PKDrawing, background: PageBackgroundStyle, size: CGSize, scale: CGFloat, results: [CanvasExportItem]) -> UIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = min(scale, sqrt(16_000_000 / max(1, size.width * size.height)))
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        var image: UIImage?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
        image = renderer.image { ctx in
            UIColor(red: 0.957, green: 0.949, blue: 0.926, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            drawBackground(background, in: CGRect(origin: .zero, size: size), context: ctx.cgContext)
            let drawingImage = drawing.image(from: CGRect(origin: .zero, size: size), scale: scale)
            drawingImage.draw(in: CGRect(origin: .zero, size: size))
            drawResults(results)
        }
        }
        return image
    }

    private static func drawResults(_ results: [CanvasExportItem]) {
        for result in results {
            UIColor.white.setFill(); UIBezierPath(roundedRect: result.rect, cornerRadius: 8).fill()
            UIColor.gray.setStroke(); UIBezierPath(roundedRect: result.rect, cornerRadius: 8).stroke()
            let title = result.isCurrent ? "Result" : "Outdated result"
            (title as NSString).draw(at: CGPoint(x: result.rect.minX + 8, y: result.rect.minY + 8),
                withAttributes: [.font: UIFont.systemFont(ofSize: 11), .foregroundColor: UIColor.black])
            guard let image = UIImage(data: result.png) else { continue }
            let area = CGRect(x: result.rect.minX + 10, y: result.rect.minY + 34, width: result.rect.width - 20, height: result.rect.height - 44)
            let pixels=CGSize(width:CGFloat(image.cgImage?.width ?? 0),height:CGFloat(image.cgImage?.height ?? 0))
            let size=CanvasResultLayout.displaySize(pixels:pixels,available:area.size)
            image.draw(in: CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height))
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
