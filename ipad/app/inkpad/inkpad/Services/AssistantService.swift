import Foundation

enum AssistantState {
    case idle, listening, thinking, responding
}

struct AssistantResponse {
    let transcript: String
    let annotation: String?
}

protocol AssistantService {
    var modelName: String { get }
    var modelLabel: String { get }
    func startListening()
    func stopListening()
    func processInput(_ text: String) async -> AssistantResponse
}

final class MockAssistantService: AssistantService {
    let modelName = "Mock"
    let modelLabel = "Mock · local"

    private let scriptedResponses: [AssistantResponse] = [
        AssistantResponse(transcript: "Check row 2 after the operation.", annotation: "What's row 2's first entry now?"),
        AssistantResponse(transcript: "The pivot should be 1, not 0.", annotation: "Check the leading coefficient."),
        AssistantResponse(transcript: "Good work on this step!", annotation: nil),
    ]
    private var responseIndex = 0

    func startListening() {}
    func stopListening() {}

    func processInput(_ text: String) async -> AssistantResponse {
        try? await Task.sleep(for: .seconds(1))
        let response = scriptedResponses[responseIndex % scriptedResponses.count]
        responseIndex += 1
        return response
    }
}

final class LayaAssistantService: AssistantService {
    // not implemented
    let modelName = "Laya"
    let modelLabel = "Laya · on-device"
    func startListening() {}
    func stopListening() {}
    func processInput(_ text: String) async -> AssistantResponse {
        AssistantResponse(transcript: "", annotation: nil)
    }
}

final class JevAssistantService: AssistantService {
    // not implemented
    let modelName = "Jev"
    let modelLabel = "Jev"
    func startListening() {}
    func stopListening() {}
    func processInput(_ text: String) async -> AssistantResponse {
        AssistantResponse(transcript: "", annotation: nil)
    }
}
