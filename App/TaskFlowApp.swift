import SwiftUI
import SwiftData

@main
struct TaskFlowApp: App {
    let container: ModelContainer
    @State private var eventKitService: EventKitService
    @State private var calendarSyncService: CalendarSyncService
    @State private var calendarManager: CalendarManager
    @State private var voiceTaskService: VoiceTaskService

    init() {
        do {
            container = try ModelContainer(for: Schema([Task.self, Project.self, Tag.self]))
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        let eks = EventKitService()
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
                .environment(eventKitService)
                .environment(calendarManager)
                .environment(voiceTaskService)
        }
        .modelContainer(container)
    }
}
