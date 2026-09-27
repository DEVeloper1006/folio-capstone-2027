import PencilKit

struct StrokePoint {
    let location: CGPoint
    let force: CGFloat
    let timestamp: TimeInterval
}

protocol StrokeProvider {
    func strokes(from drawingData: Data) -> [[StrokePoint]]
}

struct PKStrokeProvider: StrokeProvider {
    func strokes(from drawingData: Data) -> [[StrokePoint]] {
        guard let drawing = try? PKDrawing(data: drawingData) else { return [] }
        return drawing.strokes.map { stroke in
            let path = stroke.path
            return (0..<path.count).map { i in
                let point = path[i]
                return StrokePoint(
                    location: point.location,
                    force: point.force,
                    timestamp: point.timeOffset
                )
            }
        }
    }
}
