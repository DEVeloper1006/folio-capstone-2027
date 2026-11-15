import ElevenLabsKit
import Foundation

/// Curated voices for the Settings picker. Each ElevenLabs case maps to a premade voice id;
/// `.system` uses `AVSpeechSynthesizer`. IDs verified against the account's TTS endpoint on 2026-09-30.
enum TTSVoice: String, CaseIterable, Identifiable, Sendable {
    case rachel, drew, clyde, bella, charlie, system

    var id: String { rawValue }

    var name: String {
        switch self {
        case .rachel: "Rachel"
        case .drew: "Drew"
        case .clyde: "Clyde"
        case .bella: "Bella"
        case .charlie: "Charlie"
        case .system: "System Default"
        }
    }

    var detail: String {
        switch self {
        case .rachel: "Calm, warm female"
        case .drew: "Confident male"
        case .clyde: "Deep, authoritative male"
        case .bella: "Soft, friendly female"
        case .charlie: "Casual male"
        case .system: "On-device AVSpeechSynthesizer"
        }
    }

    /// ElevenLabs `voice_id`, or nil for the on-device voice.
    var elevenLabsID: String? {
        switch self {
        case .rachel: "21m00Tcm4TlvDq8ikWAM"
        case .drew: "29vD33N1CtxCmqQRPOHJ"
        case .clyde: "2EiwWnXFnvU5JabPnv8n"
        case .bella: "EXAVITQu4vr4xnSDxMaL"
        case .charlie: "IKne3meq5aSn9XLyUdCD"
        case .system: nil
        }
    }
}

/// Spoken output: ElevenLabs streaming TTS (`POST /v1/text-to-speech/{voice_id}/stream`, PCM played
/// through AVAudioEngine by ElevenLabsKit), falling back to `AVSpeechSynthesizer` when the key is
/// missing, the voice is "System Default", or the request fails before any audio arrives.
@MainActor
@Observable
final class ElevenLabsTTS {
    enum Engine: String, Sendable { case elevenLabs = "ElevenLabs", system = "System" }

    private(set) var isSpeaking = false
    /// Which engine produced the last utterance, and why ElevenLabs was skipped if it was.
    private(set) var lastEngine: Engine?
    private(set) var lastError: String?

    /// On-device fallback. Also exposed so Settings can pick its `AVSpeechSynthesisVoice`.
    let fallback = SpeechSynthesizer()

    static let sampleRate = 22_050.0
    var requestTimeout: TimeInterval = 8

    @ObservationIgnored private let player = PCMStreamingAudioPlayer.shared

    /// Returns when playback finishes, is stopped, or the task is cancelled.
    func speak(_ text: String, voice: TTSVoice = Config.ttsVoice) async {
        stop()
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        guard let voiceID = voice.elevenLabsID else {
            await speakWithSystem(text, reason: nil)
            return
        }
        guard let key = Config.elevenLabsKey()?.value else {
            await speakWithSystem(text, reason: "ELEVENLABS_API_KEY not set")
            return
        }

        let client = ElevenLabsTTSClient(apiKey: key, requestTimeoutSeconds: requestTimeout)
        let request = ElevenLabsTTSRequest(
            text: text,
            modelId: Config.Default.ttsModel,
            outputFormat: "pcm_22050"
        )
        let probe = StreamProbe()
        let stream = probe.observe(client.streamSynthesize(voiceId: voiceID, request: request))

        isSpeaking = true
        lastEngine = .elevenLabs
        let result = await withTaskCancellationHandler {
            await player.play(stream: stream, sampleRate: Self.sampleRate)
        } onCancel: {
            Task { @MainActor in _ = PCMStreamingAudioPlayer.shared.stop() }
        }
        isSpeaking = false

        // Fall back only if nothing was heard: a mid-sentence failure shouldn't restart the sentence.
        if !result.finished, let error = probe.error, !probe.receivedAudio, !Task.isCancelled {
            await speakWithSystem(text, reason: String(describing: error.localizedDescription))
        }
    }

    func stop() {
        if isSpeaking { _ = player.stop() }
        fallback.stop()
        isSpeaking = false
    }

    private func speakWithSystem(_ text: String, reason: String?) async {
        lastEngine = .system
        lastError = reason
        isSpeaking = true
        await fallback.speak(text)
        isSpeaking = false
    }
}

/// Forwards an audio stream while recording whether any audio arrived and how it ended.
@MainActor
private final class StreamProbe {
    private(set) var receivedAudio = false
    private(set) var error: Error?

    func observe(_ upstream: AsyncThrowingStream<Data, Error>) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                do {
                    for try await chunk in upstream {
                        if !chunk.isEmpty { self.receivedAudio = true }
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    self.error = error
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
