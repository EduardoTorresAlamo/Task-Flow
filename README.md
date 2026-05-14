# Task-Flow

iOS task manager built with SwiftUI, SwiftData, and EventKit. Targets iOS 18, written in Swift 6 with strict concurrency.

## Features

- **Natural language input** — type "Call dentist tomorrow urgent" and the parser extracts the date, priority, and title using `NSDataDetector` and keyword matching. No ML model required.
- **Voice input** — dictate tasks via `SFSpeechRecognizer`. Transcript feeds directly into the same NL parser.
- **Smart Inbox** — flat list of pending tasks with per-row priority badges and inline editing.
- **Completed tasks view** — separate screen showing tasks with `isCompleted == true`, with completion timestamps.
- **Projects** — group tasks under a named project with a color (`String` hex) and SF Symbol icon.
- **Tags** — many-to-many tagging across tasks.
- **Subtasks** — tasks can have child tasks (cascade-deleted when the parent is deleted; see SwiftData rules below).
- **Calendar sync** — bidirectional sync with EventKit. Tasks with a due date can become `EKEvent`s; the `CalendarSyncService` handles reconciliation. The `EventKitService` is the sole owner of `EKEventStore`.
- **Reminders sync** — requests full access to both calendars and reminders (iOS 17+ API).

## Tech

| Layer | Choice |
|-------|--------|
| UI | SwiftUI |
| Persistence | SwiftData (`@Model`, `ModelContainer`, `ModelActor` for background work) |
| Calendar / Reminders | EventKit |
| Voice | `Speech` framework (`SFSpeechRecognizer`, `AVAudioEngine`) |
| Concurrency | Swift 6 strict — all `@Observable` ViewModels are `@MainActor` |
| Dependencies | None |

## Architecture

MVVM. `@Observable` replaces `ObservableObject`/`@Published` throughout.

```
App/            TaskFlowApp.swift — owns ModelContainer, injects EventKitService into environment
Models/         Task, Project, Tag (SwiftData @Model), Priority enum
ViewModels/     InboxViewModel, TimelineViewModel — receive ModelContext via DI
Views/
  Inbox/        SmartInboxView
  Tasks/        TaskRowView, TaskEditView
  Completed/    CompletedTasksView
  Components/   RootTabView, NaturalLanguageInputBar, VoiceInputButton, PriorityBadge, GlassCard
Services/
  EventKitService         — EKEventStore owner, permission requests, event fetch
  CalendarSyncService     — bidirectional EKEvent <-> Task reconciliation
  CalendarManager         — calendar selection helpers
  NaturalLanguageParser   — date/priority/notes extraction from free text
  VoiceTaskService        — SFSpeechRecognizer wrapper (@Observable @MainActor)
  IntelligenceEnricher    — post-parse enrichment
Extensions/     Color+Hex and other utilities
```

## Requirements

- Xcode 16+
- iOS 18.0+ deployment target
- Swift 6

## Build

```bash
# Build for simulator
xcodebuild -scheme Task-Flow -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build

# Run tests
xcodebuild test -scheme Task-Flow -destination 'platform=iOS Simulator,name=iPhone 16 Pro'

# Run a single test class
xcodebuild test -scheme Task-Flow \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:Task-FlowTests/NaturalLanguageParserTests
```

Or open `Task-Flow.xcodeproj` in Xcode and press Cmd+R.

## Info.plist keys required

```
NSCalendarsFullAccessUsageDescription
NSRemindersFullAccessUsageDescription
NSSpeechRecognitionUsageDescription
NSMicrophoneUsageDescription
```

## Notes

- Colors are stored as `String` hex (e.g. `"#6E56CF"`) and converted to `SwiftUI.Color` via `Color+Hex.swift`.
- SF Symbol names are stored as `String` in `Project.symbolName`.
- `ModelContext` must never be accessed off the main actor — use `ModelActor` for background work.
- Accent: `#6E56CF`. Dark-mode-first; background is pure black.
