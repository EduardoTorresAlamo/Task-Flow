# Security & Privacy Audit Report

## 1. Overview
This module evaluates data privacy, IPC/URL scheme security, entitlement scoping, permission management, and sensitive storage on device for Task-Flow.

---

## 2. Findings

<a id="sec-01"></a>
### SEC-01: Unsanitized Custom URL Scheme (`taskflow://`) Endpoint Handling
* **Severity**: 🟡 **MEDIUM**
* **Category**: Security / Inter-Process Communication (IPC)
* **File**: [`Shared/TaskFlowSharedStore.swift`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/Shared/TaskFlowSharedStore.swift#L98-L106)

#### Problem Description
`TaskDeepLink.taskID(from:)` parses incoming URLs sent via `taskflow://` scheme:
```swift
static func taskID(from url: URL) -> UUID? {
    guard url.scheme == scheme, url.host == taskHost else { return nil }
    let raw = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    return UUID(uuidString: raw)
}
```
While `UUID(uuidString:)` enforces basic format validation, the custom scheme handler in `TaskFlowApp.swift` (`.onOpenURL`) blindly forwards any URL matching `taskflow` without validating URL components or query parameters.

#### Real-World Impact
Any third-party app installed on the iOS device can trigger `taskflow://` links (e.g. via `UIApplication.shared.open`). If future URL schemes expand to execute mutations (e.g. `taskflow://delete/<id>`), lack of explicit action validation or user confirmation could allow unauthorized local actions.

#### Recommended Remediation
Enforce strict scheme routing, path component whitelist, and ensure deep links only perform read/navigation actions:
```swift
static func taskID(from url: URL) -> UUID? {
    guard url.scheme == scheme,
          url.host == taskHost,
          let pathComponents = URLComponents(url: url, resolvingAgainstBaseURL: false),
          pathComponents.queryItems == nil // Reject unexpected query parameters
    else { return nil }
    
    let path = url.pathComponents.filter { $0 != "/" }
    guard path.count == 1, let uuid = UUID(uuidString: path[0]) else { return nil }
    return uuid
}
```

---

<a id="sec-02"></a>
### SEC-02: Unencrypted Plaintext Storage of Task Data in App Group Shared Container
* **Severity**: 🟡 **MEDIUM**
* **Category**: On-Device Data Privacy / Sensitive Data Storage
* **File**: [`Shared/TaskFlowWidgetSnapshot.swift`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/Shared/TaskFlowWidgetSnapshot.swift#L64-L70)

#### Problem Description
To update the Home Screen widget, `WidgetSnapshotPublisher` dumps active tasks into `widget-snapshot.json` in the shared App Group container:
```swift
static func write(_ snapshot: WidgetSnapshot) {
    guard let url else { return }
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    guard let data = try? encoder.encode(snapshot) else { return }
    try? data.write(to: url, options: .atomic)
}
```
The file is written as unencrypted JSON without applying Data Protection keys (`.completeFileProtection`).

#### Real-World Impact
Task titles, deadlines, notes, and project associations often contain highly sensitive personal or corporate data ("Doctor appointment for X", "Acquisition review", "Password reset"). Any process with access to the container or unencrypted device backups can read the raw JSON file.

#### Recommended Remediation
Write the JSON file using iOS Data Protection complete file protection:
```swift
try? data.write(to: url, options: [.atomic, .completeFileProtection])
```

---

<a id="sec-03"></a>
### SEC-03: Over-privileged Permission Requesting (`remindersAuthorized` Gate)
* **Severity**: 🔴 **HIGH**
* **Category**: Permission Flow / Principle of Least Privilege
* **File**: [`Services/CalendarManager.swift`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/Services/CalendarManager.swift#L81-L83) & [`Services/EventKitService.swift`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/Services/EventKitService.swift#L39)

#### Problem Description
`CalendarManager.isAuthorized` is implemented as:
```swift
var isAuthorized: Bool {
    eventKitService.calendarAuthorized && eventKitService.remindersAuthorized
}
```
`EventKitService` requests full access to **both** Calendar AND Reminders (`requestFullAccessToReminders()`). However, Task-Flow has zero Reminders features: it only creates and manages `EKEvent` calendar objects.

#### Real-World Impact
If a privacy-conscious user grants Calendar permissions but denies Reminders access, `isAuthorized` evaluates to `false`. The entire calendar sync feature is completely disabled and reports an authorization error, despite the user having granted full Calendar permissions.

#### Recommended Remediation
Remove `remindersAuthorized` from `isAuthorized` and eliminate the unnecessary `NSRemindersFullAccessUsageDescription` entitlement and `requestFullAccessToReminders()` call:
```swift
// In CalendarManager.swift:
var isAuthorized: Bool {
    eventKitService.calendarAuthorized
}
```

---

<a id="sec-04"></a>
### SEC-04: Debug Information Leakage in `TaskIntelligenceService.detail`
* **Severity**: 🔵 **LOW**
* **Category**: Information Disclosure / Diagnostics
* **File**: [`Services/TaskIntelligenceService.swift`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/Services/TaskIntelligenceService.swift#L403-L408)

#### Problem Description
```swift
private static func detail(_ message: String, _ debugDescription: String) -> String {
    #if DEBUG
    return "\(message) [\(debugDescription)]"
    #else
    return message
    #endif
}
```
While `#if DEBUG` correctly gates `debugDescription` in release builds, during internal debug testing `debugDescription` from `LanguageModelError` contains verbatim prompt fragments and unparsed user text.

#### Recommended Remediation
Ensure `Logger` calls use `.private` privacy specifiers for user text in all error branches:
```swift
logger.error("LLM failure: \(error.localizedDescription, privacy: .private)")
```
