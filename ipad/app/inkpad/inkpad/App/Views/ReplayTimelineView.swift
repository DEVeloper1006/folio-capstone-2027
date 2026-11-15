import SwiftUI

struct ReplayTimelineView: View {
    @Binding var isActive: Bool
    let events: [ReplayEvent]
    let totalDuration: TimeInterval

    @State private var currentTime: TimeInterval = 0
    @State private var isPlaying = false
    @State private var speed: Double = 1.0
    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                Button { togglePlayback() } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(FolioTheme.accent)
                        .frame(width: 36, height: 36)
                }

                timelineSlider

                speedButton

                Text(formatTime(currentTime))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(FolioTheme.muted)
                    .frame(width: 50)

                Button { withAnimation { isActive = false } } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(FolioTheme.muted)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(FolioTheme.chromeBackground)
            .shadow(color: FolioTheme.chromeShadow, radius: 4, y: -2)
        }
        .onDisappear { stopPlayback() }
    }

    private var timelineSlider: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(FolioTheme.panel)
                    .frame(height: 6)
                    .clipShape(Capsule())

                Rectangle()
                    .fill(FolioTheme.accent)
                    .frame(width: max(0, geo.size.width * progress), height: 6)
                    .clipShape(Capsule())

                ForEach(events) { event in
                    let x = (event.timestamp / max(totalDuration, 0.01)) * geo.size.width
                    eventMarker(event)
                        .offset(x: x - 4)
                }

                Circle()
                    .fill(FolioTheme.accent)
                    .frame(width: 14, height: 14)
                    .offset(x: max(0, geo.size.width * progress - 7))
            }
            .frame(height: 24)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let pct = max(0, min(1, value.location.x / geo.size.width))
                        currentTime = pct * totalDuration
                    }
            )
        }
        .frame(height: 24)
    }

    private func eventMarker(_ event: ReplayEvent) -> some View {
        let color: Color = switch event.kind {
        case .stroke: FolioTheme.ink.opacity(0.4)
        case .aiHint: FolioTheme.accent
        case .aiCheck: FolioTheme.statusOK
        case .branch: FolioTheme.statusWarn
        }
        return Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }

    private var speedButton: some View {
        Button {
            speed = switch speed {
            case 1: 2
            case 2: 4
            default: 1
            }
        } label: {
            Text("\(Int(speed))×")
                .font(FolioTheme.uiFont(size: 12, weight: .bold))
                .foregroundStyle(FolioTheme.ink)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(FolioTheme.panel))
        }
    }

    private var progress: Double {
        guard totalDuration > 0 else { return 0 }
        return currentTime / totalDuration
    }

    private func togglePlayback() {
        if isPlaying {
            stopPlayback()
        } else {
            startPlayback()
        }
    }

    private func startPlayback() {
        isPlaying = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            Task { @MainActor in
                currentTime += 0.05 * speed
                if currentTime >= totalDuration {
                    currentTime = totalDuration
                    stopPlayback()
                }
            }
        }
    }

    private func stopPlayback() {
        isPlaying = false
        timer?.invalidate()
        timer = nil
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let m = Int(t) / 60
        let s = Int(t) % 60
        return String(format: "%d:%02d", m, s)
    }
}
