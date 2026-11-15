import SwiftUI

struct Annotation: Identifiable {
    let id = UUID()
    let text: String
    let position: CGPoint
    let arrowTarget: CGPoint?
    let showAcceptChip: Bool
    let showSquiggle: Bool
    let squiggleRect: CGRect?
}

struct AnnotationLayerView: View {
    let annotations: [Annotation]
    let visible: Bool
    let scrollOffset: CGFloat
    var onAccept: ((Annotation) -> Void)?

    var body: some View {
        if visible {
            ZStack {
                ForEach(annotations) { annotation in
                    AnnotationItemView(
                        annotation: annotation,
                        scrollOffset: scrollOffset,
                        onAccept: onAccept
                    )
                }
            }
        }
    }
}

private struct AnnotationItemView: View {
    let annotation: Annotation
    let scrollOffset: CGFloat
    var onAccept: ((Annotation) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let target = annotation.arrowTarget {
                CurvedArrowShape(
                    from: CGPoint(x: annotation.position.x + 100, y: annotation.position.y - scrollOffset - 10),
                    to: CGPoint(x: target.x, y: target.y - scrollOffset)
                )
                .stroke(FolioTheme.accent, lineWidth: 1.5)
            }

            Text(annotation.text)
                .font(FolioTheme.handwritingFont(size: 22))
                .foregroundStyle(FolioTheme.accent)
                .position(x: annotation.position.x, y: annotation.position.y - scrollOffset)

            if annotation.showAcceptChip {
                Button {
                    onAccept?(annotation)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                        Text("tap to accept")
                            .font(FolioTheme.uiFont(size: 12))
                    }
                    .foregroundStyle(FolioTheme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(FolioTheme.accentFill)
                            .stroke(FolioTheme.accent.opacity(0.3), lineWidth: 1)
                    )
                }
                .position(x: annotation.position.x + 60, y: annotation.position.y - scrollOffset + 30)
            }

            if annotation.showSquiggle, let rect = annotation.squiggleRect {
                SquiggleLine()
                    .stroke(FolioTheme.statusError, lineWidth: 2)
                    .frame(width: rect.width, height: 6)
                    .position(x: rect.midX, y: rect.maxY - scrollOffset + 4)
            }
        }
    }
}

struct CurvedArrowShape: Shape {
    let from: CGPoint
    let to: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let control = CGPoint(
            x: (from.x + to.x) / 2 + 40,
            y: min(from.y, to.y) - 30
        )
        path.move(to: from)
        path.addQuadCurve(to: to, control: control)
        let angle = atan2(to.y - control.y, to.x - control.x)
        let arrowLen: CGFloat = 8
        path.move(to: to)
        path.addLine(to: CGPoint(
            x: to.x - arrowLen * cos(angle - .pi / 6),
            y: to.y - arrowLen * sin(angle - .pi / 6)
        ))
        path.move(to: to)
        path.addLine(to: CGPoint(
            x: to.x - arrowLen * cos(angle + .pi / 6),
            y: to.y - arrowLen * sin(angle + .pi / 6)
        ))
        return path
    }
}

struct SquiggleLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let amplitude: CGFloat = 3
        let wavelength: CGFloat = 8
        path.move(to: CGPoint(x: 0, y: rect.midY))
        var x: CGFloat = 0
        var up = true
        while x < rect.width {
            let nextX = min(x + wavelength / 2, rect.width)
            let y = up ? rect.midY - amplitude : rect.midY + amplitude
            path.addLine(to: CGPoint(x: nextX, y: y))
            x = nextX
            up.toggle()
        }
        return path
    }
}
