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
import DeviceActivity
import FamilyControls

extension DeviceActivityReport.Context {
    /// Must match the context in the report extension (FocusKeyReport/FocusKeyReport.swift).
    static let usage = Self("FocusKeyUsage")
}

struct StatsView: View {
    @EnvironmentObject private var model: FocusModel
    @State private var selectedDay: Date?
    @State private var usageProfileID: UUID?

    var body: some View {
        NavigationStack {
            ScrollView {
                let stats = FocusStats(records: model.records, archive: model.dailyArchive, archivedUntil: model.archivedUntil)
                VStack(spacing: 16) {
                    HStack(spacing: 12) {
                        StatTile(title: "Hoy", value: FocusStats.format(minutes: stats.today), symbol: "lock.fill")
                        StatTile(title: "Racha", value: String(localized: "\(stats.streak) días"), symbol: "flame.fill")
                    }
                    StatTile(title: "Últimos 7 días", value: FocusStats.format(minutes: stats.week.map(\.minutes).reduce(0, +)), symbol: "calendar")

                    if !model.revocations.isEmpty {
                        revocationsCard
                    }

                    chart(stats.week)

                    MonthHeatmap(days: stats.calendarDays)

                    YearOverview(counter: FocusStats.DayCounter(
                        records: model.records, archive: model.dailyArchive, archivedUntil: model.archivedUntil
                    ))

                    usage

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

    // MARK: Screen Time permission

    /// Every time the permission was found revoked: the one way left to escape a block.
    private var revocationsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Permiso de Screen Time retirado", systemImage: "exclamationmark.shield.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text(String(localized: "\(model.revocations.count) veces en los últimos 60 días"))
                .font(.title3.bold().monospacedDigit())
            if let last = model.revocations.last {
                Text("La última, \(last.formatted(.dateTime.weekday(.wide).day().month().hour().minute())).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
    }

    // MARK: Real usage

    private var usageProfile: FocusProfile? { model.profile(usageProfileID ?? model.activeProfileID) }

    /// Screen Time usage of the profile's apps, drawn by the report extension.
    private var usage: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Uso real")
                    .font(.headline)
                Spacer()
                Picker("Perfil", selection: Binding(get: { usageProfile?.id }, set: { usageProfileID = $0 })) {
                    ForEach(model.profiles) { profile in
                        Label(profile.displayName, systemImage: profile.symbol).tag(Optional(profile.id))
                    }
                }
                .pickerStyle(.menu)
            }

            if let profile = usageProfile, !profile.isEmpty, model.isAuthorized {
                DeviceActivityReport(.usage, filter: Self.filter(for: profile))
                    .frame(minHeight: 520)
            } else {
                Text(model.isAuthorized ? String(localized: "Este perfil no tiene apps seleccionadas.") : String(localized: "Autoriza Screen Time para ver tu uso."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("Tiempo que has usado las apps de este perfil según Screen Time, no el tiempo bloqueado. Estos datos no salen de tu iPhone.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
    }

    private static func filter(for profile: FocusProfile) -> DeviceActivityFilter {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: .now)) ?? .now
        return DeviceActivityFilter(
            segment: .daily(during: DateInterval(start: start, end: .now)),
            users: .all,
            devices: .init([.iPhone]),
            applications: profile.selection.applicationTokens,
            categories: profile.selection.categoryTokens,
            webDomains: profile.selection.webDomainTokens
        )
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

    fileprivate static func level(for minutes: Int) -> Int {
        guard minutes > 0 else { return 0 }
        return (1..<levels.count).first { minutes <= levels[$0] } ?? levels.count - 1
    }

    fileprivate static func shade(_ level: Int) -> Color {
        level == 0 ? Color.secondary.opacity(0.12) : Color.indigo.opacity([0, 0.3, 0.5, 0.72, 1][level])
    }

    private static var weekdayInitials: [String] {
        let symbols = Calendar.current.veryShortStandaloneWeekdaySymbols
        return Array(symbols[1...] + symbols[..<1])
    }
}

// MARK: - Year

/// Focus time over a whole year: totals, months and one cell per day.
private struct YearOverview: View {
    let counter: FocusStats.DayCounter
    @State private var year = Calendar.current.component(.year, from: .now)
    @State private var selected: Date?

    var body: some View {
        let stats = FocusYearStats(year: year, counter: counter)
        let years = counter.years()

        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Concentración en el año")
                    .font(.headline)
                Spacer()
                if years.count > 1 {
                    Picker("Año", selection: $year) {
                        ForEach(years, id: \.self) { Text(verbatim: String($0)).tag($0) }
                    }
                    .pickerStyle(.menu)
                } else {
                    Text(verbatim: String(year))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Text(FocusStats.format(minutes: stats.total))
                .font(.largeTitle.bold().monospacedDigit())
                .contentTransition(.numericText())
                .accessibilityLabel(String(localized: "Total del año: \(FocusStats.format(minutes: stats.total))"))

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    summary("Media al día", FocusStats.format(minutes: stats.dailyAverage))
                    summary("Días con foco", String(stats.activeDays))
                }
                GridRow {
                    summary("Mejor día", stats.bestDay.map { FocusStats.format(minutes: $0.minutes) } ?? "—")
                    summary("Fecha", stats.bestDay.map { $0.date.formatted(.dateTime.day().month()) } ?? "—")
                }
            }

            monthChart(stats.months)

            dayGrid(stats.days)

            if let selected, let day = stats.days.first(where: { Calendar.current.isDate($0.date, inSameDayAs: selected) }) {
                Text("\(day.date.formatted(.dateTime.weekday(.wide).day().month())): \(FocusStats.format(minutes: day.minutes))")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                Text("Toca un día para ver el detalle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
        .animation(.smooth, value: year)
        .onChange(of: year) { selected = nil }
    }

    private func summary(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospacedDigit())
        }
        .accessibilityElement(children: .combine)
    }

    private func monthChart(_ months: [FocusYearStats.Month]) -> some View {
        Chart(months) { month in
            BarMark(
                x: .value("Mes", month.date, unit: .month),
                y: .value("Horas", Double(month.minutes) / 60),
                width: .ratio(0.6)
            )
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3))
            .foregroundStyle(Color.indigo)
            .accessibilityLabel(month.date.formatted(.dateTime.month(.wide)))
            .accessibilityValue(FocusStats.format(minutes: month.minutes))
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { _ in
                AxisValueLabel(format: .dateTime.month(.narrow), centered: true)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.25))
                AxisValueLabel {
                    if let hours = value.as(Double.self) { Text("\(hours, format: .number.precision(.fractionLength(0))) h") }
                }
            }
        }
        .frame(height: 160)
    }

    /// One column per week (Monday first), one cell per day, scrolled to the current week.
    private func dayGrid(_ days: [FocusStats.Day]) -> some View {
        let calendar = Calendar.current
        // Empty cells before January 1st so every column starts on Monday.
        let leading = days.first.map { (calendar.component(.weekday, from: $0.date) + 5) % 7 } ?? 0
        let cells: [FocusStats.Day?] = Array(repeating: nil, count: leading) + days.map { Optional($0) }
        let weeks = stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<min($0 + 7, cells.count)]) }
        let currentWeek = weeks.firstIndex { $0.contains { $0.map { calendar.isDateInToday($0.date) } ?? false } }

        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 3) {
                    ForEach(Array(weeks.enumerated()), id: \.offset) { index, week in
                        VStack(spacing: 3) {
                            ForEach(0..<7, id: \.self) { row in
                                cell(row < week.count ? week[row] : nil)
                            }
                        }
                        .id(index)
                    }
                }
                .padding(.vertical, 2)
            }
            .onAppear { if let currentWeek { proxy.scrollTo(currentWeek, anchor: .trailing) } }
            .onChange(of: year) { proxy.scrollTo(currentWeek ?? weeks.count - 1, anchor: .trailing) }
        }
    }

    @ViewBuilder
    private func cell(_ day: FocusStats.Day?) -> some View {
        let shape = RoundedRectangle(cornerRadius: 2.5, style: .continuous)
        if let day, day.date <= .now {
            let isSelected = selected.map { Calendar.current.isDate(day.date, inSameDayAs: $0) } ?? false
            shape
                .fill(MonthHeatmap.shade(MonthHeatmap.level(for: day.minutes)))
                .frame(width: 12, height: 12)
                .overlay { if isSelected { shape.strokeBorder(Color.primary, lineWidth: 1.5) } }
                .contentShape(Rectangle())
                .onTapGesture { selected = isSelected ? nil : day.date }
                .accessibilityElement()
                .accessibilityLabel(day.date.formatted(.dateTime.weekday(.wide).day().month()))
                .accessibilityValue(FocusStats.format(minutes: day.minutes))
        } else {
            shape.fill(Color.clear).frame(width: 12, height: 12).accessibilityHidden(true)
        }
    }
}
