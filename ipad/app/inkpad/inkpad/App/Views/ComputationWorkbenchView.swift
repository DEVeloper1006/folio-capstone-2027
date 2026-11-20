/* Reviews operation-specific worksheet inputs, resolves only the current problem context, and saves source-validated results. */
import SwiftUI
import SwiftData

struct ComputationWorkbenchView:View {
    private enum Stage { case choose,review,result }
    private enum InputField:Hashable {case expression,secondExpression,point,lower,upper,variable}
    @FocusState private var focusedInput:InputField?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let page:Page
    let source:Step?
    let onInsert:@MainActor @Sendable (UUID) async throws->Void
    let onRemove:(ComputationResult)throws->Void
    @State private var stage:Stage
    @State private var operation:MathOperation
    @State private var matrixA:String
    @State private var polynomial:String
    @State private var matrixB=""
    @State private var algebraB=""
    @State private var variable="x"
    @State private var point="2"
    @State private var lower="0"
    @State private var upper="1"
    @State private var editingInput:Bool
    @State private var showDetails=false
    @State private var busy=false
    @State private var errorText=""
    @State private var task:Task<Void,Never>?
    @State private var latestID:UUID?
    @State private var sessionIDs:Set<UUID>=[]
    @State private var reusedID:UUID?
    @State private var inputVersion=UUID()
    @State private var openingSnapshot:IntegrationSourceSnapshot?
    @State private var review:Calc1InputReview?
    @State private var reviewError=""
    @State private var inspecting=false
    @State private var inspectionID=UUID()

    init(page:Page,source:Step?=nil,initialOperation:MathOperation?=nil,onInsert:@escaping @MainActor @Sendable(UUID)async throws->Void,onRemove:@escaping(ComputationResult)throws->Void) {
        self.page=page;self.source=source;self.onInsert=onInsert;self.onRemove=onRemove
        let input=source?.acceptedLatex ?? "",matrix=input.contains("\\begin{") || input.contains(";") || input.contains("&")
        _operation=State(initialValue:initialOperation ?? ExpressionComputeSuggestion.forLatex(input)?.operation ?? (matrix || source==nil ? .rref:.simplify))
        _stage=State(initialValue:initialOperation==nil ? .choose:.review)
        _matrixA=State(initialValue:source==nil ? "1, 2; 3, 4":input)
        _polynomial=State(initialValue:source==nil ? "x^2+3x+2":input)
        _editingInput=State(initialValue:source==nil)
        let integral=try? PolynomialIntegralInput.parse(input)
        _variable=State(initialValue:integral?.variable ?? AlgebraComputationService().suggestedVariable(input) ?? "x")
        _lower=State(initialValue:integral?.lower ?? "0");_upper=State(initialValue:integral?.upper ?? "1")
    }
    private var request:MathComputationRequest {
        let raw=MathComputationRequest(operation:operation,inputA:operation.isMatrix ? matrixA:polynomial,inputB:operation.needsB ? (operation.isMatrix ? matrixB:algebraB):"",variable:variable,point:point,lower:lower,upper:upper)
        return (try? PolynomialIntegralInput.resolved(raw)) ?? raw
    }
    private var saved:[ComputationResult] { RowComputationScope.results(on:page,source:source,sessionIDs:sessionIDs) }
    private var currentResult:ComputationResult? { saved.first { $0.stableID==latestID } }
    private var isIntegration:Bool { [.splitIntegral,.integral,.definiteIntegral,.numericalIntegral].contains(operation) }
    private var hasReadBounds:Bool { review?.kind=="definiteIntegral" && operation.needsInterval }
    private var hasReadPoint:Bool { review?.kind=="limit" && [.limit,.limitLeft,.limitRight].contains(operation) }

