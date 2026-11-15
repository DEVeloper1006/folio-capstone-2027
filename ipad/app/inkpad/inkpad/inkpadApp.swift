import SwiftUI
import SwiftData

@main
struct inkpadApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Notebook.self,
            Page.self,
            Step.self,
            StepRevision.self, ComputationResult.self,
            Branch.self,
            ChatThread.self,
            ChatMessage.self,
            Snapshot.self,
            Insight.self,
            ClassSpace.self,
            WorkedExample.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--math-smoke") || ProcessInfo.processInfo.arguments.contains("--math-reopen") {
                ProgressView("Checking offline computations…").task {
                    await MathComputationSmoke.run(userContainer:sharedModelContainer,reopen:ProcessInfo.processInfo.arguments.contains("--math-reopen"))
                }
            } else if ProcessInfo.processInfo.arguments.contains("--canvas-smoke") || ProcessInfo.processInfo.arguments.contains("--canvas-reopen") {
                ProgressView("Checking canvas tools…").task {
                    await CanvasSmoke.run(userContainer: sharedModelContainer, reopen: ProcessInfo.processInfo.arguments.contains("--canvas-reopen"))
                }
            } else if ProcessInfo.processInfo.arguments.contains("--polynomial-ui-test") {
                PolynomialUITestHost(schema: sharedModelContainer.schema)
            } else if ProcessInfo.processInfo.arguments.contains("--polynomial-offline-smoke") {
                PolynomialOfflineCheckView(container: sharedModelContainer)
            } else if ProcessInfo.processInfo.arguments.contains("--polynomial-smoke") || ProcessInfo.processInfo.arguments.contains("--polynomial-reopen") {
                ProgressView("Checking polynomial integration…").task {
                    _ = await PolynomialSmoke.run(userContainer: sharedModelContainer,
                        reopen: ProcessInfo.processInfo.arguments.contains("--polynomial-reopen"))
                }
            } else if ProcessInfo.processInfo.arguments.contains("--local-integration-smoke") || ProcessInfo.processInfo.arguments.contains("--local-integration-reopen") || ProcessInfo.processInfo.arguments.contains("--inline-workflow-smoke") || ProcessInfo.processInfo.arguments.contains("--inline-workflow-reopen") {
                ProgressView("Checking local recognition…")
                    .task { await LocalRecognitionSmoke.run(userContainer: sharedModelContainer,
                        reopen: ProcessInfo.processInfo.arguments.contains("--local-integration-reopen") || ProcessInfo.processInfo.arguments.contains("--inline-workflow-reopen")) }
            } else { AppNavigation() }
#else
            AppNavigation()
#endif
        }
        .modelContainer(sharedModelContainer)
    }
}
