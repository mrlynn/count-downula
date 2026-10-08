import ActivityKit
import SwiftUI
import WidgetKit

/// A countdown in its final hours on the Lock Screen, in the Dynamic Island and in StandBy.
/// Everything ticks on its own; once the target passes the activity goes stale and shows "Done".
struct CountdownLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CountdownActivityAttributes.self) { context in
            let accent = context.attributes.accent?.color ?? .countdownulaBlood
            LockScreenActivityView(state: context.state, kind: context.attributes.kind, isDone: isDone(context), accent: accent)
                .activityBackgroundTint(Color(red: 0.08, green: 0.02, blue: 0.05).opacity(0.92))
                .activitySystemActionForegroundColor(accent)
                .widgetURL(CountdownLink.url(for: context.attributes.countdownID))
        } dynamicIsland: { context in
            let state = context.state
            let accent = context.attributes.accent?.color ?? .countdownulaBlood
            let done = isDone(context)

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ActivityDial(state: state, isDone: done, accent: accent)
                        .frame(width: 44, height: 44)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ActivityTimeText(state: state, isDone: done)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(accent)
                        .frame(maxWidth: 130, alignment: .trailing)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(state.title)
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        ActivityProgressBar(state: state, isDone: done, accent: accent)
                        Text(state.targetDate, format: .dateTime.weekday(.wide).hour().minute())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                FangMark()
                    .foregroundStyle(accent)
                    .frame(width: 20, height: 20)
            } compactTrailing: {
                ActivityTimeText(state: state, isDone: done)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(accent)
                    .frame(maxWidth: 64)
            } minimal: {
                ActivityDial(state: state, isDone: done, accent: accent)
            }
            .widgetURL(CountdownLink.url(for: context.attributes.countdownID))
            .keylineTint(accent)
        }
    }

    private func isDone(_ context: ActivityViewContext<CountdownActivityAttributes>) -> Bool {
        context.isStale || context.state.targetDate <= Date()
    }
}

private struct LockScreenActivityView: View {
    let state: CountdownActivityAttributes.ContentState
    let kind: Countdown.Kind
    let isDone: Bool
    var accent: Color = .countdownulaBlood

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ActivityDial(state: state, isDone: isDone, accent: accent)
                    .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 2) {
                    Text(state.title)
                        .font(.headline)
                        .lineLimit(2)
                    Text(isDone ? (state.celebrating ? "It's here! Everyone's celebrating." : "Complete") : subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                }

                Spacer(minLength: 8)

                ActivityTimeText(state: state, isDone: isDone)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
                    .frame(maxWidth: 130, alignment: .trailing)
            }
            ActivityProgressBar(state: state, isDone: isDone, accent: accent)
        }
        .foregroundStyle(.white)
        .padding(16)
    }

    private var subtitle: String {
        let time = state.targetDate.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        return kind == .timer ? "Timer ends \(time)" : time
    }
}

/// Self-updating "1:42:07" (or "Done").
private struct ActivityTimeText: View {
    let state: CountdownActivityAttributes.ContentState
    let isDone: Bool
    var accent: Color = .countdownulaBlood

    var body: some View {
        if isDone {
            Text(state.celebrating ? "🎉" : "Done")
        } else {
            Text(timerInterval: state.interval, countsDown: true)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

/// A live ring around the fang mark.
private struct ActivityDial: View {
    let state: CountdownActivityAttributes.ContentState
    let isDone: Bool
    var accent: Color = .countdownulaBlood

    var body: some View {
        ZStack {
            if isDone, state.celebrating {
                Text("🎉")
                    .font(.system(size: 30))
                    .minimumScaleFactor(0.4)
            } else if isDone {
                Image(systemName: "checkmark.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(accent)
            } else {
                ProgressView(timerInterval: state.interval, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .progressViewStyle(.circular)
                .tint(accent)

                FangMark()
                    .foregroundStyle(Color.countdownulaBone)
                    .padding(9)
            }
        }
    }
}

private struct ActivityProgressBar: View {
    let state: CountdownActivityAttributes.ContentState
    let isDone: Bool
    var accent: Color = .countdownulaBlood

    var body: some View {
        if isDone {
            ProgressView(value: 1)
                .tint(accent)
        } else {
            ProgressView(timerInterval: state.interval, countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .tint(accent)
        }
    }
}
