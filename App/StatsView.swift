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
                    Text(record.end == nil ? String(localized: "En curso") : FocusStats.format(minutes: Int((record.end ?? .now).timeIntervalSince(record.start) / 60)))
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
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
