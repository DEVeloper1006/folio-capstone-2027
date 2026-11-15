import SwiftUI
import SwiftData

struct IntegrationPresentation: Identifiable {
    let id = UUID()
    let snapshot: IntegrationSourceSnapshot
    let prepared: PreparedPolynomialIntegral
}

struct PolynomialIntegrationView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let source: Step
    let request: IntegrationPresentation
    @State private var variable: String
    @State private var busy = false
    @State private var errorText = ""
    @State private var task: Task<Void, Never>?

    init(source: Step, request: IntegrationPresentation) {
        self.source = source; self.request = request
        _variable = State(initialValue: request.prepared.suggestedVariable)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Accepted source") {
                    Text(request.snapshot.inputLatex).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                }
                Section("Integrand") {
                    MathJaxWebView(steps: [TypesetStep(latex: request.prepared.integrandLatex, markdown: "", status: nil)])
                        .frame(height: 130)
                    TextField("Variable", text: $variable)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.asciiCapable)
                        .accessibilityIdentifier("integrationVariable").disabled(busy)
                    Text("One Latin-letter variable. The result includes an arbitrary constant.").font(.caption)
                }
                if !errorText.isEmpty { Section { Text(errorText).foregroundStyle(.red).accessibilityIdentifier("integrationError") } }
                Section {
                    Button(busy ? "Computing…" : "Compute & Save") { compute() }
                        .disabled(busy).accessibilityIdentifier("computeIntegral")
                    if busy { ProgressView() }
                }
                Section { Text("Computed on this iPad using exact polynomial arithmetic. Unsupported notation is not approximated.").font(.caption) }
            }
            .navigationTitle("Integrate polynomial")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { task?.cancel(); dismiss() } } }
        }
        .onDisappear { task?.cancel() }
    }
    private func compute() {
        guard !busy else { return }
        busy = true; errorText = ""
        let chosen = variable.trimmingCharacters(in: .whitespacesAndNewlines)
        task = Task { @MainActor in
            defer { busy = false }
            do {
                let answer = try await PolynomialComputationWorker.shared.integrate(request.prepared, variable: chosen)
                try Task.checkCancellation()
                _ = try PolynomialResultStore.save(answer, snapshot: request.snapshot, source: source, context: context)
                dismiss()
            } catch is CancellationError { }
            catch { errorText = error.localizedDescription }
        }
    }
}

struct PolynomialResultCard: View {
    @Environment(\.modelContext) private var context
    let result: ComputationResult
    let editorMatchesAccepted: Bool
    var onInsert: (@MainActor @Sendable (UUID) async throws -> Void)? = nil
    var onRemove: ((ComputationResult) throws -> Void)? = nil
    @State private var inserting = false
    @State private var insertionTask: Task<Void, Never>?
    @State private var errorText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(result.isCurrent && editorMatchesAccepted ? result.operationTitle : "Outdated result")
                .font(.headline).accessibilityIdentifier("integralResultState")
            if MathOperation(rawValue:result.operationRaw)?.isMatrix != true && MathOperation(rawValue:result.operationRaw)?.isComplex != true && result.operationRaw != "arithmetic" {
                Text("Variable: \(result.variable)").font(.caption)
            }
            if let request=result.computationRequest {
                if request.operation.needsB { Text("B: "+request.inputB).font(.system(.caption,design:.monospaced)) }
                if [.matrixScale,.matrixPower].contains(request.operation) { Text((request.operation == .matrixPower ? "Exponent: ":"Scalar: ")+request.point).font(.caption) }
                if request.operation == .evaluate { Text("At \(request.variable) = \(request.point)").font(.caption) }
                if request.operation == .definiteIntegral { Text("Bounds: \(request.lower) to \(request.upper)").font(.caption) }
            }
            Text("From: " + result.inputLatex).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            MathJaxWebView(steps: [TypesetStep(latex: result.outputLatex, markdown: "", status: nil)]).frame(height: 140)
            if result.outputLatex.contains("\\approx") {
                Label("Approximate result — review the method and error estimate below",systemImage:"info.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(result.outputLatex).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                .accessibilityIdentifier("integralOutput")
            if !result.explanationSteps.isEmpty {
                VStack(alignment:.leading,spacing:4) {
                    Text("Method and conditions").font(.caption.weight(.semibold))
                    ForEach(Array(result.explanationSteps.enumerated()),id:\.offset) { index,text in
                        Text("\(index+1). \(text)").font(.system(.caption,design:.monospaced)).textSelection(.enabled)
                    }
                }
            }
            HStack {
                Button(inserting ? "Preparing…" : result.isPlacedOnCanvas ? "Show on page" : "Insert result") {
                    guard let onInsert, !inserting else { return }
                    inserting = true; errorText = ""
                    insertionTask = Task { @MainActor in
                        defer { inserting = false }
                        do { try await onInsert(result.stableID) }
                        catch is CancellationError { }
                        catch { errorText = error.localizedDescription }
                    }
                }.disabled(inserting || !result.isCurrent || !editorMatchesAccepted || onInsert == nil)
                    .accessibilityIdentifier("insertIntegralResult")
                Spacer()
                Button("Remove result", role: .destructive) {
                    do { if let onRemove { try onRemove(result) } else { try PolynomialResultStore.remove(result, context: context) } }
                    catch { errorText = error.localizedDescription }
                }.accessibilityIdentifier("removeIntegralResult")
            }
            if !result.isCurrent || !editorMatchesAccepted {
                Text("The source changed. Review the current input and compute again.").font(.caption)
            }
            if !errorText.isEmpty { Text(errorText).font(.caption).foregroundStyle(.red) }
        }.buttonStyle(.borderless).padding(12).background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            .onDisappear { if !result.isPlacedOnCanvas { insertionTask?.cancel() } }
    }
}
