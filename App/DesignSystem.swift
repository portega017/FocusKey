//
//  DesignSystem.swift
//  FocusKey
//
//  Shared look of the app. Rule of thumb: the four tabs are glass cards over the grouped
//  background; secondary screens (editors, profiles, settings) are native lists and forms.
//  Accent: the AccentColor asset (system blue). Profile colors are used where a profile is involved.
//

import SwiftUI

enum Design {
    static let cardRadius: CGFloat = 24
    static let innerRadius: CGFloat = 14
    static let cardPadding: CGFloat = 18
    /// Space between cards on a screen.
    static let cardSpacing: CGFloat = 16
    /// Space between blocks inside a card.
    static let contentSpacing: CGFloat = 14
}

// MARK: - Card

extension View {
    /// Glass card used by every tab.
    func card(padding: CGFloat = Design.cardPadding, tint: Color? = nil) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(tint.map { .regular.tint($0.opacity(0.15)) } ?? .regular, in: .rect(cornerRadius: Design.cardRadius))
    }

    /// Grouped background shared by the tabs.
    func screenBackground() -> some View {
        background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
    }
}

/// Title row of a card, with an optional trailing action.
struct CardHeader<Trailing: View>: View {
    let title: LocalizedStringKey
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            trailing
                .font(.subheadline.weight(.medium))
        }
    }
}

extension CardHeader where Trailing == EmptyView {
    init(_ title: LocalizedStringKey, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

extension CardHeader {
    init(_ title: LocalizedStringKey, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.init(title: title, subtitle: subtitle, trailing: trailing)
    }
}

// MARK: - Badges and icons

/// Small capsule with a state ("En curso", "Activo"…).
struct StatusBadge: View {
    let text: String
    var color: Color = .secondary
    var symbol: String?

    var body: some View {
        Label {
            Text(text)
        } icon: {
            if let symbol { Image(systemName: symbol) }
        }
        .labelStyle(.titleAndIcon)
        .font(.caption.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.14), in: Capsule())
        .fixedSize()
    }
}

/// Profile symbol on its color, used in every row that refers to a profile.
struct ProfileIcon: View {
    let symbol: String
    var color: Color = .indigo
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Big rounded number used by tiles and summaries.
struct MetricText: View {
    let value: String
    var font: Font = .title2

    var body: some View {
        Text(value)
            .font(font.weight(.bold))
            .fontDesign(.rounded)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .contentTransition(.numericText())
    }
}

/// Compact metric: caption title over a big number.
struct MetricTile: View {
    let title: LocalizedStringKey
    let value: String
    var symbol: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label {
                Text(title)
            } icon: {
                if let symbol { Image(systemName: symbol) }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            MetricText(value: value, font: .title3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Toast

/// Short-lived message shown over any tab (replaces the old status line).
struct Toast: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.subheadline.weight(.medium))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .glassEffect(.regular, in: .capsule)
            .padding(.horizontal, 24)
            .accessibilityAddTraits(.updatesFrequently)
    }
}
