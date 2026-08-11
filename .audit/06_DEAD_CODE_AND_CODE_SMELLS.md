# Dead Code & Code Smells Audit Report

## 1. Overview
This module highlights dead code, orphan types, unused service APIs, configuration discrepancies, and code smells across the codebase.

---

## 2. Findings

<a id="code-01"></a>
### CODE-01: Entirely Dead ViewModel (`TimelineViewModel.swift`) and Unreferenced Models (`TimelineEntry`)
* **Severity**: 🔵 **LOW** (Codebase Hygiene / Maintainability)
* **File**: [`ViewModels/TimelineViewModel.swift`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/ViewModels/TimelineViewModel.swift#L1-L83)

#### Problem Description
The file `ViewModels/TimelineViewModel.swift` contains:
- `enum TimelineEntry: Identifiable`
- `class TimelineViewModel`

A comprehensive symbol search reveals **zero usages** of `TimelineViewModel` or `TimelineEntry` across the entire codebase. There is no Timeline view, tab, or component anywhere in Task-Flow.

#### Real-World Impact
Dead code increases compile times, confuses maintainers, and bloats the binary executable.

#### Recommended Remediation
Remove `ViewModels/TimelineViewModel.swift` or complete the planned Timeline view implementation.

---

<a id="code-02"></a>
### CODE-02: Dead Service Methods in `CalendarManager`
* **Severity**: 🔵 **LOW** (Codebase Hygiene)
* **File**: [`Services/CalendarManager.swift`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/Services/CalendarManager.swift#L159,L194,L231)

#### Problem Description
The following methods in `CalendarManager` have zero callers across the application:
1. `syncAllTasks(_ tasks: [Task])` (lines 159-171)
2. `importCalendarEvents(from:to:context:)` (lines 194-218)
3. `detectConflicts(for:)` (lines 231-242)

#### Real-World Impact
These methods represent abandoned or incomplete features (e.g. calendar import and conflict resolution UI). They increase test surface area without delivering value.

#### Recommended Remediation
Either remove the dead methods or connect them to actionable user interfaces (e.g. a "Sync All" button or "Import Events" setting).

---

<a id="code-03"></a>
### CODE-03: Fictional Deployment Target (`iOS 27.0`) in `project.yml`
* **Severity**: 🔵 **LOW** (Configuration / Build System)
* **File**: [`project.yml`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/project.yml#L5,L13,L23,L65)

#### Problem Description
`project.yml` defines the deployment target as `iOS 27.0`:
```yaml
deploymentTarget:
  iOS: "27.0"
```
Comments in `CLAUDE.md` state the deployment target is iOS 18.0 / 19.0.

#### Real-World Impact
Setting a target of iOS 27.0 causes Xcode tools to suppress availability warnings for APIs that may not exist on real-world iOS 18.x or 19.x devices, risking runtime crashes on actual hardware.

#### Recommended Remediation
Set `deploymentTarget` in `project.yml` to `18.0`.

---

<a id="code-04"></a>
### CODE-04: Redundant `@State` Wrapper on Immutable `DeepLinkCoordinator`
* **Severity**: 🔵 **LOW** (SwiftUI Hygiene)
* **File**: [`App/TaskFlowApp.swift`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/App/TaskFlowApp.swift#L39)

#### Problem Description
In `TaskFlowApp.swift`:
```swift
@State private var deepLinkCoordinator = DeepLinkCoordinator()
```
`DeepLinkCoordinator` is an `@Observable` class. Under Swift 6 / iOS 17+, `@Observable` reference types injected into environment do not require `@State` wrappers on top of the reference when instantiated directly.

#### Recommended Remediation
Use standard let declaration or single app-model container:
```swift
private let deepLinkCoordinator = DeepLinkCoordinator()
```
