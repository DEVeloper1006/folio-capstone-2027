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
    private var matchesAccepted:Bool { step.isAccepted && draft.trimmingCharacters(in:.whitespacesAndNewlines)==step.acceptedLatex }
    private var canReview:Bool { ![.collecting,.recognizing,.failed].contains(step.recognitionState) }
    private var results:[ComputationResult] { step.computationResults.filter{!$0.isRemoved}.sorted{$0.createdAt>$1.createdAt} }
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Text("Row \(step.sortIndex+1)").font(.headline)
                Spacer()
                if step.recognitionState == .recognizing && busy { ProgressView() }
                Text(matchesAccepted ? "Reviewed":"Check transcription").font(.caption).foregroundStyle(.secondary)
            }
            if !step.ghostLaTeX.isEmpty {
                problemGroupControls
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
                if matchesAccepted {
                    if let suggestion=ExpressionComputeSuggestion.forLatex(draft) {
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
        .onAppear { draft=step.isAccepted ? step.acceptedLatex:step.ghostLaTeX }
        .onChange(of:step.ghostLaTeX) { _,value in draft=value }
        .onChange(of:step.strokeFingerprint) { _,_ in draft=step.ghostLaTeX;editing=false;computation=nil }
    }
    @ViewBuilder private var problemGroupControls:some View {
        if let page=step.page {
            VStack(alignment:.leading,spacing:8) {
                Text("Related rows").font(.subheadline.weight(.semibold))
                if let groupID=step.problemGroupID {
                    Text("Grouped with \(page.steps.filter { $0.isActive && $0.problemGroupID == groupID }.count - 1) other row(s)")
                        .font(.caption).accessibilityIdentifier("problemGroupStatus-\(step.stableID.uuidString)")
                    Button("Start a separate problem",role:.destructive) { setProblemGroup(nil) }
                        .accessibilityIdentifier("ungroupProblemRow-\(step.stableID.uuidString)")
                } else {
                    Menu("Group with another row") {
                        ForEach(page.steps.filter { $0.isActive && $0.stableID != step.stableID }.sorted { $0.sortIndex < $1.sortIndex },id:\.stableID) { other in
                            Button("Row \(other.sortIndex + 1)") { groupProblem(with:other) }
                        }
                    }.disabled(page.steps.filter { $0.isActive && $0.stableID != step.stableID }.isEmpty)
                        .accessibilityIdentifier("groupProblemRow-\(step.stableID.uuidString)")
                    Text("Group rows that belong to one question. Definitions and calculations stay separate until you group them.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Assign both selected rows and any existing groups to one problem, then save the page.
    private func groupProblem(with other:Step) {
        guard let page=step.page else { return }
        let groupID=step.problemGroupID ?? other.problemGroupID ?? UUID()
        let previousIDs=Set([step.problemGroupID,other.problemGroupID].compactMap{$0})
        for member in page.steps where member.stableID == step.stableID || member.stableID == other.stableID || member.problemGroupID.map(previousIDs.contains) == true {
            member.problemGroupID=groupID
        }
        try? context.save()
    }

    /// Keep this row independent from its former problem and persist the change.
    private func setProblemGroup(_ groupID:UUID?) {
        step.problemGroupID=groupID
        try? context.save()
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
