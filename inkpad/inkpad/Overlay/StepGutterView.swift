import SwiftUI

struct StepBadge: Identifiable {
    let id = UUID()
    let status: StepStatus
    let yPosition: CGFloat
    let explanation: String
    var hasThread: Bool = false
    var confidence: Int? = nil
}

struct StepGutterView: View {
    let badges: [StepBadge]
    let visible: Bool
    let scrollOffset: CGFloat
    var onOpenThread: ((Int) -> Void)? = nil
    var onSetConfidence: ((Int, Int) -> Void)? = nil

    @State private var selectedBadge: StepBadge?
    @State private var confidenceTarget: IdentifiableInt?

    var body: some View {
        if visible {
            ZStack(alignment: .topLeading) {
                ForEach(Array(badges.enumerated()), id: \.element.id) { index, badge in
                    VStack(spacing: 4) {
                        Button {
                            selectedBadge = selectedBadge?.id == badge.id ? nil : badge
                        } label: {
                            badgeIcon(badge)
                        }
                        .simultaneousGesture(LongPressGesture().onEnded { _ in
                            confidenceTarget = IdentifiableInt(value: index)
                        })

                        if badge.hasThread {
                            Button {
                                onOpenThread?(index)
                            } label: {
                                Image(systemName: "bubble.left.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(FolioTheme.accent)
                            }
                        }
                    }
                    .offset(x: 8, y: badge.yPosition - scrollOffset)
                }
            }
            .frame(width: FolioTheme.gutterWidth)
            .popover(item: $selectedBadge) { badge in
                badgePopover(badge)
            }
            .popover(item: $confidenceTarget) { idx in
                confidencePopover(idx)
            }
        }
    }

    @ViewBuilder
    private func badgeIcon(_ badge: StepBadge) -> some View {
        ZStack {
            Image(systemName: badge.status == .error ? badge.status.filledIcon : badge.status.icon)
                .font(.system(size: 22))
                .foregroundStyle(badge.status.color)

            if let conf = badge.confidence {
                let matches = confidenceMatches(conf, badge.status)
                Circle()
                    .stroke(matches ? Color.clear : FolioTheme.statusWarn, lineWidth: 2)
                    .frame(width: 28, height: 28)

                Text("\(conf)")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(FolioTheme.dim)
                    .offset(x: 12, y: -12)
            }
        }
    }

    private func confidenceMatches(_ conf: Int, _ status: StepStatus) -> Bool {
        switch status {
        case .verified: conf >= 2
        case .warning: conf == 2
        case .error: conf <= 1
        }
    }

    private func badgePopover(_ badge: StepBadge) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: badge.status.filledIcon)
                    .foregroundStyle(badge.status.color)
                Text(badge.status.rawValue.capitalized)
                    .font(FolioTheme.uiFont(size: 14, weight: .semibold))
            }
            Text(badge.explanation)
                .font(FolioTheme.uiFont(size: 13))
                .foregroundStyle(FolioTheme.muted)
        }
        .padding()
        .frame(width: 240)
        .presentationCompactAdaptation(.popover)
    }

    private func confidencePopover(_ idx: IdentifiableInt) -> some View {
        VStack(spacing: 8) {
            Text("How confident?")
                .font(FolioTheme.uiFont(size: 13, weight: .semibold))
            HStack(spacing: 16) {
                ForEach(1...3, id: \.self) { level in
                    Button {
                        onSetConfidence?(idx.value, level)
                        confidenceTarget = nil
                    } label: {
                        Text("\(level)")
                            .font(FolioTheme.uiFont(size: 16, weight: .bold))
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(FolioTheme.panel))
                            .foregroundStyle(FolioTheme.ink)
                    }
                }
            }
        }
        .padding()
        .presentationCompactAdaptation(.popover)
    }
}

struct IdentifiableInt: Identifiable {
    let id = UUID()
    let value: Int
}
