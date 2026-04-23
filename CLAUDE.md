# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Task-Flow is a SwiftUI task manager for iOS 19, targeting Swift 6 strict concurrency. It uses SwiftData for local persistence and EventKit for Calendar/Reminders sync.

## Build & Run

```bash
# Build
xcodebuild -scheme Task-Flow -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build

# Run tests
xcodebuild test -scheme Task-Flow -destination 'platform=iOS Simulator,name=iPhone 16 Pro'

# Single test class
xcodebuild test -scheme Task-Flow -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:Task-FlowTests/NaturalLanguageParserTests
```

## Architecture

MVVM with Swift 6 `@Observable` ViewModels (no `ObservableObject` / `@Published`).

- **Models/** — SwiftData `@Model` classes: `Task`, `Project`, `Tag`. Enums in `Priority.swift`.
- **ViewModels/** — `@Observable` classes, one per major screen. Receive `ModelContext` via DI, not via `@Environment` directly.
- **Views/** — SwiftUI views only, no business logic. Shared subviews live in `Components/`.
- **Services/** — Side-effect owners: `EventKitService` (Calendar/Reminders), `NaturalLanguageParser` (date extraction), `CalendarSyncService` (bidirectional EKEvent ↔ Task sync).
- **App/** — `TaskFlowApp.swift` owns the `ModelContainer` and injects `EventKitService` into the environment.

## SwiftData Rules

- `@Model` classes must be `final`.
- Use `@Relationship(deleteRule: .cascade)` for owned children (subtasks, tasks owned by a project deletion should use `.nullify`).
- Never access `ModelContext` off the main actor — use `ModelActor` for background work.
- Schema registration lives in `TaskFlowApp.swift`: `Schema([Task.self, Project.self, Tag.self])`.

## EventKit Rules

- Always check `EKEventStore.authorizationStatus(for:)` before any store access.
- Use `requestFullAccessToEvents` / `requestFullAccessToReminders` (iOS 17+ API — not the deprecated `requestAccess(to:completion:)`).
- `EventKitService` is the sole owner of `EKEventStore`. No other file instantiates one.
- Required `Info.plist` keys: `NSCalendarsFullAccessUsageDescription`, `NSRemindersFullAccessUsageDescription`.

## Conventions

- Swift 6 strict concurrency: all `@Observable` ViewModels are `@MainActor`.
- Zero third-party dependencies.
- Colors stored as `String` hex (e.g. `"#6E56CF"`), converted to SwiftUI `Color` via `Color+Hex.swift`.
- SF Symbol names stored as `String` in `Project.symbolName`.
- Accent color: `#6E56CF` (deep indigo). Dark-mode-first design; background is pure black.
