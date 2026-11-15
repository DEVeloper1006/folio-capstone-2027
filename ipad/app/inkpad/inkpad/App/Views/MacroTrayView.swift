import SwiftUI

struct MacroDefinition: Identifiable {
    let id = UUID()
    let key: String
    let label: String
    let shortcut: String
}

struct MacroTrayView: View {
    let mathMode: MathMode
    @Binding var isExpanded: Bool
    var onMacro: ((String) -> Void)?

    var macros: [MacroDefinition] {
        switch mathMode {
        case .linalg:
            [
                MacroDefinition(key: "c", label: "copy matrix", shortcut: "\\ c"),
                MacroDefinition(key: "n", label: "row reduction", shortcut: "\\ n"),
                MacroDefinition(key: "t", label: "RREF", shortcut: "\\ t"),
                MacroDefinition(key: "b", label: "determinant", shortcut: "\\ b"),
            ]
        case .calc:
            [
                MacroDefinition(key: "c", label: "copy expression", shortcut: "\\ c"),
                MacroDefinition(key: "n", label: "continue step", shortcut: "\\ n"),
                MacroDefinition(key: "t", label: "derivative", shortcut: "\\ t"),
                MacroDefinition(key: "b", label: "integral", shortcut: "\\ b"),
            ]
        case .proof:
            [
                MacroDefinition(key: "c", label: "copy prior step", shortcut: "\\ c"),
                MacroDefinition(key: "n", label: "continue with justification", shortcut: "\\ n"),
                MacroDefinition(key: "t", label: "transform by inference", shortcut: "\\ t"),
                MacroDefinition(key: "b", label: "build contradiction", shortcut: "\\ b"),
            ]
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.spring(duration: 0.25)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text("Macros")
                        .font(FolioTheme.uiFont(size: 12, weight: .medium))
                        .foregroundStyle(FolioTheme.muted)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(FolioTheme.dim)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }

            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(macros) { macro in
                        Button {
                            onMacro?(macro.key)
                        } label: {
                            HStack {
                                Text(macro.label)
                                    .font(FolioTheme.uiFont(size: 13))
                                    .foregroundStyle(FolioTheme.ink)
                                Spacer()
                                Text(macro.shortcut)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(FolioTheme.dim)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        }
                        if macro.id != macros.last?.id {
                            Divider().padding(.leading, 12)
                        }
                    }
                }
                .background(FolioTheme.chromeBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: FolioTheme.chromeShadow, radius: 4, y: 2)
                .frame(width: 220)
                .transition(.scale(scale: 0.9, anchor: .top).combined(with: .opacity))
            }
        }
    }
}
