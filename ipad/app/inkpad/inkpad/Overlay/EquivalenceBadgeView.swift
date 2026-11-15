import SwiftUI

struct EquivalenceBadgeView: View {
    let isEquivalent: Bool
    let position: CGPoint
    let scrollOffset: CGFloat

    var body: some View {
        Text(isEquivalent ? "≡" : "≠")
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(isEquivalent ? FolioTheme.statusOK : FolioTheme.statusError)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(FolioTheme.chromeBackground)
                    .shadow(color: FolioTheme.chromeShadow, radius: 4, y: 2)
            )
            .offset(x: position.x, y: position.y - scrollOffset)
    }
}
