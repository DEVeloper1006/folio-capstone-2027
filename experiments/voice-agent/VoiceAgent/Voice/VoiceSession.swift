import ApplicationServices
import Carbon.HIToolbox
import Foundation

/// The app's central state machine:
/// `idle → listening → thinking → executing → speaking → done | error → idle`.
///
/// Owns the pipeline task; every UI surface (pill, menu, conversation panel) observes this object.
@MainActor
@Observable
final class VoiceSession {
    enum State: Equatable {
        case idle
        case listening
        case thinking
        case executing(label: String, symbol: String)
        case speaking
        case done(String)
        case error(String)

        var isBusy: Bool {
            switch self {
            case .idle, .done, .error: false
            default: true
            }
        }

        var symbol: String {
            switch self {
            case .idle: "waveform"
            case .listening: "mic.fill"
            case .thinking: "sparkles"
            case .executing(_, let symbol): symbol
            case .speaking: "speaker.wave.2.fill"
            case .done: "checkmark"
            case .error: "xmark"
            }
        }

        var label: String {
            switch self {
            case .idle: "Ready"
            case .listening: "Listening…"
            case .thinking: "Thinking…"
            case .executing(let label, _): label
            case .speaking: "Speaking…"
            case .done(let message): message
            case .error(let message): message
            }
        }
    }

    private(set) var state: State = .idle
    private(set) var transcript = ""
    private(set) var lastIntent: String?
    private(set) var lastJevLatency: Duration?
    /// SF Symbol of an early intent that just fired mid-speech; the pill flashes it while listening.
    private(set) var earlyFlash: String?

    let permissions: PermissionsManager
    let recognizer: SpeechRecognizer
    let tts: ElevenLabsTTS
    let conversation: ConversationManager
    let taskRunner: TaskRunner
    let apps: AppCatalog

    @ObservationIgnored private let router: IntentRouter
    @ObservationIgnored private var pipeline: Task<Void, Never>?
    @ObservationIgnored private var resetTask: Task<Void, Never>?
    @ObservationIgnored private var toggleHotKey: GlobalHotKey?
    @ObservationIgnored private var cancelHotKey: GlobalHotKey?
    @ObservationIgnored private let earlyDetector: EarlyIntentDetector
    @ObservationIgnored private var earlyFired: EarlyIntent?
    @ObservationIgnored private var lastEarlyMatch: EarlyIntent?
    @ObservationIgnored private var earlyTask: Task<ActionResult, Never>?
    @ObservationIgnored private var flashTask: Task<Void, Never>?

    init() {
        let jev = JevClient()
        let llm = LLMClient()
        let apps = AppCatalog()
        let executor = ActionExecutor(apps: apps)
        let conversation = ConversationManager()
        let taskRunner = TaskRunner(jev: jev, executor: executor, apps: apps)

        self.permissions = PermissionsManager()
        self.recognizer = SpeechRecognizer()
        self.tts = ElevenLabsTTS()
        self.conversation = conversation
        self.taskRunner = taskRunner
        self.apps = apps
        self.router = IntentRouter(
            jev: jev, llm: llm, executor: executor, taskRunner: taskRunner,
            conversation: conversation, apps: apps
        )
        self.earlyDetector = EarlyIntentDetector(resolveApp: { apps.resolve($0) != nil })
        self.tts.fallback.voiceIdentifier = UserDefaults.standard.string(forKey: Config.Key.voiceIdentifier)
    }

    /// ⌥Space toggles listening/cancel from anywhere.
    func registerHotKeys() {
        toggleHotKey = GlobalHotKey(keyCode: kVK_Space, modifiers: optionKey) { [weak self] in
            self?.toggle()
        }
    }

    // MARK: Controls

    func toggle() {
        if state.isBusy {
            cancel()
        } else {
            startListening()
        }
    }

    func startListening() {
        cancel()
        permissions.refresh()
        guard permissions.microphone.isGranted, permissions.speech.isGranted else {
            Task {
                await permissions.requestAll()
                if permissions.microphone.isGranted && permissions.speech.isGranted {
                    startListening()
                } else {
                    set(.error("Microphone / Speech permission needed"))
                }
            }
            return
        }

        beginUtterance()
        pipeline = Task { [weak self] in
            guard let self else { return }
            await runListening { try self.recognizer.transcripts() }
        }
    }

