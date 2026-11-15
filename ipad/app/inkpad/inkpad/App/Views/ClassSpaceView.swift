import SwiftUI

struct ClassSpaceView: View {
    let classInfo: ClassInfo
    @State private var examples: [WorkedExampleInfo] = []
    @State private var showLectureModePreview = false
    @State private var showMisconceptionDashboard = false

    private let classService: ClassService = MockClassService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                classHeader
                Divider()
                examplesSection
                Divider()
                tierBButtons
            }
            .padding(24)
        }
        .background(FolioTheme.paper)
        .navigationTitle(classInfo.courseCode)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            examples = classService.workedExamples(for: classInfo.id)
        }
        .sheet(isPresented: $showLectureModePreview) {
            lectureModePreview
        }
        .sheet(isPresented: $showMisconceptionDashboard) {
            misconceptionDashboardPreview
        }
    }

    private var classHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(classInfo.name)
                .font(FolioTheme.uiFont(size: 20, weight: .bold))
            HStack {
                Image(systemName: "person.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(FolioTheme.dim)
                Text(classInfo.instructor)
                    .font(FolioTheme.uiFont(size: 14))
                    .foregroundStyle(FolioTheme.muted)
            }
            Text("\(classInfo.exampleCount) worked examples")
                .font(FolioTheme.uiFont(size: 13))
                .foregroundStyle(FolioTheme.dim)
        }
    }

    private var examplesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Worked Examples")
                .font(FolioTheme.uiFont(size: 16, weight: .semibold))

            ForEach(examples) { example in
                exampleCard(example)
            }
        }
    }

    private func exampleCard(_ example: WorkedExampleInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(example.title)
                        .font(FolioTheme.uiFont(size: 15, weight: .semibold))
                        .foregroundStyle(FolioTheme.ink)
                    Text(example.detail)
                        .font(FolioTheme.uiFont(size: 13))
                        .foregroundStyle(FolioTheme.muted)
                }
                Spacer()
                Text(example.mathMode.label)
                    .font(FolioTheme.uiFont(size: 10, weight: .bold))
                    .foregroundStyle(FolioTheme.paper)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(FolioTheme.ink.opacity(0.7)))
            }

            if !example.stepsPreview.isEmpty {
                MathRendererView(
                    html: example.stepsPreview.map { "\\(\($0)\\)" }.joined(separator: "<br>"),
                    minHeight: 40
                )
                .frame(height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            Button {
            } label: {
                HStack {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 12))
                    Text("Fork to my notebook")
                        .font(FolioTheme.uiFont(size: 13, weight: .medium))
                }
                .foregroundStyle(FolioTheme.accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule().stroke(FolioTheme.accent, lineWidth: 1)
                )
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(FolioTheme.chromeBackground)
                .shadow(color: FolioTheme.chromeShadow, radius: 4, y: 2)
        )
    }

    private var tierBButtons: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { showLectureModePreview = true } label: {
                previewRow(icon: "antenna.radiowaves.left.and.right", title: "Live Lecture Mode")
            }
            Button { showMisconceptionDashboard = true } label: {
                previewRow(icon: "chart.bar.xaxis", title: "Misconception Dashboard")
            }
        }
    }

    private func previewRow(icon: String, title: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(FolioTheme.dim)
                .frame(width: 28)
            Text(title)
                .font(FolioTheme.uiFont(size: 14))
                .foregroundStyle(FolioTheme.ink)
            Spacer()
            Text("PREVIEW")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(FolioTheme.statusWarn))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(FolioTheme.panel)
        )
    }

    private var lectureModePreview: some View {
        VStack(spacing: 20) {
            previewTag
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 40))
                .foregroundStyle(FolioTheme.dim)
            Text("Live Lecture Mode")
                .font(FolioTheme.uiFont(size: 16, weight: .semibold))
            Text("Follow along in real-time with the instructor's work. Flag when you're lost and answer quick-check polls.")
                .font(FolioTheme.uiFont(size: 13))
                .foregroundStyle(FolioTheme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            HStack(spacing: 16) {
                Button { } label: {
                    HStack {
                        Image(systemName: "flag.fill")
                        Text("I'm lost here")
                    }
                    .font(FolioTheme.uiFont(size: 13, weight: .medium))
                    .foregroundStyle(FolioTheme.statusError)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().stroke(FolioTheme.statusError, lineWidth: 1))
                }

                Button { } label: {
                    HStack {
                        Image(systemName: "checkmark.circle")
                        Text("Got it")
                    }
                    .font(FolioTheme.uiFont(size: 13, weight: .medium))
                    .foregroundStyle(FolioTheme.statusOK)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().stroke(FolioTheme.statusOK, lineWidth: 1))
                }
            }

            Button("Close") { showLectureModePreview = false }
                .foregroundStyle(FolioTheme.accent)
        }
        .padding(32)
    }

    private var misconceptionDashboardPreview: some View {
        VStack(spacing: 16) {
            previewTag
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 40))
                .foregroundStyle(FolioTheme.dim)
            Text("Misconception Dashboard")
                .font(FolioTheme.uiFont(size: 16, weight: .semibold))
            Text("A heatmap of common errors across the class, broken down by step and error type.")
                .font(FolioTheme.uiFont(size: 13))
                .foregroundStyle(FolioTheme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            mockHeatmap

            Button("Close") { showMisconceptionDashboard = false }
                .foregroundStyle(FolioTheme.accent)
        }
        .padding(32)
    }

    private var mockHeatmap: some View {
        VStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 2) {
                    ForEach(0..<4, id: \.self) { col in
                        let val = Double.random(in: 0...1)
                        Rectangle()
                            .fill(FolioTheme.statusError.opacity(val * 0.8))
                            .frame(width: 40, height: 30)
                            .overlay(
                                Text("\(Int(val * 100))%")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(val > 0.5 ? .white : FolioTheme.ink)
                            )
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var previewTag: some View {
        Text("PREVIEW")
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(FolioTheme.statusWarn))
    }
}
