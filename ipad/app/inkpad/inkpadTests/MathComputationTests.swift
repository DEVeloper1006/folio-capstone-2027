import XCTest
import SwiftData
import PencilKit
@testable import inkpad

final class MathArithmeticTests:XCTestCase {
    func compute(_ operation:MathOperation,_ a:String,_ b:String="") throws -> MathComputationAnswer {
        try MathComputationService().compute(MathComputationRequest(operation:operation,inputA:a,inputB:b))
    }
    func testMatrixParsingAndExactFractions() throws {
        let expected=try ExactMatrix.parse("-1/2, 0.25; 3, -4")
        XCTAssertEqual(try ExactMatrix.parse(#"\begin{bmatrix}-\frac{1}{2} & \frac{1}{4} \\ 3 & -4\end{bmatrix}"#),expected)
        XCTAssertEqual(try ExactMatrix.parse(expected.latex),expected)
        XCTAssertEqual(try ExactMatrix.parse(#"\left[\begin{array}{cc}-\dfrac{1}{2}&\tfrac{1}{4}\\3&-4\end{array}\right]"#),expected)
        XCTAssertThrowsError(try ExactMatrix.parse(#"\begin{array}{ccc}1&2\end{array}"#))
        XCTAssertEqual(try ExactRational.scalar("-.5"),try ExactRational(-1,2))
        for input in ["1,,2","1,2;3",";","1/0","x","1,2;","\\begin{bmatrix}1&2","1,,","1,,2,3,4,5,6"] { XCTAssertThrowsError(try ExactMatrix.parse(input),input) }
        for input in ["NaN","1e20","sin(1)","__import__('os')","1/2/3","9223372036854775808","1.1234567891"] { XCTAssertThrowsError(try ExactRational.scalar(input),input) }
    }
    func testRrefRankAndDeterminant() throws {
        let result=try compute(.rref,"0, 2, 4; 1, 3, 5; 2, 6, 10")
        XCTAssertEqual(try ExactMatrix.parse(result.outputLatex),try ExactMatrix.parse("1,0,-1;0,1,2;0,0,0"))
        XCTAssertTrue(result.steps.contains {$0.contains("Swap")})
        XCTAssertEqual(try compute(.rank,"0,2,4;1,3,5;2,6,10").outputLatex,"2")
        XCTAssertEqual(try compute(.determinant,"0,1;2,3").outputLatex,"-2")
        XCTAssertEqual(try compute(.determinant,"1,2;2,4").outputLatex,"0")
        XCTAssertEqual(try compute(.rank,"0,0;0,0").outputLatex,"0")
        let a=try ExactMatrix.parse("1/2,2/3;3/4,5/6")
        XCTAssertEqual(try a.reduced().matrix.reduced().matrix,try a.reduced().matrix)
    }
    func testInverseTransposeAndBinaryOperations() throws {
        let a=try ExactMatrix.parse("1,2;3,4"),inverse=try a.inverse().matrix
        XCTAssertEqual(try a.multiplying(inverse),try ExactMatrix.identity(2))
        XCTAssertEqual(try a.transpose().transpose(),a)
        XCTAssertEqual(try compute(.matrixMultiply,"1,2,3;4,5,6","1,2;3,4;5,6").outputLatex,try ExactMatrix.parse("22,28;49,64").latex)
        XCTAssertEqual(try compute(.matrixAdd,"1,2;3,4","1/2,0;0,-1").outputLatex,try ExactMatrix.parse("3/2,2;3,3").latex)
        XCTAssertEqual(try compute(.matrixSubtract,"1,2;3,4","1,2;3,4").outputLatex,try ExactMatrix.parse("0,0;0,0").latex)
        XCTAssertThrowsError(try compute(.inverse,"1,2;2,4"))
        XCTAssertThrowsError(try compute(.inverse,"1,2,3;4,5,6"))
        XCTAssertThrowsError(try compute(.matrixMultiply,"1,2","1,2"))
        XCTAssertThrowsError(try compute(.matrixAdd,"1,2","1;2"))
    }
    func testAugmentedSystemClassifications() throws {
        let unique=try compute(.solve,"1,1,3;2,-1,0")
        XCTAssertTrue(unique.outputLatex.contains("x_{1} &= 1"));XCTAssertTrue(unique.outputLatex.contains("x_{2} &= 2"))
        let infinite=try compute(.solve,"1,2,3;2,4,6")
        XCTAssertTrue(infinite.outputLatex.contains("t_{1}"));XCTAssertTrue(infinite.steps.last!.contains("Infinitely"))
        XCTAssertEqual(try compute(.solve,"1,2,3;2,4,7").outputLatex,#"\text{No solution}"#)
        XCTAssertTrue(try compute(.solve,"0,0,0").outputLatex.contains("t_{2}"))
        XCTAssertThrowsError(try compute(.solve,"1;2"))
    }
    func testPolynomialOperationsAndBounds() throws {
        XCTAssertEqual(try compute(.derivative,"x^3+3x^2+2").outputLatex,"3x^{2} + 6x")
        XCTAssertEqual(try compute(.expand,"(x+1)(x-1)").outputLatex,"x^{2} - 1")
        var request=MathComputationRequest(operation:.evaluate,inputA:"x^2+1/2",point:"-1/2")
        XCTAssertEqual(try MathComputationService().compute(request).outputLatex,#"\frac{3}{4}"#)
        request=MathComputationRequest(operation:.definiteIntegral,inputA:"x^2",lower:"1",upper:"0")
        XCTAssertEqual(try MathComputationService().compute(request).outputLatex,#"\frac{-1}{3}"#)
        request.lower="1/2";request.upper="1/2"
        XCTAssertEqual(try MathComputationService().compute(request).outputLatex,"0")
        XCTAssertEqual(try compute(.integral,"x^2").outputLatex,#"\frac{x^{3}}{3} + C"#)
        for text in [#"\sin{x}"#,"x+y","x^-1","x^21",#"\int x dx"#] { XCTAssertThrowsError(try compute(.derivative,text),text) }
        XCTAssertThrowsError(try MathComputationService().compute(MathComputationRequest(operation:.derivative,inputA:"t^2",variable:"x")))
    }
    func testCanonicalRequestsIgnoreUnusedInputs() throws {
        var a=MathComputationRequest(operation:.rref,inputA:" 1,2;3,4 ")
        let b=MathComputationRequest(operation:.rref,inputA:"1,2;3,4")
        a.inputB="not used";a.variable="t";a.point="99";a.lower="wrong";a.upper="wrong"
        XCTAssertEqual(try a.encoded(),try b.encoded())
    }
    func testLargeNumbersAndMatrixLimitsFailSafely() throws {
        XCTAssertThrowsError(try compute(.matrixMultiply,"9223372036854775807","2"))
        XCTAssertThrowsError(try ExactMatrix.parse("1,2,3,4,5,6,7"))
        XCTAssertThrowsError(try ExactMatrix.parse(Array(repeating:"1",count:7).joined(separator:";")))
        let identity=(0..<6).map {r in (0..<6).map {r == $0 ? "1":"0"}.joined(separator:",")}.joined(separator:";")
        XCTAssertEqual(try compute(.rank,identity).outputLatex,"6")
        XCTAssertEqual(try compute(.inverse,identity).outputLatex,try ExactMatrix.parse(identity).latex)
    }
}

@MainActor
final class MathPersistenceTests:XCTestCase {
    func container(url:URL?=nil) throws -> ModelContainer {
        let schema=Schema([Notebook.self,Page.self,Step.self,StepRevision.self,ComputationResult.self,Branch.self,ChatThread.self,ChatMessage.self,Snapshot.self,Insight.self,ClassSpace.self,WorkedExample.self])
        return try ModelContainer(for:schema,configurations:[url.map {ModelConfiguration(schema:schema,url:$0)} ?? ModelConfiguration(schema:schema,isStoredInMemoryOnly:true)])
    }
    func testTypedComputationSaveDeduplicatePersistAndInsert() async throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:folder)}
        let url=folder.appendingPathComponent("math.store")
        func save() async throws -> UUID {
            let c=try container(url:url),n=Notebook(name:"Math test"),p=Page(sortIndex:0)
            c.mainContext.insert(n);n.pages.append(p);p.notebook=n
            let original=p.drawingData
            let answer=try MathComputationService().compute(MathComputationRequest(operation:.inverse,inputA:"1,2;3,4"))
            let result=try MathResultStore.save(answer,page:p,source:nil,expected:nil,context:c.mainContext)
            XCTAssertTrue(result.isCurrent);XCTAssertEqual(result.source?.source,.manual)
            XCTAssertEqual(result.stableID,try MathResultStore.save(answer,page:p,source:nil,expected:nil,context:c.mainContext).stableID)
            let image=try await ResultImageRenderer.render(result.outputLatex)
            try CanvasResultStore.insert(result,preview:image,context:c.mainContext,history:nil,onError:{_ in})
            XCTAssertEqual(original,p.drawingData)
            XCTAssertTrue(result.canvasY.isFinite);return result.stableID
        }
        let id=try await save(),c=try container(url:url)
        let result=try XCTUnwrap(c.mainContext.fetch(FetchDescriptor<ComputationResult>()).first {$0.stableID==id})
        XCTAssertTrue(result.isCurrent);XCTAssertTrue(result.isPlacedOnCanvas);XCTAssertNotNil(result.canvasPreviewPNG)
        XCTAssertEqual(result.computationRequest?.operation,.inverse);XCTAssertFalse(result.explanationSteps.isEmpty)
    }
    func testRecognizedSourceRevisionGuardAndRequestDeduplication() async throws {
        let c=try container(),notebook=try await PolynomialSmoke.seed(c.mainContext,latex:"x^2")
        let page=notebook.pages[0],source=page.steps[0],snapshot=try PolynomialResultStore.snapshot(source)
        let engine=MathComputationService(),request=MathComputationRequest(operation:.derivative,inputA:"x^2")
        let a=try engine.compute(request)
        let result=try MathResultStore.save(a,page:page,source:source,expected:snapshot,context:c.mainContext)
        XCTAssertTrue(result.source === source);XCTAssertTrue(result.isCurrent)
        let second=try engine.compute(MathComputationRequest(operation:.evaluate,inputA:"x^2",point:"3"))
        let other=try MathResultStore.save(second,page:page,source:source,expected:snapshot,context:c.mainContext)
        XCTAssertNotEqual(result.stableID,other.stableID)
        source.invalidateAcceptance();XCTAssertFalse(result.isCurrent)
        XCTAssertThrowsError(try MathResultStore.save(a,page:page,source:source,expected:snapshot,context:c.mainContext))
    }
}
