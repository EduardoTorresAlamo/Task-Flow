# Business Logic, Data Loss & Race Conditions Audit Report

## 1. Overview
This module details operational bugs, potential data loss conditions, unhandled failure modes, race conditions, and logical flaws in Task-Flow's core workflows.

---

## 2. Findings

<a id="logic-01"></a>
### LOGIC-01: App Group Fallback Causes Silent Multi-Store Data Loss & Desync
* **Severity**: 🚨 **CRITICAL**
* **Category**: Data Integrity / Data Loss
* **File**: [`Shared/TaskFlowSharedStore.swift`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/Shared/TaskFlowSharedStore.swift#L45-L52)

#### Problem Description
When building the shared `ModelContainer`, `TaskFlowContainer` checks if the App Group container URL is available:
```swift
if let groupURL = FileManager.default.containerURL(
    forSecurityApplicationGroupIdentifier: AppGroup.identifier
) {
    let storeURL = groupURL.appending(path: "TaskFlow.store")
    configuration = ModelConfiguration(schema: schema, url: storeURL)
} else {
    // App Group unavailable (e.g. entitlement missing): degrade to default per-app store
    configuration = ModelConfiguration(schema: schema)
}
```
If the App Group entitlement fails on device (e.g., during signing changes or free developer profile expiration), the main app quietly initializes a default local store file at `~/Documents/default.store`. Meanwhile, the Widget extension (which also calls `makeShared()`) fails or initializes a separate store file in its container.

#### Real-World Impact
1. Tasks created by the user in the main app are written to `default.store`.
2. The Widget extension reads from `TaskFlow.store` or `widget-snapshot.json` in the App Group directory.
3. The app and widget operate on completely different databases with zero indication to the user. Tasks saved in the app vanish from the widget, and tasks created via widget background intents are written to a store the app never reads.

#### Recommended Remediation
Fail explicitly or surface a high-visibility warning to the user if the App Group container is unreachable, rather than silently splitting user data into two independent databases:
```swift
static func makeShared() throws -> ModelContainer {
    guard let groupURL = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: AppGroup.identifier
    ) else {
        throw StoreError.appGroupUnavailable(AppGroup.identifier)
    }
    let storeURL = groupURL.appending(path: "TaskFlow.store")
    let configuration = ModelConfiguration(schema: schema, url: storeURL)
    return try ModelContainer(for: schema, configurations: configuration)
}
```

---

<a id="logic-02"></a>
### LOGIC-02: Selected Calendar Preference (`selectedCalendarIdentifier`) Silently Ignored
* **Severity**: 🔴 **HIGH**
* **Category**: Broken Feature / User Preference Loss
* **File**: [`Services/CalendarSyncService.swift`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/Services/CalendarSyncService.swift#L52) & [`Services/CalendarManager.swift`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/Services/CalendarManager.swift#L68-L73)

#### Problem Description
`CalendarManager` exposes `selectedCalendarIdentifier` (persisted to `UserDefaults` under `"selectedCalendarIdentifier"`) so users can choose which calendar Task-Flow syncs events to.

However, inside `CalendarSyncService.sync(task:)`, when a new `EKEvent` is instantiated, line 52 executes:
```swift
ekEvent = EKEvent(eventStore: store)
ekEvent.calendar = store.defaultCalendarForNewEvents
```
`CalendarSyncService` **never** reads `CalendarManager.selectedCalendarIdentifier`! It unconditionally forces every event onto `store.defaultCalendarForNewEvents`.

#### Real-World Impact
User preference selection in the app settings/picker is completely useless. If a user selects a dedicated "Task-Flow" or "Work" calendar, every synced task is still forced into their primary default calendar ("Personal" / "iCloud").

#### Recommended Remediation
Pass `selectedCalendarIdentifier` to `CalendarSyncService` or resolve the calendar from `EKEventStore`:
```swift
if let selectedID = calendarManager.selectedCalendarIdentifier,
   let calendar = store.calendar(withIdentifier: selectedID) {
    ekEvent.calendar = calendar
} else {
    ekEvent.calendar = store.defaultCalendarForNewEvents
}
```

---

<a id="logic-03"></a>
### LOGIC-03: NaturalLanguageParser Substring Stripping Corrupts English Words ("mustard" -> "ard")
* **Severity**: 🔴 **HIGH**
* **Category**: Logic Bug / Text Corruption
* **File**: [`Services/NaturalLanguageParser.swift`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/Services/NaturalLanguageParser.swift#L258-L260)

#### Problem Description
`buildTitle` strips priority keywords from the user's input:
```swift
let priorityMarkers = ["urgent", "asap", "critical", "high priority", "important",
                       "must", "need to", "low priority", "whenever", "someday",
                       "no rush", "eventually"]
for marker in priorityMarkers {
    result = result.replacingOccurrences(of: marker, with: "", options: .caseInsensitive)
}
```
`replacingOccurrences` performs raw substring replacement without word-boundary anchoring (`\b`).

#### Real-World Impact
- Input: `"Buy mustard for hot dogs"` -> `extractPriority` matches `"must"` (Priority `.medium`), then `buildTitle` strips `"must"` from `"mustard"`, leaving title as `"Buy ard for hot dogs"`.
- Input: `"Discussion regarding important matter"` -> title corrupted.
- Input: `"Someday project"` -> title becomes `" project"`.

#### Recommended Remediation
Use regex with word boundaries (`\b`) to replace priority markers:
```swift
for marker in priorityMarkers {
    let pattern = #"\b"# + NSRegularExpression.escapedPattern(for: marker) + #"\b"#
    result = result.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
}
```

---

<a id="logic-04"></a>
### LOGIC-04: Silent Exception Swallowing in EventKit I/O Operations
* **Severity**: 🔴 **HIGH**
* **Category**: Silent Failure / Error Handling
* **File**: [`Services/CalendarSyncService.swift`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/Services/CalendarSyncService.swift#L81-L83,L103-L105)

#### Problem Description
`CalendarSyncService` handles EventKit save and remove operations with empty catch blocks:
```swift
do {
    try store.save(ekEvent, span: .thisEvent)
    task.eventKitIdentifier = ekEvent.eventIdentifier
} catch {
    // Save failed -- eventKitIdentifier remains unchanged
}
```
```swift
do {
    try eventKitService.store.remove(ekEvent, span: .thisEvent)
    task.eventKitIdentifier = nil
} catch {
    // Removal failed -- identifier preserved so retry is possible
}
```

#### Real-World Impact
If a calendar is read-only (e.g. subscribed calendar), or if EventKit access fails due to store locks or restricted calendar permissions, the error is completely swallowed.
1. The UI reports `syncState = .done(lastSyncedAt: Date())`.
2. The user assumes the task was synced to their calendar, but no calendar event was created.
3. If an event fails to delete, `removeSync` silently fails, leaving orphaned calendar events on the user's device calendar.

#### Recommended Remediation
Log the error using `Logger` and update `CalendarManager.syncState` with `.error(message:)` so the UI can notify the user of failed calendar syncs:
```swift
do {
    try store.save(ekEvent, span: .thisEvent)
    task.eventKitIdentifier = ekEvent.eventIdentifier
} catch {
    Logger(subsystem: "com.eduardotorres.Task-Flow", category: "CalendarSync")
        .error("Failed to save EKEvent: \(error.localizedDescription)")
    throw error
}
```

---

<a id="logic-05"></a>
### LOGIC-05: Broken Deep-Link Coordinator Wiring (Widget Taps Never Open Target Task)
* **Severity**: 🟡 **MEDIUM**
* **Category**: Broken Feature / Deep Linking
* **File**: [`App/DeepLinkCoordinator.swift`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/App/DeepLinkCoordinator.swift#L18) & [`App/TaskFlowApp.swift`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/App/TaskFlowApp.swift#L75)

#### Problem Description
`TaskFlowApp` injects `DeepLinkCoordinator` into the environment and updates `deepLinkCoordinator.pendingTaskID` when a `taskflow://task/<uuid>` URL is received.

However, **no view in the application reads or observes `DeepLinkCoordinator`**!
- `SmartInboxView` does not observe `pendingTaskID`.
- `RootTabView` does not observe `pendingTaskID`.
- No `.onChange(of: deepLinkCoordinator.pendingTaskID)` modifier exists anywhere in the codebase.

#### Real-World Impact
When the user taps a task row in the Widget, iOS opens Task-Flow via `taskflow://task/<uuid>`. The app launches or comes to foreground, decodes the UUID, stores it in `DeepLinkCoordinator.pendingTaskID`, and **does absolutely nothing with it**. The tapped task is never selected, presented, or scrolled into view.

#### Recommended Remediation
Add deep-link observation in `SmartInboxView` or `RootTabView` to present `TaskEditView` when `pendingTaskID` changes:
```swift
.onChange(of: deepLinkCoordinator.pendingTaskID) { _, id in
    guard let id, let task = tasks.first(where: { $0.id == id }) else { return }
    selectedTask = task
    deepLinkCoordinator.pendingTaskID = nil
}
```

---

<a id="logic-06"></a>
### LOGIC-06: Deletion Ordering Race Condition in `TaskEditView` and `SmartInboxView`
* **Severity**: 🟡 **MEDIUM**
* **Category**: Concurrency / Race Condition
* **File**: [`Views/Inbox/SmartInboxView.swift`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/Views/Inbox/SmartInboxView.swift#L89-L92)

#### Problem Description
When deleting a task from `SmartInboxView` or `CompletedTasksView`:
```swift
Swift.Task {
    await calendarManager.removeSync(for: task)
    modelContext.delete(task)
}
```
`removeSync(for: task)` is an `async` operation that queries `EKEventStore`. While `removeSync` is awaiting, `task` remains in the SwiftData `ModelContext` and `@Query` results. If the user rapidly taps another action on the task card or closes/re-opens the sheet before `removeSync` returns, a race condition occurs where operations run on a task in the middle of being deleted.

#### Recommended Remediation
Mark the task UI state immediately as pending deletion (e.g. local state or flag) or wrap the deletion flow in a synchronous context update with proper async boundary isolation.
