import CoreGraphics
import Foundation

enum ScrollDirection: String, Sendable {
    case up, down
}

/// What an utterance resolved to. Every payload is a registry key, an observed element index,
/// or a verbatim span of the transcript — never model-generated text.
enum ActionIntent: Sendable, CustomStringConvertible {
    case openApp(name: String)
    case click(elementIndex: Int)
    case typeText(elementIndex: Int?, text: String)
    case pressKey(keyCode: CGKeyCode, modifiers: CGEventFlags)
    case scroll(ScrollDirection)
    case system(ActionKind)          // volume / mute / DND
    case task(transcript: String)
    case chat(transcript: String)
    case wait
    case done
    case blocked(reason: String)

    var description: String {
        switch self {
        case .openApp(let name): "Open \(name)"
        case .click(let index): "Click #\(index)"
        case .typeText(_, let text): "Type “\(text.prefix(30))”"
        case .pressKey(let keyCode, let modifiers): "Press \(KeyChord.name(keyCode: keyCode, modifiers: modifiers))"
        case .scroll(let direction): "Scroll \(direction.rawValue)"
        case .system(let kind): kind.criterion
        case .task: "Working on it…"
        case .chat: "chat"
        case .wait: "Wait"
        case .done: "Nothing to do"
        case .blocked(let reason): "Blocked: \(reason)"
        }
    }

    /// Needs Accessibility trust: AX element access or CGEvent posting. System media keys fall back
    /// to AppleScript without it, and opening apps / chat never need it.
    var requiresAccessibility: Bool {
        switch self {
        case .click, .typeText, .pressKey, .scroll, .task: true
        case .openApp, .system, .chat, .wait, .done, .blocked: false
        }
    }

