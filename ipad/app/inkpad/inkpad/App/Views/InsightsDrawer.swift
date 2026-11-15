import SwiftUI

struct InsightsDrawer: View {
    let insights: [InsightData]
    @Binding var isOpen: Bool
    var onNavigateToStep: ((Int) -> Void)?

    var body: some View {
        ZStack(alignment: .leading) {
            if isOpen {
                Color.black.opacity(0.2)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation { isOpen = false } }

                drawerContent
                    .frame(width: 300)
                    .background(FolioTheme.chromeBackground)
                    .shadow(color: FolioTheme.shadow, radius: 12, x: 4)
                    .transition(.move(edge: .leading))
            }

            tabHandle
        }
    }

    private var tabHandle: some View {
        Button {
            withAnimation(.spring(duration: 0.3)) { isOpen.toggle() }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 14))
                ForEach(Array("INSIGHTS".enumerated()), id: \.offset) { _, char in
                    Text(String(char))
                }
            }
            .font(FolioTheme.uiFont(size: 10, weight: .bold))
            .foregroundStyle(FolioTheme.statusWarn)
            .padding(.vertical, 12)
            .padding(.horizontal, 6)
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0, bottomLeadingRadius: 0,
                    bottomTrailingRadius: 8, topTrailingRadius: 8
                )
                .fill(FolioTheme.panel)
                .shadow(color: FolioTheme.chromeShadow, radius: 4, x: 2)
            )
        }
    }

    private var drawerContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(FolioTheme.statusWarn)
                Text("Insights")
                    .font(FolioTheme.uiFont(size: 16, weight: .semibold))
                Spacer()
                Button { withAnimation { isOpen = false } } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(FolioTheme.muted)
                }
            }
            .padding()
            .background(FolioTheme.panel)

            Divider()

            if insights.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 32))
                        .foregroundStyle(FolioTheme.dim)
                    Text("No insights yet")
                        .font(FolioTheme.uiFont(size: 14))
                        .foregroundStyle(FolioTheme.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(insights) { insight in
                            insightCard(insight)
                        }
                    }
                    .padding()
                }
            }
        }
    }

    private func insightCard(_ insight: InsightData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                severityDot(insight.severity)
                Text(insight.title)
                    .font(FolioTheme.uiFont(size: 14, weight: .semibold))
                    .foregroundStyle(FolioTheme.ink)
            }

            Text(insight.detail)
                .font(FolioTheme.uiFont(size: 13))
                .foregroundStyle(FolioTheme.muted)

            if !insight.linkedStepIndices.isEmpty {
                HStack(spacing: 6) {
                    Text("Steps:")
                        .font(FolioTheme.uiFont(size: 11))
                        .foregroundStyle(FolioTheme.dim)
                    ForEach(insight.linkedStepIndices, id: \.self) { idx in
                        Button {
                            onNavigateToStep?(idx)
                        } label: {
                            Text("#\(idx + 1)")
                                .font(FolioTheme.uiFont(size: 11, weight: .medium))
                                .foregroundStyle(FolioTheme.accent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(FolioTheme.accentFill))
                        }
                    }
                }
            }

            Text(insight.category.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(FolioTheme.dim)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(FolioTheme.panel)
        )
    }

    private func severityDot(_ severity: InsightSeverity) -> some View {
        Circle()
            .fill(severityColor(severity))
            .frame(width: 8, height: 8)
    }

    private func severityColor(_ severity: InsightSeverity) -> Color {
        switch severity {
        case .high: FolioTheme.statusError
        case .medium: FolioTheme.statusWarn
        case .low: FolioTheme.statusOK
        }
    }
}
