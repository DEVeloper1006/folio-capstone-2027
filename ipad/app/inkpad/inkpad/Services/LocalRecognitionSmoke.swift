#if DEBUG
import SwiftUI
import SwiftData
import PencilKit

/// Explicit launch flags only. Uses a separate store; never inserts test pages
/// into the user's library. A second process verifies the persisted correction.
@MainActor
enum LocalRecognitionSmoke {
    private struct Run: Codable {
        let folder: String
        let stepID: UUID
        let userNotebookCount: Int
        let userPageCount: Int
        let fingerprint: String
        let originalLatex: String
        let benchmarkID: String
        var computationID:UUID?=nil
    }

    static func run(userContainer: ModelContainer, reopen: Bool) async {
        do {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let root = documents.appendingPathComponent("RecognitionSmoke", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let pointer = root.appendingPathComponent("latest.json")
            let userNotebooks = try userContainer.mainContext.fetchCount(FetchDescriptor<Notebook>())
            let userPages = try userContainer.mainContext.fetchCount(FetchDescriptor<Page>())
            if reopen {
                let run = try JSONDecoder().decode(Run.self, from: Data(contentsOf: pointer))
                let url = root.appendingPathComponent(run.folder).appendingPathComponent("notebook.store")
                let config = ModelConfiguration(schema: userContainer.schema, url: url)
                let c = try ModelContainer(for: userContainer.schema, configurations: [config])
                guard let step = try c.mainContext.fetch(FetchDescriptor<Step>()).first(where: { $0.stableID == run.stepID }),
                      step.isAccepted, step.acceptedLatex == "x^{2}", step.status == .unchecked,
                      step.acceptedFingerprint == run.fingerprint, step.recognizedText == run.originalLatex,
                      let ink = step.inkData, try PKDrawing(data: ink).strokes.count == 2,
                      step.revisions.contains(where: { $0.isUserAccepted && $0.latex == "x^{2}" && $0.inkData == ink }),
                      userNotebooks == run.userNotebookCount, userPages == run.userPageCount else {
                    throw ExpressionReviewError.invalid("Persisted expression, original ink or user-library counts differed")
                }
                if let id=run.computationID {
                    guard let result=try c.mainContext.fetch(FetchDescriptor<ComputationResult>()).first(where:{$0.stableID==id}),
                          result.source?.stableID==step.stableID,result.isCurrent,result.isPlacedOnCanvas,
                          result.canvasPreviewVersion==CanvasResultLayout.previewVersion,ExpressionWorkflow.state(step) == .accepted else {
                        throw ExpressionReviewError.invalid("Inline workflow result did not survive reopen")
                    }
                    print("FOLIO_INLINE_REOPEN_PASS")
                }
                print("FOLIO_INKPAD_REOPEN_PASS " + String(data: try JSONEncoder().encode(run), encoding: .utf8)!)
                exit(0)
            }
            let folder = UUID().uuidString
            let directory = root.appendingPathComponent(folder, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let config = ModelConfiguration(schema: userContainer.schema, url: directory.appendingPathComponent("notebook.store"))
            let c = try ModelContainer(for: userContainer.schema, configurations: [config])
            let notebook = Notebook(name: "Synthetic local recognition test")
            let page = Page(sortIndex: 0); page.notebook = notebook; notebook.pages.append(page); c.mainContext.insert(notebook)
            let lines = [[CGPoint(x: 30, y: 30), CGPoint(x: 100, y: 100)],
                         [CGPoint(x: 100, y: 30), CGPoint(x: 30, y: 100)]]
            let strokes = lines.map { line in
                PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: line.enumerated().map { index, point in
                    PKStrokePoint(location: point, timeOffset: Double(index) * 0.2, size: CGSize(width: 3, height: 3),
                                  opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
                }, creationDate: Date()))
            }
            page.drawingData = PKDrawing(strokes: strokes).dataRepresentation()
            try RowInkRenderer.renderPNG(inkData: page.drawingData!).write(to: directory.appendingPathComponent("capture.png"), options: .atomic)
            let coordinator = StepTrackingCoordinator(recognizer: LocalMathRecognitionService())
            let inline=ProcessInfo.processInfo.arguments.contains("--inline-workflow-smoke")
            if inline {
                let scheduler=ExpressionRecognitionScheduler()
                scheduler.schedule {
                    await coordinator.process(drawingData:page.drawingData!,page:page,context:c.mainContext,force:true)
                }
                while scheduler.isWaiting || scheduler.isRunning { try await Task.sleep(for:.milliseconds(100)) }
            } else {
                await coordinator.process(drawingData: page.drawingData!, page: page, context: c.mainContext, force: true)
            }
            guard let step = page.steps.first, page.steps.count == 1, !step.ghostLaTeX.isEmpty,
                  step.recognitionProviderRaw == "local", step.recognitionState != .failed else {
                throw ExpressionReviewError.invalid("Local region recognition did not produce a draft: " + (page.steps.first?.explanation ?? "no row"))
            }
            guard let sample = try ExpressionReviewService.accept(step, latex: "x^{2}", page: page,
                context: c.mainContext, source: "generated-integration-smoke") else {
                throw ExpressionReviewError.invalid("No accepted example")
            }
            _ = try await RecognitionBenchmarkStore.shared.save(sample)
            var run = Run(folder: folder, stepID: step.stableID, userNotebookCount: userNotebooks,
                userPageCount: userPages, fingerprint: step.strokeFingerprint, originalLatex: step.recognizedText,
                benchmarkID: sample.record.id.uuidString)
            if inline {
                guard ExpressionWorkflow.state(step) == .accepted,let suggestion=ExpressionComputeSuggestion.forLatex(step.acceptedLatex) else {
                    throw ExpressionReviewError.invalid("Inline expression not eligible after review")
                }
                let snapshot=try PolynomialResultStore.snapshot(step)
                let answer=try await MathComputationWorker.shared.compute(MathComputationRequest(operation:suggestion.operation,inputA:step.acceptedLatex))
                let result=try MathResultStore.save(answer,page:page,source:step,expected:snapshot,context:c.mainContext)
                let png=try await ResultImageRenderer.render(result.outputLatex)
                try CanvasResultStore.insert(result,preview:png,context:c.mainContext,history:nil,onError:{print($0)})
                run.computationID=result.stableID
                try await CanvasSmoke.captureNotebook(notebook,container:c,directory:directory)
                print("FOLIO_INLINE_SMOKE_PASS (synthetic X strokes, real local inference, explicit x^2 transcription correction, local simplify/insert)")
            }
            try JSONEncoder().encode(run).write(to: pointer, options: .atomic)
            print("FOLIO_INKPAD_SMOKE_PASS " + String(data: try JSONEncoder().encode(run), encoding: .utf8)!)
            exit(0)
        } catch { print("FOLIO_INKPAD_SMOKE_ERROR " + error.localizedDescription); exit(3) }
    }
}
#endif
