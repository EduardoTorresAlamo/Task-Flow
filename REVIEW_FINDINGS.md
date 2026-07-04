# Task-Flow Code Review Findings

General health-check review. Build verified with `xcodebuild -scheme Task-Flow` after changes.

## Fixed directly

1. **Services/VoiceTaskService.swift (`startListening`)** — Reordered setup: the audio session was configured and activated *before* the auth guard and *before* `stopListening()`. Consequences: (a) an unauthorized/unavailable early return leaked an active `.record` session that mutes other audio; (b) `stopListening()` deactivated the session that had just been activated, so the engine started against a deactivated session. Now: guard first, tear down previous session, then configure/activate.
2. **Views/Inbox/SmartInboxView.swift + Views/Completed/CompletedTasksView.swift (delete flow)** — `Swift.Task { await calendarManager.removeSync(for: task) }` was only *scheduled*, and `modelContext.delete(task)` ran synchronously first, so `removeSync` later read an invalidated SwiftData model (`task.eventKitIdentifier`), risking a crash and always leaving the orphaned calendar event behind. The delete now happens inside the same async task, after `removeSync` completes, matching the intent stated in the original comment.
3. **Services/NaturalLanguageParser.swift (`buildTitle`)** — Filler-prefix removal compared a *trimmed* lowercase copy against the *untrimmed* `result`, so `dropFirst(filler.count)` dropped the wrong characters whenever the string had leading whitespace (e.g. " remind me to call John" -> "o call John"). `result` is now trimmed before each prefix check. Also replaced the single-pass `"  " -> " "` replacement (which only halves runs of spaces) with a `\s{2,}` regex collapse.
4. **App/TaskFlowApp.swift (`init`)** — `EventKitService.checkExistingAuthorization()` was dead code despite its doc saying "Call this at launch". Authorization flags were therefore always `false` at service construction, making `CalendarManager.init`'s eager `refreshCalendars()` branch unreachable. Now called right after `EventKitService()` is created (synchronous, no prompt).
5. **Services/CalendarManager.swift (`syncTask`)** — Every commit/save synced the task even with no due date; `CalendarSyncService.sync` falls back to `Date()`, so undated tasks ("buy milk") created phantom 1-hour calendar events starting "now". Added `guard task.dueDate != nil`, mirroring the eligibility rule `syncAllTasks` already applies.

## Flagged for human review (not changed)

1. **Models/Task.swift:52-62 — self-referential relationship has no explicit inverse.** `subtasks` (`.cascade`) and `parentTask` are declared as separate properties with no `inverse:`; SwiftData may treat them as two independent relationships rather than one bidirectional pair. Recommended: `@Relationship(deleteRule: .cascade, inverse: \Task.parentTask) var subtasks: [Task]`. Schema change — out of scope per review constraints.
2. **Services/CalendarManager.swift:81-83 — `isAuthorized` requires BOTH Calendar and Reminders full access**, but the app has no Reminders feature anywhere. A user who grants Calendar but denies Reminders gets all sync/import silently blocked. Likely should gate on `calendarAuthorized` only. Permission-flow change — report only.
3. **Services/CalendarSyncService.swift:52 — user calendar selection is never honored.** Events are always created on `store.defaultCalendarForNewEvents`, while `CalendarManager.selectedCalendarIdentifier` (persisted to UserDefaults) and `availableCalendars` are never read by any sync path or shown in any UI. Incomplete feature.
4. **Dead, feature-shaped code (left in place, product decision):**
   - `ViewModels/TimelineViewModel.swift` — entire file (`TimelineViewModel`, `TimelineEntry`) unused; no Timeline view exists in the app.
   - `Services/CalendarManager.swift` — `syncAllTasks` (:155), `importCalendarEvents` (:190), `detectConflicts`/`ConflictPair` (:227/:39) have no callers.
5. **Views/Tasks/TaskEditView.swift:97-99 — "Cancel" does not revert edits.** `@Bindable` writes every keystroke directly to the SwiftData model, so Cancel and Save differ only in `updatedAt`/re-sync. Needs a draft-copy pattern if Cancel is meant to discard changes. Product decision.
6. **Views/Tasks/TaskEditView.swift:87-95 — Save re-syncs completed tasks**, and clearing a task's due date leaves any previously synced calendar event in place (no removal path when `dueDate` becomes nil). Product decision on desired behavior.
7. **Views/Inbox/SmartInboxView.swift:77 — `.navigationTitle("Inbox")` has no effect**; there is no enclosing `NavigationStack` (CompletedTasksView has one). Cosmetic UI decision.
8. **project.yml vs CLAUDE.md mismatch** — deployment target is iOS 18.0 in `project.yml`, while CLAUDE.md/README describe the project as targeting iOS 19.
9. **Missing tests** — CLAUDE.md references `Task-FlowTests/NaturalLanguageParserTests`, but no test target or test files exist in the repo.
10. **Views/Components/VoiceInputButton.swift:33-44** — after the first-time permission grant the user must tap the mic again to start recording, and `.denied`/`.restricted` are silently ignored (no settings redirect). Documented in comments; UX decision.
11. **Services/NaturalLanguageParser.swift:148-152 — priority markers removed by bare substring**, so e.g. "mustard" in a title loses "must". Heuristic quality issue; fixing requires word-boundary matching (behavior change to parser output, left alone).
