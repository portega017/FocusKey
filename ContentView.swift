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
                 // Re-evaluated every 30 s so the state follows schedules starting or ending.
                 TimelineView(.periodic(from: .now, by: 30)) { context in
                     lockControls(scheduleBlocking: model.isScheduleBlocking(at: context.date))
                 }

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

     @ViewBuilder
     private func lockControls(scheduleBlocking: Bool) -> some View {
         let blocked = model.isLocked || scheduleBlocking

         Text(model.isLocked ? "Bloqueado" : scheduleBlocking ? "Bloqueado por horario" : "Desbloqueado")
             .font(.headline)
             .foregroundColor(blocked ? .red : .green)

         if blocked {
             Button("Desbloquear con NFC") {
                 nfc.start()
             }
             .buttonStyle(.bordered)
         } else {
             Button("Bloquear") {
                 model.toggleLock()
             }
             .buttonStyle(.bordered)
         }
     }
 }
