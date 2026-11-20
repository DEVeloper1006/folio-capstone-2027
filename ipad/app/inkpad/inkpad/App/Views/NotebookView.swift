import SwiftUI
import SwiftData
import PencilKit

struct NotebookView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    let notebook: Notebook

    @State private var currentPageIndex = 0
    @State private var notebookWidth:CGFloat=1024
    @State private var viewModel: CanvasViewModel
    @State private var stepTracker = StepTrackingCoordinator()
    @State private var recognitionScheduler = ExpressionRecognitionScheduler()
    @State private var inlineTarget: InlineExpressionTarget?
    @AppStorage("recognition.automaticallyRecognize") private var automaticRecognition = true
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
    @State private var showRecognitionSettings = false
    @State private var recognitionConnection = RecognitionConnection.load()
    @State private var recognitionRevision = UUID()
    // Installed drawing callbacks outlive the View value that captured them.
    // Read shared State, not the launch-time Environment scenePhase snapshot.
    @State private var recognitionIsActive = false
    private var isRecognizing: Bool { recognitionScheduler.isRunning }
    private var shouldRecognizeAutomatically: Bool {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--polynomial-ui-test") && !ProcessInfo.processInfo.arguments.contains("--inline-ui-test") { return false }
#endif
        return automaticRecognition
    }
    @State private var recognitionNotice = ""
    @State private var showCommandPalette = false
    @State private var showWorkbench = false
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
        return page.steps.filter { $0.isActive && $0.source != .manual }.sorted { $0.sortIndex < $1.sortIndex }.map { step in
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
        return page.steps.filter { $0.isActive && $0.source != .manual }.sorted { $0.sortIndex < $1.sortIndex }.compactMap { step in
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
            HStack(spacing: 0) {
                GeometryReader { canvasGeo in
                    ZStack {
                        canvasArea(geo: canvasGeo)
                        overlays(geo: canvasGeo)
                    }
                }
                if showTypeset && geo.size.width >= 900 {
                    Divider()
                    recognitionPreview.frame(width: 360)
                }
            }
            .onAppear { notebookWidth=geo.size.width }
            .onChange(of:geo.size.width) { _,width in notebookWidth=width }
            .sheet(isPresented: Binding(get: { showTypeset && geo.size.width < 900 }, set: { if !$0 { showTypeset = false } })) {
                recognitionPreview.presentationDetents([.medium, .large]).presentationBackgroundInteraction(.enabled)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .overlay(alignment: .topLeading) {
            if let tool = viewModel.settingsTool {
                CanvasToolOptions(viewModel: viewModel, tool: tool).padding(.leading, 48).padding(.top, 48)
            }
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
        .onAppear { recognitionIsActive = scenePhase == .active;setupSave(); viewModel.pageHeight = canvasContentHeight }
        .onChange(of: canvasContentHeight) { _, height in viewModel.pageHeight = height }
        .alert("Could not save canvas change", isPresented: Binding(get: { !viewModel.canvasError.isEmpty }, set: { if !$0 { viewModel.canvasError = "" } })) {
            Button("OK") { viewModel.canvasError = "" }
        } message: { Text(viewModel.canvasError) }
        .onDisappear {
            viewModel.save()
            cancelRecognition()
            viewModel.onDrawingChanged = nil
        }
        .onChange(of: scenePhase) { _, phase in
            recognitionIsActive = phase == .active
            if phase != .active { cancelRecognition(); viewModel.save() }
            else if shouldRecognizeAutomatically { scheduleRecognition() }
        }
        .onChange(of: viewModel.mathMode) { _, mode in
            currentPage?.mathMode = mode
            cancelRecognition()
        }
        .onChange(of: automaticRecognition) { _, enabled in
            if enabled { scheduleRecognition() } else { cancelRecognition() }
        }
        .sheet(item: $inlineTarget) { target in
            if let step=currentPage?.steps.first(where: { $0.stableID==target.id && $0.isActive }) {
                InlineExpressionInspector(step:step,alternatives:stepTracker.alternatives[step.stableID] ?? [],busy:isRecognizing,
                    onAccept:acceptExpression,onRetry:{ scheduleRecognition(force:true) },
                    onInsert:{ id in try await insertResult(id);inlineTarget=nil },onRemove:{ result in
                        try CanvasResultStore.removeResult(result,context:modelContext,history:viewModel.history,onError:{viewModel.canvasError=$0})
                    })
            } else { Text("This row changed or was removed. Close this panel and review the current ink.").padding() }
        }
        .sheet(isPresented: $showRecognitionSettings) {
            RecognitionSettingsView(connection: recognitionConnection) { connection in
                recognitionConnection = connection
                cancelRecognition()
                stepTracker = makeStepTracker()
                recognitionNotice = "Provider saved. Tap Recognize when ready."
            }
        }
        .sheet(isPresented: $showWorkbench) {
            if let page=currentPage {
                ComputationWorkbenchView(page:page,onInsert:{ result in try await insertResult(result) },onRemove:{ result in
                    try CanvasResultStore.removeResult(result,context:modelContext,history:viewModel.history,onError:{viewModel.canvasError=$0})
                })
            }
        }
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
            CanvasPaperBackground(style: viewModel.backgroundStyle, viewport: viewModel.viewport)
            CanvasView(viewModel: viewModel)
            if let page = currentPage { CanvasResultLayer(page: page, viewModel: viewModel) }
        }.frame(width: geo.size.width, height: geo.size.height).clipped()
    }

    // MARK: - Overlays

    @ViewBuilder
    private func overlays(geo: GeometryProxy) -> some View {
        let showOverlays = viewModel.sessionMode.showsBadges

        StepGutterView(
            badges: mockBadges.filter { badge in currentPage?.steps.first(where:{$0.stableID==badge.id})?.source != .inferred }, visible: showOverlays, scrollOffset: scrollOffset,
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

        if let page=currentPage {
            ExpressionIndicatorLayer(steps:page.steps.filter { $0.isActive && $0.source == .inferred }.sorted { $0.sortIndex < $1.sortIndex },
                viewport:viewModel.viewport,available:geo.size,isRecognizing:isRecognizing,
                obstacles:page.steps.flatMap(\.computationResults).filter{$0.isPlacedOnCanvas && !$0.isRemoved}.map(\.canvasRect),
                onAccept:{ snapshot in
                    guard let step=page.steps.first(where:{$0.stableID==snapshot.id}),snapshot.matches(step) else {
                        recognitionNotice="This row changed. Review its current preview first.";return
                    }
                    acceptExpression(step,latex:snapshot.latex)
                },onOpen:{ id in
                    viewModel.settingsTool=nil;inlineTarget=InlineExpressionTarget(id:id)
                })
                .frame(width:geo.size.width,height:geo.size.height)
        }

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
                .font(FolioTheme.uiFont(size: 16, weight: .semibold)).lineLimit(1)
                .frame(maxWidth:notebookWidth<1000 ? 70:180)
        }

        ToolbarItemGroup(placement: .principal) {
            ToolStripView(viewModel: viewModel)
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            if notebookWidth>=1000 {
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

            }

            Button {
                showTypeset.toggle()
            } label: {
                Image(systemName: "textformat")
                    .foregroundStyle(showTypeset ? FolioTheme.accent : FolioTheme.muted)
            }

            Button {
                restartRecognition()
            } label: {
                Label(isRecognizing ? "Recognizing…" : "Recognize", systemImage: "pencil.and.outline")
            }.disabled(isRecognizing).accessibilityIdentifier("recognizeNotebook")

            Button { viewModel.save();showWorkbench=true } label: {
                Label("Compute",systemImage:"function")
            }.accessibilityIdentifier("openMathWorkbench")

            if notebookWidth<1000 {
                Menu {
                    Button("Math mode: \(viewModel.mathMode.label)",systemImage:"function") { viewModel.cycleMathMode() }
                    Button("Recognition settings",systemImage:"network") { showRecognitionSettings=true }
                    Button("Export",systemImage:"square.and.arrow.up") { showExport=true }
                    Button("Commands",systemImage:"command") { showCommandPalette.toggle() }
                } label: { Image(systemName:"ellipsis.circle") }
                    .accessibilityLabel("More notebook actions").accessibilityIdentifier("notebookMoreActions")
            } else {
            Button { showRecognitionSettings = true } label: {
                Image(systemName: "network")
            }.accessibilityLabel("Handwriting recognition settings")

            Button { showExport = true } label: {
                Image(systemName: "square.and.arrow.up")
            }

            Button { showCommandPalette.toggle() } label: {
                Image(systemName: "command")
            }
            }
        }
    }

    // MARK: - Actions

    private var recognitionPreview: some View {
        RecognitionPreviewView(
            steps: (currentPage?.steps ?? []).filter { $0.isActive && $0.source != .manual }.sorted { $0.sortIndex < $1.sortIndex },
            alternatives: stepTracker.alternatives, durations: stepTracker.durations,
            provider: recognitionConnection.provider, isRecognizing: isRecognizing, notice: recognitionNotice,
            automaticRecognition:$automaticRecognition,
            onSettings: { showRecognitionSettings = true },
            onRecognize: { restartRecognition() }, onCancel: { cancelRecognition() },
            onAccept: { step, latex in acceptExpression(step, latex: latex) }, onClose: { showTypeset = false },
            onInsertResult: { result in try await insertResult(result) },
            onRemoveResult: { result in
                try CanvasResultStore.removeResult(result, context: modelContext, history: viewModel.history,
                    onError: { viewModel.canvasError = $0 })
            }
        )
    }

    private var canvasContentHeight: CGFloat {
        let resultBottom = (currentPage?.steps ?? []).flatMap(\.computationResults)
            .filter { $0.isPlacedOnCanvas && !$0.isRemoved }.map { $0.canvasRect.maxY + 80 }.max() ?? 0
        return CanvasViewModel.contentHeight(drawing: viewModel.drawing, resultBottom: resultBottom)
    }

    private func insertResult(_ resultID: UUID) async throws {
        let descriptor=FetchDescriptor<ComputationResult>(predicate:#Predicate { $0.stableID == resultID })
        guard let result=try modelContext.fetch(descriptor).first else {
            throw PolynomialError.invalid("This result is no longer available.")
        }
        guard result.source?.page === currentPage, result.isCurrent else {
            throw PolynomialError.invalid("This result is outdated. Review the current source and compute again.")
        }
        if !result.isPlacedOnCanvas {
            let image: Data
            if let cached = result.canvasPreviewPNG, result.canvasPreviewVersion == CanvasResultLayout.previewVersion { image = cached }
            else { image = try await ResultImageRenderer.render(result.outputLatex) }
            try Task.checkCancellation()
            try CanvasResultStore.insert(result, preview: image, context: modelContext, history: viewModel.history,
                onError: { viewModel.canvasError = $0 })
        }
        if result.isPlacedOnCanvas && result.canvasPreviewVersion != CanvasResultLayout.previewVersion {
            let image=try await ResultImageRenderer.render(result.outputLatex)
            try Task.checkCancellation();try CanvasResultStore.refreshPreview(result,preview:image,context:modelContext)
        }
        viewModel.selectedResultID = result.stableID
        viewModel.pageHeight = canvasContentHeight
        showTypeset = false
        viewModel.requestFocus(result.canvasRect.insetBy(dx: -16, dy: -16))
    }

    private func setupSave() {
        stepTracker = makeStepTracker()
        viewModel.onSave = { data, background in
            if let page = currentPage {
                page.drawingData = data
                page.background = background
                notebook.lastEditedAt = Date()
                try? modelContext.save()
            }
        }
        viewModel.onDrawingChanged = { data in
            cancelRecognition()
            currentPage?.drawingData = data
            let fingerprints = Set(SpatialInkSegmenter().regions(in: data).map(\.fingerprint))
            for step in currentPage?.steps ?? [] where step.source == .inferred && step.isActive {
                if !fingerprints.contains(step.strokeFingerprint) {
                    step.recognitionState = .collecting
                    step.invalidateAcceptance()
                }
                if (try? PKDrawing(data: data).strokes.isEmpty) == true { step.isActive = false }
            }
            if shouldRecognizeAutomatically { scheduleRecognition() }
        }
    }

    private func makeStepTracker()->StepTrackingCoordinator {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--inline-ui-test") { return StepTrackingCoordinator(recognizer:InlineRecognitionFixture()) }
#endif
        return StepTrackingCoordinator(recognizer:recognitionConnection.service())
    }

    private func cancelRecognition() {
        recognitionRevision=UUID();recognitionScheduler.cancel()
    }

    private func restartRecognition() {
        showTypeset=true;scheduleRecognition(force:true)
    }

    private func scheduleRecognition(force:Bool=false) {
        cancelRecognition()
        guard let page=currentPage else { return }
        viewModel.save()
        guard let data=page.drawingData,(try? PKDrawing(data:data).strokes.isEmpty)==false else { return }
        recognitionNotice=""
        let revision=recognitionRevision
        recognitionScheduler.schedule(delay:force ? .zero:.milliseconds(650)) {
            guard revision==recognitionRevision,currentPage === page,recognitionIsActive else { return }
            await stepTracker.process(drawingData:data,page:page,context:modelContext,force:force)
        }
    }

    private func acceptExpression(_ step: Step, latex: String) {
        guard let page = currentPage else { return }
        do {
            let sample = try ExpressionReviewService.accept(step, latex: latex, page: page, context: modelContext)
            recognitionNotice = "Expression saved with its original ink."
            if let sample {
                Task {
                    do { _ = try await RecognitionBenchmarkStore.shared.save(sample) }
                    catch { recognitionNotice = "Expression saved; benchmark example could not be saved: " + error.localizedDescription }
                }
            }
        } catch { recognitionNotice = error.localizedDescription }
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
        let size = CGSize(width: 1024, height: canvasContentHeight)
        let results = (currentPage?.steps ?? []).flatMap(\.computationResults)
            .filter { $0.isPlacedOnCanvas && !$0.isRemoved }.compactMap { result -> CanvasExportItem? in
                guard let image = result.canvasPreviewPNG else { return nil }
                return CanvasExportItem(rect: result.canvasRect, png: image, isCurrent: result.isCurrent)
            }
        switch format {
        case .png:
            guard let data = ExportService.renderPNG(drawing: viewModel.drawing, background: viewModel.backgroundStyle, size: size, results: results) else { return }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Folio-Page.png")
            try? data.write(to: url)
            exportedFileURL = url
            showShareSheet = true
        case .pdf:
            let data = ExportService.renderPDF(drawing: viewModel.drawing, background: viewModel.backgroundStyle, size: size, results: results)
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
