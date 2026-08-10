# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Task-Flow is an on-device, privacy-first SwiftUI task manager targeting Swift 6
strict concurrency. SwiftData for local persistence, EventKit for
Calendar/Reminders sync, Apple Intelligence for cataloging, and the modern
Speech stack for dictation. **The app has no networking code at all** — see
`PRIVACY.md` before adding any.

**Deployment target is iOS 27.0.**

## Build & Run

**You must use the Xcode 27 beta, not `/Applications/Xcode.app`.**
The release Xcode (26.6) ships only the iOS 26.5 SDK, which lacks
`systemExtraLargePortrait` and the iOS 27 FoundationModels error types. It
cannot build this project.

```
Xcode 27.0 beta (27A5228h)  →  ~/Downloads/Xcode-beta.app     ← use this
Xcode 26.6 release          →  /Applications/Xcode.app        ← too old
```

`xcode-select -p` points at the Command Line Tools, so a bare `xcodebuild`
cannot find any SDK. Always prefix with `DEVELOPER_DIR`.

**XcodeGen-driven.** `Task-Flow.xcodeproj` is generated from `project.yml`.
Never hand-edit it, and always run `xcodegen generate` after adding, renaming,
or deleting a source file: a file missing from `project.pbxproj` is silently
not compiled, with no error.

```bash
xcodegen generate    # required after any file add/rename/delete

# Simulator must be an iOS 27 runtime. `iPhone 17 Pro` on iOS 27 is
# 4D226278-B373-42D3-BEAB-A6A8A822B7D7; re-list if it changes.
DEVELOPER_DIR=~/Downloads/Xcode-beta.app/Contents/Developer \
  xcodebuild -scheme Task-Flow \
  -destination 'id=4D226278-B373-42D3-BEAB-A6A8A822B7D7' build

# List iOS 27 destinations
DEVELOPER_DIR=~/Downloads/Xcode-beta.app/Contents/Developer \
  xcodebuild -showdestinations -scheme Task-Flow | grep OS:27.0
```

There is currently no test target. `Task-FlowTests` does not exist.

### One expected warning

`VoiceTaskService` calls `installTap(onBus:bufferSize:format:block:)`, which iOS
27 deprecates in favour of a throwing variant. That replacement is
`NS_REFINED_FOR_SWIFT` and the AVFAudio overlay in beta 27A5228h ships no Swift
wrapper for it, so the deprecated spelling is the only one callable. The build
is otherwise warning-free; do not "fix" this by coercing the function type,
which silently re-selects the same deprecated overload.

## Architecture

MVVM with Swift 6 `@Observable` ViewModels (no `ObservableObject` / `@Published`).

