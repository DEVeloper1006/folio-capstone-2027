import AVFoundation
import SwiftUI

/// Settings window: API key (edited in a glass sheet), models, voice, permissions.
struct SettingsView: View {
    @Environment(VoiceSession.self) private var session
    @Environment(PermissionsManager.self) private var permissions

    @AppStorage(Config.Key.jevModel) private var jevModel = Config.Default.jevModel
    @AppStorage(Config.Key.chatModel) private var chatModel = Config.Default.chatModel
    @AppStorage(Config.Key.maxTaskSteps) private var maxTaskSteps = Config.Default.maxTaskSteps
    @AppStorage(Config.Key.speakResponses) private var speakResponses = true
    @AppStorage(Config.Key.showOverlayPill) private var showOverlayPill = true
    @AppStorage(Config.Key.voiceIdentifier) private var voiceIdentifier = ""
    @AppStorage(Config.Key.ttsVoice) private var ttsVoice = Config.Default.ttsVoice.rawValue

    @State private var showingKeySheet = false
    @State private var keyStatus = Config.openRouterKey()
    @State private var elevenLabsStatus = Config.elevenLabsKey()
    @Namespace private var glass

    var body: some View {
        Form {
            Section("OpenRouter") {
                LabeledContent("API key") {
                    GlassEffectContainer(spacing: 8) {
                        HStack(spacing: 8) {
                            Label(keyStatusText, systemImage: keyStatus == nil ? "key.slash" : "key.fill")
                                .foregroundStyle(keyStatus == nil ? .orange : .secondary)
                                .padding(.horizontal, 10)
                                .frame(height: 28)
                                .glassEffect(.regular, in: .capsule)
                                .glassEffectID("status", in: glass)
                            Button(keyStatus == nil ? "Add…" : "Change…") { showingKeySheet = true }
                                .buttonStyle(.glass)
                                .tint(.clear)
                                .glassEffectID("edit", in: glass)
                        }
                    }
                }
            }

            Section("Models") {
                TextField("Jev (Decisions)", text: $jevModel, prompt: Text(Config.Default.jevModel))
                TextField("Chat (Claude)", text: $chatModel, prompt: Text(Config.Default.chatModel))
                Stepper("Max task steps: \(maxTaskSteps)", value: $maxTaskSteps, in: 3...40)
            }

            Section("Voice") {
                Toggle("Speak replies and confirmations", isOn: $speakResponses)
                Picker("Voice", selection: $ttsVoice) {
                    ForEach(TTSVoice.allCases) { voice in
                        Text("\(voice.name) — \(voice.detail)").tag(voice.rawValue)
                    }
                }
                if selectedVoice == .system {
                    Picker("System voice", selection: $voiceIdentifier) {
                        Text("System default").tag("")
                        ForEach(SpeechSynthesizer.availableVoices, id: \.identifier) { voice in
                            Text(voice.name).tag(voice.identifier)
                        }
                    }
                    .onChange(of: voiceIdentifier) { _, id in
                        session.tts.fallback.voiceIdentifier = id.isEmpty ? nil : id
                    }
                }
                LabeledContent("ElevenLabs") {
                    GlassEffectContainer(spacing: 8) {
                        HStack(spacing: 8) {
                            Label(elevenLabsStatusText, systemImage: elevenLabsStatus == nil ? "speaker.slash" : "waveform")
                                .foregroundStyle(elevenLabsStatus == nil ? .orange : .secondary)
                                .padding(.horizontal, 10)
                                .frame(height: 28)
                                .glassEffect(.regular, in: .capsule)
                                .glassEffectID("tts-status", in: glass)
                            Button {
                                Task { await session.tts.speak("Hi, I'm \(selectedVoice.name). This is how I'll sound.", voice: selectedVoice) }
                            } label: {
                                Label("Preview", systemImage: "play.fill")
                            }
                            .buttonStyle(.glass)
                            .tint(.clear)
                            .glassEffectID("tts-preview", in: glass)
                        }
                    }
                }
                Toggle("Show floating status pill", isOn: $showOverlayPill)
            }

            Section("Permissions") {
                PermissionRow(title: "Accessibility", detail: "Read and operate app UI", status: permissions.accessibility) {
                    permissions.requestAccessibility()
                    permissions.openAccessibilitySettings()
                }
                PermissionRow(title: "Microphone", detail: "Hear your voice", status: permissions.microphone) {
                    if permissions.microphone == .notDetermined {
                        Task { await permissions.requestMicrophone() }
                    } else {
                        permissions.openMicrophoneSettings()
                    }
                }
                PermissionRow(title: "Speech Recognition", detail: "Transcribe on device", status: permissions.speech) {
                    if permissions.speech == .notDetermined {
                        Task { await permissions.requestSpeech() }
                    } else {
                        permissions.openSpeechSettings()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { permissions.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions.refresh()
        }
        .sheet(isPresented: $showingKeySheet, onDismiss: { keyStatus = Config.openRouterKey() }) {
            APIKeySheet()
        }
    }

    private var selectedVoice: TTSVoice {
        TTSVoice(rawValue: ttsVoice) ?? Config.Default.ttsVoice
    }

    private var elevenLabsStatusText: String {
        guard let elevenLabsStatus else { return "No key · using System voice" }
        return "…\(elevenLabsStatus.value.suffix(4)) · \(elevenLabsStatus.source.rawValue)"
    }

    private var keyStatusText: String {
        guard let keyStatus else { return "Not set" }
        return "…\(keyStatus.value.suffix(4)) · \(keyStatus.source.rawValue)"
    }
}

// MARK: - API key sheet

private struct APIKeySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("OpenRouter API Key", systemImage: "key.fill")
                .font(.title3.weight(.semibold))

            Text("Used for Jev intent routing (OpenRouter Decisions API) and Claude chat. Stored in your login Keychain. An `OPENROUTER_API_KEY` environment variable or `.env` file takes precedence.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            SecureField("sk-or-…", text: $key)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)

            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            HStack {
                Button("Remove Key", role: .destructive) {
                    Config.clearOpenRouterKey()
                    dismiss()
                }
                .buttonStyle(.glass)
                .tint(.clear)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .buttonStyle(.glass)
                    .tint(.clear)
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func save() {
        do {
            try Config.saveOpenRouterKey(key)
            dismiss()
        } catch {
            self.error = "Couldn't save to Keychain: \(error)"
        }
    }
}

// MARK: - Permission row

private struct PermissionRow: View {
    let title: String
    let detail: String
    let status: PermissionsManager.Status
    let grant: () -> Void

    var body: some View {
        LabeledContent {
            if status.isGranted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.green)
            } else {
                Button("Grant…", action: grant)
                    .buttonStyle(.glass)
                    .tint(.clear)
            }
        } label: {
            Text(title)
            Text(detail)
        }
    }
}
