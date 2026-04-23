import SwiftUI

struct RootTabView: View {
    @Environment(CalendarManager.self) private var calendarManager

    var body: some View {
        TabView {
            SmartInboxView()
                .tabItem { Label("Inbox", systemImage: "tray") }
            CompletedTasksView()
                .tabItem { Label("Done", systemImage: "checkmark.circle") }
        }
        .tint(Color(hex: "#6E56CF"))
        .preferredColorScheme(.dark)
        .task { await calendarManager.requestAccess() }
    }
}
