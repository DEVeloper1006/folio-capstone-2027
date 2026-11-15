import SwiftUI

struct ExportSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var studentName = ""
    @State private var courseName = ""
    @State private var dueDate = Date()
    var onExport: ((ExportFormat) -> Void)?

    var body: some View {
        NavigationStack {
            Form {
                Section("Assignment Info") {
                    TextField("Student Name", text: $studentName)
                    TextField("Course", text: $courseName)
                    DatePicker("Due Date", selection: $dueDate, displayedComponents: .date)
                }

                Section("Export Format") {
                    ForEach(ExportFormat.allCases) { format in
                        Button {
                            onExport?(format)
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: format.icon)
                                    .frame(width: 24)
                                    .foregroundStyle(FolioTheme.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(format.label)
                                        .font(FolioTheme.uiFont(size: 15, weight: .medium))
                                        .foregroundStyle(FolioTheme.ink)
                                    Text(format.description)
                                        .font(FolioTheme.uiFont(size: 12))
                                        .foregroundStyle(FolioTheme.muted)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12))
                                    .foregroundStyle(FolioTheme.dim)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

enum ExportFormat: String, CaseIterable, Identifiable {
    case png, pdf, latex, markdown

    var id: String { rawValue }

    var label: String {
        switch self {
        case .png: "PNG"
        case .pdf: "PDF"
        case .latex: "LaTeX"
        case .markdown: "Markdown"
        }
    }

    var icon: String {
        switch self {
        case .png: "photo"
        case .pdf: "doc.richtext"
        case .latex: "function"
        case .markdown: "doc.plaintext"
        }
    }

    var description: String {
        switch self {
        case .png: "Raster image of the page"
        case .pdf: "Print-ready document"
        case .latex: "LaTeX source (mock)"
        case .markdown: "Markdown source (mock)"
        }
    }
}
