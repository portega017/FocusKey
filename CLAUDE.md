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
| FocusKeyWidget (widgets, Control Center, Live Activity) | `FocusKeyWidget/` + `Shared/` | 26.6 |
| FocusKeyReport (DeviceActivityReport, **ExtensionKit**) | `FocusKeyReport/` only (no `Shared/`) | 26.6 |
| FocusKeyTests (Swift Testing, hosted in app) | `FocusKeyTests/` | 26.6 |

- `App/`, `Shared/` and the extension folders are **file-system synchronized groups**: new files
  there are picked up automatically. The root-level Swift files (`ContentView`, `FocusModel`,
  `ScheduleView`, `NFCScanner`, `FocusKeyApp`) are classic references — adding a new root file
  requires editing `project.pbxproj`, so prefer putting new files in `App/` or `Shared/`.
- Anything in `Shared/` must compile in every extension (no app-only APIs; types are `nonisolated`).
- FocusKeyReport is embedded via the "Embed ExtensionKit Extensions" phase (`Extensions/`, not
  `PlugIns/`) and has its own `Localizable.xcstrings` (separate bundle). Its context name
  `FocusKeyUsage` is declared in both the extension and `App/StatsView.swift` — keep them equal.
- Adding a target means editing `project.pbxproj` by hand: use unused `AA000…` IDs, `plutil -lint`
  it and check `xcodebuild -list`.
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
- `SessionPreset` (in `FocusModels.swift`, stored under `FocusKey.sessionPresets`): profile + minutes,
  or a pomodoro (`pomodoro: SessionPreset.Pomodoro?`, `minutes` ignored then). Started with
  `FocusModel.startPreset` / `StartPresetIntent`; pomodoro phase notifications live in
  `PomodoroNotifications` (Shared) so intents schedule them too; UI in `App/PresetsView.swift`
  (`PresetGrid` on the main screen). Deleting a profile deletes its presets. After changing presets
  or profile names call `FocusShortcuts.updateAppShortcutParameters()` (Siri parameter values).
- `Shared/FocusPomodoro.swift` — `PomodoroPlan` (focus/break/cycles) and its phase at a date.
- `Shared/FocusLiveActivity.swift` — `FocusActivityAttributes` + `FocusLiveActivity.sync()`
  (app process only; called from `FocusModel.reload()` and `LockFocusIntent`).
- `Shared/FocusStats.swift` — `DayCounter` (per-day minutes, overlaps merged; archive for old days),
  `FocusStats` (week, streak, 5-week Monday-first calendar), `FocusYearStats` (year summary).
- Records are pruned after 60 days, but `FocusStore.saveRecords` first folds whole days before the
  cutoff into `dailyArchive` (`yyyy-MM-dd` → minutes) and moves `archivedUntil`; days before it are
  read from the archive only. Never prune records without going through `saveRecords`.
- `Shared/FocusTheme.swift` — `FocusPalette` (profile colors by name), `FocusQuotes` for the shield.
- `Shared/FocusIntents.swift` — `LockFocusIntent` (a `LiveActivityIntent` so it runs in the app
  process — the widget process has no Screen Time auth), `UnlockWithKeyIntent` (sets a flag, app
  opens and starts NFC scan), `FocusStatusIntent`, `ProfileEntity`.
- `FocusModel.swift` — `@MainActor ObservableObject` app state; mirrors the store, registers
  DeviceActivity monitoring for schedules/limits, sets `status` messages.
- `FocusKeyMonitor/FocusKeyMonitor.swift` — `intervalDidStart/End` and `eventDidReachThreshold`:
  applies/clears schedule & limit shields, ends timed sessions, drives pomodoro blocks
  (`FocusLock.syncPomodoro(starting:/ending:)`), sends limit-warning notifications.
- `FocusKeyShield/` — shield screen: title, reason from `FocusStatus.reason`, profile color, quote.
- `FocusKeyWidget/` — status widget (Home/Lock Screen), Control Center lock and "use key" buttons,
  Live Activity UI (`FocusLiveActivityWidget.swift`).
- `FocusKeyReport/` — real Screen Time usage of a profile's apps (last 7 days); the app passes the
  profile's tokens in a `DeviceActivityFilter`. The extension can't send data back to the app.
- App UI: `FocusKeyApp.swift` (tabs: Bloqueo, Horarios, Límites, Estadísticas; onboarding;
  refresh on `scenePhase == .active`), `ContentView` (status, countdown ring, lock/sessions),
  `ScheduleView` (+ week overview), `App/LimitsView`, `App/ProfilesView`, `App/StatsView`,
  `App/SettingsView`, `App/OnboardingView`, `App/FocusFilter.swift` (Focus filter),
  `App/FocusShortcuts.swift` (Siri phrases).

