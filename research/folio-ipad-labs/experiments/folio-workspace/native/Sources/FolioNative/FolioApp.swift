import SwiftUI
import FolioCore

@MainActor final class FolioSession: ObservableObject {
    // All windows share one document and serialized writer. Tests never open
    // the real notebook.
    let notebook: Notebook? = CommandLine.arguments.contains("--self-test") ? nil : Notebook()
}

@main struct FolioApp: App {
    @StateObject private var session = FolioSession()
    init() {
        #if os(macOS)
        if CommandLine.arguments.contains("--self-test") {
            Task { @MainActor in
                do { try await NativeChecks.run(); print("Native integration checks passed"); exit(0) }
                catch { fputs("Native check failed: \(error)\n", stderr); exit(1) }
            }
        }
        #endif
    }
    var body: some Scene {
        WindowGroup {
            if let book = session.notebook { Workspace(book: book).preferredColorScheme(.light) }
            else { Text("Running isolated integration checks") }
        }
    }
}

struct Workspace: View {
    @StateObject private var book: Notebook
    @State private var settings = false
    @State private var examples = false
    @State private var confirmClear = false
    @MainActor init(book: Notebook? = nil) { _book = StateObject(wrappedValue: book ?? Notebook()) }
    private let accent = Color(red: 0.09, green: 0.42, blue: 0.38)
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Folio").font(.system(size: 28, weight: .medium, design: .serif))
                    Text("Ink first. Typeset beside it.").font(.subheadline).foregroundStyle(Color(red: 0.35, green: 0.40, blue: 0.42))
                }
                Spacer()
                Button(action: book.undo) { Image(systemName: "arrow.uturn.backward") }.disabled(!book.canUndo).accessibilityLabel("Undo").keyboardShortcut("z")
                Button(action: book.redo) { Image(systemName: "arrow.uturn.forward") }.disabled(!book.canRedo).accessibilityLabel("Redo").keyboardShortcut("z", modifiers: [.command, .shift])
                Button("Clear page") { confirmClear = true }.disabled(book.document.strokes.isEmpty)
                Button("Examples") { examples = true }
                Button("Connection") { settings.toggle() }
            }.padding(24)
            Divider()
            GeometryReader { geometry in
                if geometry.size.width >= 720 {
                    HStack(spacing: 0) {
                        writing.frame(width: geometry.size.width * 0.58)
                        Divider()
                        shadow
                    }
                } else {
                    VStack(spacing: 0) {
                        writing.frame(height: geometry.size.height * 0.52)
                        Divider()
                        shadow
                    }
                }
            }
            Divider()
            HStack {
                Text(book.saveStatus)
                Spacer()
                Button("Retry save", action: book.retrySave)
                Text(book.localModel)
            }.font(.caption).foregroundStyle(Color(red: 0.35, green: 0.40, blue: 0.42)).padding(12)
        }
        .foregroundStyle(Color(red: 0.15, green: 0.18, blue: 0.20))
        .task { await book.refreshLocalModel() }
        .environment(\.colorScheme, .light)
        .background(Color(red: 0.97, green: 0.98, blue: 0.98))
        .tint(accent)
        .confirmationDialog("Clear this page? You can undo this while the app stays open.", isPresented: $confirmClear) {
            Button("Clear page", role: .destructive, action: book.clearPage)
        }
        .sheet(isPresented: $examples) { PracticeGallery() }
        .sheet(isPresented: $settings) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Optional cloud recognition").font(.title2)
                Text("Only the row you select is sent to your Folio server and then Gemini. Local drawing and preview do not need a connection.")
                TextField("Folio server URL", text: $book.endpoint).textFieldStyle(.roundedBorder)
                Text("On iPad, localhost means the iPad. Use a trusted HTTPS endpoint for your Mac server; do not expose the unauthenticated API to the internet.").font(.caption).foregroundStyle(Color(red: 0.35, green: 0.40, blue: 0.42))
                Toggle("Allow sending selected handwriting to Gemini", isOn: $book.cloudConsent)
                    .onChange(of: book.cloudConsent) { _, allowed in if !allowed { book.revokeCloud() } }
                Button("Done") { settings = false }.buttonStyle(.borderedProminent).foregroundStyle(.white)
            }.padding(32).frame(minWidth: 320, idealWidth: 480)
        }
    }
    private var writing: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Text("Handwriting").font(.headline); Spacer(); Text("Original").font(.caption).foregroundStyle(Color(red: 0.35, green: 0.40, blue: 0.42)) }.padding(20)
            Picker("Recognition mode", selection: $book.recognitionMode) {
                Text("Numbers").tag("numbers")
                Text("Algebra").tag("math")
            }.pickerStyle(.segmented).padding(.horizontal, 20).padding(.bottom, 12)
                .onChange(of: book.recognitionMode) { _, _ in book.changeRecognitionMode() }
            InkSurface(book: book)
        }
    }
    private var shadow: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Typeset shadow").font(.system(size: 24, design: .serif))
                    Text("Uncertain symbols stay as ink. Select a row to correct it.").font(.subheadline).foregroundStyle(Color(red: 0.35, green: 0.40, blue: 0.42))
                }
                if book.regions.isEmpty {
                    Text("Start with a short expression.\nThe preview follows after you lift the pen.")
                        .foregroundStyle(Color(red: 0.35, green: 0.40, blue: 0.42)).padding(.vertical, 32)
                }
                ForEach(Array(book.regions.enumerated()), id: \.element.id) { index, region in
                    VStack(alignment: .leading, spacing: 12) {
                        Button { book.select(region) } label: {
                            HStack(alignment: .center, spacing: 16) {
                                Text(String(format: "%02d", index + 1)).font(.caption.monospacedDigit()).foregroundStyle(Color(red: 0.35, green: 0.40, blue: 0.42))
                                ScrollView(.horizontal) { ShadowView(node: region.node).padding(.vertical, 8) }
                                Spacer(minLength: 0)
                                Image(systemName: book.accepted(region) == nil ? "pencil" : "checkmark.circle")
                            }.padding(12).background(book.selected == region.id ? accent.opacity(0.08) : Color.white)
                        }.buttonStyle(.plain).accessibilityLabel("Review row \(index + 1)")
                        if book.localFailed(region) {
                            Text("No complete reading. Select this row to correct it, or change recognition mode.")
                                .font(.caption).foregroundStyle(Color(red: 0.35, green: 0.40, blue: 0.42))
                        }
                        if let draft = book.localDraft(region), book.accepted(region) == nil {
                            Text("Local model draft").font(.caption).foregroundStyle(accent)
                            MathPreview(latex: draft.latex).frame(height: 110)
                        }
                        if let accepted = book.accepted(region) {
                            Text("Accepted transcription").font(.caption).foregroundStyle(accent)
                            MathPreview(latex: accepted.latex).frame(height: 110)
                        }
                    }
                }
                if let region = book.selection {
                    Divider()
                    Text("Review transcription").font(.headline)
                    TextField("Enter or correct LaTeX", text: $book.correction, axis: .vertical)
                        .textFieldStyle(.roundedBorder).lineLimit(2...6)
                        .onChange(of: book.correction) { _, _ in book.correctionChanged() }
                    if !book.correction.isEmpty { MathPreview(latex: book.correction).frame(height: 110) }
                    ViewThatFits {
                        HStack { reviewButtons(region) }
                        VStack(alignment: .leading) { reviewButtons(region) }
                    }
                    if let draft = book.localDraft(region) {
                        Button("Use local draft", action: book.useLocalDraft)
                        if !draft.alternatives.isEmpty {
                            Text("Other readings").font(.caption).foregroundStyle(Color(red: 0.35, green: 0.40, blue: 0.42))
                            ForEach(draft.alternatives, id: \.self) { alternative in
                                Button { book.correction = alternative } label: {
                                    Text(alternative).font(.system(.body, design: .monospaced)).lineLimit(3)
                                }.help("Use this reading in the correction field")
                            }
                        }
                    }
                    Button("Learn this letter or digit", action: book.learnSymbol).font(.caption)
                    Text("Teaching works for a single isolated letter or digit. Examples last for this session.").font(.caption).foregroundStyle(Color(red: 0.35, green: 0.40, blue: 0.42))
                }
                Text(book.status).font(.subheadline).foregroundStyle(Color(red: 0.35, green: 0.40, blue: 0.42)).accessibilityAddTraits(.updatesFrequently)
                Text(book.localStatus).font(.subheadline).foregroundStyle(Color(red: 0.35, green: 0.40, blue: 0.42))
                Button("Retry local", action: book.retryLocalRecognition)
                Text("TexTeller reads each row locally after a pause. Original ink stays visible while it works. Drafts can be wrong; review before accepting. No cloud connection required.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    @ViewBuilder private func reviewButtons(_ region: ShadowRegion) -> some View {
        Button("Accept transcription", action: book.accept).buttonStyle(.borderedProminent).foregroundStyle(.white).disabled(book.correction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        Button(book.busy ? "Reading..." : "Ask Gemini") {
            if let data = inkPNG(region.strokes) { book.resolve(image: data) }
        }.disabled(!book.cloudConsent || book.busy || book.accepted(region) != nil)
    }
}
