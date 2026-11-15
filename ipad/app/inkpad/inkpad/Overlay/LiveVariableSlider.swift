import SwiftUI

struct LiveVariableSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var onChange: ((Double) -> Void)? = nil

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(label)
                    .font(FolioTheme.ghostTypesetFont(size: 13))
                    .foregroundStyle(FolioTheme.muted)
                Spacer()
                Text(String(format: "%.1f", value))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(FolioTheme.ink)
            }
            Slider(value: $value, in: range)
                .tint(FolioTheme.accent)
                .onChange(of: value) { _, newVal in
                    onChange?(newVal)
                }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(FolioTheme.chromeBackground)
                .shadow(color: FolioTheme.chromeShadow, radius: 4, y: 2)
        )
        .frame(width: 200)
    }
}