    #if DEBUG
    /// `-AudioFile`: same listening pipeline (partials → early intents → final), fed from a file.
    func listen(toFile url: URL) {
        cancel()
        beginUtterance()
        pipeline = Task { [weak self] in
            guard let self else { return }
            await runListening { try self.recognizer.transcripts(fileURL: url) }
        }
    }
    #endif

    // MARK: Listening + early intents

    private func beginUtterance() {
        transcript = ""
        earlyFired = nil
        lastEarlyMatch = nil
        earlyTask = nil
        recognizer.onPartialTranscript = { [weak self] partial in self?.handlePartial(partial) }
        set(.listening)
    }

    private func runListening(_ makeStream: () throws -> AsyncThrowingStream<SpeechRecognizer.Transcript, Error>) async {
        defer { recognizer.onPartialTranscript = nil }
        do {
            var finalText = ""
            for try await result in try makeStream() {
                transcript = result.text
                finalText = result.text
            }
            recognizer.onPartialTranscript = nil
            try Task.checkCancellation()
            let utterance = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
            DebugLog.print("Listen", "final: \"\(utterance)\"")
            guard !utterance.isEmpty else {
                set(.idle)
                return
            }

            guard let early = earlyFired else {
                await process(utterance)
                return
            }
            // An early intent already ran mid-speech: only the rest of the sentence is new.
            let earlyResult = await earlyTask?.value ?? .failed("Early action didn't run")
            switch earlyDetector.remainder(of: utterance, after: early) {
            case .some(let rest) where rest.isEmpty:
                DebugLog.print("Early", "final fully handled by early \(early.command)")
                set(earlyResult.success ? .done(earlyResult.message) : .error(earlyResult.message))
                await confirm(earlyResult.message)
            case .some(let rest):
                DebugLog.print("Early", "remainder after \(early.command): \"\(rest)\"")
                await process(rest)
            case nil:
                // The recognizer revised the words; the command no longer leads. Process it all.
                DebugLog.print("Early", "final no longer starts with \(early.command); processing full utterance")
                await process(utterance)
            }
        } catch is CancellationError {
            // cancelled by user
        } catch {
            set(.error(String(describing: error)))
        }
    }

    /// Runs an unambiguous single-shot command from a partial transcript while the user keeps
    /// talking. At most one per utterance, never spoken (the mic is open); the pill flashes its icon.
    private func handlePartial(_ partial: String) {
        guard state == .listening, earlyFired == nil else { return }
        let fired = earlyDetector.detect(partial, previous: lastEarlyMatch)
        lastEarlyMatch = earlyDetector.match(partial)
        DebugLog.print("Early", "partial \"\(partial)\" → match \(lastEarlyMatch.map { "\($0.command)" } ?? "none")\(fired == nil ? "" : " → FIRE")")
        guard let fired else { return }

        let intent = fired.intent
        if intent.requiresAccessibility, !AXIsProcessTrusted() {
            DebugLog.print("Early", "skipped \(fired.command): needs Accessibility")
            return
        }
        earlyFired = fired
        flash(intent.symbol)
        let router = router
        earlyTask = Task {
            let result = await router.executeEarly(intent)
            DebugLog.print("Early", "\(fired.command) → \(result.success ? "ok" : "FAILED"): \(result.message)")
            return result
        }
    }

