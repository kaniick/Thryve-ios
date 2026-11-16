import Foundation
import Observation

/// Home's data: one batched snapshot, refreshed when core's event stream says
/// something changed (at most every couple of seconds) and every 30 s regardless.
@MainActor
@Observable
final class HomeStore {
    private(set) var snapshot: HomeSnapshot?
    private(set) var system: SystemInfo?
    private(set) var error: APIError?
    private(set) var loading = false
    /// Last mutation that failed, for a transient banner.
    var actionError: String?
    /// True while the WebSocket is delivering frames.
    private(set) var live = false

    private let api: any ThryveAPI
    private let stream: EventStream?
    private var refreshQueued = false
    /// Posts banners for whatever the unit's notification feed has that's new.
    private let notifier: UnitNotifier?

    /// Mirror the pump into the watering Live Activity (off in tests).
    private let liveActivities: Bool

    init(api: any ThryveAPI, stream: EventStream? = nil, notifier: UnitNotifier? = nil, liveActivities: Bool = false) {
        self.api = api
        self.stream = stream
        self.notifier = notifier
        self.liveActivities = liveActivities
    }

    /// Loads once, then follows the event stream and a slow poll until the task is cancelled.
    func run() async {
        await refresh()
        if system == nil { system = try? await api.systemInfo() }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.poll() }
            if let stream {
                group.addTask { await self.follow(stream) }
            }
        }
    }

    func refresh() async {
        loading = snapshot == nil
        defer { loading = false }
        do {
            snapshot = try await api.home()
            error = nil
            if liveActivities { await WateringActivities.sync(pump: snapshot?.pump) }
            _ = try? await notifier?.check(api: api)
        } catch let e as APIError {
            error = e
        } catch {
            self.error = .network(error.localizedDescription)
        }
    }

    private func poll() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            await refresh()
        }
    }

    private func follow(_ stream: EventStream) async {
        for await kind in stream.kinds() {
            live = true
            // The hello frame arrives on every (re)connect: catch up on whatever was missed.
            if kind == "hello" || kind == "mutation" || kind == "hal" || kind == "schedule" { queueRefresh() }
        }
        live = false
    }

    /// Coalesces bursts of events (the sim publishes every sensor at once) into one refresh.
    private func queueRefresh() {
        guard !refreshQueued else { return }
        refreshQueued = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            refreshQueued = false
            await refresh()
        }
    }

    // MARK: - Actions

    func setLight(on: Bool? = nil, level: Double? = nil) async {
        await act { _ = try await $0.setLight(on: on, level: level) }
    }

    func resumeLight() async {
        await act { _ = try await $0.resumeLight() }
    }

    func runPump(seconds: Int) async {
        await act { _ = try await $0.runPump(seconds: seconds) }
    }

    func stopPump() async {
        await act { _ = try await $0.stopPump() }
    }

    func markHarvested(_ slot: Int) async {
        await act { _ = try await $0.markHarvested(slot: slot) }
    }

    func updatePod(_ slot: Int, _ patch: PodPatch) async {
        await act { _ = try await $0.updatePod(slot: slot, patch) }
    }

    func acknowledge(_ alert: CoreAlert) async {
        await act { try await $0.acknowledgeAlert(id: alert.id) }
    }

    private func act(_ body: (any ThryveAPI) async throws -> Void) async {
        do {
            try await body(api)
            actionError = nil
        } catch {
            actionError = error.localizedDescription
        }
        await refresh()
    }
}
