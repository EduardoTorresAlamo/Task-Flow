# Database Schema & Model Graph Audit Report

## 1. Overview
This module evaluates SwiftData schema definitions, entity relationships (`@Relationship`), deletion rules (`.cascade`, `.nullify`), indexes, constraints, and data graph integrity across `Task`, `Project`, and `Tag`.

---

## 2. Findings

<a id="db-01"></a>
### DB-01: Missing `inverse:` on Self-Referencing Subtask Relationship (`Task.subtasks` vs `Task.parentTask`)
* **Severity**: 🚨 **CRITICAL**
* **Category**: Database Schema / Relationship Graph Corruption
* **File**: [`Models/Task.swift`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/Models/Task.swift#L75-L79)

#### Problem Description
In `Models/Task.swift`:
```swift
@Relationship(deleteRule: .cascade) var subtasks: [Task] = []
var parentTask: Task?
```
Neither `subtasks` nor `parentTask` defines an explicit `inverse:` parameter connecting the two properties!

In SwiftData / CoreData backing stores, when a model class contains two relationship properties targeting the same class without an explicit inverse macro declaration, SwiftData synthesizes **two independent relationships**:
1. `Task_subtasks` (a 1-to-many relationship)
2. `Task_parentTask` (a separate 1-to-1 relationship)

#### Real-World Impact
1. **Graph Desynchronization**: Setting `child.parentTask = parent` does NOT automatically add `child` to `parent.subtasks`. Modifying one side of the relationship leaves the other side stale.
2. **Broken Cascade Deletes**: When a parent `Task` is deleted, `deleteRule: .cascade` operates on the un-linked `subtasks` array. If a child was assigned via `parentTask`, CoreData leaves orphan child rows in SQLite whose `parentTask_id` points to a deleted object ID.
3. **Runtime Traps**: Fetching an object graph with dangling relationship IDs in SwiftData triggers `EXC_BAD_INSTRUCTION` or `CoreData: annotation: CoreData could not fulfill a fault` crashes.

#### Recommended Remediation
Explicitly link the parent-child self-referential relationship using `inverse:`:
```swift
@Relationship(deleteRule: .cascade, inverse: \Task.parentTask) 
var subtasks: [Task] = []

var parentTask: Task?
```

---

<a id="db-02"></a>
### DB-02: Asymmetrical Relationship Annotation on `Task.tags` vs `Tag.tasks`
* **Severity**: 🔴 **HIGH**
* **Category**: Database Schema / Many-to-Many Join Table Duplication
* **File**: [`Models/Task.swift`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/Models/Task.swift#L82) & [`Models/Tag.swift`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/Models/Tag.swift#L27)

#### Problem Description
In `Tag.swift`:
```swift
@Relationship(inverse: \Task.tags) var tasks: [Task] = []
```
In `Task.swift`:
```swift
@Relationship var tags: [Tag] = []
```
`Tag.swift` declares `inverse: \Task.tags`, but `Task.swift` leaves `@Relationship var tags: [Tag] = []` un-annotated.

#### Real-World Impact
In SwiftData, asymmetrical annotations on Many-to-Many relationships can cause the schema generator to create redundant join tables (`Z_TASK_TAGS` vs `Z_TAG_TASKS`) across schema iterations. When `TagStore.apply` appends tags (`task.tags.append(tag)`), duplicate entries can be created in SQLite backing store.

#### Recommended Remediation
Explicitly declare the inverse on both sides or align relationship annotations:
```swift
// In Task.swift:
@Relationship(inverse: \Tag.tasks) var tags: [Tag] = []
```

---

<a id="db-03"></a>
### DB-03: Unindexed Query Target on `Task.eventKitIdentifier`
* **Severity**: 🔴 **HIGH**
* **Category**: Database Schema / Performance / Missing Index
* **File**: [`Models/Task.swift`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/Models/Task.swift#L46) & [`Services/CalendarManager.swift`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/Services/CalendarManager.swift#L203)

#### Problem Description
In `CalendarManager.importCalendarEvents`:
```swift
let descriptor = FetchDescriptor<Task>(predicate: #Predicate { $0.eventKitIdentifier == identifier })
let existing = (try? context.fetch(descriptor)) ?? []
```
In `Models/Task.swift`:
```swift
var eventKitIdentifier: String?
```
`eventKitIdentifier` is repeatedly queried during EventKit import and calendar sync passes, but it has no index or uniqueness constraint defined in SwiftData.

#### Real-World Impact
Every calendar import pass executes an un-indexed SQL table scan (`SELECT * FROM ZTASK WHERE ZEVENTKITIDENTIFIER = ?`) across every single task in the database. As the task database grows (1,000+ tasks), calendar sync performance degrades exponentially, stalling the main thread.

#### Recommended Remediation
Add `@Attribute(.unique)` or `@Attribute(.indexed)` to `eventKitIdentifier`:
```swift
@Attribute(.unique) var eventKitIdentifier: String?
```

---

<a id="db-04"></a>
### DB-04: Duplicate Project Names Allowed with No Schema Unique Constraint
* **Severity**: 🟡 **MEDIUM**
* **Category**: Database Schema / Data Quality
* **File**: [`Models/Project.swift`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/Models/Project.swift#L17) & [`Services/TaskIntelligenceService.swift`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/Services/TaskIntelligenceService.swift#L277-L280)

#### Problem Description
`Project.swift` defines `var name: String` with no uniqueness constraint. The user can create multiple projects with the exact same name (e.g. two projects named "Work").

When `TaskIntelligenceService` categorizes a task:
```swift
let projectName: String? = rawProject.caseInsensitiveCompare(noProjectSentinel) == .orderedSame
    ? nil
    : allowedProjects.first { $0.caseInsensitiveCompare(rawProject) == .orderedSame }
```
`InboxViewModel` resolves the returned string via:
```swift
if task.project == nil, let name = result.projectName {
    task.project = projects.first { $0.name == name }
}
```

#### Real-World Impact
If two projects share the name "Work", `projects.first` non-deterministically files tasks into whichever project happens to be fetched first by SwiftData. The user has no control over which "Work" project receives auto-filed tasks.

#### Recommended Remediation
Add `@Attribute(.unique)` to `Project.name` or validate project name uniqueness in `ProjectEditView` before saving.
```swift
@Attribute(.unique) var name: String
```
