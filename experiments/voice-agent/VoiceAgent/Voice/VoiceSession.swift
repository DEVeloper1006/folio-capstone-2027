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
    /// Commands already run mid-speech this utterance, in order.
    @ObservationIgnored private var earlyFired: [EarlyIntent] = []
    /// Words of the transcript consumed by `earlyFired`; the next command is matched after them.
    @ObservationIgnored private var earlyOffset = 0
    @ObservationIgnored private var lastEarlyMatch: EarlyIntent?
    /// Runs the early commands one after another ("open Safari and open YouTube" needs Safari first).
    @ObservationIgnored private var earlyTask: Task<[ActionResult], Never>?
    /// Upper bound on mid-speech commands per utterance.
    static let maxEarlyCommands = 4
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
        earlyFired = []
        earlyOffset = 0
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

            guard !earlyFired.isEmpty else {
                await process(utterance)
                return
            }
            // Early commands already ran mid-speech: only the rest of the sentence is new.
            let early = earlyFired.map { "\($0.command)" }.joined(separator: ", ")
            let earlyResults = await earlyTask?.value ?? []
            switch earlyDetector.remainder(of: utterance, after: earlyFired) {
            case .some(let rest) where rest.isEmpty:
                DebugLog.print("Early", "final fully handled by early [\(early)]")
                let message = earlyResults.map(\.message).joined(separator: ", ")
                let failed = earlyResults.contains { !$0.success }
                conversation.recordAction(user: utterance, did: message)
                set(failed ? .error(message) : .done(message))
                await confirm(message)
            case .some(let rest):
                DebugLog.print("Early", "remainder after [\(early)]: \"\(rest)\"")
                await process(rest, recordedAs: utterance, earlier: earlyResults)
            case nil:
                // The recognizer revised the words; the commands no longer lead. Process it all.
                DebugLog.print("Early", "final no longer starts with [\(early)]; processing full utterance")
                await process(utterance, earlier: earlyResults)
            }
        } catch is CancellationError {
            // cancelled by user
        } catch {
            set(.error(String(describing: error)))
        }
    }

    /// Runs unambiguous single-shot commands from a partial transcript while the user keeps talking.
    /// Commands chain: each one is matched after the words the previous one consumed, and they run
    /// in order. Never spoken (the mic is open); the pill flashes each icon.
    private func handlePartial(_ partial: String) {
        guard state == .listening else { return }
        while earlyFired.count < Self.maxEarlyCommands,
              let fired = earlyDetector.detect(partial, after: earlyOffset, previous: lastEarlyMatch) {
            DebugLog.print("Early", "partial \"\(partial)\" → FIRE \(fired.command)")
            let intent = fired.intent
            if intent.requiresAccessibility, !AXIsProcessTrusted() {
                DebugLog.print("Early", "skipped \(fired.command): needs Accessibility")
                break
            }
            earlyFired.append(fired)
            earlyOffset = fired.consumedWords
            lastEarlyMatch = nil
            flash(intent.symbol)
            let router = router
            let previous = earlyTask
            earlyTask = Task {
                var results = await previous?.value ?? []
                let result = await router.executeEarly(intent)
                DebugLog.print("Early", "\(fired.command) → \(result.success ? "ok" : "FAILED"): \(result.message)")
                results.append(result)
                return results
            }
        }
        lastEarlyMatch = earlyDetector.match(partial, after: earlyOffset)
        DebugLog.print("Early", "partial \"\(partial)\" → pending \(lastEarlyMatch.map { "\($0.command)" } ?? "none")")
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

    /// Routes and runs `utterance`, then records the exchange in the conversation. `recordedAs` is the
    /// full sentence when `utterance` is only the part left after mid-speech commands (`earlier`).
    private func process(_ utterance: String, recordedAs spoken: String? = nil, earlier: [ActionResult] = []) async {
        let userText = spoken ?? utterance
        let earlierDone = earlier.map(\.message)
        set(.thinking)
        do {
            let intent = try await router.classify(utterance)
            lastIntent = intent.description
            lastJevLatency = router.lastDecision?.latency
            try Task.checkCancellation()

            if intent.requiresAccessibility, !AXIsProcessTrusted() {
                permissions.refresh()
                conversation.recordAction(user: userText, did: (earlierDone + ["Couldn't act: Accessibility isn't granted"]).joined(separator: ". "))
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
                conversation.appendUser(userText)
                let did = earlierDone.isEmpty ? "" : "\(ConversationManager.actionPrefix) \(earlierDone.joined(separator: ". ")).\n"
                conversation.appendAssistant(did + reply)
                if speaksResponses {
                    set(.speaking)
                    await tts.speak(reply)
                    #if DEBUG
                    DebugLog.print("TTS", "engine=\(tts.lastEngine?.rawValue ?? "-") fallbackReason=\(tts.lastError ?? "-") reply=\(reply)")
                    #endif
                }
                set(.done("Replied"))
            } else {
                conversation.recordAction(user: userText, did: (earlierDone + [record(of: outcome)]).joined(separator: ". "))
                set(outcome.isFailure ? .error(outcome.summary) : .done(outcome.summary))
                await confirm(outcome.summary)
            }
        } catch is CancellationError {
            disarmCancelHotKey()
            if !earlierDone.isEmpty { conversation.recordAction(user: userText, did: earlierDone.joined(separator: ". ") + ". Then cancelled") }
        } catch {
            disarmCancelHotKey()
            conversation.recordAction(user: userText, did: (earlierDone + ["Failed: \(error)"]).joined(separator: ". "))
            set(.error(String(describing: error)))
        }
    }

    /// What an action or task did, for the conversation record. Tasks list their steps so a follow-up
    /// ("what did you click?", "why were you blocked?") can be answered.
    private func record(of outcome: IntentOutcome) -> String {
        guard case .task(let result) = outcome else { return outcome.summary }
        let steps = taskRunner.steps.filter { $0.request.kind != .wait }
            .map { "\($0.request.description) (\($0.result.success ? "ok" : "failed"): \($0.result.message))" }
        return "Task: \(result.summary)" + (steps.isEmpty ? "" : ". Steps: " + steps.joined(separator: "; "))
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
