//
//  FocusShortcuts.swift
//  FocusKey
//
//  Siri phrases and Shortcuts app entries. The intents live in Shared/FocusIntents.swift.
//

import AppIntents

struct FocusShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LockFocusIntent(),
            phrases: [
                "Bloquear apps con \(.applicationName)",
                "Activar \(.applicationName)",
                "Bloquear \(\.$profile) con \(.applicationName)"
            ],
            shortTitle: "Bloquear apps",
            systemImageName: "lock.fill"
        )
        AppShortcut(
            intent: UnlockWithKeyIntent(),
            phrases: ["Desbloquear \(.applicationName) con la llave"],
            shortTitle: "Usar llave",
            systemImageName: "wave.3.right"
        )
        AppShortcut(
            intent: FocusStatusIntent(),
            phrases: ["¿Está \(.applicationName) bloqueando?", "Estado de \(.applicationName)"],
            shortTitle: "Consultar bloqueo",
            systemImageName: "lock.shield"
        )
    }
}
