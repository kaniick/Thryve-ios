import ActivityKit
import Foundation
import UIKit

/// Starts, updates and ends the watering Live Activity from what the app sees
/// (Home's refreshes and the event stream), and hands ActivityKit's push tokens
/// to the unit so core can do the same over APNs when the app isn't running.
@MainActor
enum WateringActivities {
    private static var api: (any ThryveAPI)?
    private static var unitName = "Gardyn"
    private static var tokenTasks: [String: Task<Void, Never>] = [:]
    private static var startTokenTask: Task<Void, Never>?

    static var enabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    /// The unit the app talks to now. Also picks up activities core started by push.
    static func attach(_ api: (any ThryveAPI)?, unitName: String?) {
        self.api = api
        self.unitName = unitName ?? "Gardyn"
        guard api != nil else { return }
        observeStartToken()
        for activity in Activity<WateringAttributes>.activities { observeToken(activity) }
    }

    /// What the content state should be for a pump reading, or nil when it's off.
    nonisolated static func state(for pump: ActuatorState?, now: Date = Date(), previous: WateringAttributes.ContentState? = nil) -> WateringAttributes.ContentState? {
        guard let pump, pump.on else { return nil }
        let started = ISO.date(pump.since)?.timeIntervalSince1970 ?? previous?.startedAt ?? now.timeIntervalSince1970
        let ends = pump.remainingS.map { now.timeIntervalSince1970 + Double($0) }
        return WateringAttributes.ContentState(startedAt: started, endsAt: ends ?? previous?.endsAt,
                                               powerPct: Int(pump.level.rounded()), softStartS: previous?.softStartS ?? 0,
                                               running: true, fault: pump.fault)
    }

    /// Called with every fresh pump reading.
    static func sync(pump: ActuatorState?) async {
        guard enabled else { return }
        let current = Activity<WateringAttributes>.activities.first { $0.activityState == .active }
        guard let state = state(for: pump, previous: current?.content.state) else {
            await endAll(fault: pump?.fault)
            return
        }
        if let current {
            // The countdown runs on its own; only push a change the unit made (a new end, power or fault).
            guard Self.differs(current.content.state, state) else { return }
            await current.update(ActivityContent(state: state, staleDate: stale(state)))
        } else {
            start(state)
        }
    }

    nonisolated static func differs(_ a: WateringAttributes.ContentState, _ b: WateringAttributes.ContentState) -> Bool {
        let endMoved = abs((a.endsAt ?? 0) - (b.endsAt ?? 0)) > 3
        return endMoved || a.powerPct != b.powerPct || a.fault != b.fault || a.running != b.running
    }

    private static func start(_ state: WateringAttributes.ContentState) {
        let attributes = WateringAttributes(unitName: unitName)
        let content = ActivityContent(state: state, staleDate: stale(state))
        do {
            // With push, core can keep it current and end it while the app is asleep.
            let activity = try Activity.request(attributes: attributes, content: content, pushType: UnitNotifier.isEnabled() ? .token : nil)
            observeToken(activity)
        } catch {
            // Builds without the Push Notifications capability can still run a local one.
            Log.notify.info("live activity with push not started: \(error.localizedDescription)")
            _ = try? Activity.request(attributes: attributes, content: content, pushType: nil)
        }
    }

    static func endAll(fault: String? = nil) async {
        for activity in Activity<WateringAttributes>.activities {
            var final = activity.content.state
            final.running = false
            final.fault = fault
            final.endsAt = min(final.endsAt ?? Date().timeIntervalSince1970, Date().timeIntervalSince1970)
            await activity.end(ActivityContent(state: final, staleDate: nil), dismissalPolicy: .after(Date().addingTimeInterval(fault == nil ? 60 : 15 * 60)))
            tokenTasks[activity.id]?.cancel()
            tokenTasks[activity.id] = nil
        }
    }

    /// The Stop button: stop the pump through the unit and end the activity only if it says the pump is off.
    static func stopFromActivity() async throws {
        let api = api ?? Connection().api
        guard let api else { throw APIError.server(message: "No Gardyn connected.") }
        let state = try await api.stopPump()
        if state.on {
            throw APIError.server(message: "The unit still reports the pump running.")
        }
        await endAll(fault: state.fault)
    }

    /// A run past its end with no word from the unit shows as stale rather than at 100% forever.
    private static func stale(_ state: WateringAttributes.ContentState) -> Date? {
        state.end.map { $0.addingTimeInterval(60) }
    }

    // MARK: - Push tokens

    private static func observeStartToken() {
        guard startTokenTask == nil else { return }
        startTokenTask = Task {
            for await data in Activity<WateringAttributes>.pushToStartTokenUpdates {
                await register(kind: "start", activityId: nil, token: PushToken.hex(data))
            }
        }
    }

    private static func observeToken(_ activity: Activity<WateringAttributes>) {
        guard tokenTasks[activity.id] == nil else { return }
        let id = activity.id
        tokenTasks[id] = Task {
            for await data in activity.pushTokenUpdates {
                await register(kind: "update", activityId: id, token: PushToken.hex(data))
            }
        }
    }

    private static func register(kind: String, activityId: String?, token: String) async {
        guard let api, UnitNotifier.isEnabled() else { return }
        let registration = ActivityTokenRegistration(deviceId: PushRegistrar.shared.deviceId, kind: kind, activityId: activityId,
                                                     token: token, environment: PushToken.environment)
        do {
            try await api.registerActivityToken(registration)
        } catch {
            Log.notify.info("activity token not registered: \(error.localizedDescription)")
        }
    }
}
