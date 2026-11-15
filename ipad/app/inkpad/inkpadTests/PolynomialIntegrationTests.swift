import XCTest
import SwiftData
import PencilKit
@testable import inkpad

final class PolynomialCoreTests: XCTestCase {
    func testPolynomialFormsVariablesAndExactCoefficients() throws {
        let service = PolynomialIntegrationService()
        let cases = ["x^2+3x+2", #"\int (t^2+3t+2)\,dt"#, #"\int\frac{y+1}{2}\,\mathrm{d}y"#, "0.1x+0.25", "(x+1)(x-1)", "0", "7", "C^2"]
        for text in cases {
            let prepared = try service.prepare(text), answer = try service.integrate(prepared, variable: prepared.suggestedVariable)
            XCTAssertEqual(try answer.antiderivative.derivative(), prepared.integrand)
        }
        let decimal = try service.prepare("0.1x+0.25")
        XCTAssertEqual(decimal.integrand.coefficients[1], try ExactRational(1,10))
        XCTAssertEqual(decimal.integrand.coefficients[0], try ExactRational(1,4))
        XCTAssertEqual(try service.integrate(service.prepare("C^2"), variable: "C").latex, #"\frac{C^{3}}{3} + C_{1}"#)
    }
    func testPrecedenceAndVariableConfirmation() throws {
        let service = PolynomialIntegrationService()
        XCTAssertEqual(try service.prepare("-x^2").integrand.coefficients[2], try ExactRational(-1))
        XCTAssertEqual(try service.prepare("(-x)^2").integrand.coefficients[2], .one)
        XCTAssertThrowsError(try service.integrate(service.prepare("t^2"), variable: "x"))
        XCTAssertThrowsError(try service.integrate(service.prepare("3"), variable: "theta"))
        XCTAssertEqual(try service.integrate(service.prepare("3"), variable: "y").latex, "3y + C")
    }
    func testInvalidUnsupportedAndBoundedInputs() {
        let inputs = ["", "x+y", "1/x", #"\sin{x}"#, #"\int_0^1 x dx"#, "x^{-1}", "x^{21}", "(x^2+1)^{20}",
            "1/0", "x+", #"\int x"#, #"\int x dy"#, #"\left x"#, "(x}", "0^0", String(repeating: "9", count: 40),
            String(repeating: "(",count:100)+"x"+String(repeating:")",count:100), String(repeating:"x",count:5001),
            Array(repeating:"1", count:300).joined(separator:"+"), "999999999999999999*999999999999999999x"]
        for text in inputs { XCTAssertThrowsError(try PolynomialIntegrationService().prepare(text), text) }
    }
    func testRationalArithmeticChecksOverflowAndZero() throws {
        XCTAssertEqual(try ExactRational(1,3).adding(ExactRational(1,6)), try ExactRational(1,2))
        XCTAssertEqual(try ExactRational(2,3).multiplying(ExactRational(3,4)), try ExactRational(1,2))
        XCTAssertThrowsError(try ExactRational(Int64.max).adding(.one))
        XCTAssertThrowsError(try ExactRational(1,0))
        XCTAssertThrowsError(try ExactRational(.min))
    }
}

@MainActor
final class PolynomialPersistenceTests: XCTestCase {
    private func container(url: URL? = nil) throws -> ModelContainer {
        let schema = Schema([Notebook.self,Page.self,Step.self,StepRevision.self,ComputationResult.self,Branch.self,
            ChatThread.self,ChatMessage.self,Snapshot.self,Insight.self,ClassSpace.self,WorkedExample.self])
        let config = url.map { ModelConfiguration(schema:schema,url:$0) } ?? ModelConfiguration(schema:schema,isStoredInMemoryOnly:true)
        return try ModelContainer(for:schema,configurations:[config])
    }
    private func accepted(_ c: ModelContainer) async throws -> Step {
        let points = [CGPoint(x:20,y:20),CGPoint(x:100,y:60)].enumerated().map { i,p in
            PKStrokePoint(location:p,timeOffset:Double(i)*0.1,size:CGSize(width:3,height:3),opacity:1,force:1,azimuth:0,altitude:.pi/2)
        }
        let data = PKDrawing(strokes:[PKStroke(ink:PKInk(.pen,color:.black),path:PKStrokePath(controlPoints:points,creationDate:Date()))]).dataRepresentation()
        let page=Page(sortIndex:0);page.drawingData=data;c.mainContext.insert(page)
        await StepTrackingCoordinator(recognizer:PolynomialDraftStub()).process(drawingData:data,page:page,context:c.mainContext)
        let step=try XCTUnwrap(page.steps.first)
        _=try ExpressionReviewService.accept(step,latex:#"\int (t^2+3t+2)\,dt"#,page:page,context:c.mainContext)
        return step
    }
    private func compute(_ step:Step) throws -> (IntegrationSourceSnapshot,PolynomialIntegrationAnswer) {
        let snapshot=try PolynomialResultStore.snapshot(step), service=PolynomialIntegrationService()
        return (snapshot,try service.integrate(service.prepare(snapshot.inputLatex),variable:"t"))
    }
    func testSaveIsIdempotentAndPreservesSource() async throws {
        let c=try container(),step=try await accepted(c),ink=step.inkData
        let (snapshot,answer)=try compute(step)
        let first=try PolynomialResultStore.save(answer,snapshot:snapshot,source:step,context:c.mainContext)
        let second=try PolynomialResultStore.save(answer,snapshot:snapshot,source:step,context:c.mainContext)
        XCTAssertEqual(first.stableID,second.stableID);XCTAssertTrue(first.isCurrent)
        XCTAssertEqual(step.inkData,ink);XCTAssertEqual(step.status,.unchecked)
        XCTAssertEqual(step.computationResults.count,1)
    }
    func testNewAcceptedRevisionMakesOldResultOutdatedAndRejectsDelayedSave() async throws {
        let c=try container(),step=try await accepted(c),pair=try compute(step)
        let result=try PolynomialResultStore.save(pair.1,snapshot:pair.0,source:step,context:c.mainContext)
        _=try ExpressionReviewService.accept(step,latex:"t^3",page:step.page!,context:c.mainContext)
        XCTAssertFalse(result.isCurrent)
        XCTAssertThrowsError(try PolynomialResultStore.save(pair.1,snapshot:pair.0,source:step,context:c.mainContext))
        XCTAssertEqual(result.inputLatex,pair.0.inputLatex)
    }
    func testInkChangeAndCancellationPreventSave() async throws {
        let c=try container(),step=try await accepted(c),pair=try compute(step)
        let task=Task { @MainActor in _ = try PolynomialResultStore.save(pair.1,snapshot:pair.0,source:step,context:c.mainContext) }
        task.cancel()
        do { _=try await task.value;XCTFail("Expected cancellation") } catch is CancellationError { }
        step.page?.drawingData=PKDrawing().dataRepresentation()
        XCTAssertThrowsError(try PolynomialResultStore.save(pair.1,snapshot:pair.0,source:step,context:c.mainContext))
        XCTAssertTrue(step.computationResults.isEmpty)
    }
    func testRemovalAndCascadeDelete() async throws {
        let c=try container(),step=try await accepted(c),pair=try compute(step)
        let result=try PolynomialResultStore.save(pair.1,snapshot:pair.0,source:step,context:c.mainContext)
        try PolynomialResultStore.remove(result,context:c.mainContext)
        XCTAssertTrue(result.isRemoved);XCTAssertFalse(result.isCurrent)
        let next=try PolynomialResultStore.save(pair.1,snapshot:pair.0,source:step,context:c.mainContext)
        XCTAssertNotEqual(result.stableID,next.stableID)
        c.mainContext.delete(step);try c.mainContext.save()
        XCTAssertEqual(try c.mainContext.fetchCount(FetchDescriptor<ComputationResult>()),0)
    }
    func testDiskReopenPreservesResultProvenanceAndRemoval() async throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:directory) }
        let url=directory.appendingPathComponent("polynomial.store")
        func write() async throws -> UUID {
            let c=try container(url:url),step=try await accepted(c),pair=try compute(step)
            return try PolynomialResultStore.save(pair.1,snapshot:pair.0,source:step,context:c.mainContext).stableID
        }
        let id=try await write(),reopened=try container(url:url)
        let result=try XCTUnwrap(reopened.mainContext.fetch(FetchDescriptor<ComputationResult>()).first { $0.stableID==id })
        XCTAssertTrue(result.isCurrent);XCTAssertEqual(result.variable,"t")
        XCTAssertEqual(result.sourceRevisionNumber,result.source?.latestAcceptedRevisionNumber)
        XCTAssertNotNil(result.source?.inkData)
        try PolynomialResultStore.remove(result,context:reopened.mainContext)
        let again=try container(url:url)
        XCTAssertTrue(try XCTUnwrap(again.mainContext.fetch(FetchDescriptor<ComputationResult>()).first).isRemoved)
    }
}

private struct PolynomialDraftStub:RecognitionService {
    func recognize(inkData:Data,mode:MathMode) async throws -> RecognitionResult {
        RecognitionResult(text:"t^2+3t+2",latex:"t^2+3t+2",confidence:nil)
    }
}
