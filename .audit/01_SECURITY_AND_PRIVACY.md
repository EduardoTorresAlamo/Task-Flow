# Audit Module 01: Security, Privacy & Entitlements
**Repositorio**: Task-Flow  
**Ruta**: `/Users/eduardotorres/Developer/XCodes/Task-Flow`  
**Fecha de Auditoría**: 24 de Agosto de 2026  
**Auditor**: Antigravity Senior Security & Software Architect  
**Scope**: Permisos TCC, Sandboxing de App Group, Deep Linking, Aislamiento On-Device de IA y Audio, Telemetría y Logs  

---

## 1. Resumen Ejecutivo (Executive Summary)

Task-Flow implementa un modelo de privacidad on-device estricto y de nivel de referencia:
- **Cero código de red**: No existen imports de `URLSession`, `Network.framework`, `WebKit` ni bibliotecas de terceros.
- **Dictado local inviolable**: El reconocimiento de voz usa `SpeechAnalyzer` y `SpeechTranscriber` vinculados a modelos locales (`AssetInventory`). Si el modelo no está instalado, el micrófono permanece inactivo sin degradar a streaming remoto.
- **Inferencia local confinada**: Apple Intelligence opera mediante `SystemLanguageModel.default`, excluyendo cualquier llamada a `PrivateCloudComputeLanguageModel`.

La evaluación de seguridad identificó:
- **[HIGH-02] RESOLVED (Commit `bcbe827`)**: Eliminación del permiso sobredimensionado `NSRemindersFullAccessUsageDescription`.
- **[MED-05] OPEN**: Falta de guard de longitud en `TaskDeepLink` y desincronización de pestaña en `RootTabView`.
- **[LOW-03] OPEN**: Manejo silencioso de permisos denegados en `VoiceInputButton` sin enlace a Ajustes.

---

## 2. Hallazgos Detallados de Seguridad

### [HIGH-02] Declaración de Permisos TCC Sobredimensionada (`NSRemindersFullAccessUsageDescription`) — RESUELTO
- **Severidad**: 🔴 **HIGH**
- **Componente**: [`project.yml:40-47`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/project.yml#L40-L47), [`Task-Flow/Info.plist:32-37`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/Task-Flow/Info.plist#L32-L37)
- **CWE**: CWE-276 (Incorrect Default Permissions / Over-Privileged Manifest)
- **Estado**: ✅ **VERIFICADO RESUELTO** (Commit `bcbe827`)

#### Análisis y Verificación
En versiones previas, `project.yml` e `Info.plist` declaraban `NSRemindersFullAccessUsageDescription` a pesar de que la aplicación no utiliza la entidad de Recordatorios (`EKEntityType.reminder`).
En el commit `bcbe827`, esta clave fue removida. La configuración actual declara exclusivamente los permisos utilizados:
1. `NSCalendarsFullAccessUsageDescription`
2. `NSMicrophoneUsageDescription`
3. `NSSpeechRecognitionUsageDescription`

---

### [MED-05] Validación de Entrada en Deep Link (`taskflow://`) y Desincronización de Pestañas
- **Severidad**: 🟡 **MEDIUM**
- **Componente**: [`Shared/TaskFlowSharedStore.swift:145-149`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/Shared/TaskFlowSharedStore.swift#L145-L149), [`App/DeepLinkCoordinator.swift:16-25`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/App/DeepLinkCoordinator.swift#L16-L25), [`Views/Components/RootTabView.swift:19-26`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/Views/Components/RootTabView.swift#L19-L26)
- **CWE**: CWE-20 (Improper Input Validation) / CWE-1076 (UI State Desynchronization)
- **Estado**: ⚠️ **OPEN**

#### Descripción del Problema
1. **Falta de Límite de Longitud**: En `TaskDeepLink.taskID(from url: URL)`:
   ```swift
   static func taskID(from url: URL) -> UUID? {
       guard url.scheme == scheme, url.host == taskHost else { return nil }
       let raw = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
       return UUID(uuidString: raw)
   }
   ```
   URLs arbitrariamente largas entregadas por Safari o apps de terceros provocan operaciones innecesarias en `trimmingCharacters` antes de fallar en `UUID(uuidString:)`.
2. **Desincronización de Navegación**: En `RootTabView.swift`:
   ```swift
   TabView {
       SmartInboxView()
           .tabItem { Label("Inbox", systemImage: "tray") }
       ProjectsView()
           .tabItem { Label("Projects", systemImage: "square.grid.2x2") }
       CompletedTasksView()
           .tabItem { Label("Done", systemImage: "checkmark.circle") }
   }
   ```
   `TabView` no tiene enlace de selección (`selection: $selectedTab`). Si el usuario está en la pestaña "Projects" o "Done" y toca una tarea en el Widget, `DeepLinkCoordinator` almacena el UUID y `SmartInboxView` presenta la tarea en un modal interno, pero el usuario permanece en la pestaña no-Inbox sin ver el modal.

#### Remediación Propuesta
```diff
--- a/Shared/TaskFlowSharedStore.swift
+++ b/Shared/TaskFlowSharedStore.swift
@@ -145,3 +145,3 @@ enum TaskDeepLink {
     static func taskID(from url: URL) -> UUID? {
-        guard url.scheme == scheme, url.host == taskHost else { return nil }
+        guard url.scheme == scheme, url.host == taskHost, url.path.count <= 64 else { return nil }
         let raw = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
```
Y en `RootTabView.swift`:
```swift
@State private var selectedTab: Int = 0
// Vincular selection: $selectedTab y cambiar a 0 (Inbox) cuando deepLinkCoordinator.pendingTaskID != nil
```

---

### [LOW-03] Manejo Silencioso de Denegación de Permisos de Dictado
- **Severidad**: 🔵 **LOW**
- **Componente**: [`Views/Components/VoiceInputButton.swift:47-48, 70-74`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/Views/Components/VoiceInputButton.swift#L47-L48)
- **CWE**: CWE-1076 (Degraded UX / Permission Flow)
- **Estado**: ⚠️ **OPEN**

#### Descripción del Problema
Cuando el reconocimiento de voz o micrófono son denegados (`.denied` o `.restricted`), `VoiceInputButton` deshabilita el botón visualmente (`.disabled(isDisabled)`). El modificador `.help()` y `.accessibilityLabel()` contienen la explicación, pero en iOS táctil no hay tooltip visible y no se provee un botón para abrir Ajustes (`UIApplication.openSettingsURLString`).

---

## 3. Verificación de Arquitectura de Privacidad On-Device

1. **Aislamiento de Red**: No existen sockets, HTTP clients ni dependencias externas.
2. **Entitlements**: [`App/TaskFlow.entitlements`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/App/TaskFlow.entitlements) y [`Widget/TaskFlowWidget.entitlements`](file:///Users/eduardotorres/Developer/XCodes/Task-Flow/Widget/TaskFlowWidget.entitlements) configuran únicamente `group.com.eduardotorres.Task-Flow`.
3. **Privacidad en Logs**: Los logs en `CalendarSyncService.swift`, `TaskIntelligenceService.swift` y `TaskFlowSharedStore.swift` emplean `privacy: .public` únicamente para nombres de tipos o identificadores de subsistema, nunca para títulos de tareas, notas ni transcripciones de voz.