- **Models/** — SwiftData `@Model` classes: `Task`, `Project`, `Tag`. Enums in `Priority.swift`.
- **ViewModels/** — `@Observable` classes, one per major screen. Receive `ModelContext` via DI, not via `@Environment` directly. `TaskGrouping.swift` is the exception: pure date-bucketing functions with no state.
- **Views/** — SwiftUI views only, no business logic. Shared subviews live in `Components/`.
- **Extensions/** — compiled into the widget target as well as the app, so nothing here may depend on SwiftData or on `Views/`. `Theme.swift` lives here for that reason.
- **Resources/Assets.xcassets** — app icon only.
- **Services/** — Side-effect owners: `EventKitService` (Calendar/Reminders), `NaturalLanguageParser` (date extraction), `CalendarSyncService` (bidirectional EKEvent ↔ Task sync), `TaskIntelligenceService` (Apple Intelligence cataloging), `VoiceTaskService` (on-device dictation), `TagStore` (the only place `Tag` rows are written).
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
- Colors stored as `String` hex (e.g. `"#9184D9"`), converted to SwiftUI `Color` via `Color+Hex.swift`.
- SF Symbol names stored as `String` in `Project.symbolName`.
- `Task` (the SwiftData model) shadows `Swift.Task` module-wide. Write `Swift.Task { }` for concurrency. For the same reason, never name a module-level type after a stdlib generic (`TaskGroup` is `DatedTaskGroup`).

## On-device intelligence

Read `PRIVACY.md` first. The short version: no network, ever, and both AI paths
degrade to unavailable rather than reaching for a server.

**Cataloging — `TaskIntelligenceService`.** FoundationModels guided generation
(`@Generable` / `@Guide`) against `SystemLanguageModel.default`. Returns a
cleaned title, a priority, one of the user's *existing* project names, and 2-4
tags. Called from `InboxViewModel.catalog(_:rawInput:)` after the task is
already saved, so a model failure can never lose the user's input.

- Uses `SystemLanguageModel.default`, never `PrivateCloudComputeLanguageModel`
  (new in iOS 27, and a network call). This is deliberate.
- A **fresh `LanguageModelSession` per call**. A shared one throws
  `.concurrentRequests`, and a carried-over transcript lets one task bias the
  next task's categorisation.
- The parser stays authoritative for **due date and recurrence**; the model owns
  title, priority, project and tags. Deterministic fields that work with no
  model present should not be handed to the model.
- The model's project choice is resolved against a caller-supplied allow-list.
  It cannot invent a project.
- iOS 27 split `LanguageModelSession.GenerationError` into `LanguageModelError`,
  `SystemLanguageModel.Error`, `LanguageModelSession.Error` and
  `GeneratedContent.ParsingError`. All four are handled; the deprecated type is
  not referenced.
- Raw model diagnostics (`debugDescription`) are `#if DEBUG` only. Release
  builds surface fixed sentences. Do not relax this.
- Measured on the iOS 27 simulator: 1.0-3.2 s per task.

**Dictation — `VoiceTaskService`.** `SpeechAnalyzer` + `SpeechTranscriber`, not
`SFSpeechRecognizer`. The older API uploads audio unless you remember to set
`requiresOnDeviceRecognition`; the new one has no server path at all. When the
locale's model is not installed, `isOnDeviceReady` is false and the mic button
is disabled with an explanation.

> **Dictation cannot be tested in the simulator.** On the iOS 27 simulator
> `SpeechTranscriber.supportedLocales` is empty and
> `AssetInventory.status(forModules:)` returns `.unsupported`, so no model can
> be installed and the mic is always disabled. This needs a physical device.
> (The old `SFSpeechRecognizer` path pinned on-device would fail there too, so
> this is a property of on-device-only dictation, not of the API choice.)

Apple Intelligence itself *does* work in the simulator: on an Apple Silicon Mac
with Apple Intelligence enabled, the simulator proxies the host model and
`availability` returns `.available`.

## Design system

Every color, radius, and font size comes from `Extensions/Theme.swift`. Do not
hardcode a hex string or a point size in a view; add a token instead.

- Accent: `#9184D9` (Nocturne blurple). Dark-mode-only; background is pure black.
- Surfaces are `GlassCard`: `.ultraThinMaterial` + a 5.5% white tint + a 9% white hairline border.
- The list layout is "Airy Grouped": 34pt screen title, uppercase 11pt section labels, 18pt-radius cards with 16pt padding, 10pt between rows and 22pt between sections.
- The Inbox and project lists section tasks by due date via `groupTasksBySection`; the Done screen uses `groupCompletedTasks`.

## Widget

`TodayTasksWidget` supports six families: small, medium, large,
`systemExtraLarge`, `systemExtraLargePortrait` (**iOS 27 only** — this is the
family that forces the beta toolchain), plus `accessoryRectangular` and
`accessoryCircular` on the Lock Screen.

- Home Screen families get `WidgetWaveBackground`, radial accent blooms echoing
  the app icon. Accessory families are rendered flat: the Lock Screen composites
  them as a monochrome vibrant layer, so colour and gradient are discarded.
- `systemExtraLargePortrait` shows 12 rows; `systemExtraLarge` shows 8 plus a
  per-project summary strip fed by `TodayTasksEntry.projectSummaries`.
