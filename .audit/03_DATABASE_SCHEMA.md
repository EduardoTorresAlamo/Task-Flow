# Audit Module 03: Database Schema & SwiftData Integrity
**Repository**: Task-Flow  
**Path**: `/Users/eduardotorres/Developer/XCodes/Task-Flow`  
**Audit Date**: August 26, 2026  
**Auditor**: Antigravity Principal Security & Software Systems Architect  
**Scope**: SwiftData Entities, Relationship Inverses, Cascade Rules, Indexing, Persistence Configurations  

---

## 1. Executive Summary

Task-Flow uses **SwiftData** with schema registration centralized in `TaskFlowContainer.schema = Schema([Task.self, Project.self, Tag.self])`.

Persisted data is stored in the shared App Group sandbox container (`group.com.eduardotorres.Task-Flow`), allowing the main app to write to `TaskFlow.store` while the widget reads snapshots via `TaskFlowWidgetSnapshot.swift`.

### Structural Findings:
- **[MED-01] OPEN**: Cascade deletion of subtasks in SwiftData bypasses EventKit event desynchronization.
- **[LOW-01] OPEN**: Omission of composite B-Tree index on `isCompleted` and `dueDate`.

---

## 2. Entity-Relationship Diagram & Schema Architecture

```mermaid
erDiagram
    Task {
        UUID id PK "Stable UUID"
        String title "Task Title"
        String notes "Freeform Context"
        Date dueDate "Optional Deadline"
        Priority priority "Enum: 0=None, 1=Low, 2=Med, 3=High"
        Bool isCompleted "Completion Flag"
        Date completedAt "Completion Timestamp"
        Date createdAt "Creation Timestamp"
        Date updatedAt "Update Timestamp"
        String eventKitIdentifier INDEX "EKEvent.eventIdentifier"
        RecurrenceRule recurrenceRule "Codable Struct"
        Date recurrenceEnd "Recurrence Cutoff"
        Int recurrenceCount "Series Index (1-based)"
        UUID spawnedSuccessorID "Spawned Successor Link"
    }
    Project {
        UUID id PK "Stable UUID"
        String name "Project Display Name"
        String colorHex "CSS Hex Color (#6E56CF)"
        String symbolName "SF Symbol Name"
        Date createdAt "Creation Timestamp"
    }
    Tag {
        UUID id PK "Stable UUID"
        String name "Tag Label (Lowercase)"
        String colorHex "Hex Color"
    }

    Task }|--o| Project : "belongs to (deleteRule: .nullify, inverse: Task.project)"
    Task ||--o{ Task : "subtasks (deleteRule: .cascade, inverse: Task.parentTask)"
    Task }|--|{ Tag : "tags (many-to-many, inverse: Task.tags)"
```

---

## 3. Detailed Findings

### [MED-01] Cascade Deletion of Subtasks Omits EventKit Event Desynchronization
- **Severity**: 🟡 **MEDIUM**
- **Location**: [`Models/Task.swift:103`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/Models/Task.swift#L103), [`Views/Tasks/TaskEditView.swift:76-80`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/Views/Tasks/TaskEditView.swift#L76-L80)
- **CWE**: CWE-404 (Improper Resource Shutdown or Release)
- **Status**: ⚠️ **OPEN**

#### Technical Analysis
In `Models/Task.swift`:
```swift
@Relationship(deleteRule: .cascade, inverse: \Task.parentTask) var subtasks: [Task] = []
```
When a parent task is deleted via `modelContext.delete(parentTask)`, SwiftData automatically cascades the delete operation across all related rows in the SQLite `subtasks` table.

However, the deletion flow in `TaskEditView.swift` and `SmartInboxView.swift` only triggers:
```swift
Swift.Task {
    await calendarManager.removeSync(for: task)
    modelContext.delete(task)
}
```
If any nested `subtasks` had assigned due dates and were synchronized to Apple Calendar (`subtask.eventKitIdentifier != nil`), their corresponding `EKEvent` records in Apple Calendar are never deleted. Those calendar events remain permanently orphaned in the user's system calendar.

#### Concrete Remediation
Implement recursive calendar cleanup before committing the SwiftData deletion:

```swift
@MainActor
func deleteRecursively(_ task: Task, calendarManager: CalendarManager, context: ModelContext) async {
    for subtask in task.subtasks {
        await deleteRecursively(subtask, calendarManager: calendarManager, context: context)
    }
    await calendarManager.removeSync(for: task)
    context.delete(task)
}
```

---

### [LOW-01] Missing Composite Index on High-Frequency Filter Predicates
- **Severity**: 🔵 **LOW**
- **Location**: [`Models/Task.swift:15`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/Models/Task.swift#L15)
- **CWE**: CWE-400 (Unindexed Database Queries / Table Scan Overhead)
- **Status**: ⚠️ **OPEN**

#### Technical Analysis
Currently, `Task.swift` declares only a single index:
```swift
#Index<Task>([\.eventKitIdentifier])
```
However, the most frequent queries throughout the app evaluate:
1. `SmartInboxView.swift:35`: `#Predicate<Task> { !$0.isCompleted }` (sorted by `createdAt` / `dueDate`)
2. `WidgetSnapshotPublisher.swift:67-71`: `#Predicate<Task> { !$0.isCompleted && $0.dueDate != nil && ... }`
3. `CompletedTasksView.swift:22`: `#Predicate<Task> { $0.isCompleted }`

Without an index covering `isCompleted` and `dueDate`, SQLite performs full table scans for every inbox re-render, widget publication, and task completion toggle.

#### Concrete Remediation Diff
```diff
--- a/Models/Task.swift
+++ b/Models/Task.swift
@@ -14,2 +14,3 @@
     #Index<Task>([\.eventKitIdentifier])
+    #Index<Task>([\.isCompleted, \.dueDate])
```

---

## 4. Container Reliability & Fallback Integrity

In `Shared/TaskFlowSharedStore.swift:51-114`:
- If the App Group entitlement fails (e.g. invalid provisioning profile or container resolution failure), `TaskFlowContainer.makeShared()` throws `StoreError.appGroupUnavailable`.
- `TaskFlowContainer.makeForApp()` logs a critical fault via `os.Logger` and gracefully falls back to an in-memory `ModelConfiguration(isStoredInMemoryOnly: true)`.
- If even in-memory configuration fails, it degrades to an empty-schema in-memory container rather than crashing at the launch screen with an unchecked `try!`.