## UI conventions

- `App/DesignSystem.swift` holds the look: `Design` sizes, `.card()` (glass card), `.screenBackground()`,
  `CardHeader`, `StatusBadge`, `ProfileIcon(size:)`, `MetricText`/`MetricTile`, `Toast`. Use them instead
  of ad-hoc paddings/radii.
- The four tabs are `ScrollView` (as the NavigationStack's direct child, so large titles work) with
  glass cards; secondary screens (schedule detail, editors, profiles, presets, settings) are native
  `List`/`Form`. Lists of items inside a tab are rows in one card separated by `Divider`s, each row
  with `ProfileIcon`, title, rounded-digit subtitle, state line, chevron and toggle.
- Accent is the `AccentColor` asset (iOS system blue, set as global accent); profile colors are used wherever
  a profile is involved. Numbers use `.fontDesign(.rounded)` + `monospacedDigit()`.
- User feedback goes through `FocusModel.status`, shown as a toast over any tab (`statusID` changes on
  every assignment). Don't set it for routine successes that happen on launch.
- Debug-only launch arguments for screenshots: `-FocusKeyTab 0…3`, `-FocusKeyStats week|year|usage`.
  On the device: `xcrun devicectl device process launch --terminate-existing <bundle id> -- -FocusKeyTab 1`
  then `xcrun devicectl device capture screenshot --destination <png>`.

## Behaviour rules (intentional — don't "fix")

- **No unlock intent/shortcut/button** exists on purpose; only the NFC tag unlocks.
- NFC tag (`FocusModel.handleNFC`): if manual lock or a running schedule → lifts them (schedules are
  "skipped" until their interval ends via `scheduleSkips`); otherwise it **locks** the active profile.
  The tag **never lifts a reached daily limit**; it can only grant 5/15/30 extra minutes
  (`extendReachedLimits` → `FocusKeyExtra_` activity with `includesPastActivity: false`).
- Focus filter: Focus on → lock; Focus off → does **not** unlock (`lockOnActivate` defaults to false
  because iOS calls `perform()` with defaults when the Focus turns off).
- Pomodoro: each focus block is a `FocusKeyPomodoro_<cycle>` DeviceActivity interval (≥15 min)
  and uses the **manual store** with `sessionStart/End` = the block; breaks are the gaps (nothing
  locked). While a plan is active `lockManually` throws `.pomodoroRunning`, so any manual lock
  then belongs to the pomodoro. The tag ends the whole plan (also during breaks). Phase-change
  notifications are scheduled up front by the app. `syncPomodoro` is the single source of truth
  (monitor callbacks + app reload fallback).
- The Live Activity can be turned off in Settings (`FocusStore.liveActivities`, on by default);
  `FocusLiveActivity.sync()` then ends any running one.
- Live Activities can only be updated by the app process: a pomodoro phase change appears when
  the app next runs; until then the activity goes stale at the phase end.
- Strict mode (`FocusStore.strictMode`, off by default): weakening changes need the tag. Rules are
  pure in `Shared/FocusStrict.swift` (`isWeakened(by:)` for schedules, limits, profiles) and enforced
  in `FocusModel.needsKey(_:retry:)`, which asks the root view's `requestKey` to scan and then
  re-runs the method. New mutating model methods that can loosen blocking must go through it.
  Turning strict mode on is free; off needs the tag. Strengthening (adding days/apps, longer
  times, lower limits, enabling, extending a session, skipping a pomodoro break) is always free.
- Extending a session (`FocusLock.extendSession`) saves the new `sessionEnd` before re-registering
  `FocusKeySession`, so the monitor ignores the old interval's end. Skipping a break
  (`PomodoroPlan.skippingBreak`) shifts the plan's `start` earlier and re-registers later blocks.
- Paused schedule days (`FocusSchedule.pausedDays`, start of the day the interval *starts*):
  only future intervals; pausing needs the tag in strict mode, resuming never does. Pauses are saved
  without re-registering monitoring; `isActive`/`runs(on:)` honour them.
- Screen Time revocation: detected on app activation (`FocusModel.checkAuthorization`, 1 s delay
  to avoid false positives), logged in `FocusStore.revocations`; on re-authorization every shield
  is re-applied (`FocusLock.reapplyAllShields`) and monitoring re-registered.
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
