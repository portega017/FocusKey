//
//  FocusKeyReport.swift
//  FocusKeyReport
//
//  DeviceActivityReport extension: real usage (Screen Time data) of the apps in a profile.
//  iOS only lets this extension see the data, and it can't send anything back to the app,
//  so everything it shows is computed here. The app picks the profile through the filter.
//

import Charts
import DeviceActivity
import ExtensionKit
import FamilyControls
import ManagedSettings
import SwiftUI

@main
struct FocusKeyReport: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        UsageReport { UsageReportView(usage: $0) }
    }
}

extension DeviceActivityReport.Context {
    /// Must match the context used by the app (App/StatsView.swift).
    static let usage = Self("FocusKeyUsage")
}

// MARK: - Data

nonisolated struct ProfileUsage {
    struct Day: Identifiable {
        var date: Date
        var duration: TimeInterval
        var id: Date { date }
    }

    /// Period the "most used" list covers.
    enum Period: Hashable {
        case today, week
    }

    struct Item: Identifiable {
        var id: String
        var name: String
        var token: ApplicationToken?
        var todayDuration: TimeInterval = 0
        var todayPickups = 0
        var weekDuration: TimeInterval = 0
        var weekPickups = 0

        func duration(_ period: Period) -> TimeInterval {
            period == .today ? todayDuration : weekDuration
        }

        func pickups(_ period: Period) -> Int {
            period == .today ? todayPickups : weekPickups
        }
    }

    var days: [Day]
    var items: [Item]

    /// The ten most used items in the period (at least one minute).
    func top(_ period: Period) -> [Item] {
        Array(items.filter { $0.duration(period) >= 60 }.sorted { $0.duration(period) > $1.duration(period) }.prefix(10))
    }

    var today: TimeInterval { days.last?.duration ?? 0 }
    var total: TimeInterval { days.reduce(0) { $0 + $1.duration } }
}

nonisolated struct UsageReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .usage
    let content: (ProfileUsage) -> UsageReportView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> ProfileUsage {
        let calendar = Calendar.current
        var perDay: [Date: TimeInterval] = [:]
        var items: [String: ProfileUsage.Item] = [:]
        let today = calendar.startOfDay(for: .now)

        for await device in data {
            for await segment in device.activitySegments {
                let day = calendar.startOfDay(for: segment.dateInterval.start)
                let isToday = day == today
                // The segment total is the whole device's use, not just the filtered apps,
                // so the day total is the sum of the profile's apps and websites.

                for await category in segment.categories {
                    for await activity in category.applications {
                        let app = activity.application
                        let name = app.localizedDisplayName ?? app.bundleIdentifier ?? String(localized: "App")
                        let key = app.bundleIdentifier ?? name
                        var item = items[key] ?? .init(id: key, name: name, token: app.token)
                        item.weekDuration += activity.totalActivityDuration
                        item.weekPickups += activity.numberOfPickups
                        perDay[day, default: 0] += activity.totalActivityDuration
                        if isToday {
                            item.todayDuration += activity.totalActivityDuration
                            item.todayPickups += activity.numberOfPickups
                        }
                        items[key] = item
                    }
                    for await activity in category.webDomains {
                        let name = activity.webDomain.domain ?? String(localized: "Web")
                        var item = items[name] ?? .init(id: name, name: name, token: nil)
                        item.weekDuration += activity.totalActivityDuration
                        perDay[day, default: 0] += activity.totalActivityDuration
                        if isToday { item.todayDuration += activity.totalActivityDuration }
                        items[name] = item
                    }
                }
            }
        }

        // The last seven days, oldest first, including days without use.
        let days = (0..<7).reversed().compactMap { offset -> ProfileUsage.Day? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return .init(date: date, duration: perDay[date] ?? 0)
        }
        return ProfileUsage(days: days, items: Array(items.values))
    }
}

// MARK: - View

struct UsageReportView: View {
    let usage: ProfileUsage
    @State private var period: ProfileUsage.Period = .today

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                tile(String(localized: "Hoy"), usage.today)
                tile(String(localized: "Últimos 7 días"), usage.total)
            }

            Chart(usage.days) { day in
                BarMark(
                    x: .value("Día", day.date, unit: .day),
                    y: .value("Horas", day.duration / 3600),
                    width: .ratio(0.55)
                )
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4))
                .foregroundStyle(Color.orange)
                .accessibilityLabel(day.date.formatted(.dateTime.weekday(.wide)))
                .accessibilityValue(Self.format(day.duration))
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(.secondary.opacity(0.25))
                    AxisValueLabel {
                        if let hours = value.as(Double.self) { Text("\(hours, format: .number.precision(.fractionLength(0...1))) h") }
                    }
                }
            }
            .frame(height: 150)

            HStack {
                Text("Más usadas")
                    .font(.headline)
                Spacer()
                Picker(String(localized: "Periodo"), selection: $period) {
                    Text("Hoy").tag(ProfileUsage.Period.today)
                    Text("7 días").tag(ProfileUsage.Period.week)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }

            let top = usage.top(period)
            if top.isEmpty {
                Text(period == .today ? String(localized: "Sin uso registrado hoy.") : String(localized: "Sin uso registrado en estos días."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ForEach(top) { item in
                HStack(spacing: 12) {
                    if let token = item.token {
                        Label(token)
                            .labelStyle(.iconOnly)
                            .frame(width: 28, height: 28)
                    } else {
                        Image(systemName: "globe")
                            .frame(width: 28, height: 28)
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        Text(subtitle(item))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(Self.format(item.duration(period)))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Says which period the row covers, with the number of pickups when known.
    private func subtitle(_ item: ProfileUsage.Item) -> String {
        let pickups = item.pickups(period)
        switch (period, pickups > 0) {
        case (.today, true): return String(localized: "Hoy · abierta \(pickups) veces")
        case (.today, false): return String(localized: "Hoy")
        case (.week, true): return String(localized: "7 días · abierta \(pickups) veces")
        case (.week, false): return String(localized: "Últimos 7 días")
        }
    }

    private func tile(_ title: String, _ duration: TimeInterval) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(Self.format(duration))
                .font(.title3.bold().monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    static func format(_ duration: TimeInterval) -> String {
        Duration.seconds(duration).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}
