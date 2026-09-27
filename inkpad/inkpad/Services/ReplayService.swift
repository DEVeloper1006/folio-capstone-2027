import Foundation

struct ReplayEvent: Identifiable {
    let id = UUID()
    let timestamp: TimeInterval
    let kind: ReplayEventKind
    let label: String
}

enum ReplayEventKind {
    case stroke
    case aiHint
    case aiCheck
    case branch
}

protocol ReplayService {
    func events(for pageData: Data?) -> [ReplayEvent]
    func totalDuration(for pageData: Data?) -> TimeInterval
}

final class MockReplayService: ReplayService {
    func events(for pageData: Data?) -> [ReplayEvent] {
        [
            ReplayEvent(timestamp: 0.0, kind: .stroke, label: "Wrote augmented matrix"),
            ReplayEvent(timestamp: 2.5, kind: .stroke, label: "Row operation R2"),
            ReplayEvent(timestamp: 4.0, kind: .aiCheck, label: "Step verified ✓"),
            ReplayEvent(timestamp: 5.5, kind: .stroke, label: "Row operation R3"),
            ReplayEvent(timestamp: 7.0, kind: .aiHint, label: "Hint: check row 2"),
            ReplayEvent(timestamp: 8.5, kind: .stroke, label: "Row operation R2-4R3"),
            ReplayEvent(timestamp: 10.0, kind: .aiCheck, label: "Error detected ×"),
            ReplayEvent(timestamp: 11.0, kind: .branch, label: "Branch: Alternative pivot"),
        ]
    }

    func totalDuration(for pageData: Data?) -> TimeInterval { 12.0 }
}
