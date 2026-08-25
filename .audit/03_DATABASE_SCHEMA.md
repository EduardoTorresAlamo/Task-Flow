# Audit Module 03: Database Schema & SwiftData Integrity
**Repositorio**: Task-Flow  
**Ruta**: `/Users/eduardotorres/Developer/XCodes/Task-Flow`  
**Fecha de Auditoría**: 24 de Agosto de 2026  
**Auditor**: Antigravity Senior Security & Software Architect  
**Scope**: Modelos SwiftData, Relaciones, Reglas de Cascada, Inversas, Índices B-Tree, Contenedor Compartido  

---

## 1. Resumen Ejecutivo (Executive Summary)

El esquema de base de datos de Task-Flow está modelado mediante **SwiftData** con registro centralizado en `TaskFlowContainer.schema = Schema([Task.self, Project.self, Tag.self])`.

Las relaciones estructurales cuentan con enlaces inversos explícitos:
- `Task.project` (`deleteRule: .nullify`) <-> `Project.tasks` (`inverse: \Task.project`)
- `Task.subtasks` (`deleteRule: .cascade, inverse: \Task.parentTask`) <-> `Task.parentTask`
- `Task.tags` <-> `Tag.tasks` (`inverse: \Task.tags`)

Se identificaron dos puntos de mejora e integridad:
1. **[MED-01] OPEN**: La eliminación en cascada de subtareas omite la desincronización en EventKit.
2. **[LOW-01] OPEN**: Ausencia de índices compuestos en los predicados de consulta más frecuentes.

---

## 2. Diagrama Entidad-Relación y Estructura del Esquema

```mermaid
erDiagram
    Task {
        UUID id PK
        String title
        String notes
        Date dueDate
        Priority priority
        Bool isCompleted
        Date completedAt
        Date createdAt
        Date updatedAt
        String eventKitIdentifier INDEX
        RecurrenceRule recurrenceRule
        Date recurrenceEnd
        Int recurrenceCount
        UUID spawnedSuccessorID
    }
    Project {
        UUID id PK
        String name
        String colorHex
        String symbolName
        Date createdAt
    }
    Tag {
        UUID id PK
        String name
        String colorHex
    }

    Task }|--o| Project : "belongs to (nullify)"
    Task ||--o{ Task : "subtasks (cascade, inverse: parentTask)"
    Task }|--|{ Tag : "tags (many-to-many)"
```

---

## 3. Hallazgos Detallados

### [MED-01] Eliminación en Cascada de Subtareas Omite Desincronización en EventKit
- **Severidad**: 🟡 **MEDIUM**
- **Componente**: [`Models/Task.swift:103`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/Models/Task.swift#L103), [`Views/Tasks/TaskEditView.swift:76-80`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/Views/Tasks/TaskEditView.swift#L76-L80)
- **CWE**: CWE-404 (Improper Resource Shutdown or Release)
- **Estado**: ⚠️ **OPEN**

#### Descripción
En `Models/Task.swift`:
```swift
@Relationship(deleteRule: .cascade, inverse: \Task.parentTask) var subtasks: [Task] = []
```
Cuando se elimina una tarea padre mediante `modelContext.delete(parentTask)`, SwiftData elimina automáticamente en cascada todas las filas de `subtasks` en SQLite.
Sin embargo, el callback de eliminación de la vista solo ejecuta:
```swift
await calendarManager.removeSync(for: task)
modelContext.delete(task)
```
Si alguna subtarea tenía fecha de vencimiento y estaba sincronizada con Apple Calendar (`subtask.eventKitIdentifier != nil`), su evento en Calendar nunca es eliminado, quedando como un evento huérfano en Apple Calendar.

#### Remediación
Implementar una función de limpieza recursiva de eventos antes de invocar la eliminación en el contexto:
```swift
func deleteWithSubtasks(_ task: Task, calendarManager: CalendarManager, context: ModelContext) async {
    for subtask in task.subtasks {
        await deleteWithSubtasks(subtask, calendarManager: calendarManager, context: context)
    }
    await calendarManager.removeSync(for: task)
    context.delete(task)
}
```

---

### [LOW-01] Falta de Índice Compuesto en Predicados de Filtro Frecuentes
- **Severidad**: 🔵 **LOW**
- **Componente**: [`Models/Task.swift:15`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/Models/Task.swift#L15)
- **CWE**: CWE-400 (Unindexed Database Queries / Table Scan Overhead)
- **Estado**: ⚠️ **OPEN**

#### Descripción
`Task.swift` declara un único índice B-Tree:
```swift
#Index<Task>([\.eventKitIdentifier])
```
No obstante, las consultas más frecuentes en la UI y extensiones evalúan:
1. `#Predicate<Task> { !$0.isCompleted }` (`SmartInboxView`, `WidgetSnapshotPublisher`)
2. `#Predicate<Task> { !$0.isCompleted && $0.dueDate != nil }` (`WidgetSnapshotPublisher`)
3. `#Predicate<Task> { $0.isCompleted }` (`CompletedTasksView`)

Sin un índice en `isCompleted` y `dueDate`, SQLite debe realizar escaneos completos de tabla para filtrar las tareas activas de las completadas.

#### Remediación
Añadir índice compuesto en `Task.swift`:
```swift
#Index<Task>([\.eventKitIdentifier])
#Index<Task>([\.isCompleted, \.dueDate])
```
