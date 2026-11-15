import Foundation
import CoreGraphics

/// Draft structure, not a verified expression. Ink leaves preserve ambiguity.
public indirect enum ShadowNode: Equatable, Sendable {
    case symbol(String, [UUID])
    case ink([InkStroke])
    case row([ShadowNode])
    case fraction(ShadowNode, ShadowNode, UUID)
    case hole

    public var latex: String? {
        switch self {
        case .symbol(let value, _): return value
        case .ink, .hole: return nil
        case .row(let nodes):
            let values = nodes.compactMap(\.latex)
            return values.count == nodes.count ? values.joined(separator: " ") : nil
        case .fraction(let top, let bottom, _):
            guard let a = top.latex, let b = bottom.latex else { return nil }
            return "\\frac{\(a)}{\(b)}"
        }
    }
}

public struct ShadowRegion: Identifiable, Equatable, Sendable {
    public var id: UUID { strokes[0].id }
    public var strokes: [InkStroke]
    public var node: ShadowNode
    public var bounds: CGRect { StrokeGeometry.bounds(of: strokes) }
}

public struct InkExample: Codable, Sendable {
    public var latex: String
    public var strokes: [InkStroke]
    public init(latex: String, strokes: [InkStroke]) { self.latex = latex; self.strokes = strokes }
}

/// A deliberately small geometric recognizer plus writer-supplied templates.
/// Unknown shapes remain ink. Scores are distances, not calibrated probabilities.
public struct ShadowRecognizer: Sendable {
    public var examples: [InkExample]
    public init(examples: [InkExample] = []) { self.examples = examples }

    public func regions(_ strokes: [InkStroke], previous: [ShadowRegion] = []) -> [ShadowRegion] {
        var groups: [[InkStroke]] = []
        // Scale the neighborhood to handwriting size; fixed pixels split large
        // superscripts and detached dots into separate expressions.
        let heights = strokes.map { $0.bounds.height }.filter { $0 > 8 }.sorted()
        let neighborhood = max(28, min(100, (heights.isEmpty ? 0 : heights[heights.count / 2]) * 0.6))
        // Connected vertical neighborhoods keep fractions together. This is a
        // prototype row segmenter, not a general multi-line layout model.
        for stroke in strokes where !stroke.points.isEmpty {
            var group = [stroke]
            var i = 0
            while i < groups.count {
                let a = StrokeGeometry.bounds(of: group).insetBy(dx: 0, dy: -neighborhood)
                let b = StrokeGeometry.bounds(of: groups[i])
                if a.minY <= b.maxY && a.maxY >= b.minY {
                    group += groups.remove(at: i)
                    i = 0
                } else { i += 1 }
            }
            groups.append(group)
        }
        return groups.sorted { StrokeGeometry.bounds(of: $0).minY < StrokeGeometry.bounds(of: $1).minY }
            .map { group in
                let sorted = group.sorted { $0.id.uuidString < $1.id.uuidString }
                if let cached = previous.first(where: { $0.strokes == sorted }) { return cached }
                return ShadowRegion(strokes: sorted, node: parse(group))
            }
    }

    public func parse(_ strokes: [InkStroke], depth: Int = 0) -> ShadowNode {
        guard !strokes.isEmpty else { return .hole }
        guard depth < 8 else { return .ink(strokes) }
        // Only interpret a bar as a fraction when there is evidence on both sides.
        for bar in strokes.sorted(by: { $0.bounds.width > $1.bounds.width }) where horizontal(bar) {
            let b = bar.bounds
            let others = strokes.filter { $0.id != bar.id }
            let top = others.filter { $0.bounds.maxY < b.midY - 3 && abs($0.bounds.midX - b.midX) < b.width / 2 + 8 }
            let bottom = others.filter { $0.bounds.minY > b.midY + 3 && abs($0.bounds.midX - b.midX) < b.width / 2 + 8 }
            if !top.isEmpty && !bottom.isEmpty && top.count + bottom.count == others.count {
                return .fraction(parse(top, depth: depth + 1), parse(bottom, depth: depth + 1), bar.id)
            }
        }
        // Group overlapping x extents into symbols; preserve unknown groups intact.
        var groups: [[InkStroke]] = []
        for s in strokes.sorted(by: { $0.bounds.minX < $1.bounds.minX }) {
            if let last = groups.last, s.bounds.minX <= StrokeGeometry.bounds(of: last).maxX + 3 {
                groups[groups.count - 1].append(s)
            } else { groups.append([s]) }
        }
        return .row(groups.map(classify))
    }

