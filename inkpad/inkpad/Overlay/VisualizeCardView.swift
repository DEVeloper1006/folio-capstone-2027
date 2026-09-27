import SwiftUI
import Charts

struct VisualizeCardView: View {
    let data: VisualizeData
    let sourcePosition: CGPoint
    @State private var offset: CGSize = .zero

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            cardContent
        }
        .frame(width: 240, height: 200)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(FolioTheme.chromeBackground)
                .shadow(color: FolioTheme.shadow, radius: 8, y: 4)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .offset(offset)
        .gesture(
            DragGesture()
                .onChanged { offset = $0.translation }
                .onEnded { offset = $0.translation }
        )
        .overlay(alignment: .topLeading) {
            leaderLine
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: data.type.icon)
                .font(.system(size: 12))
                .foregroundStyle(FolioTheme.accent)
            Text(data.title)
                .font(FolioTheme.uiFont(size: 12, weight: .semibold))
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var cardContent: some View {
        switch data.type {
        case .graph:
            graphCard
        case .vector2D:
            vectorCard
        case .matrixHeatmap:
            heatmapCard
        }
    }

    private var graphCard: some View {
        Chart {
            ForEach(Array(data.graphPoints.enumerated()), id: \.offset) { _, pt in
                LineMark(x: .value("x", pt.x), y: .value("y", pt.y))
                    .foregroundStyle(FolioTheme.accent)
            }
        }
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) }
        .chartYAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
        .padding(8)
    }

    private var vectorCard: some View {
        Canvas { ctx, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let scale = min(size.width, size.height) / 6

            ctx.stroke(
                Path { p in
                    p.move(to: CGPoint(x: 0, y: center.y))
                    p.addLine(to: CGPoint(x: size.width, y: center.y))
                    p.move(to: CGPoint(x: center.x, y: 0))
                    p.addLine(to: CGPoint(x: center.x, y: size.height))
                },
                with: .color(FolioTheme.rule),
                lineWidth: 0.5
            )

            for v in data.vectors {
                let end = CGPoint(x: center.x + v.dx * scale, y: center.y - v.dy * scale)
                ctx.stroke(
                    Path { p in
                        p.move(to: center)
                        p.addLine(to: end)
                    },
                    with: .color(FolioTheme.accent),
                    lineWidth: 2
                )
                let arrowSize: CGFloat = 6
                let angle = atan2(center.y - end.y, end.x - center.x)
                ctx.fill(
                    Path { p in
                        p.move(to: end)
                        p.addLine(to: CGPoint(x: end.x - arrowSize * cos(angle - .pi / 6), y: end.y + arrowSize * sin(angle - .pi / 6)))
                        p.addLine(to: CGPoint(x: end.x - arrowSize * cos(angle + .pi / 6), y: end.y + arrowSize * sin(angle + .pi / 6)))
                        p.closeSubpath()
                    },
                    with: .color(FolioTheme.accent)
                )
            }
        }
        .padding(8)
    }

    private var heatmapCard: some View {
        VStack(spacing: 2) {
            ForEach(Array(data.matrixValues.enumerated()), id: \.offset) { row, values in
                HStack(spacing: 2) {
                    ForEach(Array(values.enumerated()), id: \.offset) { _, val in
                        let norm = min(abs(val) / 4.0, 1.0)
                        Rectangle()
                            .fill(val >= 0 ? FolioTheme.accent.opacity(norm) : FolioTheme.statusError.opacity(norm))
                            .overlay(
                                Text(String(format: "%.0f", val))
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(norm > 0.5 ? .white : FolioTheme.ink)
                            )
                    }
                }
            }
        }
        .padding(8)
    }

    private var leaderLine: some View {
        Path { path in
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: -30, y: 20))
        }
        .stroke(FolioTheme.accent, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        .frame(width: 30, height: 20)
        .offset(x: -30, y: -20)
    }
}
