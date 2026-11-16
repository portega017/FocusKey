//
//  CardKeysView.swift
//  FocusKey
//
//  Registering cards that can't be written (a transit card, for example) as backup keys.
//

import SwiftUI

/// Name, then two reads of the card: the identifier must be the same both times.
struct AddCardSheet: View {
    @EnvironmentObject private var model: FocusModel
    @EnvironmentObject private var nfc: NFCScanner
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Tarjeta del metro, del gimnasio…", text: $name)
                } header: {
                    Text("Nombre")
                }

                Section {
                    Label("Acerca la tarjeta dos veces para comprobar que siempre da el mismo identificador.", systemImage: "wave.3.right")
                    if let blocked = model.cardAddBlockedReason {
                        Label(blocked, systemImage: "lock.fill")
                            .foregroundStyle(.orange)
                    } else if let problem {
                        Label(problem, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                } footer: {
                    Text("FocusKey no graba nada en la tarjeta: solo guarda una huella de su identificador. Algunas tarjetas de transporte o bancarias cambian de identificador en cada lectura y no sirven.")
                }
            }
            .navigationTitle("Añadir tarjeta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Escanear", action: scan)
                        .disabled(model.cardAddBlockedReason != nil)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func scan() {
        problem = nil
        nfc.readIdentifier(message: String(localized: "Acerca la tarjeta al iPhone.")) { first in
            guard let first else { return }
            guard !CardKey.isRandomUID(first) else {
                problem = String(localized: "Esta tarjeta cambia de identificador en cada lectura y no puede usarse como llave.")
                return
            }
            // A second read confirms the identifier is stable. The pause lets the first sheet close.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                nfc.readIdentifier(message: String(localized: "Vuelve a acercarla para confirmar.")) { second in
                    guard let second else { return }
                    guard second == first else {
                        problem = String(localized: "Esta tarjeta cambia de identificador en cada lectura y no puede usarse como llave.")
                        return
                    }
                    // Errors stay in the sheet, next to the card being added.
                    if let error = model.addCard(name: name.trimmingCharacters(in: .whitespaces), uid: first) {
                        problem = error
                    } else {
                        dismiss()
                    }
                }
            }
        }
    }
}
