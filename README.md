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

- Block individual apps, entire app categories and web domains
- Lock from the app; unlock with a FocusKey NFC tag
- Weekly schedules with start and end times for automatic blocking
- The NFC tag works as a master key, including during a scheduled block
- Your selection is kept between launches

## How it works

1. Grant Screen Time access when the app asks.
2. Choose the apps, categories or websites you want to block.
3. Turn the lock on, or create a schedule.
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
2. Set your own team and bundle identifiers (default: `com.example.FocusKey`) for the app and the `FocusKeyMonitor` extension.
3. Run on a **physical device** — Screen Time and `DeviceActivity` callbacks don't work in the Simulator.

For Android, see the [README on the `android` branch](https://github.com/portega017/FocusKey/tree/android#readme).

## Project structure

```
FocusKeyApp.swift        App entry point
ContentView.swift        Main screen
AppSelector.swift        App / category / website picker
ScheduleView.swift       Weekly schedules
FocusModel.swift         Lock state and persistence
NFCScanner.swift         NFC key reading
FocusKeyMonitor/         Device Activity monitor extension (scheduled blocks)
```

Built with SwiftUI, FamilyControls, ManagedSettings, DeviceActivity and CoreNFC.

## Notes

- Locking requires Screen Time authorization and at least one selected app, category or website.
- A schedule that is currently running cannot be edited or deleted.

## Contributing

Issues and pull requests are welcome. iOS changes go to `dev`; Android changes go to `android`.

## License

MIT — see [LICENSE](LICENSE).
