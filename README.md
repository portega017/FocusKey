# FocusKey

FocusKey is an OpenSource iOS app designed to help you stay focused by controlling access to apps, app categories, and websites using Apple's Screen Time and Family Controls APIs.

The app lets you:
- select the apps, categories, and web domains you want to restrict;
- lock or unlock those selections from the app interface;
- use a compatible NFC tag as a physical key to toggle the lock state.

## How it works

1. Authorize Screen Time access.
2. Choose the apps, categories, or websites you want to restrict.
3. Turn the lock on from the app.
4. If you have a valid FocusKey NFC tag, tap it to your iPhone to toggle the lock automatically.

## Requirements

- An iPhone or iPad compatible with Screen Time and NFC features
- A version of iOS that supports Family Controls and CoreNFC
- Screen Time permissions granted when prompted by the app
- An NFC tag containing the text `FOCUSKEY:TOGGLE` to use the NFC unlock/lock flow

## Main features

- Lock selected apps
- Lock entire app categories
- Lock selected web domains
- Persist the current selection between launches
- Toggle locking with a valid NFC tag
- Create weekly start and end intervals for automatic blocking through a Device Activity monitor extension

## Notes

- The app checks whether Screen Time has been authorized before applying restrictions.
- Locking is not possible if no apps, categories, or web domains are selected.
- NFC scanning only accepts NDEF tags that contain exactly `FOCUSKEY:TOGGLE`.
- Automatic schedules must be tested on an authorized physical device; `DeviceActivity` callbacks are not available in the iOS Simulator.

## Project

This is a Swift iOS project built with:
- SwiftUI
- FamilyControls
- ManagedSettings
- CoreNFC

## Roadmap

