import SwiftUI
import SwiftData

/// A modal form for editing the properties of an existing task.
///
/// Presented as a sheet from `SmartInboxView`, `CompletedTasksView`, and
/// `ProjectDetailView` when the user taps a task row.
///
/// Edits are staged in local `@State` drafts rather than written straight
/// through to the model. The design puts Cancel and Save side by side in the
/// header, which only means anything if Cancel actually discards: writing
/// directly to the `@Bindable` task (as this view previously did) made the two
/// buttons behave identically. Save is the only path that touches the store.
struct TaskEditView: View {
    /// The task being edited. `@Bindable` is retained for identity and for the
    /// delete flow; property edits go through the drafts below.
    @Bindable var task: Task

    /// Closure invoked when the user confirms deletion via the destructive
    /// confirmation dialog. The caller is responsible for removing the EventKit
    /// event and deleting the task from the SwiftData context.
    var onDelete: () -> Void

    /// Dismisses the sheet when called from Save, Cancel, or Delete.
    @Environment(\.dismiss) private var dismiss

    /// Provides access to `syncTask` and `removeSync` after the user taps Save.
    @Environment(CalendarManager.self) private var calendarManager

    /// Controls visibility of the delete confirmation dialog.
    @State private var showDeleteConfirm = false

    // MARK: - Drafts

    @State private var draftTitle = ""
    @State private var draftNotes = ""
    @State private var draftDueDate: Date?
    @State private var draftPriority: Priority = .none
    @State private var draftRecurrence: RecurrenceRule?

    /// Guards the one-time seeding of the drafts from the model.
    ///
    /// `.onAppear` can fire more than once for a sheet's content; re-seeding on
    /// a later pass would silently throw away everything the user had typed.
    @State private var didSeedDrafts = false

