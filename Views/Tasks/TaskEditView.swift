import SwiftUI
import SwiftData

struct TaskEditView: View {
    @Bindable var task: Task
    var onDelete: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(CalendarManager.self) private var calendarManager
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
                        Toggle("Has due date", isOn: Binding(
                            get: { task.dueDate != nil },
                            set: { task.dueDate = $0 ? Date() : nil }
                        ))
                        if task.dueDate != nil {
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
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Edit Task")
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        task.updatedAt = Date()
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
            .confirmationDialog("Delete this task?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    onDelete()
                    dismiss()
                }
            }
        }
    }
}
