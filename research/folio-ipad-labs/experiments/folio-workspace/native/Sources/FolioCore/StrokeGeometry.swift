import Foundation
import CoreGraphics

public enum StrokeGeometry {
    public static func bounds(of strokes: [InkStroke]) -> CGRect { strokes.reduce(CGRect.null) { $0.union($1.bounds) } }
    public static func distance(_ point: CGPoint, to stroke: InkStroke) -> Double {
        guard let first = stroke.points.first else { return .infinity }
        var result = hypot(point.x-first.x, point.y-first.y)
        for (a,b) in zip(stroke.points, stroke.points.dropFirst()) {
            let dx=b.x-a.x, dy=b.y-a.y, squared=dx*dx+dy*dy
            let t = squared > 0 ? min(1,max(0,((point.x-a.x)*dx+(point.y-a.y)*dy)/squared)) : 0
            result = min(result, hypot(point.x-(a.x+t*dx), point.y-(a.y+t*dy)))
        }
        return result
    }
    public static func intersects(_ stroke: InkStroke, rect: CGRect) -> Bool {
        guard stroke.bounds.insetBy(dx: -1, dy: -1).intersects(rect) else { return false }
        if stroke.points.contains(where: { rect.contains($0.location) }) { return true }
        for (a,b) in zip(stroke.points, stroke.points.dropFirst()) {
            let dx=b.x-a.x, dy=b.y-a.y
            var lo=0.0, hi=1.0, hit=true
            for (p,q) in [(-dx,a.x-rect.minX),(dx,rect.maxX-a.x),(-dy,a.y-rect.minY),(dy,rect.maxY-a.y)] {
                if abs(p)<1e-10 { if q<0 {hit=false;break} }
                else if p<0 {lo=max(lo,q/p)} else {hi=min(hi,q/p)}
                if lo>hi {hit=false;break}
            }
            if hit { return true }
        }
        return false
    }
    public static func translated(_ strokes: [InkStroke], by offset: CGSize, within size: CGSize, newIDs: Bool = false) -> [InkStroke] {
        let bounds = bounds(of: strokes)
        guard !bounds.isNull else { return strokes }
        let dx=min(size.width-bounds.maxX,max(-bounds.minX,offset.width))
        let dy=min(size.height-bounds.maxY,max(-bounds.minY,offset.height))
        return strokes.map { s in
            var copy=s
            if newIDs { copy.id=UUID() }
            copy.points=s.points.map { p in var value=p;value.x+=dx;value.y+=dy;return value }
            return copy
        }
    }
}
public struct StrokeAnalysis: Sendable {
    public var strokeCount: Int
    public var pointCount: Int
    public var length: Double
    public var duration: Double
    public var bounds: CGRect
    public var fractionBars: [Int]
    public var rows: [CGRect]
    public init(_ strokes: [InkStroke]) {
        strokeCount=strokes.count;pointCount=strokes.reduce(0) { $0+$1.points.count }
        length=strokes.reduce(0) { $0+$1.length }
        duration=strokes.reduce(0) { $0+($1.points.last?.time ?? 0) }
        bounds=StrokeGeometry.bounds(of: strokes)
        fractionBars=strokes.indices.filter { i in
            let b=strokes[i].bounds
            guard b.width>18,b.width/max(b.height,1)>6 else { return false }
            let above=strokes.enumerated().contains { j,s in j != i && s.bounds.maxY < b.midY && b.midY-s.bounds.maxY<100 && s.bounds.midX>b.minX-8 && s.bounds.midX<b.maxX+8 }
            let below=strokes.enumerated().contains { j,s in j != i && s.bounds.minY > b.midY && s.bounds.minY-b.midY<100 && s.bounds.midX>b.minX-8 && s.bounds.midX<b.maxX+8 }
            return above && below
        }
        var lines: [CGRect]=[]
        for stroke in strokes.sorted(by: { $0.bounds.midY < $1.bounds.midY }) {
            let b=stroke.bounds
            if let i=lines.firstIndex(where: { $0.insetBy(dx: 0,dy: -16).intersects(CGRect(x: $0.minX,y: b.minY,width: max($0.width,1),height: max(b.height,1))) }) { lines[i]=lines[i].union(b) }
            else { lines.append(b) }
        }
        rows=lines.sorted { $0.minY < $1.minY }
    }
    public var summary: String {
        "\(strokeCount) strokes, \(pointCount) points, \(rows.count) spatial rows, \(fractionBars.count) possible fraction bars. Row grouping and bars are geometric hints, not recognition."
    }
}
