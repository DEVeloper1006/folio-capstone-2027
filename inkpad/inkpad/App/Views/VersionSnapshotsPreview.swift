import SwiftUI

struct VersionSnapshotsPreview: View {
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 16) {
            previewTag
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 40))
                .foregroundStyle(FolioTheme.dim)
            Text("Version Snapshots")
                .font(FolioTheme.uiFont(size: 16, weight: .semibold))
            Text("Automatic named snapshots for each page. Restore any previous version without losing your current work.")
                .font(FolioTheme.uiFont(size: 13))
                .foregroundStyle(FolioTheme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            VStack(alignment: .leading, spacing: 8) {
                snapshotRow(name: "Auto-save 4:15 PM", time: "2 min ago")
                snapshotRow(name: "Before branch", time: "8 min ago")
                snapshotRow(name: "Initial draft", time: "1 hr ago")
            }
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

    private func snapshotRow(name: String, time: String) -> some View {
        HStack {
            Image(systemName: "clock")
                .font(.system(size: 12))
                .foregroundStyle(FolioTheme.dim)
            Text(name)
                .font(FolioTheme.uiFont(size: 13))
                .foregroundStyle(FolioTheme.ink)
            Spacer()
            Text(time)
                .font(FolioTheme.uiFont(size: 11))
                .foregroundStyle(FolioTheme.dim)
        }
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
