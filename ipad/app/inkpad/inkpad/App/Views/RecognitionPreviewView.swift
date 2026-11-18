/* The handwriting review interface for checking transcriptions, grouping related rows and starting row-scoped computations. */
import SwiftUI
import SwiftData

struct RecognitionPreviewView: View {
    let steps: [Step]
    let alternatives: [UUID: [String]]
    let durations: [UUID: Int]
    let provider: String
    let isRecognizing: Bool
    let notice: String
    @Binding var automaticRecognition:Bool
    let onSettings: () -> Void
    let onRecognize: () -> Void
    let onCancel: () -> Void
    let onAccept: (Step, String) -> Void
    let onClose: () -> Void
    let onInsertResult: @MainActor @Sendable (UUID) async throws -> Void
    let onRemoveResult: (ComputationResult) throws -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Handwriting preview").font(.headline)
                Spacer()
                Button(action: onClose) { Image(systemName: "xmark") }.accessibilityLabel("Close preview")
            }.padding()
            HStack {
                Text(provider == "local" ? "Local TexTeller" : provider == "mac" ? "Mac TexTeller" : "Apple Vision").font(.caption)
                Spacer()
                Button("Settings", action: onSettings)
                Button(isRecognizing ? "Recognizing…" : "Recognize", action: onRecognize).disabled(isRecognizing)
                if isRecognizing { Button("Cancel", action: onCancel) }
            }.padding(.horizontal).padding(.bottom, 8)
            if !notice.isEmpty { Text(notice).font(.caption).textSelection(.enabled).padding(.horizontal).padding(.bottom, 8) }
            Toggle("Recognize after writing",isOn:$automaticRecognition).font(.caption).padding(.horizontal).padding(.bottom,8)
                .accessibilityIdentifier("automaticRecognitionToggle")
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if steps.filter({ $0.source == .inferred }).isEmpty {
                        Text("Write one expression per row. Tap its indicator to review and compute, or use Recognize.").foregroundStyle(.secondary)
                    }
                    ForEach(steps.filter { $0.source == .inferred }, id: \.stableID) { step in
                        ExpressionReviewRow(step: step, alternatives: alternatives[step.stableID] ?? [],
                            duration: durations[step.stableID] ?? step.recognitionMilliseconds,
                            busy: isRecognizing, onAccept: onAccept, onInsert: { id in try await onInsertResult(id) }, onRemove: onRemoveResult)
                    }
                }.padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier("recognitionRows")
            Text("Accept saves your transcription and a local benchmark example. Mathematics stays unchecked. Examples remain on this iPad.")
                .font(.caption2).foregroundStyle(.secondary).padding(8)
        }.background(.background)
    }
}

struct RowComputationPresentation:Identifiable {
    let id=UUID()
    let operation:MathOperation?
}

