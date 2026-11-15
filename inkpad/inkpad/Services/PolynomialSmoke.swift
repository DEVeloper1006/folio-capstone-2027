#if DEBUG
import SwiftUI
import SwiftData
import PencilKit
import WebKit
import Network

@MainActor
enum PolynomialSmoke {
    struct Run: Codable {
        let folder: String
        let resultID: UUID
        let notebookCount: Int
        let pageCount: Int
        let outputLatex: String
        let offlineVerified: Bool
        let physicalDevice: Bool
    }
    static func seed(_ context: ModelContext, latex: String) async throws -> Notebook {
        let notebook = Notebook(name: "Polynomial integration test")
        let page = Page(sortIndex: 0);page.notebook=notebook;notebook.pages.append(page);context.insert(notebook)
        let lines = [[CGPoint(x:30,y:30),CGPoint(x:100,y:100)],[CGPoint(x:100,y:30),CGPoint(x:30,y:100)]]
        let strokes = lines.map { line in PKStroke(ink:PKInk(.pen,color:.black),path:PKStrokePath(controlPoints:line.enumerated().map { i,p in
            PKStrokePoint(location:p,timeOffset:Double(i)*0.2,size:CGSize(width:3,height:3),opacity:1,force:1,azimuth:0,altitude:.pi/2)
        },creationDate:Date())) }
        page.drawingData=PKDrawing(strokes:strokes).dataRepresentation()
        await StepTrackingCoordinator(recognizer:PolynomialSmokeRecognizer(latex:latex)).process(drawingData:page.drawingData!,page:page,context:context)
        guard let step=page.steps.first else { throw PolynomialError.invalid("Missing test row") }
        _=try ExpressionReviewService.accept(step,latex:latex,page:page,context:context,source:"generated-polynomial-smoke")
        return notebook
    }
    static func run(userContainer:ModelContainer,reopen:Bool,offline:Bool=false,exitWhenDone:Bool=true) async -> Bool {
        do {
            let documents=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
            let root=documents.appendingPathComponent("PolynomialSmoke",isDirectory:true)
            try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
            let pointer=root.appendingPathComponent("latest.json")
            let notebookCount=try userContainer.mainContext.fetchCount(FetchDescriptor<Notebook>())
            let pageCount=try userContainer.mainContext.fetchCount(FetchDescriptor<Page>())
            if reopen {
                let run=try JSONDecoder().decode(Run.self,from:Data(contentsOf:pointer))
                let config=ModelConfiguration(schema:userContainer.schema,url:root.appendingPathComponent(run.folder).appendingPathComponent("math.store"))
                let c=try ModelContainer(for:userContainer.schema,configurations:[config])
                guard let result=try c.mainContext.fetch(FetchDescriptor<ComputationResult>()).first(where:{$0.stableID==run.resultID}),
                      result.isCurrent,result.outputLatex==run.outputLatex,let source=result.source,
                      source.isAccepted,source.inkData != nil,source.recognizedText == "t^2+3t+2",
                      notebookCount==run.notebookCount,pageCount==run.pageCount else { throw PolynomialError.invalid("Relaunch check failed") }
                let oldSnapshot=try PolynomialResultStore.snapshot(source)
                let service=PolynomialIntegrationService(),answer=try service.integrate(service.prepare(oldSnapshot.inputLatex),variable:"t")
                _=try ExpressionReviewService.accept(source,latex:"t^3",page:source.page!,context:c.mainContext,source:"generated-polynomial-smoke")
                guard !result.isCurrent else { throw PolynomialError.invalid("Old result remained current") }
                do {
                    _=try PolynomialResultStore.save(answer,snapshot:oldSnapshot,source:source,context:c.mainContext)
                    throw PolynomialError.invalid("Stale result was saved")
                } catch let error as PolynomialError {
                    guard error.errorDescription?.contains("source changed") == true else { throw error }
                }
                try PolynomialResultStore.remove(result,context:c.mainContext)
                try JSONEncoder().encode(run).write(to:root.appendingPathComponent("reopen-passed.json"),options:.atomic)
                print("FOLIO_POLYNOMIAL_REOPEN_PASS "+String(data:try JSONEncoder().encode(run),encoding:.utf8)!)
                if exitWhenDone { exit(0) };return true
            }
            let folder=UUID().uuidString,directory=root.appendingPathComponent(folder,isDirectory:true)
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            let config=ModelConfiguration(schema:userContainer.schema,url:directory.appendingPathComponent("math.store"))
            let c=try ModelContainer(for:userContainer.schema,configurations:[config])
            let notebook=try await seed(c.mainContext,latex:#"\int (t^2+3t+2)\,dt"#)
            let source=notebook.pages[0].steps[0],snapshot=try PolynomialResultStore.snapshot(source)
            let service=PolynomialIntegrationService(),prepared=try service.prepare(snapshot.inputLatex)
            let answer=try await PolynomialComputationWorker.shared.integrate(prepared,variable:"t")
            let result=try PolynomialResultStore.save(answer,snapshot:snapshot,source:source,context:c.mainContext)
            guard result.outputLatex == #"\frac{t^{3}}{3} + \frac{3t^{2}}{2} + 2t + C"#,
                  try PolynomialResultStore.save(answer,snapshot:snapshot,source:source,context:c.mainContext).stableID==result.stableID else {
                throw PolynomialError.invalid("Unexpected result or duplicate")
            }
            try await checkPreview(result,container:c,directory:directory)
            #if targetEnvironment(simulator)
            let physical=false
            #else
            let physical=true
            #endif
            let run=Run(folder:folder,resultID:result.stableID,notebookCount:notebookCount,pageCount:pageCount,
                outputLatex:result.outputLatex,offlineVerified:offline,physicalDevice:physical)
            try JSONEncoder().encode(run).write(to:pointer,options:.atomic)
            try JSONEncoder().encode(answer).write(to:directory.appendingPathComponent("answer.json"),options:.atomic)
            print("FOLIO_POLYNOMIAL_SMOKE_PASS "+String(data:try JSONEncoder().encode(run),encoding:.utf8)!)
            if exitWhenDone { exit(0) };return true
        } catch {
            print("FOLIO_POLYNOMIAL_SMOKE_ERROR "+error.localizedDescription)
            if exitWhenDone { exit(3) };return false
        }
    }
    private static func checkPreview(_ result:ComputationResult,container:ModelContainer,directory:URL) async throws {
        guard let scene=UIApplication.shared.connectedScenes.compactMap({$0 as? UIWindowScene}).first else { throw PolynomialError.invalid("No scene") }
        let window=UIWindow(windowScene:scene);window.frame=CGRect(x:0,y:0,width:560,height:600)
        window.rootViewController=UIHostingController(rootView:PolynomialResultCard(result:result,editorMatchesAccepted:true).modelContainer(container))
        window.makeKeyAndVisible();defer { window.isHidden=true }
        func web(_ view:UIView)->WKWebView? {
            if let web=view as? WKWebView { return web };return view.subviews.compactMap { web($0) }.first
        }
        for _ in 0..<100 {
            if let view=window.rootViewController?.view,let browser=web(view),
               let count=try? await browser.evaluateJavaScript("document.querySelectorAll('mjx-container svg').length"),(count as? Int ?? 0)>0 {
                let image=try await browser.takeSnapshot(configuration:nil)
                try image.pngData()?.write(to:directory.appendingPathComponent("preview.png"),options:.atomic)
                return
            }
            try await Task.sleep(for:.milliseconds(100))
        }
        throw PolynomialError.invalid("Typeset result did not render")
    }
}

private struct PolynomialSmokeRecognizer:RecognitionService {
    let latex:String
    func recognize(inkData:Data,mode:MathMode) async throws -> RecognitionResult {
        RecognitionResult(text:"t^2+3t+2",latex:latex,confidence:nil)
    }
}

struct PolynomialUITestHost:View {
    let schema:Schema
    @State private var container:ModelContainer?
    @State private var notebook:Notebook?
    @State private var errorText=""
    var body:some View {
        Group {
            if let container,let notebook {
                if ProcessInfo.processInfo.arguments.contains("--canvas-library-ui") { AppNavigation().modelContainer(container) }
                else { NavigationStack { NotebookView(notebook:notebook) }.modelContainer(container).frame(width:ProcessInfo.processInfo.arguments.contains("--narrow-window-ui") ? 820:nil) }
            }
            else if !errorText.isEmpty { Text(errorText) }
            else { ProgressView("Preparing test notebook…") }
        }.task {
            guard container==nil else { return }
            do {
                let arguments=ProcessInfo.processInfo.arguments
                let name=arguments.firstIndex(of:"--canvas-ui-store").flatMap { $0+1<arguments.count ? arguments[$0+1]:nil } ?? UUID().uuidString
                let folder=FileManager.default.temporaryDirectory.appendingPathComponent("FolioUITest-"+name)
                try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
                let config=ModelConfiguration(schema:schema,url:folder.appendingPathComponent("ui.store"))
                let c=try ModelContainer(for:schema,configurations:[config])
                if let existing=try c.mainContext.fetch(FetchDescriptor<Notebook>()).first { notebook=existing }
                else if arguments.contains("--canvas-empty-ui") {
                    let n=Notebook(name:"Polynomial integration test"),p=Page(sortIndex:0)
                    p.notebook=n;n.pages.append(p);c.mainContext.insert(n)
                    try c.mainContext.save();notebook=n
                }
                else {
                    let latex=arguments.contains("--wide-inline-preview-ui") ? (1...50).map{"x_{\($0)}"}.joined(separator:"+") : arguments.contains("--two-row-calc1") ? #"\sin x"# : arguments.contains("--definite-integral-ui") ? #"\int_{-1}^{2} t^2\,dt"# : arguments.contains("--inline-ui-test") ? "x^2+3=12" : arguments.contains("--polynomial-ui-invalid") ? #"\Gamma(t)"# : #"\int (t^2+3t+2)\,dt"#
                    notebook=try await PolynomialSmoke.seed(c.mainContext,latex:latex)
                    if arguments.contains("--inline-ui-test"),let step=notebook?.pages.first?.steps.first {
                        step.invalidateAcceptance();step.acceptedLatex=""
                        for revision in step.revisions { revision.isUserAccepted=false }
                        try c.mainContext.save()
                    }
                }
                if argumentsContainTwoRows(),let n=notebook,let p=n.pages.first,p.steps.count==1,let data=p.drawingData {
                    let drawing=try PKDrawing(data:data)
                    let many=arguments.contains("--many-pending-rows-ui")
                    let strokes=(0..<(many ? 6:2)).flatMap {index in drawing.transformed(using:CGAffineTransform(translationX:0,y:CGFloat(index)*(many ? 100:220))).strokes}
                    p.drawingData=PKDrawing(strokes:strokes).dataRepresentation()
                    await StepTrackingCoordinator(recognizer:TwoRowCalcFixture()).process(drawingData:p.drawingData!,page:p,context:c.mainContext)
                    for s in p.steps where !s.isAccepted && !arguments.contains("--pending-rows-ui") && !arguments.contains("--many-pending-rows-ui") {
                        _=try ExpressionReviewService.accept(s,latex:"x^2",page:p,context:c.mainContext,source:"two-row-ui-fixture")
                    }
                }
                container=c
            } catch { errorText=error.localizedDescription }
        }
    }
}

private func argumentsContainTwoRows()->Bool { ProcessInfo.processInfo.arguments.contains("--two-row-calc1") || ProcessInfo.processInfo.arguments.contains("--pending-rows-ui") || ProcessInfo.processInfo.arguments.contains("--many-pending-rows-ui") }
private struct TwoRowCalcFixture:RecognitionService {
    func recognize(inkData:Data,mode:MathMode)async throws->RecognitionResult { RecognitionResult(text:"x^2",latex:"x^2",confidence:nil) }
}

struct PolynomialOfflineCheckView:View {
    let container:ModelContainer
    @State private var status="Turn off Wi-Fi and cellular data, then return to Ink Pad. The test starts when no network route is available."
    @State private var finished=false
    @State private var openLibrary=false
    var body:some View {
        Group {
            if openLibrary { AppNavigation() }
            else { VStack(spacing:24) { Text(status).padding();if finished { Button("Open notebooks") { openLibrary=true } } else { ProgressView() } } }
        }.task {
            guard !finished else { return }
            let monitor=NWPathMonitor()
            let stream=AsyncStream<Bool> { continuation in
                monitor.pathUpdateHandler={ path in continuation.yield(path.status == .unsatisfied) }
                continuation.onTermination={ _ in monitor.cancel() }
                monitor.start(queue:DispatchQueue(label:"folio.offline-check"))
            }
            var offline=false
            for await value in stream { if value { offline=true;break };if Task.isCancelled { break } }
            monitor.cancel()
            guard offline,!Task.isCancelled else { return }
            status="Computing and rendering with networking unavailable…"
            let passed=await PolynomialSmoke.run(userContainer:container,reopen:false,offline:true,exitWhenDone:false)
            finished=true
            status=passed ? "Offline test passed. You can turn Wi-Fi back on and open your notebooks." : "Offline test failed. Turn Wi-Fi back on so the log can be checked."
        }
    }
}
#endif
