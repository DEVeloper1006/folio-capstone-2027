import SwiftUI

enum StepStatus: String, Codable {
    case unchecked, verified, warning, error

    var icon: String {
        switch self {
        case .unchecked: "circle.dotted"
        case .verified: "checkmark.circle"
        case .warning: "exclamationmark.circle"
        case .error: "xmark.circle"
        }
    }

    var filledIcon: String {
        switch self {
        case .unchecked: "circle.dotted"
        case .verified: "checkmark.circle.fill"
        case .warning: "exclamationmark.circle.fill"
        case .error: "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .unchecked: FolioTheme.dim
        case .verified: FolioTheme.statusOK
        case .warning: FolioTheme.statusWarn
        case .error: FolioTheme.statusError
        }
    }
}
