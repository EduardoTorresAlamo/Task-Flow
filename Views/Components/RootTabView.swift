import SwiftUI

/// The root navigation container for Task-Flow.
///
/// Presents the two top-level tabs (Inbox and Done) and triggers the
/// EventKit permission request on first appearance so the prompt is shown
/// as early as possible in the user session.
///
/// `CalendarManager` is read from the environment and is used only to fire
/// the access request; all calendar state lives in the service itself.
struct RootTabView: View {
    /// The shared calendar manager injected by `TaskFlowApp`.
    ///
    /// `@Environment` is used here rather than `@State` because `CalendarManager`
    /// is created in `TaskFlowApp` and needs to be the same instance across all tabs.
    @Environment(CalendarManager.self) private var calendarManager

    var body: some View {
        TabView {
            SmartInboxView()
                .tabItem { Label("Inbox", systemImage: "tray") }
            CompletedTasksView()
                .tabItem { Label("Done", systemImage: "checkmark.circle") }
        }
        // App-wide accent color applied to all interactive controls.
        .tint(Color(hex: "#6E56CF"))
        // Force dark appearance throughout; the design uses pure black backgrounds.
        .preferredColorScheme(.dark)
        // Request EventKit access as soon as the root view appears.
        // Using .task ensures this runs once per view lifecycle on the @MainActor.
        .task { await calendarManager.requestAccess() }
    }
}
