import ActivityKit
import Foundation

/// A watering cycle as a Live Activity (lock screen and Dynamic Island).
///
/// Shared by the app and the ThryveWidgets extension. Core sends the same JSON in
/// APNs `liveactivity` pushes (`attributes-type: "WateringAttributes"`), so times
/// are plain Unix seconds rather than `Date`, which ActivityKit would decode as
/// seconds since 2001.
struct WateringAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        /// When the pump started (Unix seconds).
        var startedAt: Double
        /// When the run is due to end (Unix seconds); nil for a run with no set length.
        var endsAt: Double?
        /// Pump power, % duty.
        var powerPct: Int
        /// The soft-start ramp in seconds, 0 when it's off.
        var softStartS: Double
        var running: Bool
        /// A latched pump fault ("dry run", "brown-out"…), shown instead of the timer.
        var fault: String?

        var start: Date { Date(timeIntervalSince1970: startedAt) }
        var end: Date? { endsAt.map { Date(timeIntervalSince1970: $0) } }

        /// The run's span for `Text(timerInterval:)` and `ProgressView(timerInterval:)`,
        /// which tick on their own without updates. Nil when there's no end to count to.
        var interval: ClosedRange<Date>? {
            guard let end, end > start else { return nil }
            return start...end
        }

        /// How far along the run is at `now`, 0–1 (for a run with no end, nil).
        func progress(at now: Date) -> Double? {
            guard let interval else { return nil }
            let total = interval.upperBound.timeIntervalSince(interval.lowerBound)
            return min(1, max(0, now.timeIntervalSince(interval.lowerBound) / total))
        }

        func isRamping(at now: Date) -> Bool {
            running && softStartS > 0 && now.timeIntervalSince(start) < softStartS
        }
    }

    /// The unit's name, as it shows on the connect screen.
    var unitName: String
}
