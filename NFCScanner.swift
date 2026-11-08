//
 //  NFCScanner.swift
 //  FocusKey
 //
 //


 import Foundation
 import Combine
 import CoreNFC

 final class NFCScanner: NSObject,
                         ObservableObject,
                         NFCNDEFReaderSessionDelegate {
     private var session: NFCNDEFReaderSession?
     /// Text record a FocusKey tag must contain.
     static let tagText = "FOCUSKEY:TOGGLE"

     var onValidTag: (() -> Void)?
     /// Runs instead of `onValidTag` for the next scan only (e.g. extending a limit).
     private var oneShot: (() -> Void)?

     /// Scans and runs `action` instead of the default toggle if the tag is valid.
     func start(then action: @escaping () -> Void) {
         start()
         oneShot = action
     }

     func start() {
         oneShot = nil
         // Invalidate any existing session before starting a new one
         session?.invalidate()
         session = nil

         guard NFCNDEFReaderSession.readingAvailable else {
             return
         }

         let reader = NFCNDEFReaderSession(
             delegate: self,
             queue: nil,
             invalidateAfterFirstRead: true
         )

         reader.alertMessage = "Acerca tu etiqueta FocusKey al iPhone."
         session = reader
         reader.begin()
     }

     func readerSession(
         _ session: NFCNDEFReaderSession,
         didDetectNDEFs messages: [NFCNDEFMessage]
     ) {
         if isValidFocusKeyTag(from: messages) {
             DispatchQueue.main.async {
                 let action = self.oneShot ?? self.onValidTag
                 self.oneShot = nil
                 action?()
             }
             session.alertMessage = "Etiqueta FocusKey reconocida."
         } else {
             session.alertMessage = "La etiqueta no es una llave FocusKey válida."
         }
     }

     private func isValidFocusKeyTag(from messages: [NFCNDEFMessage]) -> Bool {
         messages
             .flatMap(\.records)
             .contains { record in
                 guard record.typeNameFormat == .nfcWellKnown,
                       String(data: record.type, encoding: .utf8) == "T",
                       let first = record.payload.first
                 else {
                     return false
                 }

                 let languageLength = Int(first & 0x3F)
                 let start = 1 + languageLength

                 guard record.payload.count >= start,
                       let text = String(
                         data: record.payload.dropFirst(start),
                         encoding: .utf8
                       )
                 else {
                     return false
                 }

                 return text == Self.tagText
             }
     }

     func readerSession(
         _ session: NFCNDEFReaderSession,
         didInvalidateWithError error: Error
     ) {
         DispatchQueue.main.async {
             // Ignore an older session invalidated by start(): it must not clear the new action.
             guard self.session == nil || self.session === session else { return }
             self.session = nil
             // Cancelled or failed: the next scan does the default action again.
             self.oneShot = nil
         }
     }
 }
