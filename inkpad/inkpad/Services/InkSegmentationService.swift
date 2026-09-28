import Foundation
import PencilKit

struct InkRegion: Sendable {
    let bounds: CGRect
    let inkData: Data
    let strokeFingerprints: [String]

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

    func regions(in drawingData: Data) -> [InkRegion] {
        guard let drawing = try? PKDrawing(data: drawingData) else { return [] }
        let strokes = drawing.strokes.filter { $0.ink.inkType != .marker }
        guard !strokes.isEmpty else { return [] }

        var groups = DisjointSet(count: strokes.count)
        for left in strokes.indices {
            for right in strokes.indices where right > left {
                if shouldGroup(strokes[left].renderBounds, strokes[right].renderBounds) {
                    groups.union(left, right)
                }
            }
        }

        var clusters: [Int: [PKStroke]] = [:]
        for index in strokes.indices {
            clusters[groups.find(index), default: []].append(strokes[index])
        }

        return clusters.values.compactMap { cluster in
            guard let first = cluster.first else { return nil }
            let bounds = cluster.dropFirst().reduce(first.renderBounds) { $0.union($1.renderBounds) }
            return InkRegion(
                bounds: bounds,
                inkData: PKDrawing(strokes: cluster).dataRepresentation(),
                strokeFingerprints: cluster.map(Self.fingerprint(for:))
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
        var hash: UInt64 = 14_695_981_039_346_656_037
        func combine(_ value: Int64) {
            hash ^= UInt64(bitPattern: value)
            hash &*= 1_099_511_628_211
        }

        let bounds = stroke.renderBounds
        combine(Int64((bounds.minX * 10).rounded()))
        combine(Int64((bounds.minY * 10).rounded()))
        combine(Int64((bounds.width * 10).rounded()))
        combine(Int64((bounds.height * 10).rounded()))
        combine(Int64(stroke.path.count))

        guard stroke.path.count > 0 else { return String(hash, radix: 16) }
        let sampleIndices = Set([0, stroke.path.count / 2, stroke.path.count - 1])
        for index in sampleIndices.sorted() {
            let point = stroke.path[index]
            combine(Int64((point.location.x * 10).rounded()))
            combine(Int64((point.location.y * 10).rounded()))
        }
        return String(hash, radix: 16)
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
