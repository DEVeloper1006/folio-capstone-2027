import SwiftUI

struct SelectionHullView: View {
    let bounds: CGRect?
    let scrollOffset: CGFloat

    var body: some View {
        if let bounds {
            let adjusted = bounds.offsetBy(dx: 0, dy: -scrollOffset)
            let inset: CGFloat = -12
            let hullRect = adjusted.insetBy(dx: inset, dy: inset)

            Ellipse()
                .stroke(
                    FolioTheme.accent,
                    style: StrokeStyle(lineWidth: 2, dash: [8, 6])
                )
                .fill(FolioTheme.accentFill)
                .frame(width: hullRect.width, height: hullRect.height)
                .position(x: hullRect.midX, y: hullRect.midY)
                .allowsHitTesting(false)
        }
    }
}
