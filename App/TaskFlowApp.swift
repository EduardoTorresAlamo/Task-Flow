import SwiftUI
import SwiftData
import WidgetKit

/// The SwiftData container plus the graph of interdependent `@Observable`
/// services, built once and lazily.
///
/// This exists so `TaskFlowApp` needs no custom `init`. Previously the App
/// value's initialiser built the whole graph and ran side-effectful setup
/// (restoring calendar authorization) via `State(initialValue:)` — work that
/// belongs behind a lazily-instantiated `@State`, not in the struct's `init`.
/// Folding it here keeps the construction order the services require
/// (`CalendarSyncService` needs `EventKitService`; `CalendarManager` needs
/// both) while running exactly once, when SwiftUI first materialises the
/// backing state.
@MainActor
@Observable
final class AppServices {
    /// The single SwiftData model container shared across the whole app,
    /// backed by the App Group store the Widget extension also reads.
    let container: ModelContainer

    /// Observable wrapper around `EKEventStore`.
    let eventKitService: EventKitService

    /// Coordinates bidirectional sync between `Task` objects and `EKEvent` records.
    let calendarSyncService: CalendarSyncService

    /// High-level facade driving the full calendar sync workflow.
    let calendarManager: CalendarManager

    /// Manages the audio + speech stack for voice-to-task input.
    let voiceTaskService: VoiceTaskService

    /// Captures task ids opened from the Widget extension via `taskflow://` links.
    let deepLinkCoordinator: DeepLinkCoordinator

    init() {
        // Schema registration lives in TaskFlowContainer (Shared/), used by both targets.
        container = TaskFlowContainer.makeForApp()

        // Construction order matters: css depends on eks, cm depends on both.
        let eks = EventKitService()
        // Restore authorization state from a previous session synchronously
        // (no prompt) so downstream services see the correct flags at construction
        // time -- CalendarManager eagerly loads the calendar list when authorized.
        eks.checkExistingAuthorization()
        let css = CalendarSyncService(eventKitService: eks)
        eventKitService     = eks
        calendarSyncService = css
        calendarManager     = CalendarManager(eventKitService: eks, syncService: css)
        voiceTaskService    = VoiceTaskService()
        deepLinkCoordinator = DeepLinkCoordinator()
    }
}

/// The top-level app entry point for Task-Flow.
///
/// Injects the shared service objects into the SwiftUI environment so every
/// view in the hierarchy can reach them without prop-drilling.
@main
struct TaskFlowApp: App {
    /// The lazily-built service graph. Using a `@State` default expression
    /// (rather than a custom `init`) means `AppServices()` runs once, when
    /// SwiftUI first materialises this state, not on every App re-evaluation.
    @State private var services = AppServices()

    /// Used to refresh the widget when the app stops being the active scene.
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootTabView()
                // Inject services via environment so child views can read
                // them with @Environment(ServiceType.self).
                .environment(services.eventKitService)
                .environment(services.calendarSyncService)
                .environment(services.calendarManager)
                .environment(services.voiceTaskService)
                .environment(services.deepLinkCoordinator)
                // Route widget deep links (taskflow://task/<uuid>) into the
                // coordinator; the navigation layer can observe pendingTaskID.
                .onOpenURL { url in
                    if let id = TaskDeepLink.taskID(from: url) {
                        services.deepLinkCoordinator.open(taskID: id)
                    }
                }
        }
        // Attach the model container to the scene so every view in the
        // hierarchy gets access to the shared ModelContext automatically.
        .modelContainer(services.container)
        // Republish the widget's data whenever the app leaves the foreground.
        // The widget cannot read SwiftData itself, so this is the only way its
        // content ever changes; without it the Home Screen kept showing
        // whatever was true when the snapshot was last written.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                WidgetSnapshotPublisher.publish(from: services.container.mainContext)
            }
        }
    }
}
