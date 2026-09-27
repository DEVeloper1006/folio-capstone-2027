import SwiftUI

struct VoicePillView: View {
    @State private var assistantState: AssistantState = .idle
    @State private var transcript = ""
    @State private var selectedModel = "Laya"
    @State private var showModelMenu = false
    @State private var wavePhase: CGFloat = 0

    let onAnnotation: ((String) -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            if assistantState != .idle {
                pillContent
                    .transition(.scale.combined(with: .opacity))
            }

            micButton
        }
        .animation(.spring(duration: 0.3), value: assistantState)
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
                Text("on-device")
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
            transcript = "Check row 2 after the operation..."
            assistantState = .thinking
            try? await Task.sleep(for: .seconds(1))
            guard assistantState == .thinking else { return }
            assistantState = .responding
            transcript = "The pivot in row 2 should be 1."
            onAnnotation?("What's row 2's first entry now?")
            try? await Task.sleep(for: .seconds(2))
            assistantState = .idle
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
