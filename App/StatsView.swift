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
                        StatTile(title: "Racha", value: String(localized: "\(stats.streak) días"), symbol: "flame.fill")
                    }
                    StatTile(title: "Últimos 7 días", value: FocusStats.format(minutes: stats.week.map(\.minutes).reduce(0, +)), symbol: "calendar")

                    chart(stats.week)

                    MonthHeatmap(days: stats.calendarDays)

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
        .padding(20)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
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
                    Text(record.end == nil ? String(localized: "En curso") : FocusStats.format(minutes: Int((record.end ?? .now).timeIntervalSince(record.start) / 60)))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
    }
}

private struct StatTile: View {
    let title: LocalizedStringKey
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
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Calendar heatmap

/// Five weeks, one cell per day; darker = more time blocked. Single hue, light to dark.
private struct MonthHeatmap: View {
    let days: [FocusStats.Day]
    @State private var selected: Date?

    /// Upper bounds in minutes for each shade (0 = nothing blocked).
    private static let levels = [0, 30, 60, 120, 240]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Últimas 5 semanas")
                .font(.headline)

            if let selected, let day = days.first(where: { Calendar.current.isDate($0.date, inSameDayAs: selected) }) {
                Text("\(day.date.formatted(.dateTime.weekday(.wide).day().month())): \(FocusStats.format(minutes: day.minutes))")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                Text("Toca un día para ver el detalle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
            LazyVGrid(columns: columns, spacing: 6) {
                // Initials repeat (e.g. two "M"s), so identify them by position.
                ForEach(Array(Self.weekdayInitials.enumerated()), id: \.offset) { _, initial in
                    Text(initial)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                ForEach(days) { day in
                    cell(day)
                }
            }

            HStack(spacing: 4) {
                Text("Menos").font(.caption2).foregroundStyle(.secondary)
                ForEach(0..<Self.levels.count, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Self.shade(level))
                        .frame(width: 12, height: 12)
                }
                Text("Más").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityHidden(true)
        }
        .padding(20)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
    }

    private func cell(_ day: FocusStats.Day) -> some View {
        let isFuture = day.date > .now
        let isToday = Calendar.current.isDateInToday(day.date)
        let isSelected = selected.map { Calendar.current.isDate(day.date, inSameDayAs: $0) } ?? false
        return RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(isFuture ? Color.clear : Self.shade(Self.level(for: day.minutes)))
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(isSelected ? Color.primary : (isToday ? Color.indigo : .clear), lineWidth: 2)
            }
            .contentShape(Rectangle())
            .onTapGesture { if !isFuture { selected = isSelected ? nil : day.date } }
            .accessibilityElement()
            .accessibilityLabel(day.date.formatted(.dateTime.weekday(.wide).day().month()))
            .accessibilityValue(isFuture ? "" : FocusStats.format(minutes: day.minutes))
            .accessibilityHidden(isFuture)
    }

    private static func level(for minutes: Int) -> Int {
        guard minutes > 0 else { return 0 }
        return (1..<levels.count).first { minutes <= levels[$0] } ?? levels.count - 1
    }

    private static func shade(_ level: Int) -> Color {
        level == 0 ? Color.secondary.opacity(0.12) : Color.indigo.opacity([0, 0.3, 0.5, 0.72, 1][level])
    }

    private static var weekdayInitials: [String] {
        let symbols = Calendar.current.veryShortStandaloneWeekdaySymbols
        return Array(symbols[1...] + symbols[..<1])
    }
}
