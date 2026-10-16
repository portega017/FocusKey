//
 //  FocusModel.swift
 //  FocusKey
 //
 //  Created by pibol on 14/10/2026.
 //

 import SwiftUI
 import Combine
 import FamilyControls
 import ManagedSettings

 @MainActor
 final class FocusModel: ObservableObject {

     @Published var selection = FamilyControls.FamilyActivitySelection() {
         didSet {
             // Guardar la selección completa (incluyendo categorías y dominios web)
             if let data = try? JSONEncoder().encode(selection) {
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
         // The didSet will save the full selection (including categories and web domains).
     }

     var selectedBundleIdentifiers: Set<String> {
         get {
             return []
         }
         set {
             // Do nothing
         }
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

         // Applications, categories, and web domains to block
         let applicationsToBlock: Set<ManagedSettings.ApplicationToken> = selection.applicationTokens
         let categoriesToBlock: Set<ManagedSettings.ActivityCategoryToken> = selection.categoryTokens
         let webDomainsToBlock: Set<ManagedSettings.WebDomainToken> = selection.webDomainTokens

         guard !applicationsToBlock.isEmpty || !categoriesToBlock.isEmpty || !webDomainsToBlock.isEmpty else {
             status = "Selecciona aplicaciones, categorías o dominios web para bloquear."
             return
         }

         if isLocked {
             // Remove all restrictions from this store.
             store.clearAllSettings()

             isLocked = false
             status = "Bloqueo desactivado."
         } else {
             // Block selected applications, categories, and web domains.
              store.shield.applications = applicationsToBlock
              store.shield.applicationCategories = .specific(categoriesToBlock)
              store.shield.webDomains = webDomainsToBlock

             isLocked = true

             status = """
             Bloqueo solicitado:
             \(applicationsToBlock.count) aplicaciones individuales,
             \(categoriesToBlock.count) categorías,
             \(webDomainsToBlock.count) dominios web.
             """
         }
     }

     func handleNFC() {
         toggleLock()
     }
 }
