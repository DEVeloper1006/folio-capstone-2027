import SwiftUI
import SwiftData
import PencilKit

struct CanvasPageView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.undoManager) private var undoManager
    let page: Page
    @State private var viewModel: CanvasViewModel
    @State private var showExportSheet = false
    @State private var exportedFileURL: URL?

    private let exportSize = CGSize(width: 768, height: 1024)

    init(page: Page) {
        self.page = page
        self._viewModel = State(initialValue: CanvasViewModel(
            drawingData: page.drawingData,
            backgroundStyle: page.background
        ))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(.systemBackground)
                PageBackgroundView(style: viewModel.backgroundStyle, pageSize: geo.size)
                CanvasView(viewModel: viewModel)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                backgroundMenu
                fingerDrawingToggle
                undoRedoButtons
                exportMenu
            }
        }
        .onAppear {
            let context = modelContext
            viewModel.onSave = { data, background in
                page.drawingData = data
                page.background = background
                try? context.save()
            }
        }
        .onDisappear {
            viewModel.save()
        }
        .sheet(isPresented: $showExportSheet) {
            if let url = exportedFileURL {
                ShareSheet(url: url)
            }
        }
    }

    private var backgroundMenu: some View {
        Menu {
            Picker("Background", selection: $viewModel.backgroundStyle) {
                ForEach(PageBackgroundStyle.allCases) { style in
                    Text(style.displayName).tag(style)
                }
            }
        } label: {
            Label("Background", systemImage: "squareshape.split.3x3")
        }
        .onChange(of: viewModel.backgroundStyle) {
            viewModel.save()
        }
    }

    private var fingerDrawingToggle: some View {
        Toggle(isOn: $viewModel.allowFingerDrawing) {
            Label("Finger Drawing", systemImage: "hand.draw")
        }
    }

    private var undoRedoButtons: some View {
        Group {
            Button { undoManager?.undo() } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            Button { undoManager?.redo() } label: {
                Label("Redo", systemImage: "arrow.uturn.forward")
            }
        }
    }

    private var exportMenu: some View {
        Menu {
            Button("Export PNG") { exportPNG() }
            Button("Export PDF") { exportPDF() }
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }
    }

    private func exportPNG() {
        guard let data = ExportService.renderPNG(
            drawing: viewModel.drawing,
            background: viewModel.backgroundStyle,
            size: exportSize
        ) else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("InkPad-Page.png")
        try? data.write(to: url)
        exportedFileURL = url
        showExportSheet = true
    }

    private func exportPDF() {
        let data = ExportService.renderPDF(
            drawing: viewModel.drawing,
            background: viewModel.backgroundStyle,
            size: exportSize
        )
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("InkPad-Page.pdf")
        try? data.write(to: url)
        exportedFileURL = url
        showExportSheet = true
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
