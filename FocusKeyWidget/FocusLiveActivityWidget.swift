//
//  FocusLiveActivityWidget.swift
//  FocusKeyWidget
//
//  Lock Screen and Dynamic Island for a timed session or a pomodoro phase.
//  The app starts and updates it (Shared/FocusLiveActivity.swift).
//

import ActivityKit
import SwiftUI
import WidgetKit

struct FocusLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            FocusLiveActivityView(context: context)
                .padding()
                .activityBackgroundTint(FocusPalette.color(context.attributes.colorName).opacity(0.25))
                .activitySystemActionForegroundColor(FocusPalette.color(context.attributes.colorName))
        } dynamicIsland: { context in
            let tint = context.state.isBreak ? Color.green : FocusPalette.color(context.attributes.colorName)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.title, systemImage: symbol(context))
                        .font(.headline)
                        .foregroundStyle(tint)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdown(context)
                        .font(.title3.monospacedDigit().bold())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(timerInterval: context.state.start...context.state.end, countsDown: true) {
                            EmptyView()
                        } currentValueLabel: {
                            EmptyView()
                        }
                        .tint(tint)
                        Text(context.isStale ? String(localized: "Fase terminada · abre FocusKey") : context.state.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                Image(systemName: symbol(context)).foregroundStyle(tint)
            } compactTrailing: {
                countdown(context)
                    .monospacedDigit()
                    .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: symbol(context)).foregroundStyle(tint)
            }
        }
    }

    private func symbol(_ context: ActivityViewContext<FocusActivityAttributes>) -> String {
        context.state.isBreak ? "cup.and.saucer.fill" : "lock.fill"
    }

    private func countdown(_ context: ActivityViewContext<FocusActivityAttributes>) -> some View {
        Text(timerInterval: context.state.start...context.state.end, countsDown: true)
            .multilineTextAlignment(.trailing)
    }
}

private struct FocusLiveActivityView: View {
    let context: ActivityViewContext<FocusActivityAttributes>

    private var tint: Color {
        context.state.isBreak ? .green : FocusPalette.color(context.attributes.colorName)
    }

    var body: some View {
        HStack(spacing: 14) {
            ProgressView(timerInterval: context.state.start...context.state.end, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                Image(systemName: context.state.isBreak ? "cup.and.saucer.fill" : context.attributes.symbol)
                    .font(.body.bold())
            }
            .progressViewStyle(.circular)
            .tint(tint)
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 2) {
                Text(context.state.title)
                    .font(.headline)
                Text(context.isStale ? String(localized: "Fase terminada · abre FocusKey") : context.state.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(timerInterval: context.state.start...context.state.end, countsDown: true)
                .font(.title2.monospacedDigit().bold())
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 100, alignment: .trailing)
        }
    }
}
