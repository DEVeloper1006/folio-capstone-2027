import Foundation
import PencilKit
import UIKit
import Vision

struct RecognitionCandidate: Sendable, Codable, Equatable {
    let text: String
    let confidence: Double?
}

struct RecognitionResult: Sendable {
    let text: String
    let latex: String
    let confidence: Double?
    let candidates: [RecognitionCandidate]
    let debugImagePNG: Data?
    let durationMilliseconds: Int

    init(
        text: String,
        latex: String,
        confidence: Double?,
        candidates: [RecognitionCandidate] = [],
        debugImagePNG: Data? = nil,
        durationMilliseconds: Int = 0
    ) {
        self.text = text
        self.latex = latex
        self.confidence = confidence
        self.candidates = candidates
        self.debugImagePNG = debugImagePNG
        self.durationMilliseconds = durationMilliseconds
    }
}

protocol RecognitionService {
    var identifier: String { get }
    func recognize(inkData: Data, mode: MathMode) async throws -> RecognitionResult
}

extension RecognitionService { var identifier: String { "custom" } }

enum RecognitionError: LocalizedError {
    case invalidDrawing
    case renderingFailed

    var errorDescription: String? {
        switch self {
        case .invalidDrawing:
            "The row does not contain readable ink."
        case .renderingFailed:
            "The row image could not be rendered."
        }
    }
}

enum RowInkRenderer {
    @MainActor static func renderPNG(
        inkData: Data,
        padding: CGFloat = 16,
        scale: CGFloat = 2
    ) throws -> Data {
        guard let drawing = try? PKDrawing(data: inkData), !drawing.strokes.isEmpty else {
            throw RecognitionError.invalidDrawing
        }

        let sourceBounds = drawing.bounds.insetBy(dx: -padding, dy: -padding).integral
        guard sourceBounds.width > 0, sourceBounds.height > 0 else {
            throw RecognitionError.invalidDrawing
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = min(scale, 2048 / max(sourceBounds.width, sourceBounds.height))
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: sourceBounds.size, format: format)
        var image: UIImage!
        // PencilKit adapts ink to the active appearance. Export against white
        // under a light trait so black strokes cannot become white in dark mode.
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            image = renderer.image { context in
                UIColor.white.setFill()
                context.fill(CGRect(origin: .zero, size: sourceBounds.size))
                drawing.image(from: sourceBounds, scale: format.scale).draw(
                    in: CGRect(origin: .zero, size: sourceBounds.size)
                )
            }
        }

        guard let png = image.pngData() else { throw RecognitionError.renderingFailed }
        return png
    }
}

enum SimpleMathLaTeXNormalizer {
    static func normalize(_ input: String) -> String {
        var output = input
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "×", with: "\\times ")
            .replacingOccurrences(of: "÷", with: "\\div ")
            .replacingOccurrences(of: "≤", with: "\\le ")
            .replacingOccurrences(of: "≥", with: "\\ge ")
            .replacingOccurrences(of: "≠", with: "\\ne ")
            .replacingOccurrences(of: "π", with: "\\pi ")
            .replacingOccurrences(of: "∞", with: "\\infty ")
            .replacingOccurrences(of: "√", with: "\\sqrt{}")

        let superscripts: [Character: Character] = [
            "⁰": "0", "¹": "1", "²": "2", "³": "3", "⁴": "4",
            "⁵": "5", "⁶": "6", "⁷": "7", "⁸": "8", "⁹": "9",
        ]
        var normalized = ""
        var exponent = ""
        for character in output {
            if let digit = superscripts[character] {
                exponent.append(digit)
            } else {
                if !exponent.isEmpty {
                    normalized += "^{\(exponent)}"
                    exponent = ""
                }
                normalized.append(character)
            }
        }
        if !exponent.isEmpty { normalized += "^{\(exponent)}" }

        output = normalized
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// A free, fully on-device baseline. Vision is text-oriented rather than a
/// dedicated handwritten-math model, but it is useful for validating that row
/// segmentation and recognition are wired together correctly.
struct VisionMathRecognitionService: RecognitionService {
    let identifier = "vision"
    func recognize(inkData: Data, mode: MathMode) async throws -> RecognitionResult {
        let startedAt = Date()
        let png = try await MainActor.run { try RowInkRenderer.renderPNG(inkData: inkData) }
        guard let image = UIImage(data: png), let cgImage = image.cgImage else {
            throw RecognitionError.renderingFailed
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]
        request.customWords = customWords(for: mode)

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
        try handler.perform([request])

        let observations = (request.results ?? []).sorted { lhs, rhs in
            let yDifference = lhs.boundingBox.midY - rhs.boundingBox.midY
            if abs(yDifference) > 0.05 { return yDifference > 0 }
            return lhs.boundingBox.minX < rhs.boundingBox.minX
        }
        let candidates = rowCandidates(from: observations)
        let best = candidates.first ?? RecognitionCandidate(text: "", confidence: 0)

        return RecognitionResult(
            text: best.text,
            latex: SimpleMathLaTeXNormalizer.normalize(best.text),
            confidence: best.confidence,
            candidates: candidates,
            debugImagePNG: png,
            durationMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1_000)
        )
    }

    private func rowCandidates(from observations: [VNRecognizedTextObservation]) -> [RecognitionCandidate] {
        guard !observations.isEmpty else { return [] }
        return (0..<3).compactMap { rank in
            let pieces = observations.compactMap { observation -> VNRecognizedText? in
                let choices = observation.topCandidates(rank + 1)
                return choices.indices.contains(rank) ? choices[rank] : choices.first
            }
            guard !pieces.isEmpty else { return nil }
            let confidence = pieces.reduce(0.0) { $0 + Double($1.confidence) } / Double(pieces.count)
            return RecognitionCandidate(
                text: pieces.map(\.string).joined(separator: " "),
                confidence: confidence
            )
        }
    }

    private func customWords(for mode: MathMode) -> [String] {
        switch mode {
        case .calc:
            ["sin", "cos", "tan", "lim", "ln", "log", "dx", "dy"]
        case .linalg:
            ["det", "rank", "span", "null", "eigenvalue"]
        case .proof:
            ["therefore", "assume", "given", "iff"]
        }
    }
}

final class MockRecognitionService: RecognitionService {
    func recognize(inkData: Data, mode: MathMode) async throws -> RecognitionResult {
        let strokeCount = PKStrokeProvider().strokes(from: inkData).count
        let description = "Handwritten step (\(strokeCount) strokes)"
        return RecognitionResult(
            text: description,
            latex: "\\text{\(description)}",
            confidence: 0.4
        )
    }
}
