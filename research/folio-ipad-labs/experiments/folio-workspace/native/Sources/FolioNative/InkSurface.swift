import SwiftUI
import FolioCore
#if os(iOS)
import PencilKit

struct InkSurface: UIViewRepresentable {
    @ObservedObject var book: Notebook
    func makeCoordinator() -> Coordinator { Coordinator(book) }
    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.delegate = context.coordinator
        canvas.drawingPolicy = .anyInput
        canvas.tool = PKInkingTool(.pen, color: UIColor(red: 0.15, green: 0.29, blue: 0.45, alpha: 1), width: 3)
        canvas.backgroundColor = .white
        canvas.contentSize = CGSize(width: 1000, height: 1200)
        canvas.minimumZoomScale = 0.25; canvas.maximumZoomScale = 2
        canvas.accessibilityLabel = "Handwriting page. Use the PencilKit tools to draw, erase, or select ink."
        context.coordinator.picker.addObserver(canvas)
        DispatchQueue.main.async {
            context.coordinator.picker.setVisible(true, forFirstResponder: canvas)
            canvas.becomeFirstResponder()
            canvas.zoomScale = max(0.25, canvas.bounds.width / 1000)
        }
        return canvas
    }
    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        context.coordinator.book = book
        let desired = book.document.pencilKitData ?? PKDrawing().dataRepresentation()
        if canvas.drawing.dataRepresentation() != desired, let drawing = try? PKDrawing(data: desired) {
            context.coordinator.updating = true
            canvas.drawing = drawing
            context.coordinator.updating = false
        }
    }
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var book: Notebook
        let picker = PKToolPicker()
        var updating = false
        init(_ book: Notebook) { self.book = book }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !updating else { return }
            let previous = book.document.strokes
            let strokes = canvasView.drawing.strokes.map { stroke -> InkStroke in
                let points = stride(from: 0.0, through: Double(max(0, stroke.path.count - 1)), by: 0.5).map { index -> InkPoint in
                    let point = stroke.path.interpolatedPoint(at: CGFloat(index))
                    let location = point.location.applying(stroke.transform)
                    return InkPoint(x: location.x, y: location.y, time: point.timeOffset,
                                    pressure: min(1, max(0, point.force)), azimuth: point.azimuth, altitude: point.altitude)
                }
                var result = InkStroke(points: points, input: .pencil)
                // PencilKit can reorder strokes after lasso edits. Match content, not index.
                if let old = previous.first(where: { $0.points == points }) { result.id = old.id }
                return result
            }
            book.change(strokes: strokes, pencilData: canvasView.drawing.dataRepresentation())
        }
    }
}
#else
struct InkSurface: View {
    @ObservedObject var book: Notebook
    @State private var draft: [InkPoint] = []
    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / 1000
            ZStack(alignment: .topLeading) {
                Color.white
                Canvas { context, _ in
                    for stroke in book.document.strokes + (draft.isEmpty ? [] : [InkStroke(points: draft)]) {
                        var path = Path()
                        for (i, point) in stroke.points.enumerated() {
                            let p = CGPoint(x: point.x * scale, y: point.y * scale)
                            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
                        }
                        if stroke.points.count == 1, let point = stroke.points.first {
                            path.addLine(to: CGPoint(x: point.x * scale + 0.1, y: point.y * scale + 0.1))
                        }
                        context.stroke(path, with: .color(.blue.opacity(0.75)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    }
                }
                if book.document.strokes.isEmpty && draft.isEmpty {
                    Text("Write here.\nYour original ink always stays.").font(.system(size: 24, design: .serif)).foregroundStyle(.secondary).padding(32)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                draft.append(InkPoint(x: min(1000, max(0, value.location.x / scale)), y: min(1200, max(0, value.location.y / scale))))
            }.onEnded { _ in
                if !draft.isEmpty { book.change(strokes: book.document.strokes + [InkStroke(points: draft)]) }
                draft = []
            })
            .accessibilityLabel("Handwriting canvas. Drag to draw. Use the correction field for keyboard input.")
        }
    }
}
#endif

func inkPNG(_ strokes: [InkStroke]) -> Data? {
    let box = StrokeGeometry.bounds(of: strokes).insetBy(dx: -16, dy: -16)
    guard !box.isNull else { return nil }
    let width = max(1, Int(ceil(box.width))), height = max(1, Int(ceil(box.height)))
    guard width <= 1100, height <= 1300,
          let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.translateBy(x: -box.minX, y: CGFloat(height) + box.minY); context.scaleBy(x: 1, y: -1)
    context.setStrokeColor(CGColor(gray: 0.12, alpha: 1)); context.setLineCap(.round)
    for s in strokes {
        context.beginPath(); context.setLineWidth(s.width)
        for (i, p) in s.points.enumerated() {
            if i == 0 { context.move(to: p.location) } else { context.addLine(to: p.location) }
        }
        if s.points.count == 1, let p = s.points.first { context.addLine(to: CGPoint(x: p.x + 0.1, y: p.y + 0.1)) }
        context.strokePath()
    }
    guard let image = context.makeImage() else { return nil }
    #if os(iOS)
    return UIImage(cgImage: image).pngData()
    #else
    return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    #endif
}