    var body:some View {
        NavigationStack {
            Form {
                if stage != .result { sourcePreview }
                if stage == .choose { operationMenu }
                else if stage == .review {
                    Section {
                        LabeledContent("Operation",value:operation.title)
                        Button("Change operation") { stage = .choose }.accessibilityIdentifier("changeMathOperation")
                    }
                    inputReview
                    parameterFields
                    Section {
                        Button(busy ? "Computing…":"Compute",action:compute).disabled(busy || inspecting).accessibilityIdentifier("computeMath")
                        if busy { ProgressView();Button("Cancel",action:{task?.cancel()}) }
                        if !errorText.isEmpty { Text(errorText).foregroundStyle(.red).accessibilityIdentifier("mathError") }
                    }
                } else if let result=currentResult {
                    Section("Result for this calculation") { card(result) }
                    Section {
                        Button("Change inputs") { stage = .review }
                        Button("Another operation on this row") { stage = .choose }.accessibilityIdentifier("anotherRowComputation")
                    }
                }
                if !saved.filter({$0.stableID != latestID}).isEmpty {
                    Section {
                        DisclosureGroup(source==nil ? "Earlier in this calculation":"Earlier results for this row") {
                            ForEach(saved.filter{$0.stableID != latestID},id:\.stableID) { card($0) }
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively).accessibilityIdentifier("mathWorkbenchForm")
            .navigationTitle(stage == .choose ? "Choose an operation":stage == .review ? "Review calculation":"Result")
            .toolbar {
                ToolbarItemGroup(placement:.keyboard) {
                    if focusedInput != nil {
                        Spacer()
                        Button("Done editing") {focusedInput=nil}.accessibilityIdentifier("dismissMathKeyboard")
                    }
                }
                ToolbarItem(placement:.cancellationAction) { Button("Done") { task?.cancel();dismiss() }.accessibilityIdentifier("closeMathWorkbench") }
                if stage == .review {
                    ToolbarItem(placement:.confirmationAction) { Button(busy ? "Computing…":"Compute",action:compute).disabled(busy || inspecting).accessibilityIdentifier("computeMathToolbar") }
                }
            }
        }
        .onAppear { ProblemContextMathService.refresh(page:page);if let source { openingSnapshot=try? PolynomialResultStore.snapshot(source) } }
        .onChange(of:request) { _,_ in task?.cancel();errorText="";latestID=nil }
        .onChange(of:operation) { old,new in
            if [.limit,.limitLeft,.limitRight].contains(new) && ![.limit,.limitLeft,.limitRight].contains(old) { point="0" }
        }
        .task(id:request) { await inspect() }
        .onDisappear { task?.cancel() }
    }
    @ViewBuilder private var sourcePreview:some View {
        if let source {
            Section("Row \(source.sortIndex+1)") {
                MathJaxWebView(steps:[TypesetStep(latex:source.acceptedLatex,markdown:"",status:nil)]).frame(height:100)
                Text(source.acceptedLatex).font(.system(.caption,design:.monospaced)).accessibilityIdentifier("mathTargetLatex")
            }
        }
    }
    private var operationMenu:some View {
        Section("What would you like to do?") {
            Picker("Topic",selection:Binding(get:{operation.topic},set:{operation = $0==0 ? .rref:$0==1 ? .simplify:.derivative})) {
                Text("Matrices").tag(0);Text("Algebra").tag(1);Text("Calc 1").tag(2)
            }.pickerStyle(.segmented).accessibilityIdentifier("mathCategory")
            Picker("Operation",selection:$operation) {
                ForEach(MathOperation.allCases.filter{$0.topic==operation.topic}) { Text($0.title).tag($0) }
            }.accessibilityIdentifier("mathOperation")
            Button("Review inputs") { stage = .review }.buttonStyle(.borderedProminent).accessibilityIdentifier("reviewMathInputs")
            Text("Choose an operation first. You’ll review only the information it needs before running it.").font(.caption).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder private var inputReview:some View {
        Section(source==nil ? "Expression":"Review what was read") {
            if inspecting { HStack { ProgressView();Text("Reading the expression…").font(.caption) } }
            if !operation.isMatrix,let review {
                if source==nil || reusedID != nil || request.inputA != source?.acceptedLatex {
                    MathJaxWebView(steps:[TypesetStep(latex:review.integrand,markdown:"",status:nil)]).frame(height:90)
                }
                if operation.isComplex {LabeledContent("Number system",value:"Complex (i² = −1)")}
                else {LabeledContent("Variable",value:review.variable).accessibilityIdentifier("integralReadVariable")}
                if hasReadBounds,let a=review.lower,let b=review.upper {
                    LabeledContent("Lower limit",value:a).accessibilityIdentifier("integralReadLower")
                    LabeledContent("Upper limit",value:b).accessibilityIdentifier("integralReadUpper")
                }
                if hasReadPoint,let p=review.point { LabeledContent("Approach",value:p);if let side=review.direction { LabeledContent("Side",value:side) } }
            }
            if !reviewError.isEmpty { Text(reviewError).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("integralReadError") }
            DisclosureGroup(source==nil ? "Enter expression":"Edit this calculation’s input",isExpanded:$editingInput) {
                if operation.isMatrix { MatrixInputEditor(text:$matrixA,identifier:"matrixA").id(inputVersion) }
                else {
                    TextField(isIntegration ? "Full integral or integrand":"Expression or LaTeX",text:$polynomial,axis:.vertical).lineLimit(2...5)
                        .font(.system(.body,design:.monospaced)).accessibilityIdentifier("mathPolynomial").focused($focusedInput,equals:.expression)
                    Button("Clear expression") { polynomial="" }.accessibilityIdentifier("clearMathExpression")
                    if let review,(review.kind=="definiteIntegral" || review.kind=="integral") {
                        Button("Edit parts separately") {
                            // LaTeX readback is mathematical input; the worker reparses it.
                            polynomial=review.integrand;variable=review.variable
                            if let a=review.lower,let b=review.upper { lower=a;upper=b }
                        }.accessibilityIdentifier("editIntegralParts")
                    }
                }
                if source != nil { Text("Editing creates a separate calculation for this session; it does not change your accepted handwriting.").font(.caption) }
            }
        }.disabled(busy).textInputAutocapitalization(.never).autocorrectionDisabled()
    }
    @ViewBuilder private var parameterFields:some View {
        if operation.needsB {
            Section(operation == .splitIntegral ? "Split points (optional; comma-separated)":operation == .compose ? "Inner expression B (A is applied to B)":operation.isMatrix ? "Second matrix":operation == .volumeWasher ? "Inner radius r(x)":"Second expression / curve") {
                if operation.isMatrix { MatrixInputEditor(text:$matrixB,identifier:"matrixB") }
                else { TextField(operation == .splitIntegral ? "Auto-detect linear absolute-value corners, or enter 0, 1":"Expression B",text:$algebraB,axis:.vertical).accessibilityIdentifier("mathExpressionB").focused($focusedInput,equals:.secondExpression) }
            }.disabled(busy).textInputAutocapitalization(.never).autocorrectionDisabled()
        }
        if operation.needsPoint && !hasReadPoint {
            Section([.limit,.limitLeft,.limitRight].contains(operation) ? "Approach point":operation == .matrixPower ? "Integer exponent (−10…10)":operation == .matrixScale ? "Scalar":"At which point?") {
                TextField("Value",text:$point).accessibilityIdentifier("mathPoint").focused($focusedInput,equals:.point)
            }.disabled(busy).textInputAutocapitalization(.never).autocorrectionDisabled()
        }
        if operation.needsInterval && !hasReadBounds {
            Section(operation == .rootInterval ? "Bracket around one root":"Interval") {
                TextField("Lower limit",text:$lower).accessibilityIdentifier("mathLower").focused($focusedInput,equals:.lower)
                TextField("Upper limit",text:$upper).accessibilityIdentifier("mathUpper").focused($focusedInput,equals:.upper)
            }.disabled(busy).textInputAutocapitalization(.never).autocorrectionDisabled()
        }
        Section {
            DisclosureGroup("Details and supported notation",isExpanded:$showDetails) {
                if !operation.isMatrix && !operation.isComplex && operation != .implicitDerivative {
                    TextField("Variable (for constant expressions)",text:$variable).accessibilityIdentifier("mathVariable").focused($focusedInput,equals:.variable)
                }
                if !operation.isNativeAlgebraExtension {Text(operation.isMatrix ? "Exact numeric matrices up to 6 × 6.":"Single-variable elementary functions, radians. ln is natural logarithm; log is base 10. Variable and limits are read from full notation. Numerical results are marked ≈; unresolved or unsafe domains produce an error.").font(.caption)}
                if operation.isNativeAlgebraExtension { Text(operation.isComplex ? "Exact rational real/imaginary parts with i, parentheses, fractions and integer powers 0–20. Complex radicals and general variables are not supported.":operation == .solveInequality ? "One linear/quadratic polynomial inequality in a real variable. Type <= or >=; chained inequalities and variable denominators are not supported.":operation == .solveAbsolute ? "Use |a*x+b|=c or abs(a*x+b)=c, with a constant right side.":"Expression A is the outer polynomial; B is the inner polynomial. Computes A(B(x)), with result degree at most 20.").font(.caption) }
                if operation == .implicitDerivative { Text("Enter an equation in x and y. Computes dy/dx where F_y ≠ 0.").font(.caption) }
                if operation == .volumeDisk { Text("Disks about the x-axis: π ∫ f(x)² dx.").font(.caption) }
                if operation == .volumeWasher { Text("Enter nonnegative outer radius as expression A and inner radius as B, with outer ≥ inner on the interval. π ∫ (R² − r²) dx.").font(.caption) }
                if operation == .volumeShell { Text("Shells about the y-axis: 2π ∫ x |f(x)| dx; x ≥ 0.").font(.caption) }
                if operation == .integral { Text("An antiderivative includes +C and is checked by differentiation. Some functions have no supported elementary antiderivative.").font(.caption) }
                if operation == .numericalIntegral { Text("Finite, continuity-checked intervals only. Estimated error is reported; this is an approximation, not an exact result.").font(.caption) }
            }
        }
    }
    private func inspect() async {
        let id=UUID();inspectionID=id;review=nil;reviewError="";inspecting=false
        defer { if inspectionID==id { inspecting=false } }
        guard !operation.isMatrix,operation != .implicitDerivative,!request.inputA.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { return }
        let input=request;inspecting=true
        do {
            if operation.isNativeAlgebraExtension {
                let v=try AlgebraComputationService().extensionVariable(input)
                review=Calc1InputReview(variable:operation.isComplex ? "i is the imaginary unit":v,integrand:input.inputA,kind:"expression",lower:nil,upper:nil,point:nil,direction:nil)
                return
            }
            try await Task.sleep(for:.milliseconds(220));try Task.checkCancellation()
            let resolved:MathComputationRequest
            if let source,input.inputA==source.acceptedLatex,source.problemGroupID != nil {
                resolved=try ProblemContextMathService.plan(input,page:page,target:source).request
            } else { resolved=try WorksheetMathNotation.resolved(input) }
            let value=try await Calc1MathService.inspect(resolved);try Task.checkCancellation()
            guard request==input else { return };review=value
            if value.kind=="limit",let side=value.direction {
                let chosen:MathOperation=side=="left" ? .limitLeft:.limitRight
                if operation != chosen { operation=chosen }
            }
        } catch is CancellationError { }
        catch { if request==input { reviewError=error.localizedDescription } }
    }
    private func card(_ result:ComputationResult)->some View {
        VStack(alignment:.leading,spacing:10) {
            PolynomialResultCard(result:result,editorMatchesAccepted:true,onInsert:{ id in try await onInsert(id);dismiss() },onRemove:{ value in
                try onRemove(value)
                if value.stableID==latestID {latestID=nil;stage = .review}
            })
            if canReuse(result) {
                Button("Use this result as input") {
                    if (try? ExactMatrix.parse(result.outputLatex)) != nil && MathOperation(rawValue:result.operationRaw)?.isMatrix==true { matrixA=result.outputLatex;operation = .rref;inputVersion=UUID() }
                    else { polynomial=result.outputLatex;variable=result.variable;operation = MathOperation(rawValue:result.operationRaw)?.isComplex==true ? .complexCalculate:.simplify }
                    reusedID=result.stableID;editingInput=true;stage = .choose
                }.disabled(busy || !result.isCurrent).accessibilityIdentifier("reuseMathResult")
            }
        }
    }
    private func canReuse(_ result:ComputationResult)->Bool {
        if let operation=MathOperation(rawValue:result.operationRaw),[.solveEquation,.solveInequality,.solveAbsolute].contains(operation) {return false}
        guard result.isCurrent,result.operationRaw != MathOperation.integral.rawValue,!result.outputLatex.contains("\\approx"),!result.outputLatex.contains("="),!result.outputLatex.contains("\\infty") else { return false }
        if MathOperation(rawValue:result.operationRaw)?.isComplex==true {return (try? ExactComplexValue.parse(result.outputLatex)) != nil}
        if MathOperation(rawValue:result.operationRaw)?.isMatrix==true { return (try? ExactMatrix.parse(result.outputLatex)) != nil }
        return !result.outputLatex.contains("\\text{")
    }
    private func compute() {
        guard !busy else { return }
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),to:nil,from:nil,for:nil)
        let input=request
        let linked=source != nil && reusedID==nil && input.inputA.trimmingCharacters(in:.whitespacesAndNewlines)==(openingSnapshot?.inputLatex ?? source?.acceptedLatex)?.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !linked || openingSnapshot != nil else { errorText="This row changed. Review its current transcription first.";return }
        busy=true;errorText=""
        task=Task { @MainActor in
            defer { busy=false }
            do {
                let plan=try linked ? source.map{try ProblemContextMathService.plan(input,page:page,target:$0)}:nil
                let computed=try await MathComputationWorker.shared.compute(plan?.request ?? input);try Task.checkCancellation()
                let answer=MathComputationAnswer(request:computed.request,inputLatex:input.inputA,outputLatex:computed.outputLatex,
                    steps:(plan?.summaries ?? [])+computed.steps,engineVersion:computed.engineVersion)
                guard request==input else { return }
                let result=try MathResultStore.save(answer,page:page,source:linked ? source:nil,expected:linked ? openingSnapshot:nil,context:context,sourceContext:plan?.sources ?? [],contextGroupID:plan?.groupID,sourceResults:plan?.resultSources ?? [])
                sessionIDs.insert(result.stableID);latestID=result.stableID;stage = .result
            } catch is CancellationError { }
            catch { errorText=error.localizedDescription }
        }
    }
}

private struct MatrixInputEditor:View {
    @Binding var text:String
    let identifier:String
    @State private var pasteMode=false
    @State private var rows=2
    @State private var columns=2
    @State private var cells=[String](repeating:"",count:4)
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            Picker("Input format",selection:$pasteMode) {
                Text("Grid").tag(false)
                Text("LaTeX / rows").tag(true)
            }.pickerStyle(.segmented).accessibilityIdentifier(identifier+"InputMode")
            if pasteMode {
                TextField("1, 2; 3, 4",text:$text,axis:.vertical).lineLimit(3...6)
                    .font(.system(.body,design:.monospaced)).accessibilityIdentifier(identifier+"Text")
                Button("Clear matrix text") { text="" }.buttonStyle(.borderless).accessibilityIdentifier(identifier+"Clear")
                Text("Rows: newlines or semicolons. Cells: commas or spaces. Also accepts bmatrix, pmatrix and matrix LaTeX.").font(.caption)
            } else {
                HStack {
                    Stepper("Rows: \(rows)",value:Binding(get:{rows},set:{resize($0,columns)}),in:1...6).accessibilityIdentifier(identifier+"Rows")
                    Stepper("Columns: \(columns)",value:Binding(get:{columns},set:{resize(rows,$0)}),in:1...6).accessibilityIdentifier(identifier+"Columns")
                }
                ForEach(0..<rows,id:\.self) { r in
                    HStack {
                        ForEach(0..<columns,id:\.self) { c in
                            let index=r*columns+c
                            TextField("0",text:Binding(get:{cells.indices.contains(index) ? cells[index]:""},set:{ value in
                                guard cells.indices.contains(index) else { return };cells[index]=value;publish()
                            })).textFieldStyle(.roundedBorder).frame(minWidth:36)
                                .accessibilityLabel("Row \(r+1), column \(c+1)").accessibilityIdentifier(identifier+"-\(r)-\(c)")
                        }
                    }
                }
                Text("Each cell accepts an integer, decimal or fraction such as −2 or 1/3. Empty cells must be filled.").font(.caption)
            }
        }.textInputAutocapitalization(.never).autocorrectionDisabled()
            .onAppear { load(fallbackToPaste:true) }.onChange(of:pasteMode) { _,value in if !value { load(fallbackToPaste:false) } }
    }
    private func load(fallbackToPaste:Bool) {
        if let matrix=try? ExactMatrix.parse(text) {
            rows=matrix.rows;columns=matrix.columns;cells=matrix.cells.flatMap {$0.map(\.plain)}
        } else if fallbackToPaste { pasteMode=true }
        else { rows=2;columns=2;cells=[String](repeating:"",count:4) }
    }
    private func resize(_ r:Int,_ c:Int) {
        var next=[String](repeating:"0",count:r*c)
        for y in 0..<min(rows,r) { for x in 0..<min(columns,c) { next[y*c+x]=cells[y*columns+x] } }
        rows=r;columns=c;cells=next;publish()
    }
    private func publish() { text=(0..<rows).map { r in (0..<columns).map {cells[r*columns+$0]}.joined(separator:",") }.joined(separator:";") }
}
