/* Defines math modes and automatic ink-recognition quiet periods. */
import Foundation

enum MathMode: String, Codable, CaseIterable, Identifiable {
    case linalg, calc, proof

    var id: String { rawValue }

    var label: String {
        switch self {
        case .linalg: "LINALG"
        case .calc: "CALC"
        case .proof: "PROOF"
        }
    }

    /// Give matrices four seconds of quiet; preserve other modes until later tuning.
    var recognitionQuietPeriod: Duration {
        self == .linalg ? .seconds(4) : .milliseconds(650)
    }

    var next: MathMode {
        switch self {
        case .linalg: .calc
        case .calc: .proof
        case .proof: .linalg
        }
    }
}
