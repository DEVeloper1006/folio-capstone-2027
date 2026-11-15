import Foundation

struct LocalMathRecognitionService: RecognitionService {
    let identifier = "local"
    func recognize(inkData: Data, mode: MathMode) async throws -> RecognitionResult {
        let started = ProcessInfo.processInfo.systemUptime
        try Task.checkCancellation()
        let png = try await MainActor.run { try RowInkRenderer.renderPNG(inkData: inkData) }
        let result = try await LocalTexTellerRuntime.shared.recognizePNG(png)
        try Task.checkCancellation()
        guard !result.latex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LocalRecognitionError.invalid("The model returned no readable expression. Try a shorter row.")
        }
        return RecognitionResult(text: result.latex, latex: result.latex, confidence: nil,
            candidates: [.init(text: result.latex, confidence: nil)], debugImagePNG: png,
            durationMilliseconds: Int((ProcessInfo.processInfo.systemUptime - started) * 1000))
    }
}
