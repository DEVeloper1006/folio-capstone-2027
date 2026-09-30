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

    let permissions: PermissionsManager
    let recognizer: SpeechRecognizer
    let synthesizer: SpeechSynthesizer
    let conversation: ConversationManager
    let taskRunner: TaskRunner
    let apps: AppCatalog

    @ObservationIgnored private let router: IntentRouter
    @ObservationIgnored private var pipeline: Task<Void, Never>?
    @ObservationIgnored private var resetTask: Task<Void, Never>?
    @ObservationIgnored private var toggleHotKey: GlobalHotKey?
    @ObservationIgnored private var cancelHotKey: GlobalHotKey?

    init() {
        let jev = JevClient()
        let llm = LLMClient()
        let apps = AppCatalog()
        let executor = ActionExecutor(apps: apps)
        let conversation = ConversationManager()
        let taskRunner = TaskRunner(jev: jev, executor: executor, apps: apps)

        self.permissions = PermissionsManager()
        self.recognizer = SpeechRecognizer()
        self.synthesizer = SpeechSynthesizer()
        self.conversation = conversation
        self.taskRunner = taskRunner
        self.apps = apps
        self.router = IntentRouter(
            jev: jev, llm: llm, executor: executor, taskRunner: taskRunner,
            conversation: conversation, apps: apps
        )
        self.synthesizer.voiceIdentifier = UserDefaults.standard.string(forKey: Config.Key.voiceIdentifier)
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

        transcript = ""
        set(.listening)
        pipeline = Task { [weak self] in
            guard let self else { return }
            do {
                var finalText = ""
                for try await result in try recognizer.transcripts() {
                    transcript = result.text
                    finalText = result.text
                }
                try Task.checkCancellation()
                let utterance = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !utterance.isEmpty else {
                    set(.idle)
                    return
                }
                await process(utterance)
            } catch is CancellationError {
                // cancelled by user
            } catch {
                set(.error(String(describing: error)))
            }
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
        recognizer.cancel()
        synthesizer.stop()
        disarmCancelHotKey()
        if state.isBusy { set(.idle) }
    }

    // MARK: Pipeline

    private func process(_ utterance: String) async {
        set(.thinking)
        do {
            let intent = try await router.classify(utterance)
            lastIntent = intent.description
            lastJevLatency = router.lastDecision?.latency
            try Task.checkCancellation()

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
                if UserDefaults.standard.object(forKey: Config.Key.speakResponses) as? Bool ?? true {
                    set(.speaking)
                    await synthesizer.speak(reply)
                }
                set(.done("Replied"))
            } else if outcome.isFailure {
                set(.error(outcome.summary))
            } else {
                set(.done(outcome.summary))
            }
        } catch is CancellationError {
            disarmCancelHotKey()
        } catch {
            disarmCancelHotKey()
            set(.error(String(describing: error)))
        }
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
