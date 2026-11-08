# FocusKey

FocusKey is an open-source app that helps you stay focused by blocking distracting apps, app categories and websites. Locking is easy; unlocking requires a **physical NFC key** — so breaking focus takes a deliberate walk to wherever you left the tag.

FocusKey is available for **iOS** (this branch) and **Android** (see [`android` branch](https://github.com/portega017/FocusKey/tree/android)).

## Branches

| Branch | Platform | Description |
| --- | --- | --- |
| `main` | iOS | Stable iOS app (Swift / SwiftUI) |
| `dev` | iOS | iOS development; merged into `main` via pull request |
| [`android`](https://github.com/portega017/FocusKey/tree/android) | Android | Android app (Kotlin / Jetpack Compose), with the same features as iOS |

## Features

- **Profiles**: named groups of apps, categories and websites (Work, Study, Night…), used by the manual lock, schedules and limits.
- **Manual lock** of the selected profile, unlocked only with the NFC tag.
- **Timed sessions**: lock for 15 min – 12 h; it unlocks on its own when the time is up (or earlier with the tag).
- **Weekly schedules**, each with its own profile, for automatic blocking.
- **Daily usage limits**: once a profile has been used for N minutes today, it stays blocked until midnight. The NFC tag can't lift a reached limit, but it can grant 5, 15 or 30 extra minutes of use.
- **Custom shield screen** explaining why an app is blocked and until when.
- **Widgets** for the Home and Lock Screen, and **Control Center** buttons to lock or open the NFC reader.
- **Focus filters**: turning on an iOS Focus (Work, Sleep…) blocks a profile. Turning it off doesn't unlock — only the NFC tag does.
- **Siri and Shortcuts**: lock a profile (optionally for a duration), check the status, or open the NFC reader. There is deliberately no unlock shortcut.
- **Statistics**: time blocked per day, streak and recent blocks.
- **Uninstall protection**: while anything is blocked, iOS won't let apps be deleted (can be turned off in Settings).
- **Limit warnings**: a notification when 5 minutes of a daily limit are left.
- **Onboarding** on first launch, and a Settings screen.
- Available in **Spanish and English**.
- The NFC tag is the master key for the manual lock and running schedules.

## How it works

1. Grant Screen Time access when the app asks.
2. Create a profile and choose the apps, categories or websites to block.
3. Lock now, start a timed session, or create a schedule or daily limit.
4. Tap your FocusKey NFC tag on the iPhone to unlock.

## NFC key

Any NFC tag that supports NDEF works. Write a single **text record** with exactly:

```
FOCUSKEY:TOGGLE
```

You can write it with any NFC writer app (e.g. NFC Tools). Tags with any other content are ignored.

## Requirements (iOS)

- iPhone with NFC
- iOS 26.6 or later (the scheduling extension targets iOS 27)
- Xcode with the Family Controls capability enabled for your team

## Build

1. Clone the repository and open `FocusKey.xcodeproj` in Xcode.
2. Create `Config/Signing.local.xcconfig` (ignored by git) with your team:
   ```
   DEVELOPMENT_TEAM = YOUR_TEAM_ID
   ```
   Don't pick the team in Xcode's *Signing & Capabilities* UI: Xcode would write it into `project.pbxproj`.
3. Set your own bundle identifiers (default: `com.example.FocusKey…`) and App Group (default: `group.com.example.FocusKey`, also in `Shared/FocusStore.swift`). Every extension needs the Family Controls capability and the same App Group.
4. Run on a **physical device** — Screen Time and `DeviceActivity` callbacks don't work in the Simulator.

For Android, see the [README on the `android` branch](https://github.com/portega017/FocusKey/tree/android#readme).

## Project structure

```
Shared/                  Models, App Group storage, shield logic, App Intents (all targets)
App/                     Profiles, limits, statistics screens and Siri shortcuts
FocusKeyApp.swift        App entry point and tabs
ContentView.swift        Main screen (status, lock, sessions)
ScheduleView.swift       Weekly schedules
FocusModel.swift         App state
NFCScanner.swift         NFC key reading
FocusKeyMonitor/         Device Activity monitor (schedules, sessions, limits)
FocusKeyShield/          Custom shield screen
FocusKeyWidget/          Widgets and Control Center controls
FocusKeyTests/           Unit tests for the shared logic
Config/                  Build settings (signing stays local)
```

Built with SwiftUI, FamilyControls, ManagedSettings, DeviceActivity, WidgetKit, App Intents and CoreNFC.

## Tests

Logic tests (schedules, limits, statistics, data migration) use Swift Testing and run hosted in the app:

```
xcodebuild test -project FocusKey.xcodeproj -scheme FocusKey -destination 'id=<your device or simulator>'
```

## Localization

Spanish is the development language; English lives in `Shared/Localizable.xcstrings` (shared by every target), `App/AppShortcuts.xcstrings` (Siri phrases) and `App/InfoPlist.xcstrings`.

## Notes

- Locking requires Screen Time authorization and a profile with at least one app, category or website.
- A schedule that is currently running cannot be edited or deleted; a profile that is blocking can't change its apps.
- Timed sessions must last at least 15 minutes (minimum `DeviceActivity` interval).
- Daily limits are monitored from 00:00 to 23:59, so the last minute of the day is not blocked.
- Opening attempts can't be counted: iOS doesn't let shield extensions write any data.
- Uninstall protection is global: iOS only lets an app block deleting *all* apps, not just itself.

## Contributing

Issues and pull requests are welcome. iOS changes go to `dev`; Android changes go to `android`.

## License

MIT — see [LICENSE](LICENSE).
