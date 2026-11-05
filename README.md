# FocusKey para Android

Versión Android de FocusKey, con las mismas funciones que la app de iOS, escrita en Kotlin y Jetpack Compose.

## Funciones

- **Seleccionar qué bloquear**: aplicaciones instaladas, categorías de apps (redes sociales, juegos, vídeo…) y sitios web.
- **Bloquear** desde la app y **desbloquear sólo con la llave NFC** (etiqueta con el texto `FOCUSKEY:TOGGLE`).
- **Horarios semanales** con hora de inicio y fin (pueden terminar al día siguiente), días de la semana, plantillas (Estudio, Trabajo, Dormir), duplicar, editar y eliminar.
- Bloqueo manual y bloqueo por horario **independientes**: al terminar un horario no se quita un bloqueo manual.
- La llave NFC es la llave maestra: si hay algo bloqueado (manual u horario en curso) lo desbloquea todo; el horario en curso queda saltado hasta el final de su intervalo y el siguiente vuelve a bloquear.
- Un horario **en curso no se puede modificar, desactivar ni eliminar**.
- Aviso **"El bloqueo empezará ahora"** al guardar o activar un horario que incluye la hora actual.
- Al cambiar la selección mientras hay un bloqueo activo, el bloqueo sigue usando la selección del momento en que empezó.

## Equivalencias con iOS

| iOS | Android |
| --- | --- |
| Screen Time / FamilyControls (autorización) | Servicio de accesibilidad "FocusKey – Bloqueo" |
| ManagedSettings (shield) | `FocusAccessibilityService` + pantalla `BlockedActivity` |
| FamilyActivityPicker | `AppPickerScreen` (apps, categorías y webs) |
| DeviceActivityMonitor (extensión) | `FocusEngine.syncScheduleLock`, que el servicio ejecuta al cambiar de app y la app cada 30 s |
| CoreNFC | `NfcAdapter` en modo lector (`NfcKeyReader`) |
| UserDefaults del App Group | `SharedPreferences` (`FocusStore`) |

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
├── data/       Schedule, Weekday, Selection, FocusStore (persistencia)
├── logic/      FocusEngine (reglas de bloqueo manual, horarios y llave NFC)
├── blocking/   FocusAccessibilityService y BlockedActivity
├── nfc/        NfcKeyReader
└── ui/         MainActivity, ViewModel y pantallas Compose
```

## Notas

- El bloqueo de webs funciona en Chrome, Firefox, Edge, Brave, Samsung Internet, Opera, DuckDuckGo y otros navegadores basados en Chromium; lee la barra de direcciones y bloquea el dominio y sus subdominios.
- Las categorías las declara cada app; las que no indican ninguna sólo se pueden bloquear de forma individual.
- Google Play exige justificar el uso de la API de accesibilidad; la app muestra un aviso explicando su uso antes de abrir los ajustes.

## Licencia

MIT — ver [LICENSE](LICENSE).