struct ExpressionReviewRow:View {
    @Environment(\.modelContext) private var context
    let step:Step
    let alternatives:[String]
    let duration:Int
    let busy:Bool
    let onAccept:(Step,String)->Void
    let onInsert:@MainActor @Sendable(UUID)async throws->Void
    let onRemove:(ComputationResult)throws->Void
    @State private var draft=""
    @State private var editing=false
    @State private var computation:RowComputationPresentation?
    @State private var problemError=""
    private var matchesAccepted:Bool { step.isAccepted && draft.trimmingCharacters(in:.whitespacesAndNewlines)==step.acceptedLatex }
    private var canReview:Bool { ![.collecting,.recognizing,.failed].contains(step.recognitionState) }
    private var results:[ComputationResult] { step.computationResults.filter{!$0.isRemoved}.sorted{$0.createdAt>$1.createdAt} }
    private var contextualCalculation:ProblemContextCalculation? {
        guard let page=step.page,step.problemIntent != .automatic else { return nil }
        return try? ProblemContextMathService.calculate(page:page,target:step)
    }
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Text("Row \(step.sortIndex+1)").font(.headline)
                Spacer()
                if step.recognitionState == .recognizing && busy { ProgressView() }
                Text(matchesAccepted ? "Reviewed":"Check transcription").font(.caption).foregroundStyle(.secondary)
            }
            if !step.ghostLaTeX.isEmpty {
                MathJaxWebView(steps:[TypesetStep(latex:draft,markdown:"",status:nil)]).frame(height:120)
                HStack {
                    Text(matchesAccepted ? "Ready to compute":"Does this match what you wrote?").font(.callout)
                    Spacer()
                    Button { onAccept(step,draft) } label: {
                        Label(matchesAccepted ? "Accepted":"Accept",systemImage:matchesAccepted ? "checkmark.circle.fill":"checkmark")
                    }.buttonStyle(.borderedProminent)
                        .disabled(!canReview || draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || matchesAccepted)
                        .accessibilityLabel(matchesAccepted ? "Transcription accepted":"Accept this transcription")
                        .accessibilityIdentifier("acceptExpression-"+step.stableID.uuidString)
                }
                DisclosureGroup("Edit recognition",isExpanded:$editing) {
                    TextEditor(text:$draft).font(.system(.callout,design:.monospaced)).frame(minHeight:80,maxHeight:150)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().disabled(!canReview)
                        .overlay(RoundedRectangle(cornerRadius:6).stroke(Color.secondary.opacity(0.3)))
                        .accessibilityIdentifier("latexEditor-"+step.stableID.uuidString)
                    HStack {
                        Button("Clear transcription") { draft="" }.accessibilityIdentifier("clearRecognitionDraft")
                        Spacer()
                        Button("Copy LaTeX") { UIPasteboard.general.string=draft }
                    }
                    ForEach(Array(alternatives.filter{$0 != draft}.enumerated()),id:\.offset) { _,latex in
                        Button { draft=latex } label: { Text(latex).font(.system(.caption,design:.monospaced)) }
                            .disabled(!canReview)
                    }
                    Text("Correct the expression, its variable and any limits, then tap the checkmark. Original ink is preserved.").font(.caption).foregroundStyle(.secondary)
                }
                problemGroupControls
                if matchesAccepted {
                    if contextualCalculation == nil,let suggestion=ExpressionComputeSuggestion.forLatex(draft) {
                        Button(suggestion.title) { computation=RowComputationPresentation(operation:suggestion.operation) }
                            .buttonStyle(.borderedProminent).accessibilityIdentifier("suggestedComputation")
                    }
                    Button("Choose an operation") { computation=RowComputationPresentation(operation:nil) }
                        .accessibilityIdentifier("moreComputations")
                } else { Text("Confirm the transcription to choose a calculation.").font(.caption).foregroundStyle(.secondary) }
            }
            if !canReview { Text(stateLabel).font(.caption).foregroundStyle(.secondary) }
            if !results.isEmpty {
                DisclosureGroup("Results for this row (\(results.count))") {
                    ForEach(results,id:\.stableID) { result in
                        PolynomialResultCard(result:result,editorMatchesAccepted:matchesAccepted,onInsert:{ id in try await onInsert(id) },onRemove:onRemove)
                    }
                }
            }
            Text("The checkmark confirms transcription; it does not verify a mathematical step.").font(.caption2).foregroundStyle(.secondary)
        }
        .sheet(item:$computation) { presentation in
            if let page=step.page {
                ComputationWorkbenchView(page:page,source:step,initialOperation:presentation.operation,onInsert:{ id in try await onInsert(id) },onRemove:onRemove).id(presentation.id)
            }
        }
        .onAppear { draft=step.isAccepted ? step.acceptedLatex:step.ghostLaTeX;refreshProblemContext() }
        .onChange(of:step.ghostLaTeX) { _,value in draft=value }
        .onChange(of:step.strokeFingerprint) { _,_ in draft=step.ghostLaTeX;editing=false;computation=nil }
    }
    @ViewBuilder private var problemGroupControls:some View {
        if let page=step.page,let groupID=step.problemGroupID {
            let members=page.steps.filter{$0.isActive && $0.problemGroupID==groupID}.sorted{$0.sortIndex<$1.sortIndex}
            if members.count>1 {
                VStack(alignment:.leading,spacing:8) {
                    Text("Detected problem · Rows \(members.map{String($0.sortIndex+1)}.joined(separator:", "))")
                        .font(.subheadline.weight(.semibold)).accessibilityIdentifier("problemGroupStatus-\(step.stableID.uuidString)")
                    if let calculation=contextualCalculation {
                        Text("Using "+calculation.substitutions.joined(separator:"; ").replacingOccurrences(of:"Substitute ",with:""))
                            .font(.caption).accessibilityIdentifier("problemSubstitutionSources-\(step.stableID.uuidString)")
                        Button("Verify & Solve",action:saveContextualCalculation)
                            .buttonStyle(.borderedProminent).disabled(!matchesAccepted)
                            .accessibilityIdentifier("substituteAndSolve-\(step.stableID.uuidString)")
                    } else if step.problemIntent == .definition {
                        Text("Read as a definition: "+(step.isAccepted ? step.acceptedLatex:step.ghostLaTeX)).font(.caption)
                    } else {
                        Text(contextualIssue).font(.caption).foregroundStyle(.secondary)
                    }
                    DisclosureGroup("Wrong problem?") {
                        Button(step.problemStartsNewScope == true ? "Use automatic context":"Separate here",action:toggleProblemBoundary)
                        Text("A separation starts a new problem at this row. Correct any misread equation in Edit recognition.").font(.caption)
                    }
                    if !problemError.isEmpty { Text(problemError).font(.caption).foregroundStyle(.red) }
                }
            } else if step.problemStartsNewScope == true {
                Button("Use automatic context",action:toggleProblemBoundary)
            }
        }
    }

    private var contextualIssue:String {
        guard let page=step.page else { return "Review the transcription first." }
        do { _=try ProblemContextMathService.calculate(page:page,target:step);return "" }
        catch { return error.localizedDescription }
    }

    /// Refresh cached equation ASTs and persist inferred context when an existing notebook preview opens.
    private func refreshProblemContext() {
        guard let page=step.page else { return }
        ProblemContextMathService.refresh(page:page)
        do { try context.save() } catch { problemError=error.localizedDescription }
    }

    /// Record a correction to the detected boundary and recompute automatic scopes without asking for row roles.
    private func toggleProblemBoundary() {
        step.problemStartsNewScope = step.problemStartsNewScope != true
        refreshProblemContext()
    }

    /// Save the contextual answer only if the target and every grouped definition still match the reviewed snapshots.
    private func saveContextualCalculation() {
        guard let page=step.page else { return }
        do {
            guard matchesAccepted else { throw PolynomialError.invalid("Verify the edited transcription before solving.") }
            guard let calculation=contextualCalculation else { throw PolynomialError.invalid("Select an equation that uses an earlier supported definition in this group.") }
            let expected=try PolynomialResultStore.snapshot(step)
            _=try MathResultStore.save(calculation.answer,page:page,source:step,expected:expected,context:context,
                sourceContext:calculation.sources,contextGroupID:calculation.groupID)
            problemError=""
        } catch { problemError=error.localizedDescription }
    }

    private var stateLabel:String {
        switch step.recognitionState {
        case .collecting:"Ink changed. Review a new recognition before computing."
        case .recognizing:busy ? "Reading handwriting…":"Reading paused. Retry when ready."
        case .failed:step.explanation
        case .ready,.ambiguous:"Review the transcription."
        }
    }
}