    /// SF Symbol shown in the pill while this intent executes.
    var symbol: String {
        switch self {
        case .openApp: ActionKind.openApp.symbol
        case .click: ActionKind.click.symbol
        case .typeText: ActionKind.typeText.symbol
        case .pressKey: ActionKind.pressKey.symbol
        case .scroll(let direction): (direction == .up ? ActionKind.scrollUp : .scrollDown).symbol
        case .system(let kind): kind.symbol
        case .task: "checklist"
        case .chat: "bubble.left.fill"
        case .wait: ActionKind.wait.symbol
        case .done: ActionKind.done.symbol
        case .blocked: ActionKind.blocked.symbol
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

// MARK: - Jev question vocabulary

/// Options for the `intent` question: the executor's verbs plus the two routing escapes.
enum IntentOption: String, CaseIterable, Sendable {
    case openApp = "OPEN_APP"
    case click = "CLICK"
    case typeText = "TYPE_TEXT"
    case pressKey = "PRESS_KEY"
    case scrollUp = "SCROLL_UP"
    case scrollDown = "SCROLL_DOWN"
    case task = "TASK"
    case chat = "CHAT"
    case wait = "WAIT"
    case done = "DONE"
    case blocked = "BLOCKED"
    case volumeUp = "VOLUME_UP"
    case volumeDown = "VOLUME_DOWN"
    case toggleMute = "TOGGLE_MUTE"
    case toggleDoNotDisturb = "TOGGLE_DND"
    case brightnessUp = "BRIGHTNESS_UP"
    case brightnessDown = "BRIGHTNESS_DOWN"

    /// Criteria for classifying a single utterance. Worded so one-step commands grounded in the
    /// current screen stay single-shot and anything longer goes to TASK.
    var criterion: String {
        switch self {
        case .openApp: "Launch an app or open a well-known website"
        case .click: "Click one specific control that is listed in the element table"
        case .typeText: "Type the user's words into a text field that is on screen now"
        case .pressKey: "Press one key or keyboard shortcut"
        case .scrollUp: "Scroll the content up"
        case .scrollDown: "Scroll the content down"
        case .task: "A goal that needs several UI steps (e.g. compose and send a message, fill a form, open an app and then do something in it)"
        case .chat: "A question or conversation that needs a spoken answer, not a Mac action"
        case .wait: "The user asked to wait or hold on"
        case .done: "Nothing to do: the user cancelled, said thanks, or the request is already satisfied"
        case .blocked: "A Mac action that can't or shouldn't be done (e.g. needs a password, destructive, impossible here)"
        case .volumeUp, .volumeDown, .toggleMute, .toggleDoNotDisturb, .brightnessUp, .brightnessDown: actionKind!.criterion
        }
    }

    /// The executor verb this option maps to, if any.
    var actionKind: ActionKind? {
        switch self {
        case .task, .chat: nil
        default: ActionKind(rawValue: rawValue)
        }
    }

    static func criteria(_ options: [IntentOption] = allCases) -> [String: String] {
        Dictionary(uniqueKeysWithValues: options.map { ($0.rawValue, $0.criterion) })
    }
}

/// Question builders shared by `IntentRouter` (one pass per utterance) and `TaskRunner` (one per step).
enum JevQuestions {
    static let intent = "intent"
    static let targetIndex = "target_index"
    static let textPayload = "text_payload"
    static let key = "key"
    static let app = "app"
    static let goalMet = "goal_met"

    static func target(_ table: ElementTable) -> JevQuestion? {
        table.isEmpty ? nil : .choice(
            instructions: "If clicking, typing or scrolling, which element from the table (by index)?",
            criteria: table.targetCriteria()
        )
    }

    static func text(_ candidates: [String]) -> JevQuestion? {
        candidates.isEmpty ? nil : .choice(
            instructions: "If typing, which phrase from the user's words should be typed exactly?",
            criteria: TextPayload.criteria(candidates)
        )
    }

    static func keyChord() -> JevQuestion {
        .choice(instructions: "If pressing a key or shortcut, which one?", criteria: KeyChord.criteria())
    }

    @MainActor
    static func app(_ apps: AppCatalog) -> JevQuestion? {
        let criteria = apps.criteria()
        return criteria.isEmpty ? nil : .choice(instructions: "If opening an app or website, which one?", criteria: criteria)
    }

    /// State block: the user's words, then the serialized element table.
    static func state(transcript: String, table: ElementTable, extra: [String] = []) -> String {
        (["User said: \"\(transcript)\""] + extra + ["Current screen:\n" + table.serialize()])
            .joined(separator: "\n\n")
    }
}

// MARK: - Router

/// Classifies an utterance with one Jev decision over the transcript + AX element table,
/// then dispatches: single actions → `ActionExecutor`, TASK → `TaskRunner`, CHAT → `LLMClient`.
@MainActor
final class IntentRouter {
    /// Below this `intent` confidence, a single-shot action is handed to the task loop instead,
    /// which re-grounds against the screen step by step.
    var minActionConfidence = 0.45
    /// If TASK's probability is within this margin of the chosen single action, prefer TASK: the task
    /// loop can open the app as its first step, but a single action can't finish "search YouTube for X".
    var taskMargin = 0.10

    private let jev: JevClient
    private let llm: LLMClient
    private let executor: ActionExecutor
    private let taskRunner: TaskRunner
    private let conversation: ConversationManager
    private let apps: AppCatalog
    private let crawler: AXTreeCrawler

    private(set) var lastDecision: JevDecision?
    /// The table `classify` observed. Element indices in the returned intent refer to it.
    private(set) var observedTable: ElementTable = .empty

    init(
        jev: JevClient,
        llm: LLMClient,
        executor: ActionExecutor,
        taskRunner: TaskRunner,
        conversation: ConversationManager,
        apps: AppCatalog,
        crawler: AXTreeCrawler = AXTreeCrawler()
    ) {
        self.jev = jev
        self.llm = llm
        self.executor = executor
        self.taskRunner = taskRunner
        self.conversation = conversation
        self.apps = apps
        self.crawler = crawler
    }

    // MARK: Classify

    func classify(_ transcript: String) async throws -> ActionIntent {
        let table = (try? crawler.crawlFocusedApp()) ?? .empty
        observedTable = table
        let candidates = TextPayload.candidates(from: transcript)

        var questions: [String: JevQuestion] = [
            JevQuestions.intent: .choice(
                instructions: "What should the Mac do for this request?",
                criteria: IntentOption.criteria()
            ),
            JevQuestions.key: JevQuestions.keyChord(),
        ]
        questions[JevQuestions.targetIndex] = JevQuestions.target(table)
        questions[JevQuestions.textPayload] = JevQuestions.text(candidates)
        questions[JevQuestions.app] = JevQuestions.app(apps)

        let decision = try await jev.decide(
            state: JevQuestions.state(transcript: transcript, table: table),
            questions: questions
        )
        lastDecision = decision
        return try parse(decision, transcript: transcript, table: table, candidates: candidates)
    }

    /// Maps typed answers to an intent, validating every payload against what code offered.
    /// A single-shot action that can't be fully resolved escalates to `.task`.
    func parse(
        _ decision: JevDecision,
        transcript: String,
        table: ElementTable,
        candidates: [String]
    ) throws -> ActionIntent {
        guard let option = decision.choice(JevQuestions.intent).flatMap(IntentOption.init(rawValue:)) else {
            throw JevError.invalidChoice(question: JevQuestions.intent, value: decision.choice(JevQuestions.intent))
        }
        let escalate = ActionIntent.task(transcript: transcript)

        if option.actionKind.map({ !$0.isTerminal && $0 != .wait }) == true {
            if let confidence = decision.confidence(JevQuestions.intent), confidence < minActionConfidence {
                return escalate
            }
            if case .choice(_, _, let probabilities?) = decision[JevQuestions.intent],
               let chosen = probabilities[option.rawValue], let task = probabilities[IntentOption.task.rawValue],
               task >= chosen - taskMargin {
                DebugLog.print("Router", "\(option.rawValue) \(chosen) vs TASK \(task): within \(taskMargin), escalating to TASK")
                return escalate
            }
        }

        switch option {
        case .chat:
            return .chat(transcript: transcript)
        case .task:
            return escalate
        case .wait:
            return .wait
        case .done:
            return .done
        case .blocked:
            return .blocked(reason: table.appName.isEmpty ? "can't do that here" : "can't do that in \(table.appName)")
        case .volumeUp, .volumeDown, .toggleMute, .toggleDoNotDisturb, .brightnessUp, .brightnessDown:
            return option.actionKind.map(ActionIntent.system) ?? escalate
        case .scrollUp:
            return .scroll(.up)
        case .scrollDown:
            return .scroll(.down)
        case .openApp:
            guard let app = decision.choice(JevQuestions.app), apps.resolve(app) != nil else { return escalate }
            // "search YouTube for lofi music": the words carry something to type or search beyond the
            // app name, so opening the app alone can't finish it. Let the task loop open it and continue.
            let whole = TextPayload.clean(transcript).lowercased()
            if candidates.contains(where: { $0.lowercased() != whole }) {
                DebugLog.print("Router", "OPEN_APP \(app) but the request has a payload (\(candidates.first ?? "")); escalating to TASK")
                return escalate
            }
            return .openApp(name: app)
        case .pressKey:
            guard let chord = decision.choice(JevQuestions.key).flatMap(KeyChord.init(rawValue:)) else { return escalate }
            return .pressKey(keyCode: chord.keyCode, modifiers: chord.flags)
        case .click:
            guard let entry = table.entry(forKey: decision.choice(JevQuestions.targetIndex)) else { return escalate }
            return .click(elementIndex: entry.index)
        case .typeText:
            guard let text = decision.choice(JevQuestions.textPayload), candidates.contains(text) else { return escalate }
            // Only accept an observed text input as target; otherwise type at the caret.
            let target = table.entry(forKey: decision.choice(JevQuestions.targetIndex)).flatMap { $0.isTextInput ? $0.index : nil }
            return .typeText(elementIndex: target, text: text)
        }
    }

    // MARK: Dispatch

    func handle(_ intent: ActionIntent) async throws -> IntentOutcome {
        switch intent {
        case .task(let transcript):
            return .task(try await taskRunner.run(goal: transcript))
        case .chat(let transcript):
            conversation.appendUser(transcript)
            let reply = try await llm.complete(conversation.context())
            conversation.appendAssistant(reply)
            return .replied(reply)
        case .done:
            return .acted(.ok("Nothing to do"))
        case .blocked(let reason):
            return .acted(.failed("Blocked: \(reason)"))
        default:
            guard let request = Self.request(for: intent) else { return .acted(.failed("Nothing to execute")) }
            return .acted(try await executor.execute(request, table: observedTable))
        }
    }

    /// Runs a single-shot intent detected from partial speech. No crawl (early intents never target
    /// elements) and no Jev call.
    func executeEarly(_ intent: ActionIntent) async -> ActionResult {
        guard let request = Self.request(for: intent) else { return .failed("Nothing to execute") }
        do {
            return try await executor.execute(request)
        } catch {
            return .failed(String(describing: error))
        }
    }

    /// Single-shot intents → executor request. Nil for intents the executor doesn't handle.
    static func request(for intent: ActionIntent) -> ActionRequest? {
        switch intent {
        case .openApp(let name):
            ActionRequest(kind: .openApp, appName: name)
        case .click(let index):
            ActionRequest(kind: .click, targetIndex: index)
        case .typeText(let index, let text):
            ActionRequest(kind: .typeText, targetIndex: index, text: text)
        case .pressKey(let keyCode, let modifiers):
            ActionRequest(
                kind: .pressKey,
                key: KeyPress(keyCode: keyCode, modifiers: modifiers, name: KeyChord.name(keyCode: keyCode, modifiers: modifiers))
            )
        case .scroll(let direction):
            ActionRequest(kind: direction == .up ? .scrollUp : .scrollDown)
        case .system(let kind):
            ActionRequest(kind: kind)
        case .wait:
            ActionRequest(kind: .wait)
        case .task, .chat, .done, .blocked:
            nil
        }
    }
}
