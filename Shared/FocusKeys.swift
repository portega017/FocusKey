//
//  FocusKeys.swift
//  FocusKey
//
//  Cards registered as keys by their chip identifier (UID): useful as a backup for cards that
//  can't be written, like a transit card. Only a SHA-256 hash of the identifier is stored.
//  Written tags with the `FOCUSKEY:TOGGLE` text record are always keys as well.
//

import CryptoKit
import Foundation

nonisolated struct CardKey: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    /// Hex SHA-256 of the card's identifier.
    var uidHash: String
    var added: Date

    init(id: UUID = UUID(), name: String, uid: Data, added: Date = .now) {
        self.id = id
        self.name = name
        self.uidHash = Self.hash(uid)
        self.added = added
    }

    var displayName: String { name.isEmpty ? String(localized: "Tarjeta") : name }

    static func hash(_ uid: Data) -> String {
        SHA256.hash(data: uid).map { String(format: "%02x", $0) }.joined()
    }

    /// Cards that send a different random identifier on every read (a privacy feature of some
    /// transit and bank cards) can't be used: 4-byte ISO 14443 random IDs start with 0x08.
    static func isRandomUID(_ uid: Data) -> Bool {
        uid.count == 4 && uid.first == 0x08
    }
}

nonisolated extension FocusStore {
    static func cardKeys() -> [CardKey] {
        guard let data = defaults.data(forKey: Key.cardKeys) else { return [] }
        return (try? JSONDecoder().decode([CardKey].self, from: data)) ?? []
    }

    static func saveCardKeys(_ keys: [CardKey]) {
        if let data = try? JSONEncoder().encode(keys) {
            defaults.set(data, forKey: Key.cardKeys)
        }
    }

    static func isCardKey(_ uid: Data) -> Bool {
        let hash = CardKey.hash(uid)
        return cardKeys().contains { $0.uidHash == hash }
    }
}
