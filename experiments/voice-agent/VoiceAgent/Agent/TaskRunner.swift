import AppKit

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
        case stepLimit(Int, lastActions: [String])
        case stuck(String)
        /// Jev kept answering WAIT, even after a longer settle.
        case stalled

        var isSuccess: Bool {
            if case .done = self { return true }
            return false
        }

        var summary: String {
            switch self {
            case .done(let steps): steps == 0 ? "Already done" : "Done"
            case .blocked(let reason): "Blocked: \(reason)"
            case .stepLimit(let n, let lastActions):
                "Stopped after \(n) steps" + (lastActions.isEmpty ? "" : ". Last: " + lastActions.joined(separator: ", "))
            case .stuck(let step): "Stuck repeating \(step)"
            case .stalled: "I got stuck — the UI might still be loading"
            }
        }
    }

    private(set) var goal: String?
    private(set) var steps: [Step] = []
    private(set) var currentStep: ActionRequest?
    private(set) var isRunning = false

    /// Hard cap on Jev decisions per task, whatever the Settings value.
    static let maxSteps = 15

    /// Wait after every action before re-crawling: focusing a field, opening a menu or loading a page
    /// takes a moment to show up in the AX tree.
    var settleDelay: Duration = .milliseconds(400)
    /// Longer settle after `waitLimit` WAITs in a row, before one last try.
    var longSettleDelay: Duration = .milliseconds(800)
    var waitLimit = 3
    /// How long to watch for a new frontmost app after OPEN_APP (launches are slow) and after CLICK
    /// (which rarely switches apps, so a long wait would slow every click).
    var appSwitchTimeout: Duration = .milliseconds(1500)
    var clickSwitchTimeout: Duration = .milliseconds(500)
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
        let limit = min(Config.maxTaskSteps, Self.maxSteps)
        var lastDescriptions: [String] = []
        var nextDelay: Duration = .zero
        var nextPID: pid_t?
        var consecutiveWaits = 0

        for index in 0..<limit {
            try Task.checkCancellation()

            let table = await observe(delay: nextDelay, pid: nextPID)
            DebugLog.print("Task", "step \(index + 1)/\(limit) crawl (after \(nextDelay)\(nextPID.map { ", pid \($0)" } ?? "")): \(table.elements.count) elements\n\(table.serialize())")

            let decision = try await jev.decide(
                state: state(goal: goal, table: table),
                questions: questions(for: table, candidates: candidates)
            )

            if let done = decision[JevQuestions.goalMet]?.probability, done >= doneThreshold {
                return .done(steps: index)
            }

            let verbChoice = decision.choice(JevQuestions.intent)
            guard let chosenVerb = verbChoice.flatMap(ActionKind.init(rawValue:)), ActionKind.taskVerbs.contains(chosenVerb) else {
                throw JevError.invalidChoice(question: JevQuestions.intent, value: verbChoice)
            }
            let target = table.entry(forKey: decision.choice(JevQuestions.targetIndex))

            // Right after a successful OPEN_APP the new window or page is often still loading, and Jev
            // judges the half-built screen: it re-opens the same app/site (a duplicate tab) or says BLOCKED.
            // Both become WAIT, which re-crawls after a settle and still counts toward `waitLimit`.
            var verb = chosenVerb
            if let previous = steps.last, previous.request.kind == .openApp, previous.result.success,
               verb == .blocked || (verb == .openApp && previous.request.appName == decision.choice(JevQuestions.app)) {
                DebugLog.print("Task", "\(verb.rawValue) right after opening \(previous.request.appName ?? "the app"); treating as WAIT")
                verb = .wait
            }

            switch verb {
            case .done: return .done(steps: index)
            case .blocked: return .blocked(reason: blockedReason(table))
            case .wait:
                // WAIT isn't executed or repeat-checked: it just re-crawls after a settle. After
                // `waitLimit` in a row, settle longer and ask once more; another WAIT stops the task.
                consecutiveWaits += 1
                steps.append(Step(id: index, request: ActionRequest(kind: .wait), result: .ok("Waited")))
                if consecutiveWaits > waitLimit { return .stalled }
                nextDelay = consecutiveWaits == waitLimit ? longSettleDelay : settleDelay
                DebugLog.print("Task", "WAIT \(consecutiveWaits)/\(waitLimit), re-crawling after \(nextDelay)")
                continue
            default:
                consecutiveWaits = 0
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
                guard let app = decision.choice(JevQuestions.app), apps.resolve(app) != nil else {
                    return .blocked(reason: "no app or website called that")
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
            let frontmostBefore = NSWorkspace.shared.frontmostApplication?.processIdentifier
            let result: ActionResult
            do {
                result = try await executor.execute(request, table: table)
            } catch {
                result = .failed(String(describing: error))
            }
            steps.append(Step(id: index, request: request, result: result))

            let targetInfo = request.targetIndex.flatMap(table.entry(at:)).map { " on \($0.role) '\($0.spokenName)'" } ?? ""
            DebugLog.print("Task", "step \(index + 1) action: \(description)\(targetInfo) → \(result.success ? "ok" : "FAILED"): \(result.message)")

            // After CLICK / OPEN_APP the frontmost app may change; crawl the new app, not the old one.
            nextPID = nil
            if verb == .click || verb == .openApp,
               let switched = await frontmostChange(
                   from: frontmostBefore, timeout: verb == .openApp ? appSwitchTimeout : clickSwitchTimeout
               ) {
                nextPID = switched
                DebugLog.print("Task", "frontmost app changed → pid \(switched) (\(NSRunningApplication(processIdentifier: switched)?.localizedName ?? "?"))")
            }
            nextDelay = settleDelay
        }
        let done = steps.filter { $0.request.kind != .wait && $0.result.success }.suffix(3).map { $0.result.message }
        return .stepLimit(limit, lastActions: done)
    }

    /// Polls the frontmost app until it differs from `previous` or `timeout` elapses.
    private func frontmostChange(from previous: pid_t?, timeout: Duration) async -> pid_t? {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if let current = NSWorkspace.shared.frontmostApplication?.processIdentifier, current != previous {
                return current
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }

    // MARK: - Observation & prompting

    private func observe(delay: Duration, pid: pid_t?) async -> ElementTable {
        do {
            return try await crawler.crawl(delay: delay, pid: pid)
        } catch is CancellationError {
            return .empty
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