    private func horizontal(_ s: InkStroke) -> Bool {
        s.bounds.width > 14 && s.bounds.height < max(4, s.bounds.width * 0.09) && s.length < s.bounds.width * 1.15
    }

    private func classify(_ strokes: [InkStroke]) -> ShadowNode {
        let ids = strokes.map(\.id)
        if strokes.count == 2, strokes.allSatisfy(horizontal) {
            let a = strokes[0].bounds, b = strokes[1].bounds
            if abs(a.midY - b.midY) > 4 && abs(a.midY - b.midY) < max(a.width, b.width) * 0.65 && abs(a.midX - b.midX) < 8 {
                return .symbol("=", ids)
            }
        }
        if strokes.count == 2 {
            let h = strokes.first(where: horizontal)
            let v = strokes.first { $0.bounds.height > 14 && $0.bounds.width < 5 }
            if let h, let v, h.id != v.id, h.bounds.insetBy(dx: -3, dy: -3).intersects(v.bounds) {
                return .symbol("+", ids)
            }
        }
        let candidates = examples.filter { $0.strokes.count == strokes.count }.map { ($0.latex, distance(strokes, $0.strokes)) }.sorted { $0.1 < $1.1 }
        if let best = candidates.first, best.1 < 0.10 {
            let next = candidates.first { $0.0 != best.0 }?.1 ?? 1
            if next - best.1 > 0.035 { return .symbol(best.0, ids) }
        }
        // A lone horizontal line stays ink: minus and unfinished fraction are ambiguous.
        return .ink(strokes)
    }

    private func distance(_ a: [InkStroke], _ b: [InkStroke]) -> Double {
        func cloud(_ strokes: [InkStroke]) -> [CGPoint] {
            let box = StrokeGeometry.bounds(of: strokes)
            let scale = max(box.width, box.height, 1)
            let all = strokes.flatMap { s -> [CGPoint] in
                guard let first = s.points.first else { return [] }
                var samples = [first.location]
                let strideSize = max(1, s.points.count / 64)
                let reduced = stride(from: 0, to: s.points.count, by: strideSize).map { s.points[$0] } + [s.points.last!]
                for (p, q) in zip(reduced, reduced.dropFirst()) {
                    let count = min(128, max(1, Int(hypot(q.x-p.x, q.y-p.y) / scale * 48)))
                    for i in 1...count {
                        let t = Double(i) / Double(count)
                        samples.append(CGPoint(x: p.x + (q.x-p.x)*t, y: p.y + (q.y-p.y)*t))
                    }
                }
                return samples.map { CGPoint(x: ($0.x-box.midX)/scale, y: ($0.y-box.midY)/scale) }
            }
            guard all.count > 64 else { return all }
            return (0..<64).map { all[$0 * (all.count - 1) / 63] }
        }
        let x = cloud(a), y = cloud(b)
        guard !x.isEmpty, !y.isEmpty else { return 1 }
        func directed(_ p: [CGPoint], _ q: [CGPoint]) -> Double {
            p.reduce(0) { total, point in total + (q.map { hypot(point.x-$0.x, point.y-$0.y) }.min() ?? 1) } / Double(p.count)
        }
        return (directed(x,y) + directed(y,x)) / 2
    }
}

/// Tokens include content, not just IDs: moving or erasing invalidates replies.
public struct RecognitionTicket: Equatable, Sendable {
    public let documentID: UUID
    public let revision: Int
    public let strokes: [InkStroke]
    public init(documentID: UUID, revision: Int, strokes: [InkStroke]) {
        self.documentID = documentID; self.revision = revision; self.strokes = strokes
    }
    public func matches(documentID: UUID, revision: Int, strokes: [InkStroke]) -> Bool {
        self.documentID == documentID && self.revision == revision && self.strokes == strokes
    }
}
