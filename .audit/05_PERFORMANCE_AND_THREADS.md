# Audit Module 05: Performance, Memory & Threading
**Repositorio**: Task-Flow  
**Ruta**: `/Users/eduardotorres/Developer/XCodes/Task-Flow`  
**Fecha de Auditoría**: 24 de Agosto de 2026  
**Auditor**: Antigravity Senior Security & Software Architect  
**Scope**: Hilo Principal, I/O de Base de Datos EventKit, Eficiencia de Queries SwiftData, Publicación de Snapshots  

---

## 1. Resumen Ejecutivo (Executive Summary)

El análisis de rendimiento identificó un patrón de **I/O sincrónico en `@MainActor`** en la integración con EventKit (**HIGH-01**), junto con resoluciones exitosas previas en el pipeline del widget (**HIGH-03**).

---

## 2. Hallazgos Detallados

### [HIGH-01] I/O Sincrónico de EventKit e IPC Mach Bloqueando el Hilo UI (`@MainActor`)
- **Severidad**: 🔴 **HIGH**
- **Componente**: [`Services/CalendarSyncService.swift:96,122`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/Services/CalendarSyncService.swift#L96), [`Services/EventKitService.swift:66`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/Services/EventKitService.swift#L66)
- **CWE**: CWE-400 (Uncontrolled Resource Consumption / Main Thread Blocking)
- **Estado**: 🔴 **OPEN / ACTIVE**

#### Descripción del Problema
`CalendarSyncService` y `EventKitService` están aislados en el actor principal (`@MainActor`).
Dentro de `CalendarSyncService.sync(task:)` y `deleteEvent(for:)`, las llamadas a:
```swift
try store.save(ekEvent, span: ...)
try eventKitService.store.remove(ekEvent, span: .thisEvent)
```
y en `EventKitService.fetchEvents(from:to:)`:
```swift
store.events(matching: predicate)
```
se ejecutan de forma **completamente síncrona en el hilo principal**.

#### Impacto Técnico
1. **Llamadas IPC y Bloqueo de Disco**: `EKEventStore` se comunica a través de Mach IPC con el daemon `calaccessd`, el cual lee y escribe en la base de datos SQLite de Calendarios del sistema (`Calendar.sqlitedb`).
2. **Caída de Frames (Jank)**: Cuando la base de datos de calendarios del usuario es voluminosa o la sincronización de iCloud Calendar está activa, estas llamadas pueden tardar entre 50 ms y más de 300 ms, bloqueando la interfaz de usuario en transiciones o al crear/editar tareas.
3. **Riesgo de Watchdog ANR**: Si se ejecutan operaciones continuas o en bucle (e.g. `syncAllTasks`), el bloqueo acumulado del hilo principal puede disparar la terminación de la aplicación por el Watchdog de iOS (`0x8badf00d`).

#### Remediación Propuesta
Ejecutar las operaciones de I/O de `EKEventStore` fuera del hilo principal usando `Task.detached(priority: .utility)`:
```swift
func syncInBackground(eventData: TaskSnapshotData, store: EKEventStore) async throws -> String? {
    try await Task.detached(priority: .utility) {
        let event = store.event(withIdentifier: eventData.eventIdentifier ?? "") ?? EKEvent(eventStore: store)
        // Configurar campos
        try store.save(event, span: .thisEvent)
        return event.eventIdentifier
    }.value
}
```

---

### [HIGH-03] Serialización Sincrónica de Snapshot de Widget en `@MainActor` — RESUELTO
- **Severidad**: 🔴 **HIGH**
- **Componente**: [`Services/WidgetSnapshotPublisher.swift:37-40`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/Services/WidgetSnapshotPublisher.swift#L37-L40)
- **Estado**: ✅ **VERIFICADO RESUELTO** (Commit `bc61ab3`)

#### Verificación
En el commit `bc61ab3`, la codificación JSON y la escritura atómica a disco de `WidgetSnapshot` fueron desacopladas del hilo principal:
```swift
Swift.Task.detached(priority: .utility) {
    WidgetSnapshotStore.write(snapshot)
    WidgetCenter.shared.reloadAllTimelines()
}
```
Esto asegura que la transición de ciclo de vida (`scenePhase != .active`) no sufra retardo al enviar la app a segundo plano.

---

## 3. Optimizaciones de Rendimiento Existentes Verificadas

1. **Agrupación de Proyectos en un Solo Pase**: [`Services/WidgetSnapshotPublisher.swift:108-115`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/Services/WidgetSnapshotPublisher.swift#L108-L115) realiza una única consulta sobre las tareas incompletas y acumula el conteo en un diccionario (`pendingByProject[projectID, default: 0] += 1`), eliminando el antipatrón de consulta N+1.
2. **Caché Estática de `DateFormatter`**: [`Views/Tasks/TaskRowView.swift:59-70`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/Views/Tasks/TaskRowView.swift#L59-L70) reutiliza instancias `static let` de `DateFormatter`, evitando instanciaciones costosas durante el scroll en `ScrollView` y `LazyVStack`.
