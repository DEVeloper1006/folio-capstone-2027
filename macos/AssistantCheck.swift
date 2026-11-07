import Foundation

// Live service checks: no mocked provider responses.
@main
struct AssistantCheck {
    static func main() async {
        do { try await check() }
        catch { FileHandle.standardError.write(Data("Live check failed: \(error)\n".utf8)); exit(1) }
    }
    static func report(_ text: String) { FileHandle.standardOutput.write(Data((text + "\n").utf8)) }
    static func check() async throws {
        let assistant = MathAssistant()
        let models = try await assistant.models()
        let model = CommandLine.arguments.dropFirst().first ?? models[0]
        guard models.contains(model) else { throw AssistantError.noModels }
        let step = try await assistant.propose(model: model,
            request: "Subtract 3 from both sides of 2x + 3 = 7, leaving 2x = 4. Write only that step; do not divide by 2.",
            document: "$2x + 3 = 7$", mode: "linalg", selection: "", intent: "step")
        precondition(step.kind == .step && !step.latex.isEmpty, "Expected one mathematical step")
        report("STEP: \(step.latex.debugDescription)\n\(step.explanation)")
        let calculus = try await assistant.propose(model: model,
            request: "Apply the power rule to x^2 to write d/dx(x^2) = 2x. Switch to calculus mode. Write only this one step.",
            document: "$x^2$", mode: "linalg", selection: "", intent: "step")
        precondition(calculus.kind == .step && calculus.mode == "calculus", "Explicit operations should produce a proposal without asking permission")
        report("CALCULUS: \(calculus.latex.debugDescription)\n\(calculus.explanation)")
        let proof = try await assistant.propose(model: model,
            request: "From P and P implies Q, apply modus ponens to write Q. Only this step.",
            document: "$P$\n$P \\implies Q$", mode: "proof", selection: "", intent: "step")
        precondition(proof.kind == .step && proof.mode == "proof", "A specified proof step must produce notation")
        report("PROOF: \(proof.latex)\n\(proof.explanation)")
        let ambiguity = try await assistant.propose(model: model,
            request: "Apply the golden rule to get the next line.",
            document: "Proof in progress.", mode: "proof", selection: "", intent: "step")
        report("AMBIGUITY: \(ambiguity.kind) \(ambiguity.latex)\n\(ambiguity.explanation)")
        precondition(ambiguity.kind == .clarify && ambiguity.latex.isEmpty, "Ambiguous rules must not produce invented mathematics")
        let hint = try await assistant.propose(model: model,
            request: "Solve the whole equation for me.", document: "$2x + 3 = 7$",
            mode: "linalg", selection: "", intent: "hint")
        precondition([.hint, .clarify].contains(hint.kind) && hint.latex.isEmpty, "Hints must not edit")
        report("HINT: \(hint.explanation)")
        let mode = try await assistant.propose(model: model,
            request: "Switch to proof mode without changing any mathematics.", document: "$P \\implies Q$",
            mode: "linalg", selection: "", intent: "step")
        precondition(mode.kind == .mode && mode.mode == "proof" && mode.latex.isEmpty, "Mode-only requests must not edit")
        report("MODE: \(mode.mode)\nLive response structure checks passed; inspect the printed mathematics independently.")
    }
}
