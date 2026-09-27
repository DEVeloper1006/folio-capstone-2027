import SwiftUI

struct HelpSheetView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Gestures") {
                    helpRow("Draw", detail: "Use Apple Pencil on the canvas")
                    helpRow("Pan & Zoom", detail: "Two-finger pinch and drag")
                    helpRow("Lasso", detail: "Select the lasso tool, then circle strokes")
                    helpRow("Radial Menu", detail: "Tap a lasso selection to open")
                }

                Section("Pencil Shortcuts") {
                    helpRow("Double-tap", detail: "Switch between pen and eraser")
                    helpRow("Squeeze", detail: "Open command palette")
                }

                Section("Keyboard Shortcuts") {
                    helpRow("⌘K", detail: "Command palette")
                    helpRow("Ctrl-M", detail: "Cycle math mode")
                    helpRow("⌘Z / ⇧⌘Z", detail: "Undo / Redo")
                }

                Section("Math Macros") {
                    helpRow("\\ c", detail: "Copy (matrix / expression / step)")
                    helpRow("\\ n", detail: "Next (row reduction / step / justification)")
                    helpRow("\\ t", detail: "Transform (RREF / derivative / inference)")
                    helpRow("\\ b", detail: "Build (determinant / integral / contradiction)")
                }

                Section("Session Modes") {
                    helpRow("Solo", detail: "No AI annotations or badges")
                    helpRow("Coach", detail: "Badges + Socratic hints")
                    helpRow("Check", detail: "Badges only, no hints")
                }
            }
            .navigationTitle("Help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func helpRow(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(FolioTheme.uiFont(size: 14, weight: .semibold))
            Text(detail)
                .font(FolioTheme.uiFont(size: 13))
                .foregroundStyle(FolioTheme.muted)
        }
        .padding(.vertical, 2)
    }
}
