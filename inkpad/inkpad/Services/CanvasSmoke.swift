#if DEBUG
import SwiftUI
import SwiftData
import PencilKit

@MainActor
enum CanvasSmoke {
    struct Run:Codable {
        let folder:String
        let resultID:UUID
        let x:Double
        let y:Double
        let notebookCount:Int
        let pageCount:Int
        let previewHasMath:Bool
        let originalInkFingerprint:String
    }
    static func run(userContainer:ModelContainer,reopen:Bool) async {
        do {
            let root=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("CanvasSmoke",isDirectory:true)
            try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
            let pointer=root.appendingPathComponent("latest.json")
            let notebooks=try userContainer.mainContext.fetchCount(FetchDescriptor<Notebook>()),pages=try userContainer.mainContext.fetchCount(FetchDescriptor<Page>())
            if reopen {
                let run=try JSONDecoder().decode(Run.self,from:Data(contentsOf:pointer))
                let config=ModelConfiguration(schema:userContainer.schema,url:root.appendingPathComponent(run.folder).appendingPathComponent("canvas.store"))
                let c=try ModelContainer(for:userContainer.schema,configurations:[config])
                guard let result=try c.mainContext.fetch(FetchDescriptor<ComputationResult>()).first(where:{$0.stableID==run.resultID}),
                      result.isPlacedOnCanvas,result.canvasX==run.x,result.canvasY==run.y,result.canvasPreviewPNG != nil,
                      let ink=result.source?.inkData,SpatialInkSegmenter.drawingFingerprint(ink)==run.originalInkFingerprint,
                      run.notebookCount==notebooks,run.pageCount==pages else { throw PolynomialError.invalid("Canvas result did not survive relaunch") }
                print("FOLIO_CANVAS_REOPEN_PASS "+String(data:try JSONEncoder().encode(run),encoding:.utf8)!)
                try JSONEncoder().encode(run).write(to:root.appendingPathComponent("reopen-passed.json"),options:.atomic)
                exit(0)
            }
            let folder=UUID().uuidString,directory=root.appendingPathComponent(folder,isDirectory:true)
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            let c=try ModelContainer(for:userContainer.schema,configurations:[ModelConfiguration(schema:userContainer.schema,url:directory.appendingPathComponent("canvas.store"))])
            let notebook=try await PolynomialSmoke.seed(c.mainContext,latex:"t^2+3t+2"),source=notebook.pages[0].steps[0]
            let original=source.inkData!,engine=PolynomialIntegrationService(),snapshot=try PolynomialResultStore.snapshot(source)
            let answer=try engine.integrate(engine.prepare(snapshot.inputLatex),variable:"t")
            let result=try PolynomialResultStore.save(answer,snapshot:snapshot,source:source,context:c.mainContext)
            let png=try await ResultImageRenderer.render(result.outputLatex)
            guard let cg=UIImage(data:png)?.cgImage else { throw PolynomialError.invalid("No result image") }
            _=try ImagePreprocessor.prepare(cg)
            let history=UndoManager();history.groupsByEvent=false
            history.beginUndoGrouping();try CanvasResultStore.insert(result,preview:png,context:c.mainContext,history:history,onError:{ print($0) });history.endUndoGrouping()
            let initialX=result.canvasX
            history.beginUndoGrouping();try CanvasResultStore.move(result,to:CGPoint(x:200,y:420),context:c.mainContext,history:history,onError:{ print($0) });history.endUndoGrouping()
            history.undo();guard result.canvasX==initialX else { throw PolynomialError.invalid("Move undo failed") }
            history.redo();guard result.canvasX==200,result.canvasY==420 else { throw PolynomialError.invalid("Move redo failed") }
            guard source.inkData==original,result.isPlacedOnCanvas else { throw PolynomialError.invalid("Source ink changed") }
            try png.write(to:directory.appendingPathComponent("result.png"),options:.atomic)
            try await captureNotebook(notebook,container:c,directory:directory)
            let run=Run(folder:folder,resultID:result.stableID,x:result.canvasX,y:result.canvasY,notebookCount:notebooks,pageCount:pages,
                previewHasMath:true,originalInkFingerprint:SpatialInkSegmenter.drawingFingerprint(original))
            try JSONEncoder().encode(run).write(to:pointer,options:.atomic)
            print("FOLIO_CANVAS_SMOKE_PASS "+String(data:try JSONEncoder().encode(run),encoding:.utf8)!)
            exit(0)
        } catch { print("FOLIO_CANVAS_SMOKE_ERROR "+error.localizedDescription);exit(3) }
    }
    static func captureNotebook(_ notebook:Notebook,container:ModelContainer,directory:URL) async throws {
        guard let scene=UIApplication.shared.connectedScenes.compactMap({$0 as? UIWindowScene}).first else { throw PolynomialError.invalid("No window scene") }
        let window=UIWindow(windowScene:scene);window.frame=scene.coordinateSpace.bounds
        let host=UIHostingController(rootView:NavigationStack { NotebookView(notebook:notebook) }.modelContainer(container))
        host.overrideUserInterfaceStyle = .dark;window.rootViewController=host;window.makeKeyAndVisible()
        defer { window.isHidden=true }
        func canvas(_ view:UIView)->NotebookPKCanvasView? {
            if let result=view as? NotebookPKCanvasView { return result }
            return view.subviews.compactMap { canvas($0) }.first
        }
        for _ in 0..<30 {
            if let native=canvas(host.view),native.window != nil {
                guard native.overrideUserInterfaceStyle == .light else { throw PolynomialError.invalid("Canvas did not use light ink appearance") }
                try await Task.sleep(for:.milliseconds(500))
                let image=UIGraphicsImageRenderer(bounds:host.view.bounds).image { _ in host.view.drawHierarchy(in:host.view.bounds,afterScreenUpdates:true) }
                try image.pngData()?.write(to:directory.appendingPathComponent("notebook.png"),options:.atomic)
                return
            }
            try await Task.sleep(for:.milliseconds(100))
        }
        throw PolynomialError.invalid("Native notebook canvas did not appear")
    }
}
#endif
