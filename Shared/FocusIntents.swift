//
//  FocusIntents.swift
//  FocusKey
//
//  App Intents for Siri, Shortcuts, widgets and Control Center. Compiled into the app and the
//  widget extension. There is no "unlock" intent on purpose: only the NFC tag can unlock.
//

import AppIntents
import Foundation

// MARK: - Profile entity

nonisolated struct ProfileEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Perfil de bloqueo"
    static let defaultQuery = ProfileQuery()

    let id: UUID
    let name: String
    let symbol: String

    init(_ profile: FocusProfile) {
        id = profile.id
        name = profile.displayName
        symbol = profile.symbol
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", image: .init(systemName: symbol))
    }
}

nonisolated struct ProfileQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [ProfileEntity] {
        FocusStore.profiles().filter { identifiers.contains($0.id) }.map(ProfileEntity.init)
    }

    func suggestedEntities() async throws -> [ProfileEntity] {
        FocusStore.profiles().map(ProfileEntity.init)
    }
}

// MARK: - Lock

/// `LiveActivityIntent` makes iOS run `perform()` in the app's process even when it is triggered
/// from a widget or Control Center. The widget process has no Screen Time authorization, so
/// locking from there fails.
struct LockFocusIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Bloquear apps"
    static let description = IntentDescription("Bloquea un perfil de FocusKey. Solo tu llave NFC puede desbloquearlo antes de tiempo.")

    @Parameter(title: "Perfil", description: "Si no eliges ninguno, se usa el perfil seleccionado en la app.")
    var profile: ProfileEntity?

    @Parameter(
        title: "Duración (minutos)",
        description: "Déjalo vacío para bloquear hasta usar la llave. Mínimo 15 minutos.",
        inclusiveRange: (15, 720)
    )
    var minutes: Int?

    static var parameterSummary: some ParameterSummary {
        Summary("Bloquear \(\.$profile) durante \(\.$minutes) minutos")
    }

    init() {}

    init(minutes: Int?) {
        self.minutes = minutes
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            let locked = try FocusLock.lockManually(
                profileID: profile?.id ?? FocusStore.activeProfileID,
                minutes: minutes
            )
            if let end = FocusStore.sessionEnd {
                return .result(dialog: "«\(locked.displayName)» bloqueado hasta las \(end.formatted(date: .omitted, time: .shortened)).")
            }
            return .result(dialog: "«\(locked.displayName)» bloqueado. Usa tu llave para desbloquear.")
        } catch FocusLock.LockError.alreadyLocked {
            return .result(dialog: "El bloqueo ya está activo.")
        } catch {
            // Widget and Control Center buttons can't show errors: keep it for the app to show.
            FocusStore.lastIntentError = error.localizedDescription
            FocusLock.reloadWidgets()
            throw error
        }
    }
}

// MARK: - Unlock with the tag

/// Opens FocusKey and starts an NFC scan right away.
nonisolated struct UnlockWithKeyIntent: AppIntent {
    static let title: LocalizedStringResource = "Desbloquear con llave"
    static let description = IntentDescription("Abre FocusKey y prepara la lectura de tu llave NFC.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        FocusStore.requestNFCScan()
        return .result()
    }
}

// MARK: - Status

nonisolated struct FocusStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Consultar bloqueo"
    static let description = IntentDescription("Indica si FocusKey está bloqueando apps ahora mismo.")

    func perform() async throws -> some IntentResult & ReturnsValue<Bool> & ProvidesDialog {
        let status = FocusStatus.current()
        let dialog = [status.headline, status.detail].compactMap { $0 }.joined(separator: ": ")
        return .result(value: status.isBlocked, dialog: "\(dialog).")
    }
}
