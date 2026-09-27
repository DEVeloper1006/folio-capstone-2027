import SwiftUI

struct ContradictionTraceView: View {
    let badges: [StepBadge]
    let errorStepIndex: Int?
    let scrollOffset: CGFloat

    var body: some View {
        if let errorIdx = errorStepIndex {
            let ancestor = findAncestor(errorIdx)
            ZStack(alignment: .topLeading) {
                ForEach(Array(badges.enumerated()), id: \.element.id) { idx, badge in
                    let isDimmed = idx != errorIdx && idx != ancestor
                    if isDimmed {
                        Rectangle()
                            .fill(FolioTheme.paper.opacity(0.7))
                            .frame(width: 600, height: 50)
                            .offset(x: FolioTheme.gutterWidth, y: badge.yPosition - scrollOffset - 10)
                    }
                    if idx == ancestor {
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(FolioTheme.statusError, lineWidth: 2)
                            .frame(width: 600, height: 50)
                            .offset(x: FolioTheme.gutterWidth, y: badge.yPosition - scrollOffset - 10)
                    }
                }

                if ancestor != errorIdx, ancestor < badges.count, errorIdx < badges.count {
                    let startY = badges[ancestor].yPosition - scrollOffset + 15
                    let endY = badges[errorIdx].yPosition - scrollOffset + 15
                    Path { p in
                        p.move(to: CGPoint(x: 36, y: startY))
                        p.addLine(to: CGPoint(x: 36, y: endY))
                    }
                    .stroke(FolioTheme.statusError.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                }
            }
        }
    }

    private func findAncestor(_ errorIdx: Int) -> Int {
        for i in stride(from: errorIdx - 1, through: 0, by: -1) {
            if badges[i].status == .warning || badges[i].status == .error {
                return i
            }
        }
        return max(0, errorIdx - 1)
    }
}
