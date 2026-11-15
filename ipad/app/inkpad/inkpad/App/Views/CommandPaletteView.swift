import SwiftUI

struct PaletteCommand: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let action: () -> Void
}

struct CommandPaletteView: View {
    @Binding var isPresented: Bool
    @State private var searchText = ""
    let commands: [PaletteCommand]

    private var filtered: [PaletteCommand] {
        if searchText.isEmpty { return commands }
        return commands.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        if isPresented {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(FolioTheme.dim)
                    TextField("Type a command...", text: $searchText)
                        .font(FolioTheme.uiFont(size: 15))
                        .textFieldStyle(.plain)
                        .onSubmit {
                            if let first = filtered.first {
                                first.action()
                                isPresented = false
                            }
                        }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider()

                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(filtered) { cmd in
                            Button {
                                cmd.action()
                                isPresented = false
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: cmd.icon)
                                        .frame(width: 20)
                                        .foregroundStyle(FolioTheme.muted)
                                    Text(cmd.name)
                                        .font(FolioTheme.uiFont(size: 14))
                                        .foregroundStyle(FolioTheme.ink)
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Divider().padding(.leading, 48)
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
            .background(
                RoundedRectangle(cornerRadius: FolioTheme.cornerRadius)
                    .fill(FolioTheme.chromeBackground)
                    .shadow(color: FolioTheme.shadow, radius: 16, y: 4)
            )
            .frame(width: 360)
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
    }
}
