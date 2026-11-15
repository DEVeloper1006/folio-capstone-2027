import SwiftUI

struct StatusChipView: View {
    let mathMode: MathMode
    let saveState: String
    let stepCount: Int
    @State private var visible = true

    var body: some View {
        if visible {
            HStack(spacing: 8) {
                Text(mathMode.label)
                    .font(FolioTheme.uiFont(size: 11, weight: .bold))
                    .foregroundStyle(FolioTheme.paper)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(FolioTheme.ink)
                    )

                Text(saveState)
                    .font(FolioTheme.uiFont(size: 11))
                    .foregroundStyle(FolioTheme.muted)

                Text("\(stepCount) steps")
                    .font(FolioTheme.uiFont(size: 11))
                    .foregroundStyle(FolioTheme.dim)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(FolioTheme.chromeBackground)
                    .shadow(color: FolioTheme.chromeShadow, radius: 4, y: 1)
            )
            .onAppear {
                Task {
                    try? await Task.sleep(for: .seconds(4))
                    withAnimation { visible = false }
                }
            }
            .onTapGesture {
                withAnimation { visible = false }
            }
        }
    }
}
