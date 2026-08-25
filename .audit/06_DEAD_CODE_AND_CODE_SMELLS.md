# Audit Module 06: Dead Code, Code Smells & Build Settings
**Repositorio**: Task-Flow  
**Ruta**: `/Users/eduardotorres/Developer/XCodes/Task-Flow`  
**Fecha de Auditoría**: 24 de Agosto de 2026  
**Auditor**: Antigravity Senior Security & Software Architect  
**Scope**: Código Muerto, Estado No Renderizado, Directorios Vacíos, Configuración de Build y Cobertura de Tests  

---

## 1. Resumen Ejecutivo (Executive Summary)

Se realizó una búsqueda exhaustiva de código muerto, métodos sin llamadas, variables de estado huérfanas y configuraciones obsoletas en todo el proyecto.

Se identificaron tres hallazgos clave:
1. **[LOW-02] OPEN**: 3 métodos públicos en `CalendarManager` sin ningún invocador en la aplicación.
2. **[LOW-04] OPEN**: Falta de target de tests unitarios (`Task-FlowTests`) en `project.yml`.
3. **[LOW-05] OPEN**: Variables de estado (`catalogError` y `syncState`) actualizadas internamente pero nunca renderizadas en la interfaz de usuario.

---

## 2. Hallazgos Detallados

### [LOW-02] Métodos Huérfanos en `CalendarManager` (`syncAllTasks`, `importCalendarEvents`, `detectConflicts`)
- **Severidad**: 🔵 **LOW**
- **Componente**: [`Services/CalendarManager.swift:168-180, 203-227, 240-250`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/Services/CalendarManager.swift#L168-L180)
- **Estado**: ⚠️ **OPEN**

#### Descripción
`CalendarManager.swift` expone tres funciones públicas completas con sus estructuras auxiliares (`ConflictPair`):
1. `syncAllTasks(_ tasks: [Task]) async` (:168)
2. `importCalendarEvents(from:to:context:) async -> Int` (:203)
3. `detectConflicts(for:) -> [ConflictPair]` (:240)

Una búsqueda en todo el repositorio confirma que **ninguna vista, ViewModel ni servicio invoca estos métodos**.

#### Remediación
- Conectar estas funciones a flujos de UI (e.g. pantalla de Ajustes para importar eventos o banner de advertencia de solapamiento en `TaskEditView`).
- O marcarlas como deprecadas / removerlas para reducir la superficie de mantenimiento.

---

### [LOW-04] Ausencia de Target de Tests Unitarios Automatizados
- **Severidad**: 🔵 **LOW**
- **Componente**: [`project.yml:19-61`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/project.yml#L19-L61), [`CLAUDE.md:49`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/CLAUDE.md#L49)
- **Estado**: ⚠️ **OPEN**

#### Descripción
`project.yml` no incluye ningún target `type: bundle.unit-test`. Los componentes críticos y deterministas:
- `NaturalLanguageParser` (extracción de fechas, prioridades, conectores y marcadores de recurrencia)
- `RecurrenceRule` (cálculo de fechas siguientes, días hábiles, clamping de fin de mes)
- `TaskGrouping` (clasificación en Overdue, Today, Tomorrow, Later, Someday)
- `IntelligenceEnricher` (NER y extracción de duraciones)
carecen de un suite de pruebas automatizado que prevenga regresiones durante refactorizaciones.

#### Remediación
Configurar `Task-FlowTests` en `project.yml`:
```yaml
targets:
  Task-FlowTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - path: Tests
    dependencies:
      - target: Task-Flow
```

---

### [LOW-05] Variables de Estado Huérfanas No Renderizadas en la UI
- **Severidad**: 🔵 **LOW**
- **Componente**: [`ViewModels/InboxViewModel.swift:52`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/ViewModels/InboxViewModel.swift#L52), [`Services/CalendarManager.swift:64`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/Services/CalendarManager.swift#L64)
- **Estado**: ⚠️ **OPEN**

#### Descripción
1. **`InboxViewModel.catalogError`**: Declarada como `var catalogError: String?` con el comentario `/// The most recent cataloging failure, for display in the Inbox.` Se actualiza ante fallos de `TaskIntelligenceService`, pero ninguna vista en la jerarquía de `SmartInboxView` la lee ni muestra un banner de error.
2. **`CalendarManager.syncState`**: Actualizada a `.syncing`, `.done` y `.error`, pero ninguna vista de la app observa ni comunica visualmente los fallos de sincronización de calendario al usuario.
3. **`Views/Timeline/`**: Es un directorio vacío en el árbol de archivos.

#### Remediación
- Agregar un banner visual discreto en `SmartInboxView` para mostrar `catalogError` y `syncState.error`.
- Eliminar el directorio vacío `Views/Timeline/`.

---

## 3. Estado de Deprecaciones y Toolchain

### Advertencia de `installTap` en `VoiceTaskService.swift`
- **Ubicación**: [`Services/VoiceTaskService.swift:216`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/Services/VoiceTaskService.swift#L216)
- **Diagnóstico**: Advertencia esperada bajo el SDK de iOS 27 beta. `installTap` está deprecada en favor de la variante throwing `installTapOnBus:bufferSize:format:error:block:`, la cual está anotada como `NS_REFINED_FOR_SWIFT` en las cabeceras de Objective-C pero carece de wrapper público en el overlay Swift de Xcode 27 beta (`27A5228h`). La implementación actual es la única invocable de forma segura desde Swift.
