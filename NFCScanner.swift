//
//  NFCScanner.swift
//  FocusKey
//
//  Reads the NFC key. A tag is a valid key if it is a card registered by its identifier
//  (FocusStore.cardKeys) or a written tag with the `FOCUSKEY:TOGGLE` text record.
//  Uses NFCTagReaderSession, which gives the chip identifier and can still read NDEF.
//

import Foundation
import Combine
import CoreNFC

final class NFCScanner: NSObject, ObservableObject, NFCTagReaderSessionDelegate {
    private var session: NFCTagReaderSession?
    /// Text record a written FocusKey tag must contain.
    static let tagText = "FOCUSKEY:TOGGLE"

    var onValidTag: (() -> Void)?
    /// Runs instead of `onValidTag` for the next scan only (e.g. extending a limit).
    private var oneShot: (() -> Void)?
    /// Set while registering a card: receives its identifier instead of validating it.
    private var identifierReader: ((Data?) -> Void)?

    /// Scans and runs `action` instead of the default toggle if the tag is valid.
    func start(message: String? = nil, then action: @escaping () -> Void) {
        start(message: message)
        oneShot = action
    }

    func start(message: String? = nil) {
        begin(message: message ?? String(localized: "Acerca tu etiqueta FocusKey al iPhone."))
    }

    /// Reads a card's identifier (nil if cancelled or unreadable), to register it as a key.
    func readIdentifier(message: String, completion: @escaping (Data?) -> Void) {
        begin(message: message)
        identifierReader = completion
    }

    private func begin(message: String) {
        oneShot = nil
        identifierReader = nil
        // Invalidate any existing session before starting a new one.
        session?.invalidate()
        session = nil

        guard NFCTagReaderSession.readingAvailable else { return }
        // ISO 14443 covers written tags and most transit cards; ISO 15693 covers vicinity tags.
        let configuration = NFCTagReaderSession.Configuration(pollingOption: [.iso14443, .iso15693])
        let reader = NFCTagReaderSession(configuration: configuration, delegate: self, queue: nil)
        reader.alertMessage = message
        session = reader
        reader.begin()
    }

    // MARK: NFCTagReaderSessionDelegate

    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {}

    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard let tag = tags.first else { return }
        if tags.count > 1 {
            session.alertMessage = String(localized: "Acerca solo una etiqueta.")
            session.restartPolling()
            return
        }
        let identifier = Self.identifier(of: tag)

        if identifierReader != nil {
            session.alertMessage = String(localized: "Tarjeta leída.")
            session.invalidate()
            DispatchQueue.main.async {
                let reader = self.identifierReader
                self.identifierReader = nil
                reader?(identifier)
            }
            return
        }

        if let identifier, FocusStore.isCardKey(identifier) {
            accept(session)
            return
        }

        // Not a registered card: look for the FocusKey text record.
        session.connect(to: tag) { error in
            guard error == nil, let ndef = Self.ndefTag(tag) else {
                self.reject(session)
                return
            }
            ndef.readNDEF { message, _ in
                if let message, Self.containsKeyText(message) {
                    self.accept(session)
                } else {
                    self.reject(session)
                }
            }
        }
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        DispatchQueue.main.async {
            // Ignore an older session invalidated by begin(): it must not clear the new action.
            guard self.session == nil || self.session === session else { return }
            self.session = nil
            // Cancelled or failed: the next scan does the default action again.
            self.oneShot = nil
            if let reader = self.identifierReader {
                self.identifierReader = nil
                reader(nil)
            }
        }
    }

    // MARK: Helpers

    private func accept(_ session: NFCTagReaderSession) {
        session.alertMessage = String(localized: "Llave FocusKey reconocida.")
        session.invalidate()
        DispatchQueue.main.async {
            let action = self.oneShot ?? self.onValidTag
            self.oneShot = nil
            action?()
        }
    }

    private func reject(_ session: NFCTagReaderSession) {
        session.invalidate(errorMessage: String(localized: "La etiqueta no es una llave FocusKey válida."))
    }

    static func identifier(of tag: NFCTag) -> Data? {
        switch tag {
        case .miFare(let tag): return tag.identifier
        case .iso7816(let tag): return tag.identifier
        case .iso15693(let tag): return tag.identifier
        case .feliCa(let tag): return tag.currentIDm
        @unknown default: return nil
        }
    }

    private static func ndefTag(_ tag: NFCTag) -> NFCNDEFTag? {
        switch tag {
        case .miFare(let tag): return tag
        case .iso7816(let tag): return tag
        case .iso15693(let tag): return tag
        case .feliCa(let tag): return tag
        @unknown default: return nil
        }
    }

    /// Whether the message has a Well Known Text record whose text is exactly `tagText`.
    static func containsKeyText(_ message: NFCNDEFMessage) -> Bool {
        message.records.contains { record in
            guard record.typeNameFormat == .nfcWellKnown,
                  String(data: record.type, encoding: .utf8) == "T",
                  let first = record.payload.first
            else { return false }
            let start = 1 + Int(first & 0x3F)
            guard record.payload.count >= start,
                  let text = String(data: record.payload.dropFirst(start), encoding: .utf8)
            else { return false }
            return text == tagText
        }
    }
}
