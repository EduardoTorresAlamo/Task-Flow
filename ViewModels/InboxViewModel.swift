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

    /// The on-device model that files new tasks into projects and tags them.
    private let intelligence: TaskIntelligenceService

    /// IDs of tasks currently being catalogued by Apple Intelligence.
    ///
    /// The Inbox reads this to show a cataloging indicator on the affected row.
    /// Keyed by `Task.id` rather than holding the model object, because a task
    /// can be deleted while its catalog request is still in flight.
    private(set) var catalogingTaskIDs: Set<UUID> = []

    /// The most recent cataloging failure, for display in the Inbox.
    ///
    /// Cataloging is an enhancement, never a gate on saving a task, so failures
    /// are surfaced quietly here instead of being thrown at the caller.
    var catalogError: String?

    /// Creates the view model with the required dependencies.
    ///
    /// - Parameters:
    ///   - modelContext: The SwiftData context for inserting new tasks.
    ///   - calendarManager: The manager that syncs tasks to the system Calendar.
    ///   - intelligence: The on-device cataloging service. Defaulted because it
    ///     is stateless and holds no configuration; the parameter exists so a
    ///     test can substitute one.
    init(
        modelContext: ModelContext,
        calendarManager: CalendarManager,
        intelligence: TaskIntelligenceService = TaskIntelligenceService()
    ) {
        self.modelContext = modelContext
        self.calendarManager = calendarManager
        self.intelligence = intelligence
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
        let rawInput = inputText
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
        // Cataloging runs after the task is already saved and on screen. It is
        // an enhancement to a task that already exists, so it must never delay
        // the task appearing, and its failure must never lose the user's input.
        await catalog(task, rawInput: rawInput)
    }

    /// Files a freshly created task into a project, tags it, and tidies its
    /// title and priority using the on-device model.
    ///
    /// The natural-language parser stays authoritative for the due date and
    /// recurrence: those are deterministic, work with no model present, and are
    /// the fields a wrong answer would hurt most. The model owns only the
    /// fields it is actually better at.
    ///
    /// - Parameters:
    ///   - task: The already-inserted task to enrich.
    ///   - rawInput: What the user originally typed, before the parser stripped
    ///     date and priority words out of it. The model reads better signal from
    ///     the original phrasing than from the reduced title.
    private func catalog(_ task: Task, rawInput: String) async {
        guard intelligence.isReady else { return }

        let taskID = task.id
        catalogingTaskIDs.insert(taskID)
        defer { catalogingTaskIDs.remove(taskID) }

        let projects = (try? modelContext.fetch(FetchDescriptor<Project>())) ?? []

        do {
            let result = try await intelligence.catalog(
                text: rawInput,
                projectNames: projects.map(\.name)
            )

            // The task may have been deleted or edited while the model ran.
            // `isDeleted` is the documented way to ask a SwiftData model whether
            // its row still exists; touching a deleted model would trap.
            guard !task.isDeleted else { return }

            // Take the model's title whenever it produced one. There is
            // deliberately no "only if shorter" test: `TaskIntelligenceService`
            // already rejects a title that is not a rewrite of the user's own
            // words, and a length check on top of that rejects good rewrites
            // for being long — "remind me to maybe call the dentist" stayed as
            // "maybe call the dentist" rather than becoming the model's
            // "Call dentist about insurance", which is the entire feature.
            if !result.title.isEmpty {
                task.title = result.title
            }
            // Never downgrade a priority the parser read explicitly from the
            // text ("urgent" should not become None because the model disagreed).
            if task.priority == .none {
                task.priority = result.priority
            }
            if task.project == nil, let name = result.projectName {
                task.project = projects.first { $0.name == name }
            }
            TagStore.apply(result.tags, to: task, in: modelContext)
            task.updatedAt = Date()
            catalogError = nil
        } catch let error as TaskIntelligenceError {
            switch error {
            case .modelNotReady(let reason), .malformedResponse(let reason):
                catalogError = reason
            }
        } catch {
            catalogError = "Apple Intelligence could not catalog this task."
        }
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
