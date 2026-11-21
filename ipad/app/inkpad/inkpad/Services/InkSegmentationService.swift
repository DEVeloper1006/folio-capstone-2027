/* Groups handwritten expressions while reserving paired-bracket matrices as complete, isolated regions. */
import Foundation
import PencilKit
import CryptoKit

struct InkRegion: Sendable {
    let bounds: CGRect
    let inkData: Data
    let strokeFingerprints: [String]
    var isBoundedMatrix:Bool=false

    var fingerprint: String {
        strokeFingerprints.sorted().joined(separator: "|")
    }
}

protocol InkSegmenting {
    func regions(in drawingData: Data) -> [InkRegion]
}

struct SpatialInkSegmenter: InkSegmenting {
    private let maximumHorizontalGap: CGFloat = 48
    private let maximumVerticalGap: CGFloat = 24

    /// Preserve matrix boundaries before applying the existing expression proximity rules.
    func regions(in drawingData: Data) -> [InkRegion] {
        guard let drawing = try? PKDrawing(data: drawingData) else { return [] }
        let strokes = drawing.strokes.filter { $0.ink.inkType != .marker }
        guard !strokes.isEmpty else { return [] }

        let matrices=MatrixInkLayout.detect(in:strokes,extractCells:false)
        var ownership:[Int:Int]=[:]
        for (matrixID,matrix) in matrices.enumerated() {
            for index in matrix.strokeIndices { ownership[index]=matrixID }
        }
        var groups = DisjointSet(count: strokes.count)
        for left in strokes.indices {
            for right in strokes.indices where right > left {
                // A bracketed matrix owns its strokes, even across large row/column gaps.
                // Do not let ordinary proximity pull neighboring exercises into that crop.
                if let owner=ownership[left],owner==ownership[right] {
                    groups.union(left,right)
                } else if ownership[left]==nil && ownership[right]==nil && shouldGroup(strokes[left].renderBounds, strokes[right].renderBounds) {
                    groups.union(left, right)
                }
            }
        }

        var clusters: [Int: [Int]] = [:]
        for index in strokes.indices {
            clusters[groups.find(index), default: []].append(index)
        }

        return clusters.values.compactMap { indices in
            let cluster=indices.map { strokes[$0] }
            guard let first = cluster.first,let firstIndex=indices.first else { return nil }
            let bounds = cluster.dropFirst().reduce(first.renderBounds) { $0.union($1.renderBounds) }
            return InkRegion(
                bounds: bounds,
                inkData: PKDrawing(strokes: cluster).dataRepresentation(),
                strokeFingerprints: cluster.map(Self.fingerprint(for:)),
                isBoundedMatrix:ownership[firstIndex] != nil
            )
        }
        .sorted {
            if abs($0.bounds.minY - $1.bounds.minY) > 8 {
                return $0.bounds.minY < $1.bounds.minY
            }
            return $0.bounds.minX < $1.bounds.minX
        }
    }

    static func drawingFingerprint(_ data: Data) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    private func shouldGroup(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        if lhs.insetBy(dx: -8, dy: -8).intersects(rhs) { return true }

        let horizontalGap = max(0, max(lhs.minX, rhs.minX) - min(lhs.maxX, rhs.maxX))
        let verticalGap = max(0, max(lhs.minY, rhs.minY) - min(lhs.maxY, rhs.maxY))
        let verticalOverlap = overlap(lhs.minY...lhs.maxY, rhs.minY...rhs.maxY)
        let horizontalOverlap = overlap(lhs.minX...lhs.maxX, rhs.minX...rhs.maxX)

        let sameWritingLine = verticalOverlap >= min(lhs.height, rhs.height) * 0.25
            && horizontalGap <= maximumHorizontalGap
        let stackedMath = horizontalOverlap >= min(lhs.width, rhs.width) * 0.3
            && verticalGap <= maximumVerticalGap
        return sameWritingLine || stackedMath
    }

    private func overlap(_ lhs: ClosedRange<CGFloat>, _ rhs: ClosedRange<CGFloat>) -> CGFloat {
        max(0, min(lhs.upperBound, rhs.upperBound) - max(lhs.lowerBound, rhs.lowerBound))
    }

    nonisolated private static func fingerprint(for stroke: PKStroke) -> String {
        // Canonical content, not the native archive (which contains fresh IDs).
        // Include all points and erasure masks, rather than sparse geometry.
        var data = Data()
        func add(_ value: Double) {
            let rounded = (value * 10_000).rounded()
            var bits = (rounded == 0 ? 0.0 : rounded).bitPattern.littleEndian
            withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: stroke.ink.inkType.rawValue.utf8)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        stroke.ink.color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        for value in [red, green, blue, alpha] { add(Double(value)) }
        let t = stroke.transform, b = stroke.renderBounds
        for value in [t.a, t.b, t.c, t.d, t.tx, t.ty, b.minX, b.minY, b.width, b.height] { add(Double(value)) }
        add(Double(stroke.path.count))
        for point in stroke.path {
            for value in [point.location.x, point.location.y, point.size.width, point.size.height,
                          point.force, point.opacity, point.azimuth, point.altitude] { add(Double(value)) }
            add(point.timeOffset)
        }
        if let mask = stroke.mask {
            add(1)
            mask.cgPath.applyWithBlock { element in
                add(Double(element.pointee.type.rawValue))
                let count: Int
                switch element.pointee.type {
                case .moveToPoint, .addLineToPoint: count = 1
                case .addQuadCurveToPoint: count = 2
                case .addCurveToPoint: count = 3
                case .closeSubpath: count = 0
                @unknown default: count = 0
                }
                for index in 0..<count {
                    add(Double(element.pointee.points[index].x)); add(Double(element.pointee.points[index].y))
                }
            }
        } else { add(0) }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

}

private struct DisjointSet {
    private var parents: [Int]

    init(count: Int) {
        parents = Array(0..<count)
    }

    mutating func find(_ value: Int) -> Int {
        if parents[value] != value {
            parents[value] = find(parents[value])
        }
        return parents[value]
    }

    mutating func union(_ lhs: Int, _ rhs: Int) {
        let leftRoot = find(lhs)
        let rightRoot = find(rhs)
        if leftRoot != rightRoot {
            parents[rightRoot] = leftRoot
        }
    }
}
