import XCTest
import SwiftData
import SwiftUI
import PencilKit
import PDFKit
@testable import inkpad

@MainActor
final class CanvasToolsTests:XCTestCase {
    private func model()->CanvasViewModel {
        CanvasViewModel(preferences:UserDefaults(suiteName:"CanvasToolsTests-"+UUID().uuidString)!)
    }
    private func container(url:URL?=nil) throws -> ModelContainer {
        let schema=Schema([Notebook.self,Page.self,Step.self,StepRevision.self,ComputationResult.self,Branch.self,
            ChatThread.self,ChatMessage.self,Snapshot.self,Insight.self,ClassSpace.self,WorkedExample.self])
        return try ModelContainer(for:schema,configurations:[url.map { ModelConfiguration(schema:schema,url:$0) } ?? ModelConfiguration(schema:schema,isStoredInMemoryOnly:true)])
    }
    private func result(_ c:ModelContainer) async throws -> ComputationResult {
        let notebook=try await PolynomialSmoke.seed(c.mainContext,latex:"t^2+3t+2")
        let step=notebook.pages[0].steps[0],snapshot=try PolynomialResultStore.snapshot(step)
        let engine=PolynomialIntegrationService(),answer=try engine.integrate(engine.prepare(snapshot.inputLatex),variable:"t")
        return try PolynomialResultStore.save(answer,snapshot:snapshot,source:step,context:c.mainContext)
    }
    func testResultOverlayPassesThroughBlankAreasAndOnlyHitsCards() {
        let host=ResultHitTestView(frame:CGRect(x:0,y:0,width:600,height:800))
        let child=UIView(frame:host.bounds);host.addSubview(child)
        // With no card under the point, Pencil and finger touches reach the ink.
        XCTAssertNil(host.hitTest(CGPoint(x:150,y:250),with:nil))
        host.interactiveRects=[CGRect(x:100,y:200,width:200,height:100)]
        XCTAssertTrue(host.hitTest(CGPoint(x:150,y:250),with:nil) === child)
        XCTAssertNil(host.hitTest(CGPoint(x:350,y:250),with:nil))
        XCTAssertNil(host.hitTest(CGPoint(x:150,y:400),with:nil))
        host.interactiveRects=[]
        XCTAssertNil(host.hitTest(CGPoint(x:150,y:250),with:nil))
    }
    func testPencilDoubleTapRespectsPreferenceAndRestoresHighlighter() {
        let m=model();m.toggleTool(to:.highlighter)
        m.handlePencilDoubleTap(.switchEraser);XCTAssertEqual(m.currentTool,.eraser)
        m.handlePencilDoubleTap(.switchEraser);XCTAssertEqual(m.currentTool,.highlighter)
        m.toggleTool(to:.lasso);m.handlePencilDoubleTap(.switchPrevious)
        XCTAssertEqual(m.currentTool,.highlighter)
        m.handlePencilDoubleTap(.ignore);XCTAssertEqual(m.currentTool,.highlighter)
    }
    func testInputPreferenceIsConsistentAndPersists() {
        let defaults=UserDefaults(suiteName:"CanvasInput-"+UUID().uuidString)!
        let first=CanvasViewModel(preferences:defaults)
        XCTAssertTrue(first.allowFingerDrawing)
        first.allowFingerDrawing=false
        XCTAssertFalse(CanvasViewModel(preferences:defaults).allowFingerDrawing)
        first.allowFingerDrawing=true
        XCTAssertTrue(CanvasViewModel(preferences:defaults).allowFingerDrawing)
    }
    func testEmptyDrawingHasFiniteCanvasAndExportHeight() {
        let empty=PKDrawing()
        XCTAssertTrue(empty.bounds.isNull)
        XCTAssertEqual(CanvasViewModel.contentHeight(drawing:empty),2048)
        XCTAssertEqual(CanvasViewModel.contentHeight(drawing:empty,resultBottom:.infinity),2048)
        XCTAssertEqual(CanvasViewModel.contentHeight(drawing:empty,resultBottom:3200),3200)
        XCTAssertEqual(CanvasViewModel.contentHeight(drawing:empty,resultBottom:.nan),2048)
    }
    func testResultImageUsesNaturalSizeWithoutUpscaling() {
        XCTAssertEqual(CanvasResultLayout.displaySize(pixels:CGSize(width:300,height:120),available:CGSize(width:340,height:140)),CGSize(width:100,height:40))
        XCTAssertEqual(CanvasResultLayout.cardSize(pixels:CGSize(width:300,height:120)),CGSize(width:180,height:100))
        XCTAssertEqual(CanvasResultLayout.displaySize(pixels:CGSize(width:300,height:120),available:CGSize(width:50,height:100)),CGSize(width:50,height:20))
        XCTAssertEqual(CanvasResultLayout.cardSize(pixels:CGSize(width:3000,height:300)),CGSize(width:600,height:118))
        XCTAssertEqual(CanvasResultLayout.displaySize(pixels:.zero,available:CGSize(width:100,height:100)),.zero)
    }
    func testToolbarTapOnlyOpensCurrentToolSettings() {
        let m=model();m.tapToolbarTool(.eraser)
        XCTAssertEqual(m.currentTool,.eraser);XCTAssertNil(m.settingsTool)
        m.tapToolbarTool(.eraser);XCTAssertEqual(m.settingsTool,.eraser)
        m.tapToolbarTool(.pen);XCTAssertEqual(m.currentTool,.pen);XCTAssertNil(m.settingsTool)
        m.tapToolbarTool(.pen);XCTAssertEqual(m.settingsTool,.pen)
        m.tapToolbarTool(.pen);XCTAssertNil(m.settingsTool)
    }
    func testRrefRasterScaleIsIndependentOfDisplayScale() async throws {
        let rendered=try await ResultImageRenderer.snapshot(#"\begin{bmatrix}1&0\\0&1\end{bmatrix}"#)
        let image=try XCTUnwrap(UIImage(data:rendered.png)?.cgImage)
        XCTAssertEqual(image.width,Int(ceil(rendered.logicalSize.width*3)))
        XCTAssertEqual(image.height,Int(ceil(rendered.logicalSize.height*3)))
        XCTAssertNoThrow(try ImagePreprocessor.prepare(image))
        let displayed=CanvasResultLayout.displaySize(pixels:CGSize(width:image.width,height:image.height),available:CGSize(width:1000,height:1000))
        XCTAssertEqual(displayed.width,rendered.logicalSize.width,accuracy:0.34)
        XCTAssertEqual(displayed.height,rendered.logicalSize.height,accuracy:0.34)
        XCTAssertLessThan(displayed.height,100)
        XCTAssertGreaterThan(displayed.height,36,"A 20-point matrix must not collapse to tiny PDF text.")
        // Record the old thumbnail scale to establish whether device density
        // contributed to the original PNG/point mismatch.
        let pdf=UIGraphicsPDFRenderer(bounds:CGRect(x:0,y:0,width:20,height:30)).pdfData { c in c.beginPage() }
        let doc=try XCTUnwrap(PDFDocument(data:pdf)),page=try XCTUnwrap(doc.page(at:0))
        let thumbnail=withExtendedLifetime(doc) { page.thumbnail(of:CGSize(width:60,height:90),for:.mediaBox) }
        print("FOLIO_THUMBNAIL_SCALE \(thumbnail.scale) cgWidth=\(thumbnail.cgImage?.width ?? 0) requestedWidth=60")
    }
    func testLegacyResultPreviewRefitsWithoutChangingInkOrProvenance() async throws {
        let c=try container(),r=try await result(c)
        let ink=r.source?.inkData,source=r.inputLatex,output=r.outputLatex
        let image=try await ResultImageRenderer.snapshot(output)
        r.isPlacedOnCanvas=true;r.canvasX=24;r.canvasY=420;r.canvasWidth=600;r.canvasHeight=300;r.canvasPreviewVersion=0
        try c.mainContext.save()
        try CanvasResultStore.refreshPreview(r,preview:image.png,context:c.mainContext)
        XCTAssertEqual(r.canvasPreviewVersion,CanvasResultLayout.previewVersion)
        XCTAssertEqual(r.canvasY,420);XCTAssertEqual(r.canvasX,24)
        XCTAssertLessThan(r.canvasWidth,600);XCTAssertLessThan(r.canvasHeight,300)
        XCTAssertEqual(r.source?.inkData,ink);XCTAssertEqual(r.inputLatex,source);XCTAssertEqual(r.outputLatex,output)
        XCTAssertTrue(r.isCurrent)
    }
    func testBlackCustomColourAndIndependentToolWidths() {
        let m=model();m.inkColor = .black
        let pen=m.pkTool as! PKInkingTool
        var blackR:CGFloat=1,blackG:CGFloat=1,blackB:CGFloat=1,blackA:CGFloat=0
        pen.color.getRed(&blackR,green:&blackG,blue:&blackB,alpha:&blackA)
        XCTAssertEqual(blackR,0);XCTAssertEqual(blackG,0);XCTAssertEqual(blackB,0);XCTAssertEqual(blackA,1)
        XCTAssertTrue(m.matchesInk(.black))
        let chosen=UIColor(red:0.42,green:0.12,blue:0.83,alpha:1)
        m.inkColor=Color(uiColor:chosen)
        var r:CGFloat=0,g:CGFloat=0,b:CGFloat=0,a:CGFloat=0
        (m.pkTool as! PKInkingTool).color.getRed(&r,green:&g,blue:&b,alpha:&a)
        XCTAssertEqual(r,0.42,accuracy:0.001);XCTAssertEqual(b,0.83,accuracy:0.001)
        m.setWidth(4,for:.pen);m.setWidth(25,for:.highlighter);m.setWidth(30,for:.eraser)
        m.toggleTool(to:.eraser)
        XCTAssertEqual((m.pkTool as! PKEraserTool).width,m.eraserWidth)
        XCTAssertEqual((m.pkTool as! PKEraserTool).eraserType,.fixedWidthBitmap)
        m.toggleTool(to:.eraser);XCTAssertEqual(m.currentTool,.eraser)
        m.toggleTool(to:.pen);XCTAssertEqual((m.pkTool as! PKInkingTool).width,4)
        m.toggleTool(to:.highlighter);XCTAssertEqual((m.pkTool as! PKInkingTool).width,25)
    }
    func testToolPreferencesSurviveNewModel() {
        let defaults=UserDefaults(suiteName:"CanvasPreferences-"+UUID().uuidString)!
        let first=CanvasViewModel(preferences:defaults)
        first.inkColor=Color(red:0.23,green:0.67,blue:0.31)
        first.setWidth(5,for:.pen);first.setWidth(22,for:.highlighter);first.setWidth(32,for:.eraser)
        let next=CanvasViewModel(preferences:defaults)
        XCTAssertEqual(next.penWidth,5);XCTAssertEqual(next.highlighterWidth,22);XCTAssertEqual(next.eraserWidth,32)
        var r:CGFloat=0,g:CGFloat=0,b:CGFloat=0,a:CGFloat=0
        next.uiInkColor.getRed(&r,green:&g,blue:&b,alpha:&a);XCTAssertEqual(g,0.67,accuracy:0.001)
    }
    func testViewportConversionForScrolledZoomedPage() {
        let viewport=CanvasViewport(offset:CGPoint(x:100,y:250),zoom:2)
        XCTAssertEqual(viewport.displayPoint(CGPoint(x:160,y:300)),CGPoint(x:220,y:350))
        XCTAssertEqual(viewport.pageTranslation(CGSize(width:80,height:50)),CGSize(width:40,height:25))
    }
    func testResultImageContainsRenderedMath() async throws {
        let png=try await ResultImageRenderer.render(#"\frac{t^3}{3}+2t+C"#)
        let image=try XCTUnwrap(UIImage(data:png)?.cgImage)
        XCTAssertGreaterThan(image.width,30);XCTAssertNoThrow(try ImagePreprocessor.prepare(image))
    }
    func testInsertMoveUndoRedoAndRemovePreserveStrokes() async throws {
        let c=try container(),r=try await result(c),original=r.source?.inkData
        let history=UndoManager();history.groupsByEvent=false
        let png=try await ResultImageRenderer.render(r.outputLatex)
        var errors:[String]=[]
        history.beginUndoGrouping()
        try CanvasResultStore.insert(r,preview:png,context:c.mainContext,history:history,onError:{ errors.append($0) })
        history.endUndoGrouping()
        XCTAssertTrue(r.isPlacedOnCanvas);XCTAssertNotNil(r.canvasPreviewPNG)
        let origin=CGPoint(x:r.canvasX,y:r.canvasY)
        XCTAssertGreaterThan(r.canvasY,r.source!.bounds.maxY)
        history.beginUndoGrouping()
        try CanvasResultStore.move(r,to:CGPoint(x:200,y:500),context:c.mainContext,history:history,onError:{ errors.append($0) })
        history.endUndoGrouping()
        history.undo();XCTAssertEqual(CGPoint(x:r.canvasX,y:r.canvasY),origin)
        history.redo();XCTAssertEqual(CGPoint(x:r.canvasX,y:r.canvasY),CGPoint(x:200,y:500))
        history.undo();history.undo();XCTAssertFalse(r.isPlacedOnCanvas)
        history.redo();XCTAssertTrue(r.isPlacedOnCanvas)
        history.beginUndoGrouping()
        try CanvasResultStore.removeFromCanvas(r,context:c.mainContext,history:history,onError:{ errors.append($0) })
        history.endUndoGrouping();XCTAssertFalse(r.isPlacedOnCanvas);XCTAssertFalse(r.isRemoved)
        history.undo();XCTAssertTrue(r.isPlacedOnCanvas)
        XCTAssertEqual(r.source?.inkData,original);XCTAssertTrue(errors.isEmpty)
    }
    func testPlacementPersistsAndExportsWithPage() async throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:directory) }
        let url=directory.appendingPathComponent("placement.store")
        func save() async throws -> UUID {
            let c=try container(url:url),r=try await result(c),png=try await ResultImageRenderer.render(r.outputLatex)
            try CanvasResultStore.insert(r,preview:png,context:c.mainContext,history:nil,onError:{_ in})
            try CanvasResultStore.move(r,to:CGPoint(x:120,y:650),context:c.mainContext,history:nil,onError:{_ in})
            return r.stableID
        }
        let id=try await save(),reopened=try container(url:url)
        let r=try XCTUnwrap(reopened.mainContext.fetch(FetchDescriptor<ComputationResult>()).first { $0.stableID==id })
        XCTAssertTrue(r.isPlacedOnCanvas);XCTAssertEqual(r.canvasX,120);XCTAssertEqual(r.canvasY,650)
        let png=try XCTUnwrap(r.canvasPreviewPNG)
        let item=CanvasExportItem(rect:r.canvasRect,png:png,isCurrent:r.isCurrent)
        let empty=PKDrawing(),size=CGSize(width:1024,height:1024)
        XCTAssertNotEqual(ExportService.renderPNG(drawing:empty,background:.blank,size:size),ExportService.renderPNG(drawing:empty,background:.blank,size:size,results:[item]))
        XCTAssertEqual(PDFDocument(data:ExportService.renderPDF(drawing:empty,background:.blank,size:size,results:[item]))?.pageCount,1)
    }
    func testOutdatedResultCannotBeNewlyInserted() async throws {
        let c=try container(),r=try await result(c)
        r.source?.invalidateAcceptance()
        XCTAssertThrowsError(try CanvasResultStore.insert(r,preview:Data(),context:c.mainContext,history:nil,onError:{_ in}))
    }
}
