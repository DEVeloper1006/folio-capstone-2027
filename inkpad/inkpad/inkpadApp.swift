import SwiftUI
import SwiftData

@main
struct inkpadApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Notebook.self,
            Page.self,
            Step.self,
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
            AppNavigation()
        }
        .modelContainer(sharedModelContainer)
    }
}
