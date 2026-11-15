import SwiftUI

struct VoicePillView: View {
    @State private var assistantState: AssistantState = .idle
    @State private var transcript = ""
    @State private var selectedModel = "Laya"
    @State private var showModelMenu = false
    @State private var wavePhase: CGFloat = 0
    @State private var dictatedLatex = ""
    @State private var showDictateChip = false
    @State private var showReadAloudPreview = false

    var selectionContext: String? = nil
    let onAnnotation: ((String) -> Void)?
    var onInsertLatex: ((String) -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            if assistantState != .idle {
                pillContent
                    .transition(.scale.combined(with: .opacity))
            }

            if showDictateChip {
                dictateChip
                    .transition(.scale.combined(with: .opacity))
            }

            HStack(spacing: 8) {
                micButton

                Button {
                    showReadAloudPreview = true
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(FolioTheme.dim)
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(FolioTheme.chromeBackground)
                                .shadow(color: FolioTheme.chromeShadow, radius: 4, y: 1)
                        )
                }
            }
        }
        .animation(.spring(duration: 0.3), value: assistantState)
        .popover(isPresented: $showReadAloudPreview) {
            readAloudPreview
        }
    }

    private var micButton: some View {
        Button {
            toggleListening()
        } label: {
            Image(systemName: assistantState == .idle ? "mic.fill" : "stop.fill")
                .font(.system(size: 20))
                .foregroundStyle(assistantState == .idle ? FolioTheme.ink : FolioTheme.statusError)
                .frame(width: 48, height: 48)
                .background(
                    Circle()
                        .fill(FolioTheme.chromeBackground)
                        .shadow(color: FolioTheme.chromeShadow, radius: 8, y: 2)
                )
        }
    }

    private var pillContent: some View {
        VStack(spacing: 8) {
            if selectionContext != nil {
                HStack(spacing: 4) {
                    Image(systemName: "lasso")
                        .font(.system(size: 11))
                    Text("talking about: selection")
                        .font(FolioTheme.uiFont(size: 11))
                }
                .foregroundStyle(FolioTheme.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(FolioTheme.accentFill))
            }

            if assistantState == .listening || assistantState == .responding {
                WaveformView(phase: wavePhase)
                    .frame(height: 24)
                    .onAppear {
                        withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                            wavePhase = .pi * 2
                        }
                    }
            }

            if assistantState == .thinking {
                ProgressView()
                    .tint(FolioTheme.accent)
            }

            if !transcript.isEmpty {
                Text(transcript)
                    .font(FolioTheme.uiFont(size: 13))
                    .foregroundStyle(FolioTheme.ink)
                    .lineLimit(2)
            }

            HStack(spacing: 4) {
                Text(selectedModel)
                    .font(FolioTheme.uiFont(size: 11, weight: .medium))
                Text("·")
                Text(selectedModel == "Laya" ? "on-device" : "cloud")
                    .font(FolioTheme.uiFont(size: 11))
            }
            .foregroundStyle(FolioTheme.dim)
            .onTapGesture { showModelMenu.toggle() }
            .popover(isPresented: $showModelMenu) {
                VStack(spacing: 0) {
                    ForEach(["Laya", "Jev"], id: \.self) { model in
                        Button {
                            selectedModel = model
                            showModelMenu = false
                        } label: {
                            HStack {
                                Text(model)
                                    .font(FolioTheme.uiFont(size: 14))
                                if model == selectedModel {
                                    Image(systemName: "checkmark")
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                        }
                        .foregroundStyle(FolioTheme.ink)
                    }
                }
                .presentationCompactAdaptation(.popover)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(FolioTheme.chromeBackground)
                .shadow(color: FolioTheme.chromeShadow, radius: 8, y: 2)
        )
        .frame(maxWidth: 280)
    }

    private var dictateChip: some View {
        HStack(spacing: 8) {
            Text("$\(dictatedLatex)$")
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(FolioTheme.accent)

            Button {
                onInsertLatex?(dictatedLatex)
                showDictateChip = false
                dictatedLatex = ""
            } label: {
                Text("Insert")
                    .font(FolioTheme.uiFont(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(FolioTheme.accent))
            }

            Button {
                showDictateChip = false
                dictatedLatex = ""
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(FolioTheme.dim)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(FolioTheme.chromeBackground)
                .shadow(color: FolioTheme.chromeShadow, radius: 6, y: 2)
        )
    }

    private var readAloudPreview: some View {
        VStack(spacing: 12) {
            Text("PREVIEW")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(FolioTheme.statusWarn))

            Image(systemName: "speaker.wave.2.circle")
                .font(.system(size: 28))
                .foregroundStyle(FolioTheme.dim)
            Text("Read Aloud")
                .font(FolioTheme.uiFont(size: 15, weight: .semibold))
            Text("AI reads your work aloud, describing equations and steps in natural language.")
                .font(FolioTheme.uiFont(size: 12))
                .foregroundStyle(FolioTheme.muted)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(width: 240)
        .presentationCompactAdaptation(.popover)
    }

    private func toggleListening() {
        switch assistantState {
        case .idle:
            assistantState = .listening
            transcript = ""
            simulateSession()
        default:
            assistantState = .idle
            transcript = ""
        }
    }

    private func simulateSession() {
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard assistantState == .listening else { return }

            if selectionContext != nil {
                transcript = "What's happening with this part..."
                assistantState = .thinking
                try? await Task.sleep(for: .seconds(1))
                guard assistantState == .thinking else { return }
                assistantState = .responding
                transcript = "The selected step has an error in row 2."
                onAnnotation?("Check row 2's first entry in your selection")
                try? await Task.sleep(for: .seconds(2))
                assistantState = .idle
            } else {
                transcript = "x squared over two"
                assistantState = .thinking
                try? await Task.sleep(for: .seconds(0.8))
                guard assistantState == .thinking else { return }
                dictatedLatex = "\\frac{x^2}{2}"
                showDictateChip = true
                assistantState = .idle
                transcript = ""
            }
        }
    }
}

struct WaveformView: View {
    let phase: CGFloat
    private let barCount = 20

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { i in
                let height = 4.0 + 16.0 * abs(sin(phase + CGFloat(i) * 0.4))
                RoundedRectangle(cornerRadius: 1)
                    .fill(FolioTheme.accent.opacity(0.6))
                    .frame(width: 3, height: height)
            }
        }
    }
}