    /// Whether the inline date picker is expanded.
    @State private var isPickingDate = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        titleField
                        notesField
                        dueDateField
                        priorityField
                        repeatField
                        deleteButton
                    }
                    .padding(.horizontal, Theme.contentInset)
                    .padding(.bottom, 32)
                }
            }
            .padding(.top, 12)
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: seedDrafts)
        // Confirmation dialog prevents accidental deletion with a two-step flow.
        .confirmationDialog("Delete this task?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                onDelete()
                dismiss()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .font(.system(size: 16.5))
                .foregroundStyle(Theme.accent)

            Spacer()

            Text("Edit Task")
                .font(.tfSheetTitle)
                .foregroundStyle(Theme.text)

            Spacer()

            Button("Save", action: save)
                .font(.system(size: 16.5, weight: .semibold))
                .foregroundStyle(Theme.accent)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
    }

    // MARK: - Fields

    private var titleField: some View {
        labelled("Title") {
            GlassCard {
                TextField("", text: $draftTitle)
                    .font(.tfFieldValue)
                    .foregroundStyle(Theme.text)
                    .tint(Theme.accent)
            }
        }
    }

    private var notesField: some View {
        labelled("Notes") {
            GlassCard {
                // The axis-based TextField grows with its content and, unlike
                // TextEditor, needs no work to hide an opaque default background.
                TextField("", text: $draftNotes, axis: .vertical)
                    .font(.system(size: 14.5))
                    .foregroundStyle(Theme.textSecondary)
                    .tint(Theme.accent)
                    .lineLimit(3...8)
                    .frame(minHeight: 28, alignment: .topLeading)
            }
        }
    }

    private var dueDateField: some View {
        labelled("Due Date") {
            GlassCard {
                VStack(spacing: 12) {
                    Toggle(isOn: hasDueDateBinding) {
                        Text("Has due date")
                            .font(.tfFormRow)
                            .foregroundStyle(Theme.text)
                    }
                    .tint(Theme.accent)

                    if let dueDate = draftDueDate {
                        Divider().overlay(Theme.cardBorder)

                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { isPickingDate.toggle() }
                        } label: {
                            HStack {
                                Text(dueDate.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 14))
                                    .foregroundStyle(isPickingDate ? Theme.accent : Theme.textSecondary)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)

                        if isPickingDate {
                            // A second custom Binding unwraps the Optional for DatePicker,
                            // which requires a non-optional Binding<Date>.
                            DatePicker(
                                "",
                                selection: Binding(
                                    get: { draftDueDate ?? Date() },
                                    set: { draftDueDate = $0 }
                                ),
                                displayedComponents: [.date, .hourAndMinute]
                            )
                            .datePickerStyle(.graphical)
                            .tint(Theme.accent)
                            .labelsHidden()
                        }
                    }
                }
            }
        }
    }

    private var priorityField: some View {
        labelled("Priority") {
            HStack(spacing: 4) {
                ForEach(Priority.allCases, id: \.self) { priority in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { draftPriority = priority }
                    } label: {
                        Text(priority.label)
                            .font(.system(size: 13.5, weight: draftPriority == priority ? .semibold : .regular))
                            .foregroundStyle(draftPriority == priority ? .white : Theme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background {
                                if draftPriority == priority {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Theme.accent)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(Theme.cardFill)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.cardBorder, lineWidth: 1)
            )
        }
    }

    private var repeatField: some View {
        GlassCard {
            VStack(spacing: 12) {
                // A Menu lets the user pick a base frequency; the current
                // selection is shown trailing. Weekly rules reveal a
                // weekday picker below.
                Menu {
                    Button("Never") { setRecurrence(nil) }
                    Button("Daily") { setRecurrence(.daily) }
                    Button("Weekdays") { setRecurrence(.weekdays) }
                    Button("Weekly") { setRecurrence(.weekly(day: defaultWeekday)) }
                    Button("Monthly") { setRecurrence(.monthly(day: defaultDayOfMonth)) }
                    Button("Yearly") { setRecurrence(.yearly) }
                } label: {
                    HStack {
                        Text("Repeat")
                            .font(.tfFormRow)
                            .foregroundStyle(Theme.text)
                        Spacer()
                        Text(draftRecurrence?.label ?? "Never")
                            .font(.system(size: 14.5))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                if case .weekly(let day)? = draftRecurrence?.frequency {
                    Divider().overlay(Theme.cardBorder)

                    Picker("On", selection: Binding(
                        get: { day },
                        set: { setRecurrence(.weekly(day: $0)) }
                    )) {
                        ForEach(Weekday.allCases) { weekday in
                            Text(weekday.label).tag(weekday)
                        }
                    }
                    .tint(Theme.accent)
                    .foregroundStyle(Theme.text)
                }
            }
        }
    }

    private var deleteButton: some View {
        Button {
            showDeleteConfirm = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "trash")
                    .font(.system(size: 15))
                Text("Delete Task")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(Theme.red)
            .frame(maxWidth: .infinity)
            .padding(14)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.red.opacity(0.4), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.top, 6)
    }

    /// Wraps a field in the design's uppercase section label.
    @ViewBuilder
    private func labelled<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(text: label)
            content()
        }
    }

    // MARK: - Bindings

    /// Converts the optional draft due date into a Bool toggle.
    ///
    /// Turning the toggle on seeds the date from the task's existing deadline
    /// when there is one, so flipping it off and back on does not silently
    /// reset a carefully chosen time to "now".
    private var hasDueDateBinding: Binding<Bool> {
        Binding(
            get: { draftDueDate != nil },
            set: { isOn in
                draftDueDate = isOn ? (task.dueDate ?? Date()) : nil
                if !isOn { isPickingDate = false }
            }
        )
    }

    // MARK: - Persistence

    /// Copies the model's current values into the drafts, once.
    private func seedDrafts() {
        guard !didSeedDrafts else { return }
        didSeedDrafts = true
        draftTitle = task.title
        draftNotes = task.notes
        draftDueDate = task.dueDate
        draftPriority = task.priority
        draftRecurrence = task.recurrenceRule
    }

    /// Writes the drafts back to the model and reconciles the calendar event.
    ///
    /// Clearing a due date removes the mirrored calendar event rather than
    /// leaving it orphaned in the user's calendar, which is what happened when
    /// Save unconditionally re-synced.
    private func save() {
        let hadDueDate = task.dueDate != nil

        task.title = draftTitle
        task.notes = draftNotes
        task.dueDate = draftDueDate
        task.priority = draftPriority
        task.recurrenceRule = draftRecurrence
        task.recurrenceEnd = draftRecurrence?.endDate
        // Stamp the update time before syncing so the calendar event
        // reflects the latest edit timestamp.
        task.updatedAt = Date()

        let clearedDueDate = hadDueDate && draftDueDate == nil
        // Sync is async; Swift.Task bridges the synchronous button action into
        // an async call without blocking the main thread.
        Swift.Task {
            if clearedDueDate {
                await calendarManager.removeSync(for: task)
            } else {
                await calendarManager.syncTask(task)
            }
        }
        dismiss()
    }

    // MARK: - Recurrence Helpers

    /// Applies a new recurrence frequency to the draft, preserving any existing
    /// interval and end conditions. Passing `nil` clears the recurrence entirely.
    ///
    /// - Parameter frequency: The chosen frequency, or `nil` for a one-off task.
    private func setRecurrence(_ frequency: RecurrenceFrequency?) {
        guard let frequency else {
            draftRecurrence = nil
            return
        }
        let existing = draftRecurrence
        draftRecurrence = RecurrenceRule(
            frequency: frequency,
            interval: existing?.interval ?? 1,
            endDate: existing?.endDate,
            maxOccurrences: existing?.maxOccurrences
        )
    }

    /// The weekday to default a newly-chosen weekly rule to: the draft due
    /// date's weekday when set, otherwise Monday.
    private var defaultWeekday: Weekday {
        guard let dueDate = draftDueDate else { return .monday }
        return Weekday.from(dueDate)
    }

    /// The day-of-month to default a newly-chosen monthly rule to: the draft
    /// due date's day when set, otherwise the 1st.
    private var defaultDayOfMonth: Int {
        guard let dueDate = draftDueDate else { return 1 }
        return Calendar.current.component(.day, from: dueDate)
    }
}
