import SwiftUI

struct StepBadge: Identifiable {
    let id = UUID()
    let status: StepStatus
    let yPosition: CGFloat
    let explanation: String
}

struct StepGutterView: View {
    let badges: [StepBadge]
    let visible: Bool
    let scrollOffset: CGFloat

    @State private var selectedBadge: StepBadge?

    var body: some View {
        if visible {
            ZStack(alignment: .topLeading) {
                ForEach(badges) { badge in
                    Button {
                        selectedBadge = selectedBadge?.id == badge.id ? nil : badge
                    } label: {
                        Image(systemName: badge.status == .error ? badge.status.filledIcon : badge.status.icon)
                            .font(.system(size: 22))
                            .foregroundStyle(badge.status.color)
                    }
                    .offset(x: 12, y: badge.yPosition - scrollOffset)
                }
            }
            .frame(width: FolioTheme.gutterWidth)
            .popover(item: $selectedBadge) { badge in
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
        }
    }
}
