import AVFoundation
import Speech

/// Streaming speech-to-text: mic → `AVAudioEngine` → `SFSpeechAudioBufferRecognitionRequest`.
///
/// `transcripts()` yields partial results and finishes after the final one. End of utterance is
/// detected by silence (no new partials for `silenceTimeout`) or `maxDuration`.
@MainActor
@Observable
final class SpeechRecognizer {
    struct Transcript: Sendable, Equatable {
        let text: String
        let isFinal: Bool
    }

    enum RecognizerError: Error, CustomStringConvertible {
        case unavailable
        case alreadyRunning

        var description: String {
            switch self {
            case .unavailable: "Speech recognizer is unavailable for this locale"
            case .alreadyRunning: "Already listening"
            }
        }
    }

    /// Normalized 0…1 mic level for the listening waveform.
    private(set) var level: Float = 0
    private(set) var isRunning = false

    var silenceTimeout: Duration = .milliseconds(1400)
    var maxDuration: Duration = .seconds(20)

    private let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceTimer: Task<Void, Never>?
    private var maxTimer: Task<Void, Never>?

    func transcripts() throws -> AsyncThrowingStream<Transcript, Error> {
        guard !isRunning else { throw RecognizerError.alreadyRunning }
        guard let recognizer, recognizer.isAvailable else { throw RecognizerError.unavailable }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        let (stream, continuation) = AsyncThrowingStream<Transcript, Error>.makeStream()

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(
            onBus: 0,
            bufferSize: 1024,
            format: format,
            block: Self.makeTap(request: request) { [weak self] level in
                Task { @MainActor in self?.level = level }
            }
        )
        engine.prepare()
        try engine.start()

        task = recognizer.recognitionTask(
            with: request,
            resultHandler: Self.makeResultHandler(continuation: continuation) { [weak self] in
                Task { @MainActor in self?.restartSilenceTimer() }
            }
        )
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.teardown() }
        }

        self.request = request
        isRunning = true
        maxTimer = Task { [weak self, maxDuration] in
            try? await Task.sleep(for: maxDuration)
            guard !Task.isCancelled else { return }
            self?.finishAudio()
        }
        return stream
    }

    /// Stop capturing and let the recognizer deliver its final result.
    func finishAudio() {
        guard isRunning else { return }
        stopEngine()
        request?.endAudio()
    }

    /// Abort without waiting for a final result.
    func cancel() {
        task?.cancel()
        teardown()
    }

    // MARK: - Private

    private func restartSilenceTimer() {
        silenceTimer?.cancel()
        silenceTimer = Task { [weak self, silenceTimeout] in
            try? await Task.sleep(for: silenceTimeout)
            guard !Task.isCancelled else { return }
            self?.finishAudio()
        }
    }

    private func stopEngine() {
        if engine.isRunning {
            engine.stop()
        }
        engine.inputNode.removeTap(onBus: 0)
        level = 0
    }

    private func teardown() {
        stopEngine()
        silenceTimer?.cancel()
        maxTimer?.cancel()
        silenceTimer = nil
        maxTimer = nil
        request = nil
        task = nil
        isRunning = false
    }

    // Built in nonisolated contexts so the closures are not main-actor isolated:
    // the tap runs on the audio render thread and results arrive on a background queue.

    private nonisolated static func makeTap(
        request: SFSpeechAudioBufferRecognitionRequest,
        onLevel: @escaping @Sendable (Float) -> Void
    ) -> AVAudioNodeTapBlock {
        { buffer, _ in
            request.append(buffer)
            guard let samples = buffer.floatChannelData?[0] else { return }
            let count = Int(buffer.frameLength)
            guard count > 0 else { return }
            var sum: Float = 0
            for i in 0..<count { sum += samples[i] * samples[i] }
            let rms = (sum / Float(count)).squareRoot()
            onLevel(min(1, rms * 12))
        }
    }

    private nonisolated static func makeResultHandler(
        continuation: AsyncThrowingStream<Transcript, Error>.Continuation,
        onActivity: @escaping @Sendable () -> Void
    ) -> (SFSpeechRecognitionResult?, Error?) -> Void {
        { result, error in
            if let result {
                let transcript = Transcript(text: result.bestTranscription.formattedString, isFinal: result.isFinal)
                continuation.yield(transcript)
                if result.isFinal {
                    continuation.finish()
                } else {
                    onActivity()
                }
            } else if let error {
                continuation.finish(throwing: error)
            }
        }
    }
}
