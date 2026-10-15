//
//  FocusModel.swift
//  FocusKey
//
//  Created by Pablo Ortega on 14/10/2026.
//

import SwiftUI
import Combine
import FamilyControls
import ManagedSettings

@MainActor
final class FocusModel: ObservableObject {

    @Published var selection = FamilyActivitySelection()
    @Published var isLocked: Bool = UserDefaults.standard.bool(
        forKey: "FocusKey.isLocked"
    ) {
        didSet {
            UserDefaults.standard.set(isLocked, forKey: "FocusKey.isLocked")
        }
    }
    @Published var status = "Autoriza Screen Time para empezar."

    private let store = ManagedSettingsStore()
    private let selectionKey = "FocusKeySelection"

    init() {
        if let data = UserDefaults.standard.data(
            forKey: selectionKey
        ),
        let saved = try? JSONDecoder().decode(
            FamilyActivitySelection.self,
            from: data
        ) {
            selection = saved
        }

        // No asumimos que el sistema siga bloqueado
        // después de un reinicio o un cambio de autorización.
    }

    func authorize() async {
        let center = AuthorizationCenter.shared

        switch center.authorizationStatus {
        case .approved:
            status = "Screen Time ya está autorizado."
            print("✅ Autorización existente.")

        case .notDetermined, .denied:
            do {
                try await center.requestAuthorization(for: .individual)

                if center.authorizationStatus == .approved {
                    status = "Autorización concedida."
                } else {
                    status = "La autorización no está aprobada."
                }
            } catch {
                status = "Error de autorización: \(error.localizedDescription)"
                print("❌ Error de autorización:", error)
            }

        @unknown default:
            status = "Estado de autorización desconocido."
        }
    }

    func saveSelection() {
        if let data = try? JSONEncoder().encode(selection) {
            UserDefaults.standard.set(data, forKey: selectionKey)
        }
    }

    func toggleLock() {
        guard AuthorizationCenter.shared.authorizationStatus == .approved else {
            status = "Error: autorización de Screen Time no aprobada."
            return
        }

        let hasApps = !selection.applicationTokens.isEmpty
        let hasCategories = !selection.categoryTokens.isEmpty
        let hasWebDomains = !selection.webDomainTokens.isEmpty

        guard hasApps || hasCategories || hasWebDomains else {
            status = "Selecciona aplicaciones, categorías o sitios web."
            return
        }

        if isLocked {
            // Retirar todas las restricciones de este almacén.
            store.clearAllSettings()

            isLocked = false
            status = "Bloqueo desactivado."
            print("🔓 FocusKey: restricciones retiradas.")
        } else {
            // Bloquear aplicaciones seleccionadas individualmente.
            store.shield.applications =
                selection.applicationTokens.isEmpty
                ? nil
                : selection.applicationTokens

            // Bloquear las categorías completas seleccionadas.
            store.shield.applicationCategories =
                selection.categoryTokens.isEmpty
                ? nil
                : .specific(selection.categoryTokens)

            // Bloquear dominios web seleccionados individualmente.
            store.shield.webDomains =
                selection.webDomainTokens.isEmpty
                ? nil
                : selection.webDomainTokens

            isLocked = true

            status = """
            Bloqueo solicitado:
            \(selection.applicationTokens.count) aplicaciones individuales.
            \(selection.categoryTokens.count) categorías.
            \(selection.webDomainTokens.count) sitios web.
            """

            print("🔒 FocusKey: restricciones aplicadas.")
            print("Aplicaciones:", selection.applicationTokens.count)
            print("Categorías:", selection.categoryTokens.count)
            print("Dominios web:", selection.webDomainTokens.count)
        }
    }

    func handleNFC() {
        toggleLock()
    }
}