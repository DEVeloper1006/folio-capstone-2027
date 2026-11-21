/* Recognizes local math, reading clearly bounded matrices cell by cell before rebuilding a reviewable LaTeX grid. */
import Foundation
import PencilKit

struct LocalMathRecognitionService: RecognitionService {
    let identifier = "local"
    /// Keep original crops for diagnostics; bounded matrix grids use independent entry inference.
    func recognize(inkData: Data, mode: MathMode) async throws -> RecognitionResult {
        let started = ProcessInfo.processInfo.systemUptime
        try Task.checkCancellation()
        let png = try await MainActor.run { try RowInkRenderer.renderPNG(inkData: inkData) }
        if let drawing=try? PKDrawing(data:inkData) {
            let strokes=drawing.strokes.filter { $0.ink.inkType != .marker }
            let layouts=MatrixInkLayout.detect(in:strokes)
            if layouts.count==1,let matrix=layouts.first,matrix.strokeIndices.count==strokes.count {
                guard let cells=matrix.cells else {
                    throw LocalRecognitionError.invalid("Matrix bounds found, but the row/column grid is unclear or incomplete. Use aligned entries with clear gaps and review the transcription. Automatic entry recognition supports up to 6 × 6; blank cells are not assumed to be zero.")
                }
                let latex=try await recognizeMatrix(cells)
                return RecognitionResult(text:latex,latex:latex,confidence:nil,
                    candidates:[.init(text:latex,confidence:nil)],debugImagePNG:png,
                    durationMilliseconds:Int((ProcessInfo.processInfo.systemUptime-started)*1000))
            }
        }
        let result = try await LocalTexTellerRuntime.shared.recognizePNG(png)
        try Task.checkCancellation()
        guard !result.latex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LocalRecognitionError.invalid("The model returned no readable expression. Try a shorter row.")
        }
        return RecognitionResult(text: result.latex, latex: result.latex, confidence: nil,
            candidates: [.init(text: result.latex, confidence: nil)], debugImagePNG: png,
            durationMilliseconds: Int((ProcessInfo.processInfo.systemUptime - started) * 1000))
    }
    /// Read every occupied cell in row-major order. Reject structural output rather than silently changing dimensions.
    private func recognizeMatrix(_ cells:[[Data]]) async throws -> String {
        var rows:[String]=[]
        for (rowIndex,row) in cells.enumerated() {
            var entries:[String]=[]
            for (columnIndex,ink) in row.enumerated() {
                try Task.checkCancellation()
                let image=try await MainActor.run { try RowInkRenderer.renderPNG(inkData:ink,padding:10) }
                let prediction=try await LocalTexTellerRuntime.shared.recognizePNG(image)
                let value=prediction.latex.trimmingCharacters(in:.whitespacesAndNewlines)
                guard !value.isEmpty,!value.contains("&"),!value.contains("\\\\"),!value.contains("\\begin"),
                      !value.contains("="),!value.contains("\n") else {
                    throw LocalRecognitionError.invalid("Matrix entry at row \(rowIndex+1), column \(columnIndex+1) could not be isolated. Review the ink and spacing; no entries have been filled in.")
                }
                entries.append(value)
            }
            rows.append(entries.joined(separator:" & "))
        }
        return "\\begin{bmatrix}"+rows.joined(separator:" \\\\ ")+"\\end{bmatrix}"
    }
}
