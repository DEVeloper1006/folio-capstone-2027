import SwiftUI
import CoreImage.CIFilterBuiltins

struct DesktopHandoffPreview: View {
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 16) {
            previewTag
            Text("Desktop Handoff")
                .font(FolioTheme.uiFont(size: 16, weight: .semibold))
            Text("Continue your work on the desktop version of Folio. Scan the QR code to transfer this notebook.")
                .font(FolioTheme.uiFont(size: 13))
                .foregroundStyle(FolioTheme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            mockQRCode
                .frame(width: 160, height: 160)
                .padding()

            Text("folio://handoff/mock-session-id")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(FolioTheme.dim)

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

    private var mockQRCode: some View {
        Canvas { ctx, size in
            let cellSize = size.width / 10
            for row in 0..<10 {
                for col in 0..<10 {
                    let isFilled = (row + col) % 3 == 0 || (row * col) % 7 == 0
                    if isFilled {
                        ctx.fill(
                            Path(CGRect(
                                x: CGFloat(col) * cellSize,
                                y: CGFloat(row) * cellSize,
                                width: cellSize, height: cellSize
                            )),
                            with: .color(FolioTheme.ink)
                        )
                    }
                }
            }
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
