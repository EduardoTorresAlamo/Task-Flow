import SwiftUI
import SwiftData

/// A modal form for editing the properties of an existing task.
///
/// Presented as a sheet from both `SmartInboxView` and `CompletedTasksView`
/// when the user taps a task row. Changes are written directly to the SwiftData
/// model (via `@Bindable`) so no explicit save action is needed beyond touching
/// `task.updatedAt` and triggering an EventKit re-sync on Save.
struct TaskEditView: View {
    /// The task being edited. `@Bindable` enables two-way binding to individual
    /// properties (e.g. `$task.title`) without wrapping the whole struct in a
    /// separate `@State` copy, so edits are immediately reflected in the store.
    @Bindable var task: Task

    /// Closure invoked when the user confirms deletion via the destructive
    /// confirmation dialog. The caller is responsible for removing the EventKit
    /// event and deleting the task from the SwiftData context.
    var onDelete: () -> Void

    /// SwiftData context used for any additional fetch operations if needed.
    @Environment(\.modelContext) private var modelContext

    /// Dismisses the sheet when called from Save, Cancel, or Delete.
    @Environment(\.dismiss) private var dismiss

    /// Provides access to `syncTask` after the user taps Save.
    @Environment(CalendarManager.self) private var calendarManager

    /// Controls visibility of the delete confirmation dialog.
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                Form {
                    Section("Title") {
                        TextField("Title", text: $task.title)
                            .foregroundStyle(.white)
                    }
                    Section("Notes") {
                        TextEditor(text: $task.notes)
                            .frame(minHeight: 80)
                            .foregroundStyle(.white)
                    }
                    Section("Due Date") {
                        // Custom Binding converts the Optional<Date> to a Bool toggle.
                        // Setting to true initialises dueDate to now; setting to false
                        // removes the deadline entirely.
                        Toggle("Has due date", isOn: Binding(
                            get: { task.dueDate != nil },
                            set: { task.dueDate = $0 ? Date() : nil }
                        ))
                        if task.dueDate != nil {
                            // A second custom Binding unwraps the Optional for DatePicker,
                            // which requires a non-optional Binding<Date>.
                            DatePicker(
                                "",
                                selection: Binding(
                                    get: { task.dueDate ?? Date() },
                                    set: { task.dueDate = $0 }
                                ),
                                displayedComponents: [.date, .hourAndMinute]
                            )
                            .datePickerStyle(.graphical)
                            .accentColor(Color(hex: "#6E56CF"))
                        }
                    }
                    Section("Priority") {
                        Picker("Priority", selection: $task.priority) {
                            ForEach(Priority.allCases, id: \.self) { p in
                                Text(p.label).tag(p)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
                // Hide the default white Form background so the black ZStack shows through.
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Edit Task")
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        // Stamp the update time before syncing so the calendar event
                        // reflects the latest edit timestamp.
                        task.updatedAt = Date()
                        // Sync is async; Swift.Task bridges the synchronous toolbar
                        // action into an async call without blocking the main thread.
                        Swift.Task { await calendarManager.syncTask(task) }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete Task", systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                }
            }
            // Confirmation dialog prevents accidental deletion with a two-step flow.
            .confirmationDialog("Delete this task?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    onDelete()
                    dismiss()
                }
            }
        }
    }
}
