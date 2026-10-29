import Foundation
import CoreGraphics

public enum InputKind: String, Codable, Sendable { case pointer, pencil, touch }
public struct InkPoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var time: Double
    public var pressure: Double
    public var azimuth: Double?
    public var altitude: Double?
    public init(x: Double, y: Double, time: Double = 0, pressure: Double = 0.5, azimuth: Double? = nil, altitude: Double? = nil) {
        self.x = x; self.y = y; self.time = time; self.pressure = pressure
        self.azimuth = azimuth; self.altitude = altitude
    }
    public var location: CGPoint { CGPoint(x: x, y: y) }
}
public struct InkStroke: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var points: [InkPoint]
    public var width: Double
    public var color: String
    public var input: InputKind
    public init(id: UUID = UUID(), points: [InkPoint], width: Double = 2.6, color: String = "#274a73", input: InputKind = .pointer) {
        self.id = id; self.points = points; self.width = width; self.color = color; self.input = input
    }
    public var bounds: CGRect {
        guard let first = points.first else { return .null }
        var left = first.x, right = first.x, top = first.y, bottom = first.y
        for p in points { left = min(left, p.x); right = max(right, p.x); top = min(top, p.y); bottom = max(bottom, p.y) }
        return CGRect(x: left, y: top, width: max(0.1, right-left), height: max(0.1, bottom-top))
    }
    public var length: Double { zip(points, points.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) } }
}
public struct AcceptedExpression: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID = UUID()
    public var latex: String
    public var provider: String
    public var createdAt: Date = Date()
    public var sourceStrokes: [InkStroke]
    public init(latex: String, provider: String, sourceStrokes: [InkStroke]) { self.latex = latex; self.provider = provider; self.sourceStrokes = sourceStrokes }
}
public struct InkDocument: Codable, Identifiable, Equatable, Sendable {
    public var version: Int = 1
    public var id: UUID = UUID()
    public var title: String = "Untitled notebook"
    public var updatedAt: Date = Date()
    public var canvasWidth: Double = 1000
    public var canvasHeight: Double = 1200
    public var strokes: [InkStroke] = []
    public var pencilKitData: Data?
    public var expressions: [AcceptedExpression] = []
    public init(title: String = "Untitled notebook") { self.title = title }
    public var canvasSize: CGSize { CGSize(width: canvasWidth, height: canvasHeight) }
    public func validated() throws -> InkDocument {
        guard version == 1, title.count <= 200, canvasWidth == 1000, canvasHeight == 1200, strokes.count <= 2000, expressions.count <= 200, (pencilKitData?.count ?? 0) <= 10_000_000 else { throw InkError.invalidDocument }
        func validateStrokes(_ values: [InkStroke]) throws {
            guard values.count <= 2000, Set(values.map(\.id)).count == values.count, values.reduce(0, { $0 + $1.points.count }) <= 100_000 else { throw InkError.tooMuchInk }
            for stroke in values {
                guard !stroke.points.isEmpty, stroke.points.count <= 10_000, stroke.width.isFinite, (0.5...20).contains(stroke.width), stroke.color.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil else { throw InkError.invalidDocument }
                var previousTime = 0.0
                for point in stroke.points {
                    guard point.x.isFinite, point.y.isFinite, point.time.isFinite, point.pressure.isFinite,
                          (0...canvasWidth).contains(point.x), (0...canvasHeight).contains(point.y), (0...1).contains(point.pressure), point.time >= previousTime,
                          point.azimuth.map({ $0.isFinite }) ?? true, point.altitude.map({ $0.isFinite }) ?? true else { throw InkError.invalidDocument }
                    previousTime = point.time
                }
            }
        }
        try validateStrokes(strokes)
        guard Set(expressions.map(\.id)).count == expressions.count else { throw InkError.invalidDocument }
        for expression in expressions {
            guard expression.latex.count <= 20_000, expression.provider.count <= 200 else { throw InkError.invalidDocument }
            try validateStrokes(expression.sourceStrokes)
        }
        return self
    }
    public static func decode(_ data: Data) throws -> InkDocument {
        guard data.count <= 25_000_000 else { throw InkError.tooMuchInk }
        return try JSONDecoder().decode(InkDocument.self, from: data).validated()
    }
    public func encoded() throws -> Data { try JSONEncoder().encode(validated()) }
}
public enum InkError: LocalizedError {
    case invalidDocument, tooMuchInk, emptySelection
    public var errorDescription: String? {
        switch self {
        case .invalidDocument: return "This drawing contains unsupported or invalid data. The original file has not been changed."
        case .tooMuchInk: return "This page is full. Start a new notebook to keep drawing."
        case .emptySelection: return "Draw an expression or select some ink first."
        }
    }
}
