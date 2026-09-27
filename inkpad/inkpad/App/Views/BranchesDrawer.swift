import SwiftUI

struct BranchItem: Identifiable {
    let id = UUID()
    let name: String
    let status: StepStatus
    let thumbnailData: Data?
}

struct BranchesDrawer: View {
    let branches: [BranchItem]
    @Binding var isOpen: Bool
    var onSelectBranch: ((BranchItem) -> Void)?

    var body: some View {
        ZStack(alignment: .trailing) {
            if isOpen {
                Color.black.opacity(0.2)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation { isOpen = false } }

                drawerContent
                    .frame(width: 260)
                    .background(FolioTheme.chromeBackground)
                    .shadow(color: FolioTheme.shadow, radius: 12, x: -4)
                    .transition(.move(edge: .trailing))
            }

            tabHandle
        }
    }

    private var tabHandle: some View {
        Button {
            withAnimation(.spring(duration: 0.3)) {
                isOpen.toggle()
            }
        } label: {
            VStack(spacing: 2) {
                Text("B")
                Text("R")
                Text("A")
                Text("N")
                Text("C")
                Text("H")
                Text("E")
                Text("S")
            }
            .font(FolioTheme.uiFont(size: 10, weight: .bold))
            .foregroundStyle(FolioTheme.muted)
            .padding(.vertical, 12)
            .padding(.horizontal, 6)
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: 8,
                    bottomLeadingRadius: 8,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 0
                )
                .fill(FolioTheme.panel)
                .shadow(color: FolioTheme.chromeShadow, radius: 4, x: -2)
            )
        }
    }

    private var drawerContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Branches")
                    .font(FolioTheme.uiFont(size: 16, weight: .semibold))
                Spacer()
                Button {
                    withAnimation { isOpen = false }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(FolioTheme.muted)
                }
            }
            .padding()
            .background(FolioTheme.panel)

            Divider()

            if branches.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 32))
                        .foregroundStyle(FolioTheme.dim)
                    Text("No branches yet")
                        .font(FolioTheme.uiFont(size: 14))
                        .foregroundStyle(FolioTheme.muted)
                    Text("Lasso some strokes and tap Branch")
                        .font(FolioTheme.uiFont(size: 12))
                        .foregroundStyle(FolioTheme.dim)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(branches) { branch in
                            Button {
                                onSelectBranch?(branch)
                            } label: {
                                branchCard(branch)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
    }

    private func branchCard(_ branch: BranchItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 6)
                .fill(FolioTheme.paper)
                .frame(height: 80)
                .overlay(
                    Image(systemName: "scribble.variable")
                        .font(.system(size: 24))
                        .foregroundStyle(FolioTheme.dim)
                )

            HStack {
                Image(systemName: branch.status.icon)
                    .font(.system(size: 12))
                    .foregroundStyle(branch.status.color)
                Text(branch.name)
                    .font(FolioTheme.uiFont(size: 13, weight: .medium))
                    .foregroundStyle(FolioTheme.ink)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(FolioTheme.chromeBackground)
                .shadow(color: FolioTheme.chromeShadow, radius: 4, y: 2)
        )
    }
}
