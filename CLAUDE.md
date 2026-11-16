# FocusKey — context for Claude

iOS app (SwiftUI) that blocks apps/categories/websites with Screen Time APIs. Locking is easy;
unlocking needs a physical NFC tag whose NDEF text record is exactly `FOCUSKEY:TOGGLE`.
User-facing docs: `README.md`. This file covers architecture and the non-obvious rules.

## Repo and branches

- Public repo (MIT). `dev` = iOS work → PR into `main`. `android` = separate Kotlin/Compose app with
  the same features (different codebase; don't mix).
- **Never commit personal identifiers**: team ID, names, emails, local paths, real bundle IDs.
  Signing lives in `Config/Signing.local.xcconfig` (git-ignored, included by `Config/Base.xcconfig`).
  Committed placeholders: bundle `com.example.FocusKey…`, App Group `group.com.example.FocusKey`
  (also hardcoded in `Shared/FocusStore.swift`). Never set the team via Xcode's Signing UI.
- Code comments and identifiers in English; UI strings are written in **Spanish** (development
  language) with `String(localized:)`, English translations in the `.xcstrings` catalogs.

## Targets and file membership

| Target | Sources | Min iOS |
| --- | --- | --- |
| FocusKey (app) | root `*.swift` + `App/` + `Shared/` | 26.6 |
| FocusKeyMonitor (DeviceActivityMonitor) | `FocusKeyMonitor/` + `Shared/` | 27.0 |
| FocusKeyShield (ShieldConfiguration) | `FocusKeyShield/` + `Shared/` | 26.6 |
| FocusKeyWidget (widgets + Control Center) | `FocusKeyWidget/` + `Shared/` | 26.6 |
| FocusKeyTests (Swift Testing, hosted in app) | `FocusKeyTests/` | 26.6 |

- `App/`, `Shared/` and the extension folders are **file-system synchronized groups**: new files
  there are picked up automatically. The root-level Swift files (`ContentView`, `FocusModel`,
  `ScheduleView`, `NFCScanner`, `FocusKeyApp`) are classic references — adding a new root file
  requires editing `project.pbxproj`, so prefer putting new files in `App/` or `Shared/`.
- Anything in `Shared/` must compile in every extension (no app-only APIs; types are `nonisolated`).
- App target uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, Swift 5 mode.

## Architecture

All state lives in App Group `UserDefaults` so the app, extensions, widgets and intents share it.

- `Shared/FocusModels.swift` — `FocusProfile` (name, SF symbol, `colorName`, `FamilyActivitySelection`),
  `FocusSchedule` (weekly interval, may cross midnight), `UsageLimit` (daily minutes per profile),
  `BlockRecord` (stats), `FocusActivity` (DeviceActivity name prefixes:
  `FocusKeySchedule_<uuid>`, `FocusKeyLimit_<uuid>`, `FocusKeyExtra_<uuid>`, `FocusKeySession`).
- `Shared/FocusStore.swift` — persistence (all keys in `FocusStore.Key`), migrations of old data,
  limit reached/extension dictionaries keyed by UUID string, record open/close (kept 60 days).
- `Shared/FocusLock.swift` — applies/lifts shields. **Three named `ManagedSettingsStore`s**
  (`FocusKey.manual`, `FocusKey.schedule`, `FocusKey.limit`); iOS combines them. Schedule and limit
  stores always hold the *union* of every active source. Also NFC unlock, limit extensions,
  `denyAppRemoval`, widget reload.
- `Shared/FocusStatus.swift` — snapshot of what is blocking now (used by app, widgets, shield, intents).
- `Shared/FocusStats.swift` — per-day minutes (overlaps merged), streak, 5-week Monday-first calendar.
- `Shared/FocusTheme.swift` — `FocusPalette` (profile colors by name), `FocusQuotes` for the shield.
- `Shared/FocusIntents.swift` — `LockFocusIntent` (a `LiveActivityIntent` so it runs in the app
  process — the widget process has no Screen Time auth), `UnlockWithKeyIntent` (sets a flag, app
  opens and starts NFC scan), `FocusStatusIntent`, `ProfileEntity`.
- `FocusModel.swift` — `@MainActor ObservableObject` app state; mirrors the store, registers
  DeviceActivity monitoring for schedules/limits, sets `status` messages.
- `FocusKeyMonitor/FocusKeyMonitor.swift` — `intervalDidStart/End` and `eventDidReachThreshold`:
  applies/clears schedule & limit shields, ends timed sessions, sends limit-warning notifications.
- `FocusKeyShield/` — shield screen: title, reason from `FocusStatus.reason`, profile color, quote.
- `FocusKeyWidget/` — status widget (Home/Lock Screen) + Control Center lock and "use key" buttons.
- App UI: `FocusKeyApp.swift` (tabs: Bloqueo, Horarios, Límites, Estadísticas; onboarding;
  refresh on `scenePhase == .active`), `ContentView` (status, countdown ring, lock/sessions),
  `ScheduleView` (+ week overview), `App/LimitsView`, `App/ProfilesView`, `App/StatsView`,
  `App/SettingsView`, `App/OnboardingView`, `App/FocusFilter.swift` (Focus filter),
  `App/FocusShortcuts.swift` (Siri phrases).

## Behaviour rules (intentional — don't "fix")

- **No unlock intent/shortcut/button** exists on purpose; only the NFC tag unlocks.
- NFC tag (`FocusModel.handleNFC`): if manual lock or a running schedule → lifts them (schedules are
  "skipped" until their interval ends via `scheduleSkips`); otherwise it **locks** the active profile.
  The tag **never lifts a reached daily limit**; it can only grant 5/15/30 extra minutes
  (`extendReachedLimits` → `FocusKeyExtra_` activity with `includesPastActivity: false`).
- Focus filter: Focus on → lock; Focus off → does **not** unlock (`lockOnActivate` defaults to false
  because iOS calls `perform()` with defaults when the Focus turns off).
- Timed sessions: min 15 min (DeviceActivity minimum interval), max 720 in the intent.
  `expireSessionIfNeeded` is the fallback if the monitor missed the end.
- Limits are monitored 00:00–23:59 (interval can't end at 00:00). Warning event 5 min before
  (1 min for limits < 15 min, none < 3 min).
- A running schedule can't be edited/deleted (re-registering ends the interval and lifts the block).
  A profile that is currently blocking can't change its apps; a profile used by schedules/limits
  can't be deleted; there must always be ≥1 profile.
- Only re-register monitoring when it changed (`startMonitoringForEnabledSchedules`) — restarting an
  active one can re-fire interval callbacks.
- Decoders must stay backward compatible (`decodeIfPresent` with defaults); a failed profile decode
  would recreate the default "General" profile and lose data. Add a test when adding fields.
- Shield extensions can't write data, so opening attempts can't be counted.
- `denyAppRemoval` is global (blocks deleting any app) while something is blocked; toggle in Settings.

## Build, test, run

- Must run on a **physical iPhone** (Screen Time/DeviceActivity don't work in the Simulator).
  Device-specific install commands are kept in Claude's local memory, not here.
- Tests: `xcodebuild test -project FocusKey.xcodeproj -scheme FocusKey -destination 'id=<device>'`
  (`FocusKeyTests/FocusKeyTests.swift`: schedules, limits, stats, shield union, decoding migrations).
- Schemes: `FocusKey`, `FocusKeyMonitor`.

## Conventions

- Commit messages: imperative English summary ("Add …"), work on `dev`.
- When adding user-visible text: write it in Spanish via `String(localized:)` and add the English
  entry in `Shared/Localizable.xcstrings` (or `App/AppShortcuts.xcstrings` / `App/InfoPlist.xcstrings`).
- After changing shared state, call `FocusLock.reloadWidgets()`; after store changes from the app,
  `FocusModel.reload()`.
- Keep `README.md` features list in sync when adding user-facing features.
