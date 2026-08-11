# Architecture & Design Patterns Audit Report

## 1. Overview
This module analyzes architectural choices, dependency injection, SwiftUI state lifecycles (`@State`, `@Observable`), separation of concerns, and MVVM layer boundaries across the Task-Flow application.

---

## 2. Findings

<a id="arch-01"></a>
### ARCH-01: Impermissible `@State` Property Initialization in `TaskFlowApp.init()`
* **Severity**: 🔴 **HIGH**
* **Category**: SwiftUI Architecture / State Lifecycle Anti-Pattern
* **File**: [`App/TaskFlowApp.swift`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/App/TaskFlowApp.swift#L22-L36,L61-L64)

#### Problem Description
In `TaskFlowApp.swift`:
```swift
@State private var eventKitService: EventKitService
@State private var calendarSyncService: CalendarSyncService
@State private var calendarManager: CalendarManager
@State private var voiceTaskService: VoiceTaskService

init() {
    ...
    let eks = EventKitService()
    eks.checkExistingAuthorization()
    let css = CalendarSyncService(eventKitService: eks)
    let cm  = CalendarManager(eventKitService: eks, syncService: css)
    _eventKitService     = State(initialValue: eks)
    _calendarSyncService = State(initialValue: css)
    _calendarManager     = State(initialValue: cm)
    _voiceTaskService    = State(initialValue: VoiceTaskService())
}
```
Initializing `@State` storage directly via `_property = State(initialValue: ...)` inside an `App` or `View` `init()` is a known SwiftUI anti-pattern.

In SwiftUI, the system creates and re-instantiates `App` and `View` structs whenever scene properties, traits, or environmental changes occur. Re-running `init()` instantiates new service instances (`EventKitService()`, `CalendarManager()`, etc.). Because `@State` storage is managed externally by SwiftUI's graph, the new instances created in `init()` are discarded, BUT transient initializations inside `init()` (such as `eks.checkExistingAuthorization()` and `CalendarManager.init()`'s `refreshCalendars()`) re-run on discarded instances!

#### Real-World Impact
1. Unnecessary allocations and side-effects on every App struct re-evaluation.
2. If SwiftUI re-evaluates `App` during scene phase transitions, state mismatch can occur between the discarded local initialization and the persisted `@State` storage.

#### Recommended Remediation
Use singletons, a root dependency container, or lazy holder pattern for top-level services:
```swift
@main
struct TaskFlowApp: App {
    let container: ModelContainer
    
    // Hold services in a dedicated observable app model or state object
    @State private var services = AppServices()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(services.eventKitService)
                .environment(services.calendarManager)
                ...
        }
        .modelContainer(container)
    }
}
```

---

<a id="arch-02"></a>
### ARCH-02: Omitted Environment Injection for `CalendarSyncService`
* **Severity**: 🔴 **HIGH**
* **Category**: Dependency Injection / Environment Failure
* **File**: [`App/TaskFlowApp.swift`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/App/TaskFlowApp.swift#L72-L75)

#### Problem Description
`TaskFlowApp` initializes `calendarSyncService` as `@State` (line 26), but injects only a subset of services into the view hierarchy:
```swift
RootTabView()
    .environment(eventKitService)
    .environment(calendarManager)
    .environment(voiceTaskService)
    .environment(deepLinkCoordinator)
```
`calendarSyncService` is **omitted** from `.environment(...)`!

#### Real-World Impact
If any child view or component attempts to read `@Environment(CalendarSyncService.self)` (or if code is refactored to consume it directly), Swift 6 observation will immediately crash the application at runtime with a missing environment object precondition failure.

#### Recommended Remediation
Either inject `calendarSyncService` into the environment alongside other services or explicitly document that `CalendarSyncService` is internal to `CalendarManager`.

---

<a id="arch-03"></a>
### ARCH-03: Option-wrapped Lazy ViewModel Instantiation Anti-Pattern in `SmartInboxView`
* **Severity**: 🟡 **MEDIUM**
* **Category**: SwiftUI Architecture / View Lifecycle
* **File**: [`Views/Inbox/SmartInboxView.swift`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/Views/Inbox/SmartInboxView.swift#L36,L80-L82)

#### Problem Description
In `SmartInboxView.swift`:
```swift
@State private var viewModel: InboxViewModel?

var body: some View {
    ...
    if let vm = viewModel {
        NaturalLanguageInputBar(viewModel: vm)
    }
}
.onAppear {
    if viewModel == nil {
        viewModel = InboxViewModel(modelContext: modelContext, calendarManager: calendarManager)
    }
}
```

#### Real-World Impact
1. **Initial Frame Pop-In**: On the very first frame `SmartInboxView` is rendered by SwiftUI, `viewModel` is `nil`. `NaturalLanguageInputBar` is not present in the body.
2. When `.onAppear` fires, `viewModel` is set, triggering an immediate layout shift and visual pop-in as the input bar inserts itself at the top of the stack.
3. If `.onAppear` is delayed due to tab switching or animation transitions, the user sees a header with no input bar.

#### Recommended Remediation
Initialize `InboxViewModel` deterministically using `@State` default initializers or inject dependencies via view initializers so the view model is available on frame 0.

---

<a id="arch-04"></a>
### ARCH-04: Direct Store Mutation from Row Views (`TaskRowView` `@Bindable`) Bypass ViewModel Layer
* **Severity**: 🟡 **MEDIUM**
* **Category**: MVVM / Separation of Concerns
* **File**: [`Views/Tasks/TaskRowView.swift`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/Views/Tasks/TaskRowView.swift#L20,L222-L226)

#### Problem Description
`TaskRowView` receives `@Bindable var task: Task`.
When the completion toggle is tapped and `onToggleComplete` is `nil`:
```swift
task.isCompleted.toggle()
task.completedAt = task.isCompleted ? Date() : nil
task.updatedAt = Date()
```
The view mutates the SwiftData model directly inside a subview helper method (`complete()`), bypassing view models or coordinators.

#### Real-World Impact
Bypassing the ViewModel layer for task completion prevents side-effects (such as spawning the next occurrence of a recurring task, triggering widget snapshot updates, or syncing EventKit calendar events) from running when a task is toggled in secondary views (e.g. `CompletedTasksView` or `ProjectDetailView`).
