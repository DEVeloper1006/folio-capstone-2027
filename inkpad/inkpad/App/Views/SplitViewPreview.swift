import SwiftUI

struct SplitViewPreview: View {
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 16) {
            previewTag
            Image(systemName: "rectangle.split.2x1")
                .font(.system(size: 40))
                .foregroundStyle(FolioTheme.dim)
            Text("Split View")
                .font(FolioTheme.uiFont(size: 16, weight: .semibold))
            Text("View two pages side by side in landscape mode. Compare solutions, reference notes while working, or check against examples.")
                .font(FolioTheme.uiFont(size: 13))
                .foregroundStyle(FolioTheme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button("Close") { isPresented = false }
                .font(FolioTheme.uiFont(size: 14, weight: .medium))
                .foregroundStyle(FolioTheme.accent)
        }
        .padding(32)
        .background(FolioTheme.chromeBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: FolioTheme.shadow, radius: 16, y: 8)
        .frame(maxWidth: 340)
    }

    private var previewTag: some View {
        Text("PREVIEW")
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(FolioTheme.statusWarn))
    }
}
