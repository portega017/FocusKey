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
            await FocusLiveActivity.sync()
            if let end = FocusStore.sessionEnd {
                return .result(dialog: "«\(locked.displayName)» bloqueado hasta las \(end.formatted(date: .omitted, time: .shortened)).")
            }
            return .result(dialog: "«\(locked.displayName)» bloqueado. Usa tu llave para desbloquear.")
        } catch FocusLock.LockError.alreadyLocked {
            return .result(dialog: "El bloqueo ya está activo.")
        } catch FocusLock.LockError.pomodoroRunning {
            return .result(dialog: "Hay un pomodoro en curso. Termínalo con tu llave.")
        } catch {
            // Widget and Control Center buttons can't show errors: keep it for the app to show.
            FocusStore.lastIntentError = error.localizedDescription
            FocusLock.reloadWidgets()
            throw error
        }
    }
}

// MARK: - Session presets

nonisolated struct SessionPresetEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Sesión rápida"
    static let defaultQuery = SessionPresetQuery()

    let id: UUID
    let title: String
    let symbol: String

    init(_ preset: SessionPreset, profiles: [FocusProfile]) {
        let profile = profiles.first { $0.id == preset.profileID }
        id = preset.id
        title = preset.title(profile: profile)
        symbol = profile?.symbol ?? "timer"
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", image: .init(systemName: symbol))
    }
}

nonisolated struct SessionPresetQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [SessionPresetEntity] {
        let profiles = FocusStore.profiles()
        return FocusStore.presets().filter { identifiers.contains($0.id) }.map { SessionPresetEntity($0, profiles: profiles) }
    }

    func suggestedEntities() async throws -> [SessionPresetEntity] {
        let profiles = FocusStore.profiles()
        return FocusStore.presets().map { SessionPresetEntity($0, profiles: profiles) }
    }
}

/// Starts a session preset. A `LiveActivityIntent` for the same reason as `LockFocusIntent`:
/// it must run in the app's process to have Screen Time authorization.
struct StartPresetIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Empezar sesión rápida"
    static let description = IntentDescription("Empieza una sesión rápida: bloquea su perfil durante su tiempo o en ciclos de pomodoro. Solo tu llave NFC puede terminarla antes.")

    @Parameter(title: "Sesión")
    var preset: SessionPresetEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Empezar \(\.$preset)")
    }

    init() {}

    init(preset: SessionPresetEntity?) {
        self.preset = preset
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let id = preset?.id, let saved = FocusStore.presets().first(where: { $0.id == id }) else {
            let message = String(localized: "Esa sesión rápida ya no existe. Elige otra.")
            FocusStore.lastIntentError = message
            return .result(dialog: "\(message)")
        }
        do {
            if let pomodoro = saved.pomodoro {
                let plan = try FocusLock.startPomodoro(
                    profileID: saved.profileID, focusMinutes: pomodoro.focusMinutes,
                    breakMinutes: pomodoro.breakMinutes, cycles: pomodoro.cycles
                )
                PomodoroNotifications.schedule(plan)
                await FocusLiveActivity.sync()
                let end = plan.end.formatted(date: .omitted, time: .shortened)
                return .result(dialog: "Pomodoro de \(plan.cycles) ciclos iniciado. Termina a las \(end).")
            }
            let locked = try FocusLock.lockManually(profileID: saved.profileID, minutes: saved.minutes)
            await FocusLiveActivity.sync()
            let end = (FocusStore.sessionEnd ?? .now).formatted(date: .omitted, time: .shortened)
            return .result(dialog: "«\(locked.displayName)» bloqueado hasta las \(end).")
        } catch FocusLock.LockError.alreadyLocked {
            return .result(dialog: "El bloqueo ya está activo.")
        } catch FocusLock.LockError.pomodoroRunning {
            return .result(dialog: "Hay un pomodoro en curso. Termínalo con tu llave.")
        } catch {
            FocusStore.lastIntentError = error.localizedDescription
            FocusLock.reloadWidgets()
            throw error
        }
    }
}

/// Which preset a Control Center button starts (chosen when adding the control).
struct PresetControlConfiguration: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Sesión rápida"

    @Parameter(title: "Sesión")
    var preset: SessionPresetEntity?
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
