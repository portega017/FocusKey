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

    struct Item: Identifiable {
        var id: String
        var name: String
        var token: ApplicationToken?
        var duration: TimeInterval
        var pickups: Int
    }

    var days: [Day]
    var items: [Item]

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

        for await device in data {
            for await segment in device.activitySegments {
                let day = calendar.startOfDay(for: segment.dateInterval.start)
                perDay[day, default: 0] += segment.totalActivityDuration

                for await category in segment.categories {
                    for await activity in category.applications {
                        let app = activity.application
                        let name = app.localizedDisplayName ?? app.bundleIdentifier ?? String(localized: "App")
                        let key = app.bundleIdentifier ?? name
                        var item = items[key] ?? .init(id: key, name: name, token: app.token, duration: 0, pickups: 0)
                        item.duration += activity.totalActivityDuration
                        item.pickups += activity.numberOfPickups
                        items[key] = item
                    }
                    for await activity in category.webDomains {
                        let name = activity.webDomain.domain ?? String(localized: "Web")
                        var item = items[name] ?? .init(id: name, name: name, token: nil, duration: 0, pickups: 0)
                        item.duration += activity.totalActivityDuration
                        items[name] = item
                    }
                }
            }
        }

        // The last seven days, oldest first, including days without use.
        let today = calendar.startOfDay(for: .now)
        let days = (0..<7).reversed().compactMap { offset -> ProfileUsage.Day? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return .init(date: date, duration: perDay[date] ?? 0)
        }
        let sorted = items.values.filter { $0.duration >= 60 }.sorted { $0.duration > $1.duration }
        return ProfileUsage(days: days, items: Array(sorted.prefix(10)))
    }
}

// MARK: - View

struct UsageReportView: View {
    let usage: ProfileUsage

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

            Text("Más usadas")
                .font(.headline)

            if usage.items.isEmpty {
                Text("Sin uso registrado en estos días.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ForEach(usage.items) { item in
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
                        if item.pickups > 0 {
                            Text("Abierta \(item.pickups) veces")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(Self.format(item.duration))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
