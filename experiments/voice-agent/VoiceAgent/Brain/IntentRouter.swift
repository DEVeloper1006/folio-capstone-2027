import Foundation

/// What an utterance resolved to. Every payload is a registry key or code-extracted value.
enum Intent: Sendable, CustomStringConvertible {
    case action(ActionRequest)
    case task(goal: String)
    case chat(String)

    var description: String {
        switch self {
        case .action(let request): "action(\(request))"
        case .task(let goal): "task(\(goal))"
        case .chat: "chat"
        }
    }
}

/// Result of handling an intent, used by `VoiceSession` for UI + TTS.
enum IntentOutcome: Sendable {
    case acted(ActionResult)
    case task(TaskRunner.Outcome)
    case replied(String)

    /// Short line for the pill and for spoken feedback.
    var summary: String {
        switch self {
        case .acted(let result): result.message
        case .task(let outcome): outcome.summary
        case .replied(let text): text
        }
    }

    var isFailure: Bool {
        switch self {
        case .acted(let result): !result.success
        case .task(let outcome): !outcome.isSuccess
        case .replied: false
        }
    }
}

/// Classifies an utterance with a single parallel Jev call, then dispatches to a handler.
@MainActor
final class IntentRouter {
    enum Mode: String, CaseIterable {
        case action, task, chat

        var criterion: String {
            switch self {
            case .action: "One immediate Mac command: open an app, press a shortcut, scroll, change volume, toggle Do Not Disturb"
            case .task: "A multi-step goal that needs operating an app's UI (clicking, filling fields, navigating)"
            case .chat: "A question or conversation that needs a spoken answer, not a Mac action"
            }
        }
    }

    private let jev: JevClient
    private let llm: LLMClient
    private let executor: ActionExecutor
    private let taskRunner: TaskRunner
    private let conversation: ConversationManager
    private let apps: AppCatalog

    private(set) var lastDecision: JevDecision?

    init(
        jev: JevClient,
        llm: LLMClient,
        executor: ActionExecutor,
        taskRunner: TaskRunner,
        conversation: ConversationManager,
        apps: AppCatalog
    ) {
        self.jev = jev
        self.llm = llm
        self.executor = executor
        self.taskRunner = taskRunner
        self.conversation = conversation
        self.apps = apps
    }

    // MARK: Classify

    func classify(_ utterance: String) async throws -> Intent {
        var questions: [String: JevQuestion] = [
            "mode": .choice(
                instructions: "What kind of request is this?",
                criteria: Dictionary(uniqueKeysWithValues: Mode.allCases.map { ($0.rawValue, $0.criterion) })
            ),
            "action": .choice(
                instructions: "If this is a single Mac command, which one?",
                criteria: ActionKind.criteria(ActionKind.singleShot)
            ),
            "key": .choice(
                instructions: "If a key or shortcut should be pressed, which one?",
                criteria: KeyChord.criteria()
            ),
        ]
        let appCriteria = apps.criteria()
        if !appCriteria.isEmpty {
            questions["app"] = .choice(instructions: "Which application does the user mean, if any?", criteria: appCriteria)
        }

        let decision = try await jev.decide(state: "User said: \(utterance)", questions: questions)
        lastDecision = decision

        guard let mode = decision.choice("mode").flatMap(Mode.init(rawValue:)) else {
            throw JevError.invalidChoice(question: "mode", value: decision.choice("mode"))
        }

        switch mode {
        case .chat:
            return .chat(utterance)
        case .task:
            return .task(goal: utterance)
        case .action:
            // Anything we can't fully resolve as a single-shot action escalates to the task loop,
            // which grounds against the live AX tree.
            guard let kind = decision.choice("action").flatMap(ActionKind.init(rawValue:)),
                  ActionKind.singleShot.contains(kind) else {
                return .task(goal: utterance)
            }
            var request = ActionRequest(kind: kind)
            switch kind {
            case .openApp:
                guard let app = decision.choice("app"), apps.url(for: app) != nil else { return .task(goal: utterance) }
                request.appName = app
            case .pressKey:
                guard let key = decision.choice("key").flatMap(KeyChord.init(rawValue:)) else { return .task(goal: utterance) }
                request.key = key
            default:
                break
            }
            return .action(request)
        }
    }

    // MARK: Dispatch

    func handle(_ intent: Intent) async throws -> IntentOutcome {
        switch intent {
        case .action(let request):
            return .acted(try await executor.execute(request))
        case .task(let goal):
            return .task(try await taskRunner.run(goal: goal))
        case .chat(let text):
            conversation.appendUser(text)
            let reply = try await llm.complete(conversation.context())
            conversation.appendAssistant(reply)
            return .replied(reply)
        }
    }
}
