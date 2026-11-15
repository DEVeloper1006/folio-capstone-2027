import SwiftUI

struct BranchCompareView: View {
    let branchA: BranchItem
    let branchB: BranchItem
    let stepsA: [StepBadge]
    let stepsB: [StepBadge]
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            HStack(spacing: 1) {
                branchColumn(branch: branchA, steps: stepsA, side: "A")
                Rectangle().fill(FolioTheme.rule).frame(width: 1)
                branchColumn(branch: branchB, steps: stepsB, side: "B")
            }
            .background(FolioTheme.paper)
            .navigationTitle("Compare Branches")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { isPresented = false }
                }
            }
        }
    }

    private func branchColumn(branch: BranchItem, steps: [StepBadge], side: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: branch.status.icon)
                    .foregroundStyle(branch.status.color)
                Text(branch.name)
                    .font(FolioTheme.uiFont(size: 14, weight: .semibold))
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { idx, step in
                        let isDivergent = isDivergentStep(idx, side: side)
                        HStack(spacing: 8) {
                            Image(systemName: step.status.icon)
                                .font(.system(size: 16))
                                .foregroundStyle(step.status.color)
                            Text(step.explanation)
                                .font(FolioTheme.uiFont(size: 13))
                                .foregroundStyle(FolioTheme.ink)
                                .lineLimit(2)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isDivergent ? FolioTheme.accentFill : Color.clear)
                                .overlay(
                                    isDivergent ?
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(FolioTheme.accent, lineWidth: 1) : nil
                                )
                        )
                    }
                }
                .padding(12)
            }
        }
    }

    private func isDivergentStep(_ idx: Int, side: String) -> Bool {
        guard idx < stepsA.count, idx < stepsB.count else { return true }
        return stepsA[idx].status != stepsB[idx].status
    }
}
