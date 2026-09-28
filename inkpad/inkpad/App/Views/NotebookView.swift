import SwiftUI
import SwiftData
import PencilKit

struct NotebookView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.undoManager) private var undoManager
    let notebook: Notebook

    @State private var currentPageIndex = 0
    @State private var viewModel: CanvasViewModel
    @State private var stepTracker = StepTrackingCoordinator()
    @State private var stepTrackingTask: Task<Void, Never>?
    @State private var showPageSidebar = false
    @State private var showBranches = false
    @State private var showChat = false
    @State private var chatAnchor: ChatAnchor = .page
    @State private var showInsights = false
    @State private var showReplay = false
    @State private var showFormulaSheet = false
    @State private var visualizeCards: [VisualizeData] = []
    @State private var contradictionStepIndex: Int? = nil
    @State private var confidenceValues: [UUID: Int] = [:]
    @State private var showTypeset = false
    @State private var showCommandPalette = false
    @State private var showExport = false
    @State private var showHelp = false
    @State private var showMacroTray = false
    @State private var scrollOffset: CGFloat = 0
    @State private var exportedFileURL: URL?
    @State private var showShareSheet = false
    @State private var showTemplatePicker = false
    @State private var showPDFImport = false
    @State private var showSplitViewPreview = false
    @State private var showDesktopHandoff = false
    @State private var showUnitCheck = false
    @State private var showForkToPractise = false
    @State private var showVersionSnapshots = false
    @State private var showBranchCompare = false

    init(notebook: Notebook) {
        self.notebook = notebook
        let page = notebook.pages.sorted { $0.sortIndex < $1.sortIndex }.first
        self._viewModel = State(initialValue: CanvasViewModel(
            drawingData: page?.drawingData,
            backgroundStyle: page?.background ?? .dot,
            mathMode: notebook.mathMode
        ))
    }

    private var sortedPages: [Page] {
        notebook.pages.sorted { $0.sortIndex < $1.sortIndex }
    }

    private var currentPage: Page? {
        guard currentPageIndex < sortedPages.count else { return nil }
        return sortedPages[currentPageIndex]
    }

    private var mockBadges: [StepBadge] {
        guard let page = currentPage else { return [] }
        let threads = page.chatThreads
        return page.steps.filter(\.isActive).sorted { $0.sortIndex < $1.sortIndex }.map { step in
            let hasThread = threads.contains {
                $0.anchorStepID == step.stableID || ($0.anchorStepID == nil && $0.anchorStepIndex == step.sortIndex)
            }
            return StepBadge(
                id: step.stableID,
                status: step.status, yPosition: step.yPosition, explanation: step.explanation,
                hasThread: hasThread, confidence: confidenceValues[step.stableID]
            )
        }
    }

    private var mockGhostLines: [GhostTypesetLine] {
        guard let page = currentPage else { return [] }
        return page.steps.filter(\.isActive).sorted { $0.sortIndex < $1.sortIndex }.compactMap { step in
            guard !step.ghostLaTeX.isEmpty else { return nil }
            return GhostTypesetLine(latex: step.ghostLaTeX, yPosition: step.yPosition + 36)
        }
    }

    private var mockAnnotations: [Annotation] {
        guard viewModel.sessionMode == .coach else { return [] }
        guard let page = currentPage else { return [] }
        let errorSteps = page.steps.filter { $0.isActive && ($0.status == .warning || $0.status == .error) }
        return errorSteps.enumerated().compactMap { i, step in
            let engine = MockMathEngine()
            let hintText = engine.hint(for: step.label, mode: viewModel.mathMode)
            return Annotation(
                text: hintText,
                position: CGPoint(x: 520, y: step.yPosition - 10),
                arrowTarget: CGPoint(x: 380, y: step.yPosition + 20),
                showAcceptChip: true,
                showSquiggle: step.status == .error,
                squiggleRect: step.status == .error ? CGRect(x: 130, y: step.yPosition + 10, width: 200, height: 6) : nil
            )
        }
    }

    private var mockBranches: [BranchItem] {
        guard let page = currentPage else { return [] }
        return page.branches.sorted { $0.sortIndex < $1.sortIndex }.map { branch in
            BranchItem(name: branch.name, status: branch.status, thumbnailData: branch.thumbnailData)
        }
    }

    private var paletteCommands: [PaletteCommand] {
        var commands = [
            PaletteCommand(name: "Save", icon: "square.and.arrow.down") { viewModel.save() },
            PaletteCommand(name: "Switch Math Mode", icon: "function") { viewModel.cycleMathMode() },
            PaletteCommand(name: "Export", icon: "square.and.arrow.up") { showExport = true },
            PaletteCommand(name: "New Page", icon: "plus.rectangle") { showTemplatePicker = true },
            PaletteCommand(name: "Import PDF", icon: "doc.fill") { showPDFImport = true },
            PaletteCommand(name: "Help", icon: "questionmark.circle") { showHelp = true },
            PaletteCommand(name: "Toggle Typeset", icon: "textformat") { showTypeset.toggle() },
            PaletteCommand(name: "Start Voice", icon: "mic") { },
            PaletteCommand(name: "Replay", icon: "play.circle") { showReplay = true },
            PaletteCommand(name: "Formula Sheet", icon: "list.bullet.rectangle") { showFormulaSheet = true },
            PaletteCommand(name: "Insights", icon: "lightbulb") { showInsights = true },
        ]
#if DEBUG
        commands.append(
            PaletteCommand(name: "Share Recognition Log", icon: "doc.text.magnifyingglass") {
                Task { @MainActor in
                    if let url = try? await RecognitionDebugRecorder.shared.currentLogURL() {
                        exportedFileURL = url
                        showShareSheet = true
                    }
                }
            }
        )
#endif
        return commands
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                canvasArea(geo: geo)
                overlays(geo: geo)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .overlay(alignment: .top) {
            SessionModeControl(mode: $viewModel.sessionMode)
                .padding(.top, 8)
        }
        .overlay(alignment: .bottomTrailing) {
            StatusChipView(
                mathMode: viewModel.mathMode,
                saveState: "saved",
                stepCount: mockBadges.count
            )
            .padding(.trailing, 60)
            .padding(.bottom, 8)
            .allowsHitTesting(false)
        }
        .overlay(alignment: .bottomTrailing) {
            VStack(spacing: 12) {
                VoicePillView(onAnnotation: { _ in })
                Button {
                    withAnimation { showChat.toggle() }
                } label: {
                    Image(systemName: "bubble.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(FolioTheme.ink)
                        .frame(width: 48, height: 48)
                        .background(
                            Circle()
                                .fill(FolioTheme.chromeBackground)
                                .shadow(color: FolioTheme.chromeShadow, radius: 8, y: 2)
                        )
                }
            }
            .padding(.trailing, 16)
            .padding(.bottom, 16)
        }
        .overlay(alignment: .trailing) {
            if showChat {
                ChatPanelView(
                    isOpen: $showChat,
                    sessionMode: viewModel.sessionMode,
                    mathMode: viewModel.mathMode,
                    anchor: chatAnchor
                )
                .padding(.trailing, 72)
                .padding(.bottom, 80)
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .overlay(alignment: .leading) {
            InsightsDrawer(
                insights: MockLearnerModelService().insights(for: mockBadges.map { $0.explanation }, mode: viewModel.mathMode),
                isOpen: $showInsights,
                onNavigateToStep: { _ in }
            )
        }
        .overlay(alignment: .trailing) {
            BranchesDrawer(
                branches: mockBranches,
                isOpen: $showBranches,
                onSelectBranch: { _ in }
            )
        }
        .overlay(alignment: .bottom) {
            if showReplay {
                ReplayTimelineView(
                    isActive: $showReplay,
                    events: RevisionReplayService().events(for: currentPage),
                    totalDuration: RevisionReplayService().totalDuration(for: currentPage)
                )
            }
        }
        .overlay {
            if showCommandPalette {
                ZStack {
                    Color.black.opacity(0.2)
                        .ignoresSafeArea()
                        .onTapGesture { showCommandPalette = false }
                    CommandPaletteView(
                        isPresented: $showCommandPalette,
                        commands: paletteCommands
                    )
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .onAppear { setupSave() }
        .onDisappear { viewModel.save() }
        .sheet(isPresented: $showExport) {
            ExportSheetView { format in
                handleExport(format)
            }
        }
        .sheet(isPresented: $showHelp) { HelpSheetView() }
        .sheet(isPresented: $showFormulaSheet) {
            FormulaSheetView(
                formulas: mockBadges.enumerated().map { i, b in
                    (label: "Step \(i + 1)", latex: mockGhostLines.indices.contains(i) ? mockGhostLines[i].latex : "")
                }.filter { !$0.latex.isEmpty },
                isPresented: $showFormulaSheet
            )
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = exportedFileURL { ShareSheet(url: url) }
        }
        .sheet(isPresented: $showTemplatePicker) {
            TemplatePickerView(isPresented: $showTemplatePicker) { template in
                let nextIndex = (sortedPages.last?.sortIndex ?? -1) + 1
                let page = Page(sortIndex: nextIndex, backgroundStyle: template.background, mathMode: viewModel.mathMode)
                page.notebook = notebook
                notebook.pages.append(page)
            }
        }
        .sheet(isPresented: $showPDFImport) {
            PDFImportView(isPresented: $showPDFImport, notebook: notebook)
        }
        .sheet(isPresented: $showBranchCompare) {
            if mockBranches.count >= 2 {
                BranchCompareView(
                    branchA: mockBranches[0], branchB: mockBranches[1],
                    stepsA: mockBadges, stepsB: mockBadges,
                    isPresented: $showBranchCompare
                )
            }
        }
        .overlay {
            if showSplitViewPreview { SplitViewPreview(isPresented: $showSplitViewPreview) }
        }
        .overlay {
            if showDesktopHandoff { DesktopHandoffPreview(isPresented: $showDesktopHandoff) }
        }
        .overlay {
            if showUnitCheck { UnitCheckPreview(isPresented: $showUnitCheck) }
        }
        .overlay {
            if showForkToPractise { ForkToPractisePreview(isPresented: $showForkToPractise) }
        }
        .overlay {
            if showVersionSnapshots { VersionSnapshotsPreview(isPresented: $showVersionSnapshots) }
        }
        .onKeyPress(.init("k"), phases: .down) { _ in
            showCommandPalette.toggle()
            return .handled
        }
    }

    // MARK: - Canvas

    @ViewBuilder
    private func canvasArea(geo: GeometryProxy) -> some View {
        ZStack {
            PageBackgroundView(style: viewModel.backgroundStyle, pageSize: CGSize(width: geo.size.width, height: max(geo.size.height, 2048)))
            CanvasView(viewModel: viewModel)
        }
    }

    // MARK: - Overlays

    @ViewBuilder
    private func overlays(geo: GeometryProxy) -> some View {
        let showOverlays = viewModel.sessionMode.showsBadges

        StepGutterView(
            badges: mockBadges, visible: showOverlays, scrollOffset: scrollOffset,
            onOpenThread: { stepID in
                let stepIndex = currentPage?.steps.first { $0.stableID == stepID }?.sortIndex ?? 0
                chatAnchor = .step(stepIndex)
                showChat = true
            },
            onSetConfidence: { stepID, level in
                confidenceValues[stepID] = level
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

        GhostTypesetView(lines: mockGhostLines, visible: viewModel.showTypeset, scrollOffset: scrollOffset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .allowsHitTesting(false)

        AnnotationLayerView(
            annotations: mockAnnotations,
            visible: viewModel.sessionMode.showsHints,
            scrollOffset: scrollOffset,
            onAccept: { _ in }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)

        if let bounds = viewModel.selectedStrokesBounds {
            SelectionHullView(bounds: bounds, scrollOffset: scrollOffset)
                .allowsHitTesting(false)
        }

        if viewModel.showRadialMenu, let bounds = viewModel.selectedStrokesBounds {
            RadialMenuView(
                center: CGPoint(x: bounds.midX, y: bounds.midY),
                scrollOffset: scrollOffset,
                onAction: { handleRadialAction($0) },
                onDismiss: { viewModel.showRadialMenu = false }
            )
        }

        ContradictionTraceView(
            badges: mockBadges,
            errorStepIndex: contradictionStepIndex,
            scrollOffset: scrollOffset
        )
        .allowsHitTesting(false)

        ForEach(visualizeCards) { card in
            let stepY = mockBadges.first(where: { _ in card.stepIndex < mockBadges.count })?.yPosition ?? 200
            VisualizeCardView(
                data: card,
                sourcePosition: CGPoint(x: 400, y: stepY)
            )
            .offset(x: 380, y: stepY - scrollOffset - 20)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarLeading) {
            Text(notebook.name)
                .font(FolioTheme.uiFont(size: 16, weight: .semibold))
        }

        ToolbarItemGroup(placement: .principal) {
            ToolStripView(viewModel: viewModel)
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                viewModel.cycleMathMode()
            } label: {
                Text(viewModel.mathMode.label)
                    .font(FolioTheme.uiFont(size: 12, weight: .bold))
                    .foregroundStyle(FolioTheme.paper)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(FolioTheme.ink))
            }

            Button {
                viewModel.showTypeset.toggle()
            } label: {
                Image(systemName: "textformat")
                    .foregroundStyle(viewModel.showTypeset ? FolioTheme.accent : FolioTheme.muted)
            }

            Button { showExport = true } label: {
                Image(systemName: "square.and.arrow.up")
            }

            Button { showCommandPalette.toggle() } label: {
                Image(systemName: "command")
            }
        }
    }

    // MARK: - Actions

    private func setupSave() {
        let context = modelContext
        viewModel.onSave = { data, background in
            if let page = currentPage {
                page.drawingData = data
                page.background = background
                notebook.lastEditedAt = Date()
                try? context.save()
                stepTrackingTask?.cancel()
                stepTrackingTask = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1.25))
                    guard !Task.isCancelled else { return }
                    await stepTracker.process(
                        drawingData: data,
                        page: page,
                        context: context
                    )
                }
            }
        }
    }

    private func addPage() {
        let nextIndex = (sortedPages.last?.sortIndex ?? -1) + 1
        let page = Page(sortIndex: nextIndex, mathMode: viewModel.mathMode)
        page.notebook = notebook
        notebook.pages.append(page)
    }

    private func handleRadialAction(_ action: RadialAction) {
        viewModel.showRadialMenu = false
        switch action {
        case .check:
            break
        case .hint, .explain:
            break
        case .formalize:
            showTypeset = true
        case .branch:
            if let page = currentPage {
                let branch = Branch(name: "Branch \(page.branches.count + 1)", sortIndex: page.branches.count)
                branch.page = page
                page.branches.append(branch)
                showBranches = true
            }
        case .visualize:
            let viz = MockVisualizationService()
            let card = viz.visualize(stepLabel: "", mode: viewModel.mathMode)
            visualizeCards.append(card)
        }
    }

    private func handleExport(_ format: ExportFormat) {
        let size = CGSize(width: 768, height: 1024)
        switch format {
        case .png:
            guard let data = ExportService.renderPNG(drawing: viewModel.drawing, background: viewModel.backgroundStyle, size: size) else { return }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Folio-Page.png")
            try? data.write(to: url)
            exportedFileURL = url
            showShareSheet = true
        case .pdf:
            let data = ExportService.renderPDF(drawing: viewModel.drawing, background: viewModel.backgroundStyle, size: size)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Folio-Page.pdf")
            try? data.write(to: url)
            exportedFileURL = url
            showShareSheet = true
        case .latex:
            let text = "% Mock LaTeX export\n\\documentclass{article}\n\\begin{document}\nMock content\n\\end{document}"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Folio-Page.tex")
            try? text.write(to: url, atomically: true, encoding: .utf8)
            exportedFileURL = url
            showShareSheet = true
        case .markdown:
            let text = "# Mock Markdown Export\n\nMock content"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Folio-Page.md")
            try? text.write(to: url, atomically: true, encoding: .utf8)
            exportedFileURL = url
            showShareSheet = true
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
