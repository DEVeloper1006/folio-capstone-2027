import Foundation

/// Multi-step computer-use loop: crawl AX tree → ask Jev for the next step → validate → execute → repeat.
///
/// Jev only selects keys: a verb from `ActionKind.taskVerbs`, an element index from the current
/// `ElementTable`, a `KeyChord`, an installed app, or a phrase from the goal's own words.
/// Anything outside those sets is rejected.
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
    private(set) var currentStep: ActionRequest?
    private(set) var isRunning = false

    var settleDelay: Duration = .milliseconds(450)
    var doneThreshold = 0.9
    var repeatLimit = 3

    private let jev: JevClient
    private let executor: ActionExecutor
    private let crawler: AXTreeCrawler
    private let apps: AppCatalog

    init(jev: JevClient, executor: ActionExecutor, apps: AppCatalog, crawler: AXTreeCrawler = AXTreeCrawler()) {
        self.jev = jev
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

        let candidates = TextPayload.candidates(from: goal)
        var lastDescriptions: [String] = []

        for index in 0..<Config.maxTaskSteps {
            try Task.checkCancellation()

            let table = observe()
            let decision = try await jev.decide(
                state: state(goal: goal, table: table),
                questions: questions(for: table, candidates: candidates)
            )

            if let done = decision[JevQuestions.goalMet]?.probability, done >= doneThreshold {
                return .done(steps: index)
            }

            let verbChoice = decision.choice(JevQuestions.intent)
            guard let verb = verbChoice.flatMap(ActionKind.init(rawValue:)), ActionKind.taskVerbs.contains(verb) else {
                throw JevError.invalidChoice(question: JevQuestions.intent, value: verbChoice)
            }
            let target = table.entry(forKey: decision.choice(JevQuestions.targetIndex))

            switch verb {
            case .done: return .done(steps: index)
            case .blocked: return .blocked(reason: blockedReason(table))
            default: break
            }

            var request = ActionRequest(kind: verb)
            switch verb {
            case .click:
                guard let target else { return .blocked(reason: "no matching element to click") }
                request.targetIndex = target.index
            case .typeText:
                guard let text = decision.choice(JevQuestions.textPayload), candidates.contains(text) else {
                    return .blocked(reason: "no text to type")
                }
                request.text = text
                // Only accept a target that is an observed text input; otherwise type at the caret.
                if let target, target.isTextInput { request.targetIndex = target.index }
            case .pressKey:
                guard let chord = decision.choice(JevQuestions.key).flatMap(KeyChord.init(rawValue:)) else {
                    return .blocked(reason: "no valid key")
                }
                request.key = chord.press
            case .openApp:
                guard let app = decision.choice(JevQuestions.app), apps.url(for: app) != nil else {
                    return .blocked(reason: "app not installed")
                }
                request.appName = app
            case .scrollUp, .scrollDown:
                request.targetIndex = target?.index
            default:
                break
            }

            let description = request.description
            lastDescriptions.append(description)
            if lastDescriptions.suffix(repeatLimit).count == repeatLimit,
               Set(lastDescriptions.suffix(repeatLimit)).count == 1 {
                return .stuck(description)
            }

            currentStep = request
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

    private func questions(for table: ElementTable, candidates: [String]) -> [String: JevQuestion] {
        var questions: [String: JevQuestion] = [
            JevQuestions.intent: .choice(
                instructions: "What is the single best next step toward the goal?",
                criteria: ActionKind.criteria(ActionKind.taskVerbs)
            ),
            JevQuestions.goalMet: .noul(
                instructions: "Is the goal already fully achieved on the current screen?",
                whenTrue: "The goal is fully achieved",
                whenFalse: "More steps are needed"
            ),
            JevQuestions.key: JevQuestions.keyChord(),
        ]
        questions[JevQuestions.targetIndex] = JevQuestions.target(table)
        questions[JevQuestions.textPayload] = JevQuestions.text(candidates)
        questions[JevQuestions.app] = JevQuestions.app(apps)
        return questions
    }

    private func state(goal: String, table: ElementTable) -> String {
        var extra: [String] = []
        if !steps.isEmpty {
            let history = steps.suffix(8).map { "\($0.id + 1). \($0.request) → \($0.result.success ? "ok" : "failed"): \($0.result.message)" }
            extra.append("Steps so far:\n" + history.joined(separator: "\n"))
        }
        return JevQuestions.state(transcript: goal, table: table, extra: extra)
    }

    private func blockedReason(_ table: ElementTable) -> String {
        table.isEmpty ? "nothing actionable on screen" : "can't proceed in \(table.appName)"
    }
}
