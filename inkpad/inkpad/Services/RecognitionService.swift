import Foundation

struct RecognitionResult: Sendable {
    let text: String
    let latex: String
    let confidence: Double
}

protocol RecognitionService {
    func recognize(inkData: Data, mode: MathMode) async throws -> RecognitionResult
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
