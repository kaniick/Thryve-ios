import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// The watering cycle on the lock screen and in the Dynamic Island.
///
/// Live Activities can't run their own timers, so everything that moves is drawn
/// by the system from the run's start and end: `Text(timerInterval:)` counts down,
/// `ProgressView(timerInterval:)` fills, here turned upright and cut to the
/// tower's outline so the water rises up the tower as the run goes on.
struct WateringLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WateringAttributes.self) { context in
            LockScreenWatering(attributes: context.attributes, state: context.state)
                .padding(16)
                .activityBackgroundTint(Palette.background)
                .activitySystemActionForegroundColor(Palette.text)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        RisingWater(state: state).frame(width: 18, height: 46)
                        Image("BrandIcon").resizable().scaledToFit().frame(width: 30, height: 30)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(state.powerPct)%").font(.title3.monospacedDigit().weight(.semibold))
                        Text("power").font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(state.headline).font(.headline)
                        RunClock(state: state).font(.title2.monospacedDigit().weight(.semibold)).foregroundStyle(Palette.water)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 12) {
                        RunBar(state: state)
                        if state.running { StopButton() }
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: state.fault == nil ? "drop.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(state.fault == nil ? Palette.water : .orange)
                    .symbolEffect(.pulse, isActive: state.running)
            } compactTrailing: {
                RunClock(state: state)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Palette.water)
                    .frame(maxWidth: 44)
            } minimal: {
                RunRing(state: state)
            }
            .keylineTint(Palette.water)
        }
    }
}

enum Palette {
    static let water = Color(red: 0x8F / 255, green: 0xB4 / 255, blue: 0xC4 / 255)
    static let leaf = Color(red: 0x96 / 255, green: 0xBE / 255, blue: 0x8E / 255)
    static let text = Color(red: 0xEF / 255, green: 0xE8 / 255, blue: 0xDA / 255)
    static let background = Color(red: 0x11 / 255, green: 0x10 / 255, blue: 0x0C / 255)
}

extension WateringAttributes.ContentState {
    var headline: String {
        if let fault { return "Pump stopped: \(fault)" }
        return running ? "Watering" : "Watered"
    }

    var detail: String {
        var parts = ["Power \(powerPct)%"]
        if softStartS > 0 { parts.append("soft start \(softStartS.formatted(.number.precision(.fractionLength(0...1)))) s") }
        if let interval {
            let minutes = Int(interval.upperBound.timeIntervalSince(interval.lowerBound).rounded())
            parts.append("\(minutes / 60):\(String(format: "%02d", minutes % 60)) run")
        }
        return parts.joined(separator: " · ")
    }
}

struct LockScreenWatering: View {
    let attributes: WateringAttributes
    let state: WateringAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    RisingWater(state: state).frame(width: 26, height: 64)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image("BrandIcon").resizable().scaledToFit().frame(width: 18, height: 18)
                        Text("\(state.headline) · \(attributes.unitName)").font(.subheadline.weight(.semibold)).lineLimit(1)
                    }
                    RunClock(state: state).font(.system(size: 34, weight: .semibold).monospacedDigit()).foregroundStyle(Palette.water)
                    HStack(spacing: 4) {
                        if state.running {
                            Text("Elapsed")
                            Text(state.start, style: .timer).monospacedDigit()
                            Text("·")
                        }
                        Text(state.detail)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                Spacer(minLength: 0)
                if state.running { StopButton() }
            }
            RunBar(state: state)
        }
        .foregroundStyle(Palette.text)
    }
}

/// Remaining time while there's an end to count to, otherwise time since the start.
struct RunClock: View {
    let state: WateringAttributes.ContentState

    var body: some View {
        if !state.running {
            Text(state.fault == nil ? "Done" : "Stopped")
        } else if let interval = state.interval {
            Text(timerInterval: interval, countsDown: true)
                .contentTransition(.numericText(countsDown: true))
        } else {
            Text(state.start, style: .timer)
        }
    }
}

struct RunBar: View {
    let state: WateringAttributes.ContentState

    var body: some View {
        Group {
            if state.running, let interval = state.interval {
                ProgressView(timerInterval: interval, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
            } else {
                ProgressView(value: state.running ? 0 : 1)
            }
        }
        .progressViewStyle(.linear)
        .tint(state.fault == nil ? Palette.water : .orange)
    }
}

struct RunRing: View {
    let state: WateringAttributes.ContentState

    var body: some View {
        Group {
            if state.running, let interval = state.interval {
                ProgressView(timerInterval: interval, countsDown: false) { EmptyView() } currentValueLabel: {
                    Image(systemName: "drop.fill").font(.system(size: 9))
                }
            } else {
                ProgressView(value: 1) { EmptyView() } currentValueLabel: {
                    Image(systemName: state.fault == nil ? "checkmark" : "exclamationmark").font(.system(size: 9, weight: .bold))
                }
            }
        }
        .progressViewStyle(.circular)
        .tint(Palette.water)
    }
}

/// The tower's outline with water filling it from the bottom over the run.
struct RisingWater: View {
    let state: WateringAttributes.ContentState

    var body: some View {
        GeometryReader { geo in
            Group {
                if state.running, let interval = state.interval {
                    ProgressView(timerInterval: interval, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                } else {
                    ProgressView(value: state.running ? 0.15 : 1)
                }
            }
            .progressViewStyle(.linear)
            .tint(Palette.water)
            // A linear bar on its side, as tall as the tower and as wide: the fill rises.
            .frame(width: geo.size.height)
            .scaleEffect(x: 1, y: max(1, geo.size.width / 3))
            .rotationEffect(.degrees(-90))
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .mask(TowerSilhouette())
        .background(TowerSilhouette().fill(Palette.text.opacity(0.12)))
        .overlay(TowerSilhouette().stroke(Palette.leaf.opacity(0.7), lineWidth: 1))
    }
}

/// A Gardyn tower: a tall rounded column under a narrower cap.
struct TowerSilhouette: Shape {
    func path(in rect: CGRect) -> Path {
        let cap = rect.height * 0.1
        var path = Path()
        path.addRoundedRect(in: CGRect(x: rect.minX + rect.width * 0.25, y: rect.minY, width: rect.width * 0.5, height: cap + 2),
                            cornerSize: CGSize(width: 2, height: 2))
        path.addRoundedRect(in: CGRect(x: rect.minX, y: rect.minY + cap, width: rect.width, height: rect.height - cap),
                            cornerSize: CGSize(width: rect.width * 0.3, height: rect.width * 0.3))
        return path
    }
}

struct StopButton: View {
    var body: some View {
        Button(intent: StopPumpIntent()) {
            Label("Stop", systemImage: "stop.fill")
                .font(.caption.weight(.semibold))
                .labelStyle(.iconOnly)
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.circle)
        .tint(.orange)
        .accessibilityLabel("Stop watering")
    }
}

#Preview("Lock screen", as: .content, using: WateringAttributes(unitName: "Kitchen Gardyn")) {
    WateringLiveActivity()
} contentStates: {
    let now = Date().timeIntervalSince1970
    WateringAttributes.ContentState(startedAt: now - 20, endsAt: now + 100, powerPct: 100, softStartS: 2, running: true, fault: nil)
    WateringAttributes.ContentState(startedAt: now - 120, endsAt: now, powerPct: 100, softStartS: 2, running: false, fault: nil)
}
