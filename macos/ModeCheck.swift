import Foundation

// Calls the installed model; no predefined domain-to-mode mapping or canned responses.
@main
struct ModeCheck {
    static func report(_ value: String) { FileHandle.standardOutput.write(Data((value + "\n").utf8)) }
    static func main() async {
        do {
            let assistant = MathAssistant()
            let installed = try await assistant.models()
            let model = CommandLine.arguments.dropFirst().first ?? installed[0]
            let modes = [
                ModeSummary(id: "linalg", title: "Linear algebra", summary: "Matrices, row reduction, RREF, determinants."),
                ModeSummary(id: "calculus", title: "Calculus", summary: "Derivatives, integrals, limits of scalar functions."),
                ModeSummary(id: "proof", title: "Propositional logic", summary: "Natural deduction, logical connectives, explicit justifications.")]
            for (passage, expected) in [
                ("Differentiate f(x) = x^3 and integrate the resulting scalar polynomial.", "calculus"),
                ("Reduce this matrix to reduced row echelon form and compute its determinant.", "linalg"),
                ("From P and P implies Q, use modus ponens to derive Q in natural deduction.", "proof"),
                ("Remember to bring lunch tomorrow.", "uncertain")
            ] {
                let decision = try await assistant.recognize(model: model, context: passage, current: "linalg", available: modes)
                report("BASELINE: " + String(decoding: try JSONEncoder().encode(decision), as: UTF8.self))
                guard decision.modeID == expected else { throw AssistantError.invalidMode }
            }
            for passage in ["Quaternion rotation: q = a + bi + cj + dk. Work with conjugation and noncommutative quaternion multiplication.",
                            "A qubit is in the state alpha |0> + beta |1>. Apply quantum gates and describe bra-ket inner products."] {
                let decision = try await assistant.recognize(model: model, context: passage, current: "linalg", available: modes)
                report(String(decoding: try JSONEncoder().encode(decision), as: UTF8.self))
                guard decision.action == .create else { throw AssistantError.invalidMode }
                let draft = try await assistant.draftMode(model: model, topic: decision.topic)
                report("DRAFT: " + String(decoding: try JSONEncoder().encode(draft), as: UTF8.self))
                let created = try draft.materialize()
                report(String(decoding: try JSONEncoder().encode(created), as: UTF8.self))
                let reused = try await assistant.recognize(model: model, context: passage, current: "linalg",
                    available: modes + [ModeSummary(id: created.id, title: created.title, summary: created.summary)])
                report("REUSE: " + String(decoding: try JSONEncoder().encode(reused), as: UTF8.self))
                guard reused.action == .select && reused.modeID == created.id else { throw AssistantError.invalidMode }
                report("Recognized, created, validated, and reused \(created.title)")
            }
        } catch { FileHandle.standardError.write(Data("Mode check failed: \(error)\n".utf8)); exit(1) }
    }
}
