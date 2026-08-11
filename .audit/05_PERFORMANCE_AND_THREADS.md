# Performance, Memory & Threading Audit Report

## 1. Overview
This module evaluates memory allocations, main-thread blocking, query efficiency, relationship faulting, and SwiftUI re-render performance across the Task-Flow codebase.

---

## 2. Findings

<a id="perf-01"></a>
### PERF-01: Un-paginated In-Memory Array Filtering of All Database Tasks in `WidgetSnapshotPublisher`
* **Severity**: 🚨 **CRITICAL**
* **Category**: Performance / Memory Pressure
* **File**: [`Services/WidgetSnapshotPublisher.swift`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/Services/WidgetSnapshotPublisher.swift#L44-L49)

#### Problem Description
Whenever the app moves to background (`onChange(of: scenePhase)` in `TaskFlowApp.swift`), `WidgetSnapshotPublisher.publish(from:)` is called.
`todaysTasks(in:)` executes:
```swift
let descriptor = FetchDescriptor<Task>(predicate: #Predicate { !$0.isCompleted })
let pending = (try? context.fetch(descriptor)) ?? []

return pending
    .filter { task in
        guard let due = task.dueDate else { return false }
        return due >= startOfDay && due < endOfDay
    }
```

#### Real-World Impact
1. `FetchDescriptor<Task>(predicate: #Predicate { !$0.isCompleted })` fetches **every single uncompleted task** in the database into RAM without a fetch limit or SQL `WHERE` clause on `dueDate`.
2. If a power user has 5,000 pending tasks across months or years, `publish(from:)` instantiates 5,000 SwiftData `Task` instances in memory, allocates array storage, and evaluates Swift closures on the main thread right as the app is transitioning to background.
3. iOS background execution limits give apps very few milliseconds to complete background scene phase transitions. High memory/CPU overhead during backgrounding risks process termination by `runningboardd` (0x20000000 / watchdog kill).

#### Recommended Remediation
Execute the date filtering directly inside the SwiftData `#Predicate` so SQLite performs the index-backed query:
```swift
let descriptor = FetchDescriptor<Task>(
    predicate: #Predicate<Task> { task in
        !task.isCompleted && task.dueDate != nil && task.dueDate! >= startOfDay && task.dueDate! < endOfDay
    },
    sortBy: [SortDescriptor(\.priority, order: .reverse), SortDescriptor(\.dueDate)]
)
descriptor.fetchLimit = maxTasks
let todaysTasks = (try? context.fetch(descriptor)) ?? []
```

---

<a id="perf-02"></a>
### PERF-02: N+1 Relationship Faulting Queries in `WidgetSnapshotPublisher.projects`
* **Severity**: 🔴 **HIGH**
* **Category**: Performance / Database Faulting
* **File**: [`Services/WidgetSnapshotPublisher.swift`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/Services/WidgetSnapshotPublisher.swift#L73-L84)

#### Problem Description
In `WidgetSnapshotPublisher.projects(in:)`:
```swift
let descriptor = FetchDescriptor<Project>(sortBy: [SortDescriptor(\.createdAt)])
let all = (try? context.fetch(descriptor)) ?? []
return all
    .map { project in
        WidgetProject(
            id: project.id,
            name: project.name,
            colorHex: project.colorHex,
            pendingCount: project.tasks.filter { !$0.isCompleted }.count
        )
    }
```

#### Real-World Impact
`all` fetches all `Project` objects. Iterating through `all` and calling `project.tasks.filter { ... }` triggers CoreData fault resolution on `project.tasks` for **every single project** in a separate SQL query. This is a classic **N+1 query problem**. If the user has 20 projects, SwiftData executes 1 query for projects + 20 separate SQL queries for tasks, causing UI stutters on main actor.

#### Recommended Remediation
Use `FetchDescriptor` with aggregate queries or pre-fetch relationship data using `relationshipKeyPathsForPrefetching`.

---

<a id="perf-03"></a>
### PERF-03: Excessive SwiftUI Body Re-evaluations & Array Sorting in `SmartInboxView`
* **Severity**: 🔴 **HIGH**
* **Category**: Performance / SwiftUI Re-renders
* **File**: [`Views/Inbox/SmartInboxView.swift`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/Views/Inbox/SmartInboxView.swift#L44) & [`ViewModels/TaskGrouping.swift`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/ViewModels/TaskGrouping.swift#L93-L108)

#### Problem Description
In `SmartInboxView`:
```swift
private var groups: [DatedTaskGroup] { groupTasksBySection(tasks) }
```
`groups` is a computed property that executes `groupTasksBySection(tasks)` on **every single view body re-evaluation**.
`groupTasksBySection` creates dictionaries, groups arrays, and re-sorts all elements (`bucket.sorted { ... }`).

#### Real-World Impact
When the user types text into `NaturalLanguageInputBar`, `viewModel.inputText` updates on every single keystroke. This causes `SmartInboxView` body to re-evaluate, re-running `groupTasksBySection(tasks)` over all tasks in the inbox on every single keystroke. Typing feels sluggish on device.

#### Recommended Remediation
Memoize grouped tasks or update `groups` only when `tasks` array changes or date boundaries cross.

---

<a id="perf-04"></a>
### PERF-04: Synchronous EventKit XPC Queries on `@MainActor`
* **Severity**: 🟡 **MEDIUM**
* **Category**: Performance / Thread Blocking
* **File**: [`Services/EventKitService.swift`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/Services/EventKitService.swift#L71-L72) & [`Services/CalendarManager.swift`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/Services/CalendarManager.swift#L196)

#### Problem Description
`EventKitService.fetchEvents(from:to:)` calls `store.events(matching: predicate)` synchronously on `@MainActor`.
`EKEventStore.events(matching:)` performs synchronous XPC IPC calls to Apple's `calaccessd` calendar daemon.

#### Real-World Impact
If calendar access is slow or the system daemon is under load, calling `fetchEvents` directly on `@MainActor` blocks main thread UI rendering, causing dropped frames (hitch rate increase) during scroll or view appearance.

#### Recommended Remediation
Perform EventKit predicate fetching on a background actor and return immutable snapshot models to `@MainActor`.
