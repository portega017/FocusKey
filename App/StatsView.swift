//
//  StatsView.swift
//  FocusKey
//
//  Time blocked per day and streak, from the records the app
//  and the monitor extension write to the App Group.
//  Opening attempts can't be counted: iOS doesn't let shield extensions write any data.
//

import SwiftUI
import Charts

struct StatsView: View {
    @EnvironmentObject private var model: FocusModel
    @State private var selectedDay: Date?

    var body: some View {
        NavigationStack {
            ScrollView {
                let stats = FocusStats(records: model.records)
                VStack(spacing: 16) {
                    HStack(spacing: 12) {
                        StatTile(title: "Hoy", value: FocusStats.format(minutes: stats.today), symbol: "lock.fill")
                        StatTile(title: "Racha", value: "\(stats.streak) \(stats.streak == 1 ? "día" : "días")", symbol: "flame.fill")
                    }
                    StatTile(title: "Últimos 7 días", value: FocusStats.format(minutes: stats.week.map(\.minutes).reduce(0, +)), symbol: "calendar")

                    chart(stats.week)

                    recent(stats.recent)
                }
                .padding()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Estadísticas")
            .refreshable { model.reload() }
        }
    }

    private func chart(_ week: [FocusStats.Day]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tiempo bloqueado")
                .font(.headline)

            if let day = selectedDay.flatMap({ date in week.first { Calendar.current.isDate($0.date, inSameDayAs: date) } }) {
                Text("\(day.date.formatted(.dateTime.weekday(.wide).day().month())): \(FocusStats.format(minutes: day.minutes))")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                Text("Toca una barra para ver el detalle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Chart(week) { day in
                BarMark(
                    x: .value("Día", day.date, unit: .day),
                    y: .value("Horas", Double(day.minutes) / 60),
                    width: .ratio(0.55)
                )
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4))
                .foregroundStyle(Color.indigo.opacity(selectedDay == nil || Calendar.current.isDate(day.date, inSameDayAs: selectedDay!) ? 1 : 0.35))
                .accessibilityLabel(day.date.formatted(.dateTime.weekday(.wide)))
                .accessibilityValue(FocusStats.format(minutes: day.minutes))
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
            .chartXSelection(value: $selectedDay)
            .frame(height: 200)
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func recent(_ records: [BlockRecord]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Bloqueos recientes")
                .font(.headline)

            if records.isEmpty {
                Text("Aún no hay bloqueos registrados.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ForEach(records) { record in
                HStack(spacing: 12) {
                    Image(systemName: record.kind.symbol)
                        .foregroundStyle(.indigo)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.title).font(.subheadline.weight(.medium))
                        Text("\(record.kind.label) · \(record.start.formatted(.dateTime.weekday().day().hour().minute()))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(record.end == nil ? "En curso" : FocusStats.format(minutes: Int((record.end ?? .now).timeIntervalSince(record.start) / 60)))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct StatTile: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.bold().monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Computation

struct FocusStats {
    struct Day: Identifiable {
        var date: Date
        var minutes: Int
        var id: Date { date }
    }

    let week: [Day]
    let today: Int
    let streak: Int
    let recent: [BlockRecord]

    init(records: [BlockRecord], now: Date = .now, calendar: Calendar = .current) {
        let intervals = Self.merged(records.map { ($0.start, min($0.end ?? now, now)) })
        let todayStart = calendar.startOfDay(for: now)

        func minutes(on dayStart: Date) -> Int {
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            let seconds = intervals.reduce(0.0) { total, interval in
                let start = max(interval.0, dayStart)
                let end = min(interval.1, dayEnd)
                return total + max(0, end.timeIntervalSince(start))
            }
            return Int(seconds / 60)
        }

        week = (0..<7).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: todayStart).map { Day(date: $0, minutes: minutes(on: $0)) }
        }
        today = minutes(on: todayStart)

        // Consecutive days with at least one minute blocked; today counts only once it has some.
        var streak = 0
        var day = today > 0 ? todayStart : calendar.date(byAdding: .day, value: -1, to: todayStart)!
        while minutes(on: day) > 0, streak < 365 {
            streak += 1
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        self.streak = streak

        recent = Array(records.sorted { $0.start > $1.start }.prefix(15))
    }

    /// Overlapping blocks (e.g. a schedule during a manual lock) count once.
    private static func merged(_ intervals: [(Date, Date)]) -> [(Date, Date)] {
        var result: [(Date, Date)] = []
        for interval in intervals.filter({ $0.1 > $0.0 }).sorted(by: { $0.0 < $1.0 }) {
            if let last = result.last, interval.0 <= last.1 {
                result[result.count - 1].1 = max(last.1, interval.1)
            } else {
                result.append(interval)
            }
        }
        return result
    }

    static func format(minutes: Int) -> String {
        minutes < 60 ? "\(minutes) min" : UsageLimit.formatted(minutes: minutes)
    }
}
