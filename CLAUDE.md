# FocusKey (Android) — context for Claude

Android app (Kotlin, Jetpack Compose, Material 3) that blocks apps, categories and websites.
Locking is easy; unlocking needs a physical NFC tag whose NDEF text record is exactly
`FOCUSKEY:TOGGLE`. Port of the iOS app (Swift), which lives on the `main`/`dev` branches of the
same GitHub repo in a separate local folder. User-facing docs: `README.md` (Spanish).

## Repo and branches

- Public repo (MIT). This folder is a clone used **only** for the `android` branch. iOS work never
  happens here, and Android work never happens in the iOS folder.
- **Never commit personal identifiers**: names, emails, local paths, signing data.
- Commit messages: imperative English summary ("Add …"). Push Android work to `android`.

## Build and test

```bash
export JAVA_HOME=~/Library/Java/JavaVirtualMachines/jbr-21.0.11/Contents/Home
./gradlew testDebugUnitTest assembleDebug lintDebug
```
- `local.properties` (git-ignored) holds `sdk.dir`. Debug APK: `app/build/outputs/apk/debug/`.
- `app/src/test/…/RulesTest.kt`: JVM tests of the rules (schedules, pauses, pomodoro, strict mode,
  JSON). `org.json` is added as a test dependency because android.jar only stubs it.
- No Android device or emulator image is set up: only build, lint and JVM tests can be verified.
  Lint warnings left on purpose: `OldTargetApi`, `GradleDependency`, `PluralsCandidate`.

## Architecture (`app/src/main/java/com/focuskey/app/`)

| iOS | Android |
| --- | --- |
| Screen Time authorization | Accessibility service on (`FocusEngine.isAuthorized`) |
| ManagedSettings shields | `blocking/FocusAccessibilityService` + `blocking/BlockedActivity` |
| DeviceActivityMonitor | `FocusEngine.sync(store)`: run by the service on app changes (≤ every 5 s), by the ViewModel every second and by pomodoro alarms. Sessions, pomodoro phases and schedules follow the clock, so blocking is exact with the app closed. |
| App Group UserDefaults | `data/FocusStore` (SharedPreferences, JSON lists) |
| Live Activity | `notify/FocusNotifications.refreshLive` (ongoing countdown notification, `setTimeoutAfter`) |
| Pomodoro phase notifications | `AlarmManager.setAndAllowWhileIdle` → `notify/PhaseReceiver` (inexact; lost on reboot) |
| FamilyActivityPicker | `ui/AppPickerScreen` (apps, `ApplicationInfo.CATEGORY_*`, domains) |
| DeviceActivity limit events / DeviceActivityReport | `logic/UsageTracker` (UsageStatsManager, needs "Usage access"); `FocusEngine.syncLimits` (service ≤ every 30 s, app every 15 s) |
| Widgets, Control Center | `widget/FocusWidget` (Glance), `tiles/LockTileService`, `tiles/KeyTileService` |
| `denyAppRemoval` | `admin/FocusAdminReceiver` (device admin, no policies); while blocked the service blocks Settings' `DeviceAdminAdd` screen |
| FocusStats / archive | `logic/Stats.kt` (`DayCounter`, `WeekStats`, `YearStats`); `FocusStore.openRecord/closeRecords`, records pruned after 60 days into `dailyArchive` |

- `data/`: `Profile` (name, icon key, color name, `Selection`), `Schedule` (minutes since midnight,
  `profileId`, `pausedDays` = day the interval starts), `PomodoroPlan` + `SessionPreset` (`Pomodoro.kt`),
  `Selection` + `AppCategory`, `FocusStore`.
- `logic/FocusEngine`: manual lock (profile snapshot in `manualShield`, `sessionStart/End` for timed
  sessions and pomodoro blocks), schedule lock (union of running non-skipped schedules' profiles,
  recomputed when the set of running ids changes), pomodoro, extend session, skip break, NFC key.
  Errors are `LockError`; the ViewModel turns them into strings.
- `ui/FocusViewModel`: single `UiState`, messages (snackbar), NFC dialog, and `guarded(weakening)`
  which in strict mode asks for the tag (`pendingKeyAction`) before applying a change.
- `notify/FocusUpdates.refreshAll` keeps the countdown notification, widget and tiles in step; call it
  after any state change outside the ViewModel (`FocusEngine.sync` returns true when state changed).
- UI: `FocusKeyRoot` (4 tabs: Lock, Schedules, Limits, Stats; onboarding first; pushed `Route`s via a simple stack + NFC dialog + snackbar),
  `LockScreen`, `ScheduleScreen` (rows + detail + pause dialog), `ScheduleForm`, `Screens.kt`
  (profiles, profile editor, preset editor, settings, form helpers), `Components.kt` (`Design`,
  `FocusCard`, `CardHeader`, `ProfileIcon`, `StatusBadge`), `UiFormat.kt` (formatting, colors, icons).

## Behaviour rules (same as iOS — don't "fix")

- No unlock without the tag. The tag lifts the manual lock, ends a pomodoro (also during breaks)
  and skips running schedules until their interval ends; if nothing is blocking it locks the active
  profile.
- While a pomodoro exists no other manual lock can start, so the manual lock belongs to it.
- Strict mode (off by default): weakening needs the tag — turning off/deleting/shortening a
  schedule, changing its profile, removing days, pausing a day, removing apps from a profile,
  turning strict mode off. Strengthening is always free (adding, extending a session, skipping a
  break, removing a pause). Rules: `Schedule.isWeakenedBy`, `Profile.isWeakenedBy`.
- A running schedule can't be edited, disabled or deleted; a blocking profile can't change its
  apps; a profile used by schedules can't be deleted; deleting a profile deletes its presets.
- Reached limits last until midnight; the tag never lifts them, it only grants 5/15/30 extra minutes
  (`LimitDay.extendedUntil`). Raising, disabling, deleting or re-profiling an enabled limit is weakening.
- Quick sessions can always be created/edited; only *starting* one is refused during another
  manual block or pomodoro.
- JSON decoding must stay backward compatible (`opt*` with defaults). The old single `selection`
  is migrated into a first profile named "General".

## Conventions

- All user-visible text in resources: `res/values/strings.xml` (English, default) and
  `res/values-es/strings.xml` (Spanish). Spanish plurals need `one`, `many` and `other`.
- Times follow the phone's 12/24 h setting (`formatTime`, `formatClock`).
- Keep `README.md` (feature list and iOS equivalence table) in sync with features.

## Feature parity with iOS

Everything on iOS exists here except Focus filters and Siri/Shortcuts (no Android equivalent was
ported). Android-only: limits show today's usage. Websites can't be measured, so limits and the
usage report count apps and categories only.
