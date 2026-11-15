import XCTest
import SwiftData
import PencilKit
@testable import inkpad

@MainActor
final class ExpressionWorkflowTests:XCTestCase {
    func testSuggestionsRespectMathematicalShapeAndUnsupportedInputs() {
        let samples:[(String,MathOperation)]=[("x^2+3=12",.solveEquation),("2t=8",.solveEquation),(#"\begin{bmatrix}1&2\\3&4\end{bmatrix}"#,.rref),(#"\int t^2\,dt"#,.integral),(#"\int_0^1 x\,dx"#,.definiteIntegral),(#"\sin x"#,.derivative),("x^2+3x",.simplify),("2+3/4",.arithmetic)]
        for (input,operation) in samples { XCTAssertEqual(ExpressionComputeSuggestion.forLatex(input)?.operation,operation,input) }
        for invalid in ["","x^3=1","x+y=2","x=1=2","\\begin{bmatrix}1&2\\\\3\\end{bmatrix}"] {
            XCTAssertNil(ExpressionComputeSuggestion.forLatex(invalid),invalid)
        }
    }
    func testIndicatorsDistinguishReviewAcceptanceStaleAndFailure() {
        let s=Step(sortIndex:0,status:.unchecked,label:"x",source:.inferred)
        XCTAssertEqual(ExpressionWorkflow.state(s),.review)
        s.strokeFingerprint="ink";s.acceptedFingerprint="ink";s.acceptedAt=Date();s.acceptedLatex="x"
        XCTAssertEqual(ExpressionWorkflow.state(s),.accepted);XCTAssertEqual(s.status,.unchecked)
        s.invalidateAcceptance();s.recognitionState = .collecting
        XCTAssertEqual(ExpressionWorkflow.state(s),.stale)
        s.recognitionState = .recognizing;XCTAssertEqual(ExpressionWorkflow.state(s),.reading)
        XCTAssertEqual(ExpressionWorkflow.state(s,isRecognizing:false),.paused)
        s.recognitionState = .failed;XCTAssertEqual(ExpressionWorkflow.state(s),.failed)
    }
    func testIndicatorFramesTrackZoomScrollAndAvoidTouchOverlap() {
        let bounds=[CGRect(x:20,y:200,width:100,height:20),CGRect(x:20,y:210,width:100,height:20)]
        let viewport=CanvasViewport(offset:CGPoint(x:10,y:250),zoom:2)
        let frames=ExpressionIndicatorLayout.frames(bounds:bounds,viewport:viewport,available:CGSize(width:400,height:600))
        XCTAssertEqual(frames[0].minX,260);XCTAssertEqual(frames[0].minY,150)
        XCTAssertFalse(frames[0].intersects(frames[1]));XCTAssertLessThanOrEqual(frames[1].maxX,400)
        XCTAssertTrue(ExpressionIndicatorLayout.frames(bounds:[.null],viewport:viewport,available:CGSize(width:400,height:600))[0].isNull)
        XCTAssertTrue(ExpressionIndicatorLayout.frames(bounds:[],viewport:viewport,available:.zero).isEmpty)
    }
    func testPreviewRailTracksRowsAndKeepsControlsOnTheSide() {
        let bounds=[CGRect(x:20,y:40,width:100,height:40),CGRect(x:20,y:180,width:100,height:40)]
        let size=CGSize(width:820,height:800)
        let p=ExpressionPreviewLayout.placements(bounds:bounds,pending:[true,true],obstacles:[],viewport:CanvasViewport(),available:size)
        XCTAssertFalse(p[0].compact);XCTAssertFalse(p[1].compact)
        XCTAssertEqual(p[0].frame.maxX,812);XCTAssertEqual(p[1].frame.maxX,812)
        XCTAssertGreaterThan(p[0].frame.minX,500);XCTAssertEqual(p[0].frame.minY,40)
        XCTAssertFalse(p[0].frame.intersects(p[1].frame))
        let scrolled=ExpressionPreviewLayout.placements(bounds:[bounds[0]],pending:[true],obstacles:[],viewport:CanvasViewport(offset:CGPoint(x:0,y:1000),zoom:2),available:size)
        XCTAssertTrue(scrolled[0].frame.isNull)
    }
    func testExpandedPreviewLeavesTopControlsClearAndFitsSmallViewports() {
        for size in [CGSize(width:1180,height:734),CGSize(width:820,height:734),CGSize(width:320,height:240)] {
            let frame=ExpressionPreviewLayout.expandedFrame(anchor:CGRect(x:900,y:25,width:220,height:158),available:size)
            XCTAssertTrue(CGRect(origin:.zero,size:size).contains(frame));XCTAssertGreaterThanOrEqual(frame.minY,min(64,size.height/5))
            XCTAssertLessThanOrEqual(frame.width,620)
        }
    }
    func testPreviewSnapshotRejectsChangedInkTextStateAndIdentity() {
        let s=Step(sortIndex:0,status:.unchecked,label:"x",ghostLaTeX:"x",source:.inferred)
        s.strokeFingerprint="first";s.recognitionState = .ready
        let snapshot=ExpressionPreviewSnapshot(s)
        XCTAssertTrue(snapshot.matches(s))
        s.ghostLaTeX="y";XCTAssertFalse(snapshot.matches(s));s.ghostLaTeX="x"
        s.strokeFingerprint="second";XCTAssertFalse(snapshot.matches(s));s.strokeFingerprint="first"
        s.recognitionState = .recognizing;XCTAssertFalse(snapshot.matches(s));s.recognitionState = .ready
        s.acceptedFingerprint="first";s.acceptedLatex="x";s.acceptedAt=Date();XCTAssertFalse(snapshot.matches(s))
        let other=Step(sortIndex:1,status:.unchecked,label:"x",ghostLaTeX:"x",source:.inferred)
        other.strokeFingerprint="first";XCTAssertFalse(snapshot.matches(other))
    }
    func testDebounceOnlyRunsLatestScheduledSnapshotAndCanCancel() async throws {
        let scheduler=ExpressionRecognitionScheduler();var ran:[Int]=[]
        scheduler.schedule(delay:.milliseconds(50)) { ran.append(1) }
        scheduler.schedule(delay:.milliseconds(10)) { ran.append(2) }
        XCTAssertTrue(scheduler.isWaiting)
        try await Task.sleep(for:.milliseconds(90));XCTAssertEqual(ran,[2]);XCTAssertFalse(scheduler.isRunning)
        scheduler.schedule(delay:.milliseconds(30)) { ran.append(3) };scheduler.cancel()
        try await Task.sleep(for:.milliseconds(50));XCTAssertEqual(ran,[2]);XCTAssertFalse(scheduler.isWaiting)
    }
    func testCancelledOldTaskCannotClearNewRunningState() async throws {
        let scheduler=ExpressionRecognitionScheduler();var oldStarted=false,newStarted=false
        scheduler.schedule(delay:.zero) { oldStarted=true;try? await Task.sleep(for:.milliseconds(200)) }
        while !oldStarted { await Task.yield() }
        scheduler.schedule(delay:.zero) { newStarted=true;try? await Task.sleep(for:.milliseconds(100)) }
        while !newStarted { await Task.yield() }
        try await Task.sleep(for:.milliseconds(10));XCTAssertTrue(scheduler.isRunning)
        scheduler.cancel();XCTAssertFalse(scheduler.isRunning)
    }
    private func container(_ url:URL?=nil)throws->ModelContainer {
        let schema=Schema([Notebook.self,Page.self,Step.self,StepRevision.self,ComputationResult.self,Branch.self,ChatThread.self,ChatMessage.self,Snapshot.self,Insight.self,ClassSpace.self,WorkedExample.self])
        return try ModelContainer(for:schema,configurations:[url.map { ModelConfiguration(schema:schema,url:$0) } ?? ModelConfiguration(schema:schema,isStoredInMemoryOnly:true)])
    }
    func testReviewedRecognitionSolveInsertReopenAndStaleGuard() async throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:folder) }
        let url=folder.appendingPathComponent("workflow.store"),c=try container(url)
        // Generated strokes + fixed recognition provider, not a model accuracy test.
        let notebook=try await PolynomialSmoke.seed(c.mainContext,latex:"x^2+3=12")
        let page=try XCTUnwrap(notebook.pages.first),s=try XCTUnwrap(page.steps.first)
        let ink=page.drawingData,snapshot=try PolynomialResultStore.snapshot(s)
        let suggestion=try XCTUnwrap(ExpressionComputeSuggestion.forLatex(s.acceptedLatex))
        let request=MathComputationRequest(operation:suggestion.operation,inputA:s.acceptedLatex)
        let answer=try await MathComputationWorker.shared.compute(request)
        XCTAssertTrue(answer.outputLatex.contains("-3"));XCTAssertTrue(answer.outputLatex.contains("3"))
        let result=try MathResultStore.save(answer,page:page,source:s,expected:snapshot,context:c.mainContext)
        let png=try await ResultImageRenderer.render(answer.outputLatex)
        try CanvasResultStore.insert(result,preview:png,context:c.mainContext,history:nil,onError:{XCTFail($0)})
        XCTAssertEqual(page.drawingData,ink);XCTAssertEqual(s.status,.unchecked)
        let id=result.stableID,other=try container(url),saved=try XCTUnwrap(other.mainContext.fetch(FetchDescriptor<ComputationResult>()).first(where:{$0.stableID==id}))
        XCTAssertTrue(saved.isCurrent);XCTAssertTrue(saved.isPlacedOnCanvas);XCTAssertEqual(saved.source?.acceptedLatex,"x^2+3=12")
        _=try ExpressionReviewService.accept(s,latex:"x^2=16",page:page,context:c.mainContext)
        XCTAssertFalse(result.isCurrent)
        XCTAssertThrowsError(try MathResultStore.save(answer,page:page,source:s,expected:snapshot,context:c.mainContext))
    }
    func testExplicitRetryPreservesAcceptedTranscription() async throws {
        let c=try container(),n=try await PolynomialSmoke.seed(c.mainContext,latex:"x^2+3=12")
        let p=try XCTUnwrap(n.pages.first),s=try XCTUnwrap(p.steps.first)
        let tracker=StepTrackingCoordinator(recognizer:InlineRecognitionFixture())
        // Accepted rows are not scheduled, even on explicit retry.
        await tracker.process(drawingData:try XCTUnwrap(p.drawingData),page:p,context:c.mainContext,force:true)
        XCTAssertTrue(s.isAccepted);XCTAssertEqual(s.acceptedLatex,"x^2+3=12")
    }
}
