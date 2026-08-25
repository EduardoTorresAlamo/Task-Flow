# Audit Module 02: Business Logic, Sync & Data Integrity
**Repositorio**: Task-Flow  
**Ruta**: `/Users/eduardotorres/Developer/XCodes/Task-Flow`  
**Fecha de Auditoría**: 24 de Agosto de 2026  
**Auditor**: Antigravity Senior Security & Software Architect  
**Scope**: Mecánicas de Recurrencia, Sincronización EventKit, Cadenas de Sucesores, Parser de Lenguaje Natural  

---

## 1. Resumen Ejecutivo (Executive Summary)

El análisis de la lógica de negocio, ciclo de vida de tareas y sincronización con Apple Calendar reveló **1 VULNERABILIDAD CRÍTICA (`CRIT-01`)** en el modelo de recurrencia EventKit y **1 anomalía de integridad (`MED-04`)** en el seguimiento de sucesores eliminados.

---

## 2. Hallazgos Detallados

### [CRIT-01] Mapeo Dual de Recurrencia Genera Series Duplicadas Exponenciales en Apple Calendar
- **Severidad**: 🚨 **CRITICAL**
- **Componente**: [`Services/CalendarSyncService.swift:88-93`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/Services/CalendarSyncService.swift#L88-L93), [`ViewModels/InboxViewModel.swift:211-222`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/ViewModels/InboxViewModel.swift#L211-L222)
- **CWE**: CWE-400 (Uncontrolled Resource Consumption / Calendar Data Duplication)
- **Estado**: 🚨 **OPEN / ACTIVE**

#### Causa Raíz
Task-Flow gestiona la recurrencia mediante **materialización discreta de tareas**: al completar una tarea recurrente, `InboxViewModel.completeRecurring(task)` marca la tarea original como completada en SwiftData y genera una nueva instancia de `Task` (`next`) con la siguiente fecha de vencimiento (`nextDue`), heredando la regla `recurrenceRule`.

Sin embargo, en `CalendarSyncService.swift`:
```swift
let saveSpan: EKSpan
if let rule = task.recurrenceRule {
    ekEvent.recurrenceRules = [Self.ekRecurrenceRule(from: rule)]
    saveSpan = .futureEvents
} else {
    saveSpan = .thisEvent
}
try store.save(ekEvent, span: saveSpan)
```
Cuando `CalendarSyncService.sync(task:)` procesa la primera tarea recurrente, crea un `EKEvent` en Apple Calendar y le adjunta una regla `EKRecurrenceRule`. En EventKit, un evento con `EKRecurrenceRule` genera una serie que se repite automáticamente en el calendario hacia el futuro.

Cuando el usuario completa la ocurrencia 1 en la app:
1. `InboxViewModel` crea la ocurrencia 2 (`next`), que también tiene `next.recurrenceRule = rule`.
2. `completeRecurring` invoca `await calendarManager.syncTask(next)`.
3. `CalendarSyncService` crea un **segundo** `EKEvent` para `next` y **también le añade una regla `EKRecurrenceRule`**.
4. Ahora Apple Calendar tiene **DOS series de eventos recurrentes paralelas y superpuestas**.
5. Al completar la ocurrencia 2, se crea la ocurrencia 3 con su propio `EKEvent` recurrente, generando **TRES series superpuestas**.

#### Escenario de Impacto
```
Tarea Inicial (Diaria):
  Task-Flow: [Tarea 1 (23 Ago)] -> Sincroniza EKEvent #1 (Repite Diario)
  Calendar: 23 Ago (Evt1), 24 Ago (Evt1), 25 Ago (Evt1), 26 Ago (Evt1)...

Usuario completa Tarea 1 el 23 Ago:
  Task-Flow: Tarea 1 Completada. Tarea 2 creada para 24 Ago.
  Task-Flow: [Tarea 2 (24 Ago)] -> Sincroniza EKEvent #2 (Repite Diario desde 24 Ago)
  Calendar: 
    23 Ago: Evt1
    24 Ago: Evt1 + Evt2 (DUPLICADO)
    25 Ago: Evt1 + Evt2 (DUPLICADO)
    26 Ago: Evt1 + Evt2 (DUPLICADO)...

Usuario completa Tarea 2 el 24 Ago:
  Calendar:
    25 Ago: Evt1 + Evt2 + Evt3 (TRIPLICADO)...
```

#### Remediación Obligatoria
Dado que Task-Flow materializa cada ocurrencia como un `Task` independiente en SwiftData, la sincronización en Calendar debe crear eventos puntuales (`EKEvent` discretos sin `EKRecurrenceRule`):

```diff
--- a/Services/CalendarSyncService.swift
+++ b/Services/CalendarSyncService.swift
@@ -87,7 +87,3 @@ final class CalendarSyncService {
-        let saveSpan: EKSpan
-        if let rule = task.recurrenceRule {
-            ekEvent.recurrenceRules = [Self.ekRecurrenceRule(from: rule)]
-            saveSpan = .futureEvents
-        } else {
-            saveSpan = .thisEvent
-        }
+        ekEvent.recurrenceRules = nil
+        let saveSpan: EKSpan = .thisEvent
```

---

### [MED-04] Ruptura de Cadena de Sucesores al Eliminar Manualmente una Tarea Sucesora
- **Severidad**: 🟡 **MEDIUM**
- **Componente**: [`ViewModels/InboxViewModel.swift:235-254`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/ViewModels/InboxViewModel.swift#L235-L254), [`Views/Tasks/TaskEditView.swift:76-80`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/Views/Tasks/TaskEditView.swift#L76-L80)
- **CWE**: CWE-672 (Operation on Resource After Expiration or Release)
- **Estado**: ⚠️ **OPEN**

#### Descripción
Al completar una tarea recurrente `A`, se asigna `A.spawnedSuccessorID = B.id`.
Si el usuario abre la tarea `B` en `TaskEditView` y la elimina con el botón "Delete Task", `B` es eliminada de SwiftData.
Sin embargo, `A.spawnedSuccessorID` mantiene el UUID de `B` (puntero huérfano).
Si el usuario más tarde des-completa `A` en `CompletedTasksView`:
`removeSpawnedSuccessor(of: A)` busca a `B` por UUID, la consulta devuelve `nil` y la función retorna de inmediato. Si `B` ya había generado a `C` antes de ser eliminada, la tarea `C` queda huérfana en el Inbox duplicando el flujo.

#### Remediación
Al eliminar cualquier tarea en `TaskEditView` o en el ViewModel, buscar y limpiar referencias en tareas precursoras:
```swift
func deleteTaskAndCleanPointers(_ task: Task, in context: ModelContext) {
    let taskID = task.id
    let descriptor = FetchDescriptor<Task>(predicate: #Predicate { $0.spawnedSuccessorID == taskID })
    if let precursor = try? context.fetch(descriptor).first {
        precursor.spawnedSuccessorID = nil
    }
    context.delete(task)
}
```

---

## 3. Evaluación de `NaturalLanguageParser` e `IntelligenceEnricher`

1. **Word-Boundary Matching**: [`NaturalLanguageParser.swift:86-100`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/Services/NaturalLanguageParser.swift#L86-L100) utiliza expresiones regulares con `\b` (`#"\b(?:urgent|asap|critical|high priority)\b"#`), evitando colisiones léxicas como `"mustard"` o `"somedays"`.
2. **Extracción de Fechas**: `NSDataDetector` opera de forma determinista y síncrona sin llamadas a red.
3. **Extracción de Metadatos Enriquecidos**: [`IntelligenceEnricher.swift`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/Services/IntelligenceEnricher.swift) procesa nombres de lugares y personas mediante `NLTagger` con `.nameType` y calcula duraciones con patrones regex (`30 min`, `2 hours`).
