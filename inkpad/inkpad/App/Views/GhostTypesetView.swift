import SwiftUI

struct GhostTypesetLine: Identifiable {
    let id = UUID()
    let latex: String
    let yPosition: CGFloat
}

struct GhostTypesetView: View {
    let lines: [GhostTypesetLine]
    let visible: Bool
    let scrollOffset: CGFloat

    var body: some View {
        if visible {
            ZStack(alignment: .topLeading) {
                ForEach(lines) { line in
                    Text(line.latex)
                        .font(FolioTheme.ghostTypesetFont(size: 12))
                        .foregroundStyle(FolioTheme.muted.opacity(0.4))
                        .offset(
                            x: FolioTheme.gutterWidth + 16,
                            y: line.yPosition - scrollOffset
                        )
                }
            }
            .allowsHitTesting(false)
        }
    }
}
