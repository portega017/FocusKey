# FocusKey para Android

Versión Android de FocusKey, con las mismas funciones que la app de iOS, escrita en Kotlin y Jetpack Compose.

## Funciones

- **Perfiles**: grupos con nombre, color e icono de aplicaciones, categorías y sitios web (Trabajo, Estudio, Noche…). Los usan el bloqueo manual, las sesiones rápidas y los horarios.
- **Bloquear** desde la app y **desbloquear sólo con la llave NFC** (etiqueta con el texto `FOCUSKEY:TOGGLE`).
- **Sesiones con tiempo** (15 min – 12 h) que se desbloquean solas al terminar. Se pueden **alargar** sin llave.
- **Pomodoro**: bloques de concentración (25–60 min) con descansos (5–20 min) durante 2–6 ciclos. Las apps sólo se bloquean en los bloques; un aviso marca cada cambio. Un descanso se puede **saltar**; la llave termina el pomodoro.
- **Sesiones rápidas**: botones en la pantalla principal que bloquean un perfil durante un tiempo («Redes · 1 h») o empiezan un pomodoro («Estudio · 4×25»).
- **Horarios semanales**, cada uno con su perfil: pueden terminar al día siguiente, tienen plantillas, y un día concreto se puede **pausar**. Un horario en curso no se puede modificar, desactivar ni eliminar.
- **Modo estricto**: desactivar o borrar un horario, acortarlo, pausar un día, quitar apps de un perfil o desactivar el propio modo pide la llave. Endurecer siempre es libre.
- **Límites diarios**: cuando las apps de un perfil se han usado N minutos hoy, quedan bloqueadas hasta medianoche. Se ve el uso de hoy, avisa unos minutos antes y la llave puede dar 5, 15 o 30 minutos más (nunca quitar el límite). Usa el «Acceso al uso» de Android; las webs no se pueden medir.
- **Estadísticas**: tiempo bloqueado por día, racha, calendario de 5 semanas, bloqueos recientes, **vista anual** y **uso real** de las apps de cada perfil.
- **Notificación con cuenta atrás** de las sesiones y los pomodoros (equivalente a la Live Activity de iOS), que se puede desactivar en Ajustes.
- **Widget** de pantalla de inicio y botones en los **ajustes rápidos** (Bloquear y Usar llave).
- **Protección contra desinstalación**: FocusKey se hace administrador del dispositivo y, mientras haya algo bloqueado, no deja abrir la pantalla que lo desactiva.
- **Aviso si se desactiva el servicio de bloqueo**, que queda registrado en las estadísticas.
- **Introducción** en el primer arranque.
- La llave NFC es la llave maestra: quita el bloqueo manual, termina el pomodoro y salta los horarios en curso hasta el final de su intervalo.
- En **inglés y español**.

## Equivalencias con iOS

| iOS | Android |
| --- | --- |
| Screen Time / FamilyControls (autorización) | Servicio de accesibilidad "FocusKey – Bloqueo" |
| ManagedSettings (shield) | `FocusAccessibilityService` + pantalla `BlockedActivity` |
| FamilyActivityPicker | `AppPickerScreen` (apps, categorías y webs) |
| DeviceActivityMonitor (extensión) | `FocusEngine.sync`, que el servicio ejecuta al cambiar de app y la app cada segundo: sesiones, fases del pomodoro y horarios siguen al reloj |
| CoreNFC | `NfcAdapter` en modo lector (`NfcKeyReader`) |
| UserDefaults del App Group | `SharedPreferences` (`FocusStore`) |
| Live Activity | Notificación persistente con cronómetro (`FocusNotifications`) |
| Avisos de fase del pomodoro | `AlarmManager` + `PhaseReceiver` |
| DeviceActivityReport / eventos de límite | `UsageStatsManager` (`UsageTracker`, `FocusEngine.syncLimits`) |
| Widgets y Centro de Control | Widget Glance (`FocusWidget`) y `TileService` (`LockTileService`, `KeyTileService`) |
| `denyAppRemoval` | Administrador de dispositivo (`FocusAdminReceiver`) + el servicio bloquea su pantalla de desactivación |

## Requisitos

- Android 8.0 (API 26) o superior.
- NFC para usar la llave física.
- Activar el servicio de accesibilidad de FocusKey cuando la app lo pida (botón **Autorizar bloqueo**).

## Compilar

Abre la raíz del repositorio en Android Studio, o desde terminal:

```bash
./gradlew assembleDebug
```

El APK queda en `app/build/outputs/apk/debug/`.

## Estructura

```
app/src/main/java/com/focuskey/app/
├── data/       Profile, Schedule, PomodoroPlan, SessionPreset, UsageLimit, BlockRecord, FocusStore
├── logic/      FocusEngine (bloqueos, límites, llave NFC), Stats, UsageTracker
├── notify/     Notificación con cuenta atrás, avisos de pomodoro y límites, FocusUpdates
├── widget/     Widget de pantalla de inicio (Glance)
├── tiles/      Botones de ajustes rápidos
├── admin/      Administrador de dispositivo (protección contra desinstalación)
├── blocking/   FocusAccessibilityService y BlockedActivity
├── nfc/        NfcKeyReader
└── ui/         MainActivity, ViewModel y pantallas Compose
app/src/test/   Tests JVM de las reglas (./gradlew testDebugUnitTest)
```

Los textos están en `res/values/strings.xml` (inglés) y `res/values-es/strings.xml` (español).

## Notas

- El bloqueo de webs funciona en Chrome, Firefox, Edge, Brave, Samsung Internet, Opera, DuckDuckGo y otros navegadores basados en Chromium; lee la barra de direcciones y bloquea el dominio y sus subdominios.
- Las categorías las declara cada app; las que no indican ninguna sólo se pueden bloquear de forma individual.
- Google Play exige justificar el uso de la API de accesibilidad; la app muestra un aviso explicando su uso antes de abrir los ajustes.

## Licencia

MIT — ver [LICENSE](LICENSE).
