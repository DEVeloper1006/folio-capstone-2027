import SwiftUI

enum PageTemplate: String, CaseIterable, Identifiable {
    case problemSet = "Problem Set"
    case proof = "Proof"
    case lectureNotes = "Lecture Notes"
    case examPractice = "Exam Practice"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .problemSet: "list.number"
        case .proof: "function"
        case .lectureNotes: "text.alignleft"
        case .examPractice: "clock"
        }
    }

    var background: PageBackgroundStyle {
        switch self {
        case .problemSet: .dot
        case .proof: .blank
        case .lectureNotes: .lined
        case .examPractice: .grid
        }
    }

    var headerText: String {
        switch self {
        case .problemSet: "Problem Set"
        case .proof: "Proof"
        case .lectureNotes: "Lecture Notes"
        case .examPractice: "Exam Practice"
        }
    }
}

struct TemplatePickerView: View {
    @Binding var isPresented: Bool
    var onSelect: ((PageTemplate) -> Void)?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 16)], spacing: 16) {
                    ForEach(PageTemplate.allCases) { template in
                        templateCard(template)
                    }
                }
                .padding(20)
            }
            .background(FolioTheme.paper)
            .navigationTitle("New Page")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { isPresented = false }
                }
            }
        }
    }

    private func templateCard(_ template: PageTemplate) -> some View {
        Button {
            onSelect?(template)
            isPresented = false
        } label: {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(FolioTheme.panel)
                        .frame(height: 120)

                    VStack(spacing: 6) {
                        Image(systemName: template.icon)
                            .font(.system(size: 24))
                            .foregroundStyle(FolioTheme.accent)

                        Text(template.headerText)
                            .font(FolioTheme.uiFont(size: 11, weight: .medium))
                            .foregroundStyle(FolioTheme.muted)
                    }
                }

                Text(template.rawValue)
                    .font(FolioTheme.uiFont(size: 13, weight: .medium))
                    .foregroundStyle(FolioTheme.ink)
            }
        }
    }
}
