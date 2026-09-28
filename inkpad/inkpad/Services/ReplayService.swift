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
    func events(for page: Page?) -> [ReplayEvent]
    func totalDuration(for page: Page?) -> TimeInterval
}

final class RevisionReplayService: ReplayService {
    func events(for page: Page?) -> [ReplayEvent] {
        guard let page else { return [] }
        let revisions = page.steps
            .flatMap { step in step.revisions.map { (step, $0) } }
            .sorted { $0.1.createdAt < $1.1.createdAt }
        guard let start = revisions.first?.1.createdAt else { return [] }

        return revisions.map { step, revision in
            let label = revision.recognizedText.isEmpty
                ? "Updated step \(step.sortIndex + 1)"
                : revision.recognizedText
            return ReplayEvent(
                timestamp: revision.createdAt.timeIntervalSince(start),
                kind: .stroke,
                label: label
            )
        }
    }

    func totalDuration(for page: Page?) -> TimeInterval {
        let events = events(for: page)
        return max(1, (events.last?.timestamp ?? 0) + 1)
    }
}
