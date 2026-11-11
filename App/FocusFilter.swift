//
//  FocusFilter.swift
//  FocusKey
//
//  Focus filter: Settings › Focus › (a Focus) › Focus Filters › FocusKey.
//  Turning the Focus on locks a profile. Turning it off does NOT unlock: a Focus can be turned
//  off from Control Center in a second, so only the NFC tag lifts the block.
//

import AppIntents

struct FocusKeyFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Bloquear con FocusKey"
    static let description = IntentDescription("Bloquea un perfil cuando se activa este modo de concentración. Al desactivarlo, el bloqueo sigue hasta que uses tu llave.")

    /// Defaults to false: iOS calls `perform()` with default values when the Focus turns off.
    @Parameter(title: "Bloquear al activar", default: false)
    var lockOnActivate: Bool

    @Parameter(title: "Perfil", description: "Si no eliges ninguno, se usa el perfil seleccionado en la app.")
    var profile: ProfileEntity?

    var displayRepresentation: DisplayRepresentation {
        guard lockOnActivate else { return DisplayRepresentation(title: "Sin bloqueo") }
        let name = profile?.name ?? String(localized: "Perfil seleccionado")
        return DisplayRepresentation(title: "Bloquear «\(name)»", subtitle: "Solo la llave desbloquea")
    }

    func perform() async throws -> some IntentResult {
        // Called with the configured values when the Focus turns on, and with the defaults
        // (lockOnActivate == false) when it turns off. Turning it off never unlocks.
        guard lockOnActivate else { return .result() }
        do {
            try FocusLock.lockManually(profileID: profile?.id ?? FocusStore.activeProfileID)
        } catch FocusLock.LockError.alreadyLocked {
            // Already blocked: nothing to do.
        } catch {
            FocusStore.lastIntentError = error.localizedDescription
        }
        return .result()
    }
}
