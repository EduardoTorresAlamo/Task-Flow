# Audit Module 04: Architecture & Design Patterns
**Repositorio**: Task-Flow  
**Ruta**: `/Users/eduardotorres/Developer/XCodes/Task-Flow`  
**Fecha de Auditoría**: 24 de Agosto de 2026  
**Auditor**: Antigravity Senior Security & Software Architect  
**Scope**: MVVM con `@Observable`, Concurrencia Estricta Swift 6, Inyección de Dependencias, Ciclos de Vida SwiftUI  

---

## 1. Resumen Ejecutivo (Executive Summary)

Task-Flow sigue un patrón arquitectónico moderno basado en SwiftUI y ViewModels `@Observable` bajo Swift 6 strict concurrency.

Puntos arquitectónicos clave:
- **`AppServices`**: Centraliza la inicialización de servicios y el contenedor de SwiftData sin re-instanciación redundante en `TaskFlowApp`.
- **Aislamiento de Concurrencia**: Tipos `@MainActor` bien delimitados y closures de audio desacoplados (`nonisolated static`).

Se identifican dos áreas de mejora arquitectónica:
1. **[MED-02] OPEN**: Inicialización de ViewModels opcionales `@State` en `.onAppear`.
2. **[MED-03] OPEN**: Violación de SRP por acoplamiento de múltiples vistas a `InboxViewModel`.

---

## 2. Hallazgos Detallados

### [MED-02] Inicialización Lazy de ViewModels Opcionales `@State` en `.onAppear`
- **Severidad**: 🟡 **MEDIUM**
- **Componente**: [`Views/Inbox/SmartInboxView.swift:40,84-86`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/Views/Inbox/SmartInboxView.swift#L40), [`Views/Completed/CompletedTasksView.swift:30,56-58`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/Views/Completed/CompletedTasksView.swift#L30), [`Views/Projects/ProjectDetailView.swift:22,70-72`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/Views/Projects/ProjectDetailView.swift#L22)
- **CWE**: CWE-1076 (Code Quality / Architectural Anti-Pattern)
- **Estado**: ⚠️ **OPEN**

#### Descripción
En las vistas de Inbox, Done y Detalle de Proyecto, los view models se declaran como `@State private var viewModel: InboxViewModel?` y se instancian condicionalmente en `.onAppear`:
```swift
@State private var viewModel: InboxViewModel?

.onAppear {
    if viewModel == nil {
        viewModel = InboxViewModel(modelContext: modelContext, calendarManager: calendarManager)
    }
}
```
En `SmartInboxView.swift`:
```swift
if let vm = viewModel {
    NaturalLanguageInputBar(viewModel: vm)
        .padding(.bottom, 16)
}
```
En el primer pase de renderizado de SwiftUI, `viewModel` es `nil`, por lo que la barra de entrada no se incluye en la jerarquía visual. Al ejecutarse `.onAppear`, `viewModel` se inicializa, forzando un segundo ciclo de layout inmediato y un salto visual (layout shift / pop-in).

#### Remediación
Inicializar el view model directamente o usar un inicializador con `State(wrappedValue:)`:
```swift
@State private var viewModel: InboxViewModel

init(modelContext: ModelContext, calendarManager: CalendarManager) {
    _viewModel = State(wrappedValue: InboxViewModel(modelContext: modelContext, calendarManager: calendarManager))
}
```

---

### [MED-03] Violación del Principio de Responsabilidad Única (SRP) en `InboxViewModel`
- **Severidad**: 🟡 **MEDIUM**
- **Componente**: [`ViewModels/InboxViewModel.swift:177-254`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/ViewModels/InboxViewModel.swift#L177-L254), [`Views/Completed/CompletedTasksView.swift:57`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/Views/Completed/CompletedTasksView.swift#L57), [`Views/Projects/ProjectDetailView.swift:72`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/Views/Projects/ProjectDetailView.swift#L72)
- **Estado**: ⚠️ **OPEN**

#### Descripción
`InboxViewModel` fue diseñado para manejar el estado del campo de texto de entrada natural (`inputText`, `parsedPreview`, `onInputChange()`) y el proceso de catalogación con Apple Intelligence en el Inbox.
Sin embargo, `CompletedTasksView` y `ProjectDetailView` instancian `InboxViewModel` únicamente para invocar `viewModel.toggleCompletion(task)`.

Esto genera un acoplamiento innecesario entre pantallas de sólo lectura/historial y la lógica de parsing de texto y dictado por voz.

#### Remediación
Extraer la lógica de cambio de estado de completado y gestión de recurrencia a un servicio de dominio reutilizable (`TaskCompletionService` o inyectarlo en `CalendarManager` / `TaskCoordinator`):
```swift
@MainActor
final class TaskCompletionService {
    let modelContext: ModelContext
    let calendarManager: CalendarManager

    init(modelContext: ModelContext, calendarManager: CalendarManager) {
        self.modelContext = modelContext
        self.calendarManager = calendarManager
    }

    func toggleCompletion(_ task: Task) async {
        if task.isCompleted {
            task.isCompleted = false
            task.completedAt = nil
            task.updatedAt = Date()
            await removeSpawnedSuccessor(of: task)
            return
        }
        if task.isRecurring {
            await completeRecurring(task)
        } else {
            task.isCompleted = true
            task.completedAt = Date()
            task.updatedAt = Date()
        }
    }
}
```

---

## 3. Verificación de Concurrencia y Aislamiento Swift 6

1. **Aislamiento UI**: Todos los ViewModels y servicios que interactúan con `ModelContext` están marcados como `@MainActor`.
2. **Callbacks de Audio**: `VoiceTaskService.requestSpeechAuthorization()` y `VoiceTaskService.makeTapBlock(...)` son `nonisolated static`, lo que evita aserciones de executor de Swift 6 al ser invocados en hilos en tiempo real de `AVAudioEngine` o colas de TCC.
3. **Inmutabilidad y Sendable**: `TaskCatalog`, `RecurrenceRule`, `Weekday`, `WidgetSnapshot`, `WidgetTask` son estrictamente `Sendable`.
