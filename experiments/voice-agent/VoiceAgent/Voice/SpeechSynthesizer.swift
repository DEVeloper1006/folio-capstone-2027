import AVFoundation

/// Async wrapper over `AVSpeechSynthesizer`: `await speak(text)` returns when speech ends or is stopped.
@MainActor
@Observable
final class SpeechSynthesizer: NSObject, AVSpeechSynthesizerDelegate {
    private(set) var isSpeaking = false

    /// `AVSpeechSynthesisVoice.identifier`; nil uses the system default voice.
    var voiceIdentifier: String?
    var rate: Float = AVSpeechUtteranceDefaultSpeechRate

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var current: ObjectIdentifier?
    @ObservationIgnored private var continuation: CheckedContinuation<Void, Never>?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) async {
        stop()
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = rate
        if let voiceIdentifier, let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
            utterance.voice = voice
        }
        let id = ObjectIdentifier(utterance)

        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                self.current = id
                self.isSpeaking = true
                synthesizer.speak(utterance)
            }
        } onCancel: {
            Task { @MainActor in self.stop() }
        }
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        finish(current)
    }

    static var availableVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(Locale.current.language.languageCode?.identifier ?? "en") }
            .sorted { $0.name < $1.name }
    }

    private func finish(_ id: ObjectIdentifier?) {
        guard let id, id == current else { return }
        current = nil
        isSpeaking = false
        continuation?.resume()
        continuation = nil
    }

    // MARK: AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.finish(id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.finish(id) }
    }
}
