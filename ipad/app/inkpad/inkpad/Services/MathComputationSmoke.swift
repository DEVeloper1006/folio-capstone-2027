#if DEBUG
import Foundation
import SwiftData
import UIKit

@MainActor
enum MathComputationSmoke {
    struct Run:Codable {
        let folder:String
        let resultIDs:[UUID]
        let outputs:[String]
        let notebookCount:Int
        let pageCount:Int
        let operationCount:Int
        let displayMetrics:[String:[Double]]?
    }
    static func run(userContainer:ModelContainer,reopen:Bool) async {
        do {
            let root=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("MathComputationSmoke")
            try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
            let pointer=root.appendingPathComponent("latest.json")
            let notebooks=try userContainer.mainContext.fetchCount(FetchDescriptor<Notebook>()),pages=try userContainer.mainContext.fetchCount(FetchDescriptor<Page>())
            if reopen {
                let run=try JSONDecoder().decode(Run.self,from:Data(contentsOf:pointer))
                let c=try ModelContainer(for:userContainer.schema,configurations:[ModelConfiguration(schema:userContainer.schema,url:root.appendingPathComponent(run.folder).appendingPathComponent("math.store"))])
                let results=try c.mainContext.fetch(FetchDescriptor<ComputationResult>())
                guard run.notebookCount==notebooks,run.pageCount==pages,results.count==run.operationCount else { throw PolynomialError.invalid("Notebook or result counts changed.") }
                for (i,id) in run.resultIDs.enumerated() {
                    guard let result=results.first(where:{$0.stableID==id}),result.isCurrent,result.isPlacedOnCanvas,
                          result.outputLatex==run.outputs[i],result.canvasPreviewVersion==CanvasResultLayout.previewVersion,result.canvasPreviewPNG != nil,!result.explanationSteps.isEmpty else { throw PolynomialError.invalid("Saved computation did not survive relaunch.") }
                }
                print("FOLIO_MATH_REOPEN_PASS "+String(decoding:try JSONEncoder().encode(run),as:UTF8.self));exit(0)
            }
            let folder=UUID().uuidString,dir=root.appendingPathComponent(folder)
            try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
            let c=try ModelContainer(for:userContainer.schema,configurations:[ModelConfiguration(schema:userContainer.schema,url:dir.appendingPathComponent("math.store"))])
            let notebook=Notebook(name:"Isolated computation smoke test"),page=Page(sortIndex:0)
            c.mainContext.insert(notebook);notebook.pages.append(page);page.notebook=notebook
            var ids:[UUID]=[],outputs:[String]=[],metrics:[String:[Double]]=[:]
            for operation in MathOperation.allCases {
                let input:String
                switch operation {
                case .solve: input="1,1,3;2,-1,0"
                case .arithmetic: input="(3/4+2)/5"
                case .solveEquation: input="x^2+2x+5=0"
                case .solveInequality: input="x^2-1<=0"
                case .solveAbsolute: input="|2x-3|=5"
                case .complexCalculate: input="(1+i)/(1-i)"
                case .complexConjugate,.complexModulus: input="3+4i"
                case .implicitDerivative: input="x^2+y^2=1"
                case .rootInterval: input="x-1/2"
                case .numericalIntegral: input = #"\int_0^1 e^{-x^2} dx"#
                case .expand: input="(x+1)(x-1)"
                case .integral: input="x^2"
                case .definiteIntegral: input = #"\int_{-1}^{2} t^2\,dt"#
                default:input=operation.isMatrix ? "1,2;3,4":"x^2+3x+2"
                }
                let request=MathComputationRequest(operation:operation,inputA:input,inputB:operation.needsB ? (operation.isMatrix ? "1,0;0,1":"x+1"):"")
                let answer=try await MathComputationWorker.shared.compute(request)
                if operation == .definiteIntegral {
                    guard answer.outputLatex=="3",answer.request.variable=="t",answer.request.lower=="-1",answer.request.upper=="2" else {
                        throw PolynomialError.invalid("Full definite integral parameters were not read correctly.")
                    }
                }
                if operation == .solveEquation {
                    guard answer.outputLatex == #"x = -1 \pm 2\,i"# else {throw PolynomialError.invalid("Complex quadratic roots were not returned.")}
                }
                let result=try MathResultStore.save(answer,page:page,source:nil,expected:nil,context:c.mainContext)
                let snapshot=try await ResultImageRenderer.snapshot(result.outputLatex)
                let png=snapshot.png
                try png.write(to:dir.appendingPathComponent(operation.rawValue+".png"),options:.atomic)
                guard let image=UIImage(data:png)?.cgImage else { throw PolynomialError.invalid("No result image.") }
                _=try ImagePreprocessor.prepare(image)
                try CanvasResultStore.insert(result,preview:png,context:c.mainContext,history:nil,onError:{print($0)})
                guard result.isCurrent,result.canvasY.isFinite,page.drawingData==nil else { throw PolynomialError.invalid("Computation changed the ink or has invalid placement.") }
                metrics[operation.rawValue]=[Double(image.width),Double(image.height),snapshot.logicalSize.width,snapshot.logicalSize.height,result.canvasWidth,result.canvasHeight]
                ids.append(result.stableID);outputs.append(result.outputLatex)
            }
            try await CanvasSmoke.captureNotebook(notebook,container:c,directory:dir)
            let run=Run(folder:folder,resultIDs:ids,outputs:outputs,notebookCount:notebooks,pageCount:pages,operationCount:ids.count,displayMetrics:metrics)
            try JSONEncoder().encode(run).write(to:pointer,options:.atomic)
            print("FOLIO_MATH_SMOKE_PASS "+String(decoding:try JSONEncoder().encode(run),as:UTF8.self));exit(0)
        } catch { print("FOLIO_MATH_SMOKE_ERROR "+error.localizedDescription);exit(3) }
    }
}
#endif
