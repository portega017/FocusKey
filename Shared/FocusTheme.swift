//
//  FocusTheme.swift
//  FocusKey
//
//  Profile colors and motivational lines, shared by the app, widgets and shield screen.
//

import SwiftUI

nonisolated enum FocusPalette {
    /// Order shown in the profile editor; new profiles take the next unused one.
    static let names = ["indigo", "blue", "teal", "green", "orange", "red", "pink", "purple", "brown", "gray"]

    static func color(_ name: String) -> Color {
        switch name {
        case "blue": return .blue
        case "teal": return .teal
        case "green": return .green
        case "orange": return .orange
        case "red": return .red
        case "pink": return .pink
        case "purple": return .purple
        case "brown": return .brown
        case "gray": return .gray
        default: return .indigo
        }
    }

    /// First color not used by `profiles`, so new profiles look different by default.
    static func nextName(after profiles: [FocusProfile]) -> String {
        let used = Set(profiles.map(\.colorName))
        return names.first { !used.contains($0) } ?? names[profiles.count % names.count]
    }

    static func accessibilityName(_ name: String) -> String {
        switch name {
        case "blue": return String(localized: "Azul")
        case "teal": return String(localized: "Verde azulado")
        case "green": return String(localized: "Verde")
        case "orange": return String(localized: "Naranja")
        case "red": return String(localized: "Rojo")
        case "pink": return String(localized: "Rosa")
        case "purple": return String(localized: "Morado")
        case "brown": return String(localized: "Marrón")
        case "gray": return String(localized: "Gris")
        default: return String(localized: "Índigo")
        }
    }
}

extension FocusProfile {
    var color: Color { FocusPalette.color(colorName) }
}

nonisolated enum FocusQuotes {
    static var all: [String] {
        [
            String(localized: "Lo que haces hoy cuenta más que lo que harás mañana."),
            String(localized: "Diez minutos de foco valen más que una hora de distracciones."),
            String(localized: "Tu atención es tuya. Decide tú dónde ponerla."),
            String(localized: "La app seguirá ahí luego. Este momento no."),
            String(localized: "Pequeños bloques, grandes resultados."),
            String(localized: "Respira. Vuelve a lo que estabas haciendo."),
            String(localized: "Cada vez que resistes, el hábito se hace más fuerte."),
            String(localized: "Menos pantalla, más vida.")
        ]
    }

    /// Changes every hour, so repeated attempts don't always show the same line.
    static func current(at date: Date = .now) -> String {
        let hours = Int(date.timeIntervalSinceReferenceDate / 3600)
        return all[hours % all.count]
    }
}
