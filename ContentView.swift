//
//  ContentView.swift
//  FocusKey
//
//  Created by Pablo Ortega on 14/10/2026.
//


import SwiftUI
import FamilyControls

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

                Button("Autorizar bloqueo") {
                    Task {
                        await model.authorize()
                    }
                }
                .buttonStyle(.borderedProminent)

                Button("Elegir aplicaciones") {
                    showPicker = true
                }
                .buttonStyle(.bordered)

                Text(
                    "\(model.selection.applicationTokens.count) aplicaciones seleccionadas"
                )
                .font(.subheadline)

                Button(
                    model.isLocked
                    ? "Desbloquear aplicaciones"
                    : "Bloquear aplicaciones"
                ) {
                    model.toggleLock()
                }
                .buttonStyle(.borderedProminent)
                .tint(model.isLocked ? .orange : .indigo)

                Button("Leer etiqueta NFC") {
                    nfc.onValidTag = {
                        Task { @MainActor in
                            model.handleNFC()
                        }
                    }
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
            .onChange(of: model.selection) { _ in
                model.saveSelection()
            }
            .navigationTitle("Concentración")
        }
    }
}
