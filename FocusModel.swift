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

     @Published var selection = FamilyControls.FamilyActivitySelection() {
         didSet {
             // Save the cleaned selection (applications only)
             if let data = try? JSONEncoder().encode(ensureApplicationOnlySelection(selection)) {
                 UserDefaults.standard.set(data, forKey: selectionKey)
             }
         }
     }
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
     private var cachedSelfApplicationToken: String?

     private func ensureApplicationOnlySelection(_ selection: FamilyControls.FamilyActivitySelection) -> FamilyControls.FamilyActivitySelection {
         var cleanSelection = selection
         cleanSelection.categoryTokens = []
         cleanSelection.webDomainTokens = []
         return cleanSelection
     }

     init() {
         if let data = UserDefaults.standard.data(
             forKey: selectionKey
         ),
         let saved = try? JSONDecoder().decode(
             FamilyControls.FamilyActivitySelection.self,
             from: data
         ) {
             selection = saved
         }
         // The didSet will save the cleaned selection (applications only).
     }

     private var selfApplicationToken: String? {
         if cachedSelfApplicationToken == nil {
             cachedSelfApplicationToken = Bundle.main.bundleIdentifier
         }
         return cachedSelfApplicationToken
     }

     func authorize() async {
         let center = AuthorizationCenter.shared

         switch center.authorizationStatus {
         case .approved:
             status = "Screen Time ya está autorizado."
         case .approvedWithDataAccess:
             status = "Screen Time ya está autorizado con acceso a datos."
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
             }

         @unknown default:
             status = "Estado de autorización desconocido."
         }
     }

     
     func toggleLock() {
         guard AuthorizationCenter.shared.authorizationStatus == .approved else {
             status = "Error: autorización de Screen Time no aprobada."
             return
         }

         // Get applications to block, excluding self
         let cleanedSelection = ensureApplicationOnlySelection(selection)
         var applicationsToBlock = cleanedSelection.applicationTokens
         if let selfToken = selfApplicationToken {
             applicationsToBlock = Set(applicationsToBlock.filter { String(describing: $0) != selfToken })
         }

         guard !applicationsToBlock.isEmpty else {
             status = "Selecciona aplicaciones para bloquear."
             return
         }

         if isLocked {
             // Retirar todas las restricciones de este almacén.
             store.clearAllSettings()

             isLocked = false
             status = "Bloqueo desactivado."
         } else {
             // Bloquear aplicaciones seleccionadas individualmente.
             store.shield.applications = applicationsToBlock

             // Asegurarse de que categorías y webs no estén bloqueadas.
             store.shield.applicationCategories = nil
             store.shield.webDomains = nil

             isLocked = true

             status = """
             Bloqueo solicitado:
             \(applicationsToBlock.count) aplicaciones individuales.
             """
         }
     }

     func handleNFC() {
         toggleLock()
     }
 }