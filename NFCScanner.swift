//
 //  NFCScanner.swift
 //  FocusKey
 //
 //  Created by pibol on 14/10/2026.
 //


 import Foundation
 import Combine
 import CoreNFC

 final class NFCScanner: NSObject,
                         ObservableObject,
                         NFCNDEFReaderSessionDelegate {
     private var session: NFCNDEFReaderSession?
     var onValidTag: (() -> Void)?

     func start() {
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
                 self.onValidTag?()
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

                 return text == "FOCUSKEY:TOGGLE"
             }
     }

     func readerSession(
         _ session: NFCNDEFReaderSession,
         didInvalidateWithError error: Error
     ) {
         self.session = nil
     }
 }
