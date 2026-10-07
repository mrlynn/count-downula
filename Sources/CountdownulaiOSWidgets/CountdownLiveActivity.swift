import ActivityKit
import SwiftUI
import WidgetKit

/// A countdown in its final hours on the Lock Screen, in the Dynamic Island and in StandBy.
/// Everything ticks on its own; once the target passes the activity goes stale and shows "Done".
struct CountdownLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CountdownActivityAttributes.self) { context in
            LockScreenActivityView(state: context.state, kind: context.attributes.kind, isDone: isDone(context))
                .activityBackgroundTint(Color(red: 0.08, green: 0.02, blue: 0.05).opacity(0.92))
                .activitySystemActionForegroundColor(.countdownulaBlood)
                .widgetURL(CountdownLink.url(for: context.attributes.countdownID))
        } dynamicIsland: { context in
            let state = context.state
            let done = isDone(context)

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ActivityDial(state: state, isDone: done)
                        .frame(width: 44, height: 44)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ActivityTimeText(state: state, isDone: done)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.countdownulaBlood)
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
                        ActivityProgressBar(state: state, isDone: done)
                        Text(state.targetDate, format: .dateTime.weekday(.wide).hour().minute())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                FangMark()
                    .foregroundStyle(Color.countdownulaBlood)
                    .frame(width: 20, height: 20)
            } compactTrailing: {
                ActivityTimeText(state: state, isDone: done)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(Color.countdownulaBlood)
                    .frame(maxWidth: 64)
            } minimal: {
                ActivityDial(state: state, isDone: done)
            }
            .widgetURL(CountdownLink.url(for: context.attributes.countdownID))
            .keylineTint(.countdownulaBlood)
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

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ActivityDial(state: state, isDone: isDone)
                    .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 2) {
                    Text(state.title)
                        .font(.headline)
                        .lineLimit(2)
                    Text(isDone ? "Complete" : subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                }

                Spacer(minLength: 8)

                ActivityTimeText(state: state, isDone: isDone)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.countdownulaBlood)
                    .frame(maxWidth: 130, alignment: .trailing)
            }
            ActivityProgressBar(state: state, isDone: isDone)
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

    var body: some View {
        if isDone {
            Text("Done")
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

    var body: some View {
        ZStack {
            if isDone {
                Image(systemName: "checkmark.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.countdownulaBlood)
            } else {
                ProgressView(timerInterval: state.interval, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .progressViewStyle(.circular)
                .tint(.countdownulaBlood)

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

    var body: some View {
        if isDone {
            ProgressView(value: 1)
                .tint(.countdownulaBlood)
        } else {
            ProgressView(timerInterval: state.interval, countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .tint(.countdownulaBlood)
        }
    }
}
