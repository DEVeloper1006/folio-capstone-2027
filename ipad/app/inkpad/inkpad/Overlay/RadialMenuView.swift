import SwiftUI

enum RadialAction: String, CaseIterable, Identifiable {
    case check, hint, explain, formalize, branch, visualize

    var id: String { rawValue }

    var label: String { rawValue.capitalized }
}

struct RadialMenuView: View {
    let center: CGPoint
    let scrollOffset: CGFloat
    var onAction: ((RadialAction) -> Void)?
    var onDismiss: (() -> Void)?

    private let actions: [RadialAction] = RadialAction.allCases
    private let radius: CGFloat = 80

    var body: some View {
        let adjustedCenter = CGPoint(x: center.x, y: center.y - scrollOffset)

        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { onDismiss?() }

            Circle()
                .fill(FolioTheme.ink.opacity(0.06))
                .frame(width: 8, height: 8)
                .position(adjustedCenter)

            ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                let angle = angleFor(index: index, total: actions.count)
                let x = adjustedCenter.x + radius * cos(angle)
                let y = adjustedCenter.y + radius * sin(angle)

                Button {
                    onAction?(action)
                } label: {
                    Text(action.label)
                        .font(FolioTheme.uiFont(size: 14, weight: .medium))
                        .foregroundStyle(FolioTheme.ink)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(FolioTheme.chromeBackground)
                                .shadow(color: FolioTheme.chromeShadow, radius: 6, y: 2)
                        )
                }
                .position(x: x, y: y)
            }
        }
    }

    private func angleFor(index: Int, total: Int) -> CGFloat {
        let startAngle: CGFloat = -.pi / 2
        let step = (2 * .pi) / CGFloat(total)
        return startAngle + step * CGFloat(index)
    }
}
