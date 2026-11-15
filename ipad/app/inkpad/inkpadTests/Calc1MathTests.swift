import XCTest
import SwiftData
@testable import inkpad

@MainActor
final class Calc1MathTests:XCTestCase {
    private func compute(_ operation:MathOperation,_ input:String,point:String="2",lower:String="0",upper:String="1",second:String="")async throws->MathComputationAnswer {
        try await MathComputationWorker.shared.compute(MathComputationRequest(operation:operation,inputA:input,inputB:second,point:point,lower:lower,upper:upper))
    }
    func testComplexResultRendersAndMalformedPreviewIsRejected() async throws {
        let answer=try MathComputationService().compute(.init(operation:.solveEquation,inputA:"x^2+2x+5=0"))
        let snapshot=try await ResultImageRenderer.snapshot(answer.outputLatex)
        XCTAssertGreaterThan(snapshot.logicalSize.width,20);XCTAssertGreaterThan(snapshot.logicalSize.height,5)
        XCTAssertNotNil(UIImage(data:snapshot.png))
        do {
            _=try await ResultImageRenderer.snapshot(#"\frac{"#)
            XCTFail("Malformed math must not enable inline acceptance")
        } catch {XCTAssertTrue(error.localizedDescription.contains("typeset") || error.localizedDescription.contains("large"),error.localizedDescription)}
    }
    func testLargeRecognitionPreviewPreservesFullSizeForScrolling() async throws {
        let latex=(1...50).map{"x_{\($0)}"}.joined(separator:"+")
        let snapshot=try await ResultImageRenderer.snapshot(latex,forRecognition:true)
        XCTAssertGreaterThan(snapshot.logicalSize.width,220)
        XCTAssertEqual(snapshot.scale,2)
        let image=try XCTUnwrap(UIImage(data:snapshot.png)?.cgImage)
        XCTAssertEqual(CGFloat(image.width),snapshot.logicalSize.width*snapshot.scale,accuracy:2)
    }
    func testOfflineWorkerDerivativeAndIntegral() async throws {
        let d=try await compute(.derivative,#"\sin x"#)
        XCTAssertTrue(d.outputLatex.contains("cos"),d.outputLatex);XCTAssertEqual(d.engineVersion,Calc1MathService.version)
        let integral=try await compute(.definiteIntegral,#"\int_{0}^{\pi} \sin x dx"#)
        XCTAssertEqual(integral.outputLatex,"2");XCTAssertEqual(integral.request.variable,"x")
    }
    func testInspectReadsTrigIntegralWithoutExecutingIt()async throws {
        let r=try await Calc1MathService.inspect(MathComputationRequest(operation:.definiteIntegral,inputA:#"\int_0^{\pi} \sin t dt"#))
        XCTAssertEqual(r.variable,"t");XCTAssertEqual(r.lower,"0");XCTAssertEqual(r.upper,#"\pi"#);XCTAssertEqual(r.kind,"definiteIntegral")
    }
    func testAntiderivativesAndInverseTrigNotation()async throws {
        let integral=try await compute(.integral,#"\int \frac{1}{x} dx"#)
        XCTAssertTrue(integral.outputLatex.contains("ln"));XCTAssertTrue(integral.outputLatex.contains("|"));XCTAssertTrue(integral.outputLatex.hasSuffix(" + C"))
        let inverse=try await compute(.derivative,#"\sin^{-1} x"#)
        XCTAssertTrue(inverse.outputLatex.contains("sqrt"),inverse.outputLatex)
        do { _=try await compute(.integral,"e^{-x^2}");XCTFail("A special function must not be misparsed as variable multiplication") }
        catch { XCTAssertTrue(error.localizedDescription.contains("elementary"),error.localizedDescription) }
    }
    func testFiniteOneSidedAndInfiniteLimits()async throws {
        let zero=try await compute(.limit,#"\lim_{x\to0} \frac{\sin x}{x}"#);XCTAssertEqual(zero.outputLatex,"1")
        let left=try await compute(.limitLeft,"1/x",point:"0");XCTAssertEqual(left.outputLatex,#"-\infty"#)
        let log=try await compute(.limit,#"\lim_{x\to0^{+}} \ln x"#);XCTAssertEqual(log.outputLatex,#"-\infty"#);XCTAssertEqual(log.request.operation,.limitRight)
        let infinity=try await compute(.limit,"(1+1/x)^x",point:"Inf");XCTAssertEqual(infinity.outputLatex,"e")
        do { _=try await compute(.limit,"1/x",point:"0");XCTFail("Two-sided pole is not a computed limit") } catch { }
    }
    func testNumericalIntegralAndSingularityRejection()async throws {
        let r=try await compute(.numericalIntegral,#"\int_0^1 e^{-x^2} dx"#)
        XCTAssertTrue(r.outputLatex.contains("0.7468241328"),r.outputLatex);XCTAssertTrue(r.outputLatex.contains(#"\approx"#))
        for f in [#"\int_{-1}^{1} 1/x dx"#,#"\int_0^{\pi} \tan x dx"#,#"\int_0^1 \ln x dx"#] {
            do { _=try await compute(.numericalIntegral,f);XCTFail("Unresolved singularities must fail: "+f) } catch { }
        }
    }
    func testApplicationsAndRootBrackets()async throws {
        let tangent=try await compute(.tangentLine,"x^2",point:"2");XCTAssertEqual(tangent.outputLatex,#"y = 4 \cdot x-4"#)
        let normal=try await compute(.normalLine,"x^2",point:"0");XCTAssertEqual(normal.outputLatex,"x = 0")
        let average=try await compute(.averageRate,"x^2",lower:"0",upper:"2");XCTAssertEqual(average.outputLatex,"2")
        let disk=try await compute(.volumeDisk,"x");XCTAssertEqual(disk.outputLatex,#"\frac{\pi}{3}"#)
        let root=try await compute(.rootInterval,#"\cos x-x"#);XCTAssertTrue(root.outputLatex.contains("0.739085"))
        let implicit=try await compute(.implicitDerivative,"x^2+y^2=1");XCTAssertTrue(implicit.outputLatex.contains(#"\frac{x}{y}"#))
    }
    func testFunctionDefinitionsScientificNotationAndWasherVolume()async throws {
        let function=try await compute(.derivative,"f(t)=sin(t)")
        XCTAssertTrue(function.outputLatex.contains("cos"));XCTAssertEqual(function.request.variable,"t")
        let euler=try await compute(.derivative,"e");XCTAssertEqual(euler.outputLatex,"0")
        do { _=try await MathComputationWorker.shared.compute(MathComputationRequest(operation:.solveEquation,inputA:"e^2=4",variable:"e"));XCTFail("Euler's constant must not become a polynomial unknown") } catch { }
        let scientific=try await compute(.arithmetic,"1e-3");XCTAssertEqual(scientific.outputLatex,#"\frac{1}{1000}"#)
        let root=try await compute(.rootInterval,"cos(x)=x");XCTAssertTrue(root.outputLatex.contains("0.739085"))
        let washer=try await compute(.volumeWasher,"2",second:"x");XCTAssertEqual(washer.outputLatex,#"\frac{11 \cdot \pi}{3}"#)
        do { _=try await compute(.expand,"(x+1)^1000");XCTFail("Large expansions must be bounded") } catch { }
        do { _=try await compute(.arithmetic,"0^0");XCTFail("Undefined constant") } catch { }
    }
    func testAbsoluteValueDerivativeHasExplicitDomainQualification()async throws {
        let result=try await compute(.derivative,"abs(x)")
        XCTAssertTrue(result.outputLatex.contains(#"\ne0"#));XCTAssertTrue(result.steps.contains{$0.contains("one-sided")})
    }
    func testUnusedParametersCannotLeakAndMissingBoundsAreNotDefaulted()async throws {
        let derivative=try await compute(.derivative,#"\sin x"#,point:"bad",lower:"",upper:"bad")
        XCTAssertTrue(derivative.outputLatex.contains("cos"))
        do { _=try await compute(.numericalIntegral,"x^2",lower:"",upper:"1");XCTFail("A cleared limit must not become zero silently") }
        catch { XCTAssertTrue(error.localizedDescription.contains("lower"),error.localizedDescription) }
    }
    func testWorkerTimeoutTerminatesActualBusyWorker()async throws {
        let runner=Calc1WorkerRunner();runner.testWorkerSource="self.onmessage=()=>{while(true){}}";runner.testDeadlineMS=30
        let start=ProcessInfo.processInfo.systemUptime
        do { _=try await runner.run(MathComputationRequest(operation:.derivative,inputA:"x"));XCTFail("Expected a worker deadline") }
        catch { XCTAssertTrue(error.localizedDescription.contains("time limit"),error.localizedDescription) }
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime-start,4)
        let next=try await compute(.derivative,#"\cos x"#);XCTAssertTrue(next.outputLatex.contains("sin"))
    }
    func testCancellationAndFreshWorkerState()async throws {
        let runner=Calc1WorkerRunner();runner.testWorkerSource="self.onmessage=()=>{while(true){}}"
        let task=Task { try await runner.run(MathComputationRequest(operation:.derivative,inputA:"x")) }
        try await Task.sleep(for:.milliseconds(100));task.cancel()
        do { _=try await task.value;XCTFail("Cancelled work returned a result") } catch is CancellationError { } catch { XCTFail(error.localizedDescription) }
        let r=try await Calc1MathService.inspect(MathComputationRequest(operation:.derivative,inputA:#"\sin t"#))
        XCTAssertEqual(r.variable,"t")
    }
    private func container(_ url:URL?=nil)throws->ModelContainer {
        let s=Schema([Notebook.self,Page.self,Step.self,StepRevision.self,ComputationResult.self,Branch.self,ChatThread.self,ChatMessage.self,Snapshot.self,Insight.self,ClassSpace.self,WorkedExample.self])
        return try ModelContainer(for:s,configurations:[url.map{ModelConfiguration(schema:s,url:$0)} ?? ModelConfiguration(schema:s,isStoredInMemoryOnly:true)])
    }
    func testRowScopeNeverIncludesAnotherRowsHistory()async throws {
        let c=try container(),n=try await PolynomialSmoke.seed(c.mainContext,latex:"x^2"),p=n.pages[0],s=p.steps[0]
        let a=try await compute(.derivative,"x^2"),snapshot=try PolynomialResultStore.snapshot(s)
        let first=try MathResultStore.save(a,page:p,source:s,expected:snapshot,context:c.mainContext)
        let b=try await compute(.derivative,"t^2"),second=try MathResultStore.save(b,page:p,source:nil,expected:nil,context:c.mainContext)
        XCTAssertEqual(RowComputationScope.results(on:p,source:s,sessionIDs:[]).map(\.stableID),[first.stableID])
        XCTAssertTrue(RowComputationScope.results(on:p,source:nil,sessionIDs:[]).isEmpty)
        XCTAssertEqual(RowComputationScope.results(on:p,source:second.source,sessionIDs:[]).map(\.stableID),[second.stableID])
        XCTAssertEqual(Set(RowComputationScope.results(on:p,source:s,sessionIDs:[second.stableID]).map(\.stableID)),[first.stableID,second.stableID])
    }
    func testCASProvenanceDeduplicationAndDiskReopen()async throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:folder)}
        let url=folder.appendingPathComponent("calc1.store"),c=try container(url)
        let n=try await PolynomialSmoke.seed(c.mainContext,latex:#"\sin x"#),p=n.pages[0],s=p.steps[0],snapshot=try PolynomialResultStore.snapshot(s)
        let answer=try await compute(.derivative,s.acceptedLatex),result=try MathResultStore.save(answer,page:p,source:s,expected:snapshot,context:c.mainContext)
        XCTAssertEqual(result.engineVersion,Calc1MathService.version)
        XCTAssertEqual(result.stableID,try MathResultStore.save(answer,page:p,source:s,expected:snapshot,context:c.mainContext).stableID)
        let id=result.stableID,other=try container(url),saved=try XCTUnwrap(other.mainContext.fetch(FetchDescriptor<ComputationResult>()).first{$0.stableID==id})
        XCTAssertTrue(saved.isCurrent);XCTAssertEqual(saved.engineVersion,Calc1MathService.version);XCTAssertEqual(saved.inputLatex,#"\sin x"#)
    }
}
