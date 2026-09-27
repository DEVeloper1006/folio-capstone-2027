import SwiftUI

struct SessionModeControl: View {
    @Binding var mode: SessionMode

    var body: some View {
        HStack(spacing: 0) {
            ForEach(SessionMode.allCases) { sessionMode in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        mode = sessionMode
                    }
                } label: {
                    Text(sessionMode.label)
                        .font(FolioTheme.uiFont(size: 14, weight: mode == sessionMode ? .semibold : .regular))
                        .foregroundStyle(mode == sessionMode ? FolioTheme.ink : FolioTheme.muted)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(
                            mode == sessionMode
                            ? FolioTheme.chromeBackground
                            : Color.clear
                        )
                        .clipShape(Capsule())
                }
            }
        }
        .padding(3)
        .background(
            Capsule()
                .fill(FolioTheme.panel)
                .shadow(color: FolioTheme.chromeShadow, radius: 4, y: 1)
        )
    }
}
