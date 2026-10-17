//
 //  ContentView.swift
 //  FocusKey
 //
 //  Created by pibol on 14/10/2026.
 //


 import SwiftUI
 import FamilyControls
 import ManagedSettings

 struct ContentView: View {
     @EnvironmentObject var model: FocusModel
     @State private var showPicker = false
     @StateObject private var nfc = NFCScanner()

     var body: some View {
         NavigationStack {
             VStack(spacing: 20) {
                 Image(systemName: "lock.shield")
                     .font(.system(size: 48))

                 Text("FocusKey")
                     .font(.largeTitle.bold())

                 Text(model.status)
                     .multilineTextAlignment(.center)
                 Text(model.isLocked ? "Bloqueado" : "Desbloqueado")
                 .font(.headline)
                 .foregroundColor(model.isLocked ? .red : .green)

                 if AuthorizationCenter.shared.authorizationStatus != .approved {
                     Button("Autorizar bloqueo") {
                         Task {
                             await model.authorize()
                         }
                     }
                     .buttonStyle(.borderedProminent)
                 }

                 Button("Seleccionar aplicaciones") {
                     showPicker = true
                 }
                 .buttonStyle(.bordered)

                 Text(
                     "\(model.selection.applicationTokens.count) aplicaciones seleccionadas"
                 )
                 .font(.subheadline)


                 Button(model.isLocked ? "Desbloquear" : "Bloquear") {
                     nfc.start()
                 }
                 .buttonStyle(.bordered)

                 Spacer()
             }
             .padding()
             .familyActivityPicker(
                 isPresented: $showPicker,
                 selection: $model.selection
             )
             .navigationTitle("Concentración")
             .task { await model.authorize() }
             .onAppear {
                 nfc.onValidTag = {
                     Task { @MainActor in
                         model.handleNFC()
                     }
                 }
             }
         }
     }
 }
