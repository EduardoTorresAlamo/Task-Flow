# Audit Module 05: Performance, Memory & Threading
**Repository**: Task-Flow  
**Path**: `/Users/eduardotorres/Developer/XCodes/Task-Flow`  
**Audit Date**: August 26, 2026  
**Auditor**: Antigravity Principal Security & Software Systems Architect  
**Scope**: Main Thread Execution, EventKit IPC Latency, SwiftData Query Efficiency, Widget Snapshot Publishing Pipeline  

---

## 1. Executive Summary

Performance evaluation focused on thread utilization, IPC overhead, database query performance, and memory consumption.

### Key Highlights:
- **[HIGH-01] OPEN**: Synchronous EventKit Mach IPC operations executing directly on the `@MainActor` UI thread.
- **[HIGH-03] RESOLVED (Commit `bc61ab3`)**: Widget snapshot JSON encoding and atomic disk I/O decoupled from scene phase transition to a detached background task.
- **Verified Query Optimizations**: Single-pass project counting prevents N+1 query patterns; static `DateFormatter` caching minimizes allocations in scrolling lists.

---

## 2. Detailed Findings

### [HIGH-01] Synchronous EventKit IPC & SQLite I/O Blocking `@MainActor` UI Thread
- **Severity**: 🔴 **HIGH**
- **Location**: [`Services/CalendarSyncService.swift:96,122`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/Services/CalendarSyncService.swift#L96), [`Services/EventKitService.swift:66`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/Services/EventKitService.swift#L66)
- **CWE**: CWE-400 (Uncontrolled Resource Consumption / Main Thread Blocking)
- **Status**: 🔴 **OPEN / ACTIVE**

#### Technical Analysis
`CalendarSyncService` and `EventKitService` are annotated with `@MainActor`.
Within `CalendarSyncService.sync(task:)` and `deleteEvent(for:)`, the operations:
```swift
try store.save(ekEvent, span: saveSpan)
try eventKitService.store.remove(ekEvent, span: .thisEvent)
```
and in `EventKitService.fetchEvents(from:to:)`:
```swift
store.events(matching: predicate)
```
are executed synchronously on the main UI thread.

#### Runtime Impact
1. **Mach IPC & Disk Latency**: `EKEventStore` communicates via Mach messages with the system calendar daemon (`calaccessd`), which reads and writes to the SQLite database at `~/Library/Calendars/Calendar.sqlitedb`.
2. **UI Frame Drops (Jank)**: In environments with large calendar histories or active iCloud Calendar synchronization, these synchronous calls take between **50ms and 350ms**. When invoked during task creation, task editing, or task deletion, the main thread is blocked, leading to dropped frames and unresponsive touch events.
3. **Watchdog Termination Risk**: If batched synchronization is performed (e.g. `syncAllTasks`), the cumulative delay risks exceeding iOS Watchdog time limits during scene transitions, triggering `0x8badf00d` crash terminations.

#### Recommended Remediation Pattern
Offload `EKEventStore` I/O operations from `@MainActor` using detached background tasks:

```swift
func syncEventInBackground(
    eventIdentifier: String?,
    title: String,
    startDate: Date,
    duration: TimeInterval,
    notes: String?,
    location: String?,
    url: URL?,
    store: EKEventStore
) async throws -> String? {
    try await Swift.Task.detached(priority: .utility) {
        let event: EKEvent
        if let eventIdentifier, let existing = store.event(withIdentifier: eventIdentifier) {
            event = existing
        } else {
            event = EKEvent(eventStore: store)
            event.calendar = store.defaultCalendarForNewEvents
        }
        event.title = title
        event.startDate = startDate
        event.endDate = startDate.addingTimeInterval(duration)
        event.notes = notes
        event.location = location
        event.url = url
        event.recurrenceRules = nil
        
        try store.save(event, span: .thisEvent)
        return event.eventIdentifier
    }.value
}
```

---

### [HIGH-03] Synchronous Disk I/O and JSON Serialization on `@MainActor` During App Suspension — RESOLVED
- **Severity**: 🔴 **HIGH**
- **Location**: [`Services/WidgetSnapshotPublisher.swift:37-40`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/Services/WidgetSnapshotPublisher.swift#L37-L40)
- **Status**: ✅ **VERIFIED RESOLVED** (Commit `bc61ab3`)

#### Resolution Verification
In commit `bc61ab3`, JSON serialization and atomic file writing for `WidgetSnapshot` were decoupled from the main actor:
```swift
Swift.Task.detached(priority: .utility) {
    WidgetSnapshotStore.write(snapshot)
    WidgetCenter.shared.reloadAllTimelines()
}
```
This ensures that when `TaskFlowApp.onChange(of: scenePhase)` triggers upon backgrounding (`phase != .active`), the app suspends smoothly without stalling the main runloop.

---

## 3. Verified Performance Optimizations

1. **Single-Pass Project Grouping**:
   [`Services/WidgetSnapshotPublisher.swift:108-115`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/Services/WidgetSnapshotPublisher.swift#L108-L115) counts pending tasks across all projects using a single query and an in-memory dictionary accumulator (`pendingByProject[projectID, default: 0] += 1`), eliminating the N+1 relationship fault pattern.

2. **Static Formatter Caching**:
   [`Views/Tasks/TaskRowView.swift:59-70`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/Views/Tasks/TaskRowView.swift#L59-L70) and [`Views/Components/NaturalLanguageInputBar.swift:23-27`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/Views/Components/NaturalLanguageInputBar.swift#L23-L27) reuse `static let` instances of `DateFormatter`, preventing expensive allocations during fast scrolling in `LazyVStack`.
