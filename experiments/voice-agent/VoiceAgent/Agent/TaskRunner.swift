import Foundation

/// Multi-step computer-use loop: crawl AX tree → ask Jev for the next step → validate → execute → repeat.
///
/// Jev only selects keys: a verb from `ActionKind.taskVerbs`, an element id from the current
/// `ElementTable`, a `KeyChord`, or an installed app. Anything outside those sets is rejected.
@MainActor
@Observable
final class TaskRunner {
    struct Step: Identifiable, Sendable {
        let id: Int
        let request: ActionRequest
        let result: ActionResult
    }

    enum Outcome: Sendable {
        case done(steps: Int)
        case blocked(reason: String)
        case stepLimit(Int)
        case stuck(String)

        var isSuccess: Bool {
            if case .done = self { return true }
            return false
        }

        var summary: String {
            switch self {
            case .done(let steps): steps == 0 ? "Already done" : "Done in \(steps) step\(steps == 1 ? "" : "s")"
            case .blocked(let reason): "Blocked: \(reason)"
            case .stepLimit(let n): "Stopped after \(n) steps"
            case .stuck(let step): "Stuck repeating \(step)"
            }
        }
    }

    private(set) var goal: String?
    private(set) var steps: [Step] = []
    private(set) var currentStep: String?
    private(set) var isRunning = false

    var settleDelay: Duration = .milliseconds(450)
    var doneThreshold = 0.9
    var repeatLimit = 3

    private let jev: JevClient
    private let llm: LLMClient
    private let executor: ActionExecutor
    private let crawler: AXTreeCrawler
    private let apps: AppCatalog

    init(jev: JevClient, llm: LLMClient, executor: ActionExecutor, apps: AppCatalog, crawler: AXTreeCrawler = AXTreeCrawler()) {
        self.jev = jev
        self.llm = llm
        self.executor = executor
        self.apps = apps
        self.crawler = crawler
    }

    func run(goal: String) async throws -> Outcome {
        self.goal = goal
        steps = []
        isRunning = true
        defer {
            isRunning = false
            currentStep = nil
        }

        var textToType: String?? = .none   // lazily extracted once per goal
        var lastDescriptions: [String] = []

        for index in 0..<Config.maxTaskSteps {
            try Task.checkCancellation()

            let table = observe()
            let decision = try await jev.decide(state: state(goal: goal, table: table), questions: questions(for: table))

            if let done = decision["goal_met"]?.probability, done >= doneThreshold {
                return .done(steps: index)
            }

            guard let verb = decision.choice("next").flatMap(ActionKind.init(rawValue:)),
                  ActionKind.taskVerbs.contains(verb) else {
                throw JevError.invalidChoice(question: "next", value: decision.choice("next"))
            }

            switch verb {
            case .done: return .done(steps: index)
            case .blocked: return .blocked(reason: blockedReason(table))
            default: break
            }

            var request = ActionRequest(kind: verb)
            switch verb {
            case .click:
                guard let id = decision.choice("target"), table[id] != nil else {
                    return .blocked(reason: "no matching element to click")
                }
                request.targetID = id
            case .typeText:
                if textToType == nil {
                    textToType = .some(try await llm.extractTextToType(from: goal))
                }
                guard let text = textToType ?? nil else { return .blocked(reason: "no text to type") }
                request.text = text
                // Only accept a target that is an observed text input; otherwise type at the caret.
                if let id = decision.choice("target"), table[id]?.isTextInput == true {
                    request.targetID = id
                }
            case .pressKey:
                guard let key = decision.choice("key").flatMap(KeyChord.init(rawValue:)) else {
                    return .blocked(reason: "no valid key")
                }
                request.key = key
            case .openApp:
                guard let app = decision.choice("app"), apps.url(for: app) != nil else {
                    return .blocked(reason: "app not installed")
                }
                request.appName = app
            case .scrollUp, .scrollDown:
                if let id = decision.choice("target"), table[id] != nil { request.targetID = id }
            default:
                break
            }

            let description = request.description
            lastDescriptions.append(description)
            if lastDescriptions.suffix(repeatLimit).count == repeatLimit,
               Set(lastDescriptions.suffix(repeatLimit)).count == 1 {
                return .stuck(description)
            }

            currentStep = description
            let result: ActionResult
            do {
                result = try await executor.execute(request, table: table)
            } catch {
                result = .failed(String(describing: error))
            }
            steps.append(Step(id: index, request: request, result: result))

            try await Task.sleep(for: settleDelay)
        }
        return .stepLimit(Config.maxTaskSteps)
    }

    // MARK: - Observation & prompting

    private func observe() -> ElementTable {
        do {
            return try crawler.crawlFocusedApp()
        } catch AXTreeCrawler.CrawlError.noWindow(let app) {
            return ElementTable(appName: app, windowTitle: nil, elements: [])
        } catch {
            return .empty
        }
    }

    private func questions(for table: ElementTable) -> [String: JevQuestion] {
        var questions: [String: JevQuestion] = [
            "next": .choice(
                instructions: "What is the single best next step toward the goal?",
                criteria: ActionKind.criteria(ActionKind.taskVerbs)
            ),
            "goal_met": .noul(instructions: "Is the goal already fully achieved on the current screen?"),
            "key": .choice(instructions: "If pressing a key, which one?", criteria: KeyChord.criteria()),
        ]
        if !table.isEmpty {
            questions["target"] = .choice(
                instructions: "If clicking, typing or scrolling, which on-screen element?",
                criteria: table.criteria()
            )
        }
        let appCriteria = apps.criteria()
        if !appCriteria.isEmpty {
            questions["app"] = .choice(instructions: "If opening an app, which one?", criteria: appCriteria)
        }
        return questions
    }

    private func state(goal: String, table: ElementTable) -> String {
        var parts = ["Goal: \(goal)"]
        if !steps.isEmpty {
            let history = steps.suffix(8).map { "\($0.id + 1). \($0.request) → \($0.result.success ? "ok" : "failed"): \($0.result.message)" }
            parts.append("Steps so far:\n" + history.joined(separator: "\n"))
        }
        parts.append("Current screen:\n" + (table.isEmpty && table.appName.isEmpty ? "(nothing observable)" : table.render()))
        return parts.joined(separator: "\n\n")
    }

    private func blockedReason(_ table: ElementTable) -> String {
        table.isEmpty ? "nothing actionable on screen" : "can't proceed in \(table.appName)"
    }
}
