import XCTest
import SwiftData
@testable import inkpad

final class DefiniteIntegralTests:XCTestCase {
    func testReadsVariableBoundsAndDifferentialFromFullLatex() throws {
        let samples=[#"\int_{-1}^{2} t^2\,dt"#,#"\int^{2}_{-1} t^2\,\mathrm{d}t"#,"∫_{-1}^{2} t^2 dt",#"\displaystyle\int\limits_{-1}^{2} t^2 dt"#,#"\[\int_{-1}^{2} t^2 dt\]"#]
        for source in samples {
            let parsed=try PolynomialIntegralInput.parse(source)
            XCTAssertEqual(parsed.variable,"t",source);XCTAssertEqual(parsed.lower,"-1");XCTAssertEqual(parsed.upper,"2")
            let result=try MathComputationService().compute(MathComputationRequest(operation:.definiteIntegral,inputA:source))
            XCTAssertEqual(result.outputLatex,"3",source);XCTAssertEqual(result.request.variable,"t")
            XCTAssertEqual(result.request.lower,"-1");XCTAssertEqual(result.request.upper,"2");XCTAssertEqual(result.request.inputA,source)
        }
    }
    func testFractionDecimalEqualReversedBoundsAndConstantIntegrands() throws {
        let samples:[(String,String)]=[(#"\int_{0}^{\frac{1}{2}} x^2 dx"#,#"\frac{1}{24}"#),(#"\int_2^0 x dx"#,"-2"),(#"\int_{1.5}^{1.5} z^3 dz"#,"0"),(#"\int_{-0.5}^{0.5} 2 dt"#,"2"),(#"\int_{-\frac{1}{2}}^{\frac{1}{2}} 1 dx"#,"1"),(#"\int_{- \frac{1}{2}}^{+ \frac{1}{2}} 1 dt"#,"1")]
        for (source,expected) in samples {
            XCTAssertEqual(try MathComputationService().compute(MathComputationRequest(operation:.definiteIntegral,inputA:source)).outputLatex,expected,source)
        }
    }
    func testIntegrandOnlyAndFullIndefiniteCanUseSeparateBounds() throws {
        let service=MathComputationService()
        XCTAssertEqual(try service.compute(MathComputationRequest(operation:.definiteIntegral,inputA:"t^2",variable:"t",lower:"-1",upper:"2")).outputLatex,"3")
        let full=try service.compute(MathComputationRequest(operation:.definiteIntegral,inputA:#"\int t^2 dt"#,lower:"-1",upper:"2"))
        XCTAssertEqual(full.request.variable,"t");XCTAssertEqual(full.outputLatex,"3")
        XCTAssertTrue(try service.compute(MathComputationRequest(operation:.integral,inputA:#"\int t^2 dt"#)).outputLatex.contains("C"))
    }
    func testRejectsMissingAmbiguousUnsupportedAndMismatchedNotation() {
        for source in [#"\int_{0} x dx"#,#"\int_{0}^{1 x dx"#,#"\int_{}^{1} x dx"#,#"\int_{0}^{\infty} x dx"#,#"\int_{a}^{2} x dx"#,#"\int_{0}^{1} x dt"#,#"\int_{0}^{1} x^2"#,#"\int_{0}^{1} \sin x dx"#,#"\int_{0}^{1} \int x dx"#] {
            XCTAssertThrowsError(try PolynomialIntegralInput.parse(source),source)
        }
        XCTAssertThrowsError(try MathComputationService().compute(MathComputationRequest(operation:.integral,inputA:#"\int_0^1 x dx"#))) { error in
            XCTAssertTrue(error.localizedDescription.contains("Choose Definite"))
        }
    }
    func testFullNotationOverridesStaleDefaultParameterFieldsAndSuggestsDefiniteOperation() throws {
        let input=#"\int_{3}^{5} y dy"#
        let result=try MathComputationService().compute(MathComputationRequest(operation:.definiteIntegral,inputA:input,variable:"x",lower:"0",upper:"1"))
        XCTAssertEqual(result.outputLatex,"8");XCTAssertEqual(result.request.variable,"y")
        XCTAssertEqual(ExpressionComputeSuggestion.forLatex(input)?.operation,.definiteIntegral)
        XCTAssertNil(ExpressionComputeSuggestion.forLatex(#"\int_{0}^{\infty} x dx"#))
    }
    @MainActor func testFullRecognizedIntegralRetainsSourceAndResolvedParameters() async throws {
        let schema=Schema([Notebook.self,Page.self,Step.self,StepRevision.self,ComputationResult.self,Branch.self,ChatThread.self,ChatMessage.self,Snapshot.self,Insight.self,ClassSpace.self,WorkedExample.self])
        let c=try ModelContainer(for:schema,configurations:[ModelConfiguration(schema:schema,isStoredInMemoryOnly:true)])
        let input=#"\int_{-1}^{2} t^2\,dt"#,n=try await PolynomialSmoke.seed(c.mainContext,latex:input)
        let p=try XCTUnwrap(n.pages.first),s=try XCTUnwrap(p.steps.first),snapshot=try PolynomialResultStore.snapshot(s)
        let a=try MathComputationService().compute(MathComputationRequest(operation:.definiteIntegral,inputA:input))
        let r=try MathResultStore.save(a,page:p,source:s,expected:snapshot,context:c.mainContext)
        XCTAssertTrue(r.source === s);XCTAssertTrue(r.isCurrent);XCTAssertEqual(r.variable,"t")
        XCTAssertEqual(r.inputLatex,input);XCTAssertEqual(r.computationRequest?.lower,"-1");XCTAssertEqual(r.computationRequest?.upper,"2")
        XCTAssertEqual(r.outputLatex,"3")
    }
}
