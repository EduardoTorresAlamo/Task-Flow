import SwiftUI
import SwiftData

/// The top-level app entry point for Task-Flow.
///
/// Owns the `ModelContainer` for all SwiftData models and injects
/// shared service objects into the SwiftUI environment so every view
/// in the hierarchy can reach them without prop-drilling.
@main
struct TaskFlowApp: App {
    /// The single SwiftData model container shared across the whole app.
    ///
    /// Created eagerly at launch because every view that uses `@Query`
    /// or `@Environment(\.modelContext)` depends on it being present
    /// before the first render.
    let container: ModelContainer

    /// Observable wrapper around `EKEventStore`. Injected into the
    /// environment so that the calendar permission flow can be triggered
    /// from any descendant view.
    @State private var eventKitService: EventKitService

    /// Coordinates bidirectional sync between `Task` objects and
    /// `EKEvent` records inside `EKEventStore`.
    @State private var calendarSyncService: CalendarSyncService

    /// High-level facade that drives the full calendar sync workflow,
    /// including conflict detection and per-calendar selection.
    @State private var calendarManager: CalendarManager

    /// Manages `SFSpeechRecognizer` and `AVAudioEngine` for voice-to-task
    /// input. Kept as a `@State` service so the audio session lifecycle
    /// is tied to the app lifetime rather than a single view.
    @State private var voiceTaskService: VoiceTaskService

    /// Captures task ids opened from the Widget extension via `taskflow://`
    /// deep links so views can present the tapped task.
    @State private var deepLinkCoordinator = DeepLinkCoordinator()

    init() {
        // Build the container against the shared App Group store so the Widget
        // extension reads the exact same database this app writes to. Schema
        // registration lives in TaskFlowContainer (Shared/), used by both targets.
        container = TaskFlowContainer.makeShared()

        // Build the service graph manually because SwiftUI's DI system
        // cannot create @Observable services that have inter-dependencies.
        // CalendarSyncService depends on EventKitService, and CalendarManager
        // depends on both, so construction order matters here.
        let eks = EventKitService()
        // Restore authorization state from a previous session synchronously
        // (no prompt) so downstream services see the correct flags at construction
        // time -- CalendarManager eagerly loads the calendar list when authorized.
        eks.checkExistingAuthorization()
        let css = CalendarSyncService(eventKitService: eks)
        let cm  = CalendarManager(eventKitService: eks, syncService: css)
        _eventKitService     = State(initialValue: eks)
        _calendarSyncService = State(initialValue: css)
        _calendarManager     = State(initialValue: cm)
        _voiceTaskService    = State(initialValue: VoiceTaskService())
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                // Inject services via environment so child views can read
                // them with @Environment(ServiceType.self).
                .environment(eventKitService)
                .environment(calendarManager)
                .environment(voiceTaskService)
                .environment(deepLinkCoordinator)
                // Route widget deep links (taskflow://task/<uuid>) into the
                // coordinator; the navigation layer can observe pendingTaskID.
                .onOpenURL { url in
                    if let id = TaskDeepLink.taskID(from: url) {
                        deepLinkCoordinator.open(taskID: id)
                    }
                }
        }
        // Attach the model container to the scene so every view in the
        // hierarchy gets access to the shared ModelContext automatically.
        .modelContainer(container)
    }
}
