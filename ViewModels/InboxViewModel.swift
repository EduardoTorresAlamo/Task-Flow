import SwiftUI
import SwiftData
import Observation

/// View model for `SmartInboxView`.
///
/// Holds the mutable state for the natural-language input bar, runs the parser
/// on every keystroke to produce a live preview, and commits finished tasks to
/// SwiftData followed by an async EventKit sync.
///
/// Isolated to `@MainActor` because:
/// - `ModelContext` is not `Sendable` and must only be used on the main actor.
/// - `@Observable` tracking requires mutations to happen on a single actor to
///   avoid data-race warnings under Swift 6 strict concurrency.
@Observable @MainActor final class InboxViewModel {
    /// The raw text currently typed or dictated into the input bar.
    var inputText = ""

    /// The live parse result for `inputText`, or `nil` when the input is blank.
    ///
    /// Updated on every character change via `onInputChange()`. The UI displays
    /// the extracted due date from this value as a preview pill below the input.
    var parsedPreview: ParsedTaskInput?

    /// The NL parser used to extract structured fields from `inputText`.
    private let parser = NaturalLanguageParser()

    /// The SwiftData context used to persist newly created tasks.
    ///
    /// Injected at init time rather than read from `@Environment` directly,
    /// because `@Observable` ViewModels cannot use property wrappers that
    /// require a SwiftUI view lifecycle (they are not `View` conforming types).
    var modelContext: ModelContext

    /// The calendar manager used to sync newly committed tasks to EventKit.
    private let calendarManager: CalendarManager

    /// Creates the view model with the required dependencies.
    ///
    /// - Parameters:
    ///   - modelContext: The SwiftData context for inserting new tasks.
    ///   - calendarManager: The manager that syncs tasks to the system Calendar.
    init(modelContext: ModelContext, calendarManager: CalendarManager) {
        self.modelContext = modelContext
        self.calendarManager = calendarManager
    }

    /// Re-parses `inputText` and updates `parsedPreview`.
    ///
    /// Called from the view's `onChange(of: viewModel.inputText)` modifier so
    /// the preview updates incrementally as the user types. Clears `parsedPreview`
    /// when the input is blank to hide the preview pill.
    func onInputChange() {
        parsedPreview = inputText.trimmingCharacters(in: .whitespaces).isEmpty
            ? nil
            : parser.parse(inputText)
    }

    /// Validates the current parse result, inserts a new `Task` into SwiftData,
    /// resets the input field, and triggers an async EventKit sync.
    ///
    /// The method is a no-op if `parsedPreview` is `nil` or if the extracted
    /// title is empty (which can happen when the input consists entirely of
    /// keywords that the parser strips out).
    func commitTask() async {
        guard let parsed = parsedPreview, !parsed.title.isEmpty else { return }
        let task = Task(title: parsed.title, dueDate: parsed.dueDate, priority: parsed.priority, notes: parsed.notes)
        // Carry any detected recurrence onto the task, mirroring the rule's own
        // endDate onto recurrenceEnd so the task-level cutoff stays in sync.
        if let recurrence = parsed.recurrence {
            task.recurrenceRule = recurrence
            task.recurrenceEnd = recurrence.endDate
        }
        // Insert into the context immediately so the task appears in @Query results
        // before the async sync completes.
        modelContext.insert(task)
        inputText = ""
        parsedPreview = nil
        // Sync to EventKit asynchronously so the UI is not blocked waiting for
        // the calendar store write.
        await calendarManager.syncTask(task)
    }

    /// Toggles a task's completion state, applying recurrence rules on completion.
    ///
    /// Un-completing simply clears the completed flags. Completing a non-recurring
    /// task marks it done. Completing a recurring task marks the original done
    /// (preserving it as history) and spawns the next occurrence via
    /// `completeRecurring(_:)`.
    ///
    /// - Parameter task: The task whose completion state should be toggled.
    func toggleCompletion(_ task: Task) async {
        if task.isCompleted {
            task.isCompleted = false
            task.completedAt = nil
            task.updatedAt = Date()
            return
        }
        if task.isRecurring {
            await completeRecurring(task)
        } else {
            task.isCompleted = true
            task.completedAt = Date()
            task.updatedAt = Date()
        }
    }

    /// Completes a recurring task and generates its successor.
    ///
    /// The original task is left marked complete so it remains in the user's
    /// history. A new task for the next occurrence (same title, project, tags,
    /// priority, notes, and recurrence rule, with an advanced due date) is
    /// inserted and synced to the calendar. When the recurrence has ended
    /// (`makeNextOccurrence` returns `nil`) no successor is created.
    ///
    /// - Parameter task: The recurring task being completed.
    private func completeRecurring(_ task: Task) async {
        task.isCompleted = true
        task.completedAt = Date()
        task.updatedAt = Date()

        guard let next = task.makeNextOccurrence() else { return }
        modelContext.insert(next)
        await calendarManager.syncTask(next)
    }
}
