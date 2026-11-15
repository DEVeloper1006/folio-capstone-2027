import Foundation

enum SessionMode: String, CaseIterable, Identifiable {
    case solo, coach, check

    var id: String { rawValue }

    var label: String {
        switch self {
        case .solo: "Solo"
        case .coach: "Coach"
        case .check: "Check"
        }
    }

    var showsBadges: Bool { self != .solo }
    var showsHints: Bool { self == .coach }
}