    private func flash(_ symbol: String) {
        earlyFlash = symbol
        flashTask?.cancel()
        flashTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1200))
            guard !Task.isCancelled else { return }
            self?.earlyFlash = nil
        }
    }

    /// Typed input from the conversation panel skips STT and enters the same pipeline.
    func submit(_ text: String) {
        let utterance = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !utterance.isEmpty else { return }
        cancel()
        transcript = utterance
        pipeline = Task { [weak self] in await self?.process(utterance) }
    }

    /// Stops speaking early but keeps listening/finishing the current utterance.
    func stopListening() {
        recognizer.finishAudio()
    }

    func cancel() {
        pipeline?.cancel()
        pipeline = nil
        recognizer.onPartialTranscript = nil
        flashTask?.cancel()
        earlyFlash = nil
        recognizer.cancel()
        tts.stop()
        disarmCancelHotKey()
        if state.isBusy { set(.idle) }
    }

    // MARK: Pipeline

    /// Message shown (and spoken) when an action needs AX but trust is missing. Debug rebuilds get a
    /// new code signature, which silently invalidates the grant, so this never re-opens the TCC prompt.
    static let accessibilityMessage = "Re-grant Accessibility in System Settings"

    private func process(_ utterance: String) async {
        set(.thinking)
        do {
            let intent = try await router.classify(utterance)
            lastIntent = intent.description
            lastJevLatency = router.lastDecision?.latency
            try Task.checkCancellation()

            if intent.requiresAccessibility, !AXIsProcessTrusted() {
                permissions.refresh()
                set(.error(Self.accessibilityMessage))
                await confirm(Self.accessibilityMessage)
                return
            }

            if case .chat = intent {
                // Chat keeps .thinking until the reply arrives.
            } else {
                set(.executing(label: intent.description, symbol: intent.symbol))
                armCancelHotKey()
            }

            let outcome = try await withObservedSteps { try await router.handle(intent) }
            disarmCancelHotKey()
            try Task.checkCancellation()

            if case .replied(let reply) = outcome {
                if speaksResponses {
                    set(.speaking)
                    await tts.speak(reply)
                    #if DEBUG
                    DebugLog.print("TTS", "engine=\(tts.lastEngine?.rawValue ?? "-") fallbackReason=\(tts.lastError ?? "-") reply=\(reply)")
                    #endif
                }
                set(.done("Replied"))
            } else {
                set(outcome.isFailure ? .error(outcome.summary) : .done(outcome.summary))
                await confirm(outcome.summary)
            }
        } catch is CancellationError {
            disarmCancelHotKey()
        } catch {
            disarmCancelHotKey()
            set(.error(String(describing: error)))
        }
    }

    /// Shows the re-grant message in the pill if AX trust is missing. Used at launch instead of the
    /// system prompt.
    func showAccessibilityHintIfNeeded() {
        guard !AXIsProcessTrusted(), !state.isBusy else { return }
        set(.error(Self.accessibilityMessage))
    }

    private var speaksResponses: Bool {
        UserDefaults.standard.object(forKey: Config.Key.speakResponses) as? Bool ?? true
    }

    /// Speaks a short action confirmation ("Opened YouTube", "Done in 3 steps") while the pill
    /// keeps showing the done/error state.
    private func confirm(_ message: String) async {
        guard speaksResponses, !Task.isCancelled else { return }
        await tts.speak(message)
        #if DEBUG
        DebugLog.print("TTS", "engine=\(tts.lastEngine?.rawValue ?? "-") fallbackReason=\(tts.lastError ?? "-") said=\(message)")
        #endif
    }

    /// Mirrors `TaskRunner.currentStep` into the pill label while a task runs.
    private func withObservedSteps<T>(_ body: () async throws -> T) async rethrows -> T {
        let mirror = Task { [weak self] in
            while !Task.isCancelled {
                if let self, let step = taskRunner.currentStep, case .executing = state {
                    state = .executing(label: step.description, symbol: step.kind.symbol)
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        defer { mirror.cancel() }
        return try await body()
    }

    /// Esc cancels a running action/task. Registered only while executing so Esc works normally otherwise.
    private func armCancelHotKey() {
        guard cancelHotKey == nil else { return }
        cancelHotKey = GlobalHotKey(keyCode: kVK_Escape, modifiers: 0) { [weak self] in
            self?.cancel()
        }
    }

    private func disarmCancelHotKey() {
        cancelHotKey?.unregister()
        cancelHotKey = nil
    }

    #if DEBUG
    /// Pins the pill in one state for visual checks: launch with `-PillState <name>`.
    /// No auto-reset and no pipeline, so the state stays on screen.
    func debugPin(_ name: String) {
        let pinned: State? = switch name {
        case "idle": .idle
        case "listening": .listening
        case "thinking": .thinking
        case "executing": .executing(label: "Open Safari", symbol: ActionKind.openApp.symbol)
        case "speaking": .speaking
        case "done": .done("Opened Safari")
        case "error": .error("Jev timed out")
        default: nil
        }
        guard let pinned else { return }
        if pinned == .thinking { transcript = "open safari" }
        resetTask?.cancel()
        state = pinned
    }
    #endif

    private func set(_ newState: State) {
        #if DEBUG
        DebugLog.print("VoiceSession", "\(newState)" + (lastIntent.map { " intent=\($0)" } ?? "") + (lastJevLatency.map { " jev=\($0)" } ?? ""))
        #endif
        state = newState
        resetTask?.cancel()
        switch newState {
        case .done, .error:
            let delay: Duration = if case .done = newState { .seconds(2) } else { .seconds(4) }
            resetTask = Task { [weak self] in
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                self?.state = .idle
            }
        default:
            break
        }
    }
}
