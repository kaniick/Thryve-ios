import Foundation

/// What the app asks of a Thryve unit. `CoreClient` talks to a real core over tRPC;
/// `DemoClient` is an in-memory tower for trying the app without one.
protocol ThryveAPI: Sendable {
    func systemInfo() async throws -> SystemInfo
    func home() async throws -> HomeSnapshot

    func setLight(on: Bool?, level: Double?) async throws -> ActuatorState
    /// Ends a manual hold and hands the light back to Autopilot or the schedule.
    func resumeLight() async throws -> LightOwner
    func runPump(seconds: Int) async throws -> ActuatorState
    func stopPump() async throws -> ActuatorState

    func markHarvested(slot: Int) async throws -> Pod
    func updatePod(slot: Int, _ patch: PodPatch) async throws -> Pod
    func acknowledgeAlert(id: Int) async throws

    // Notifications (core's "ios" channel)
    /// What's new after `afterId` (nil: just the newest id, nothing to show).
    func notificationFeed(after afterId: Int?) async throws -> NotificationFeed
    func registerDevice(_ registration: DeviceRegistration) async throws -> DeviceStatus
    func unregisterDevice(id: String) async throws
    func testNotification(deviceId: String) async throws -> TestResult
    func registerActivityToken(_ registration: ActivityTokenRegistration) async throws
}

enum APIError: LocalizedError, Sendable, Equatable {
    case invalidURL
    case unauthorized
    case invalidResponse(statusCode: Int)
    case decodingFailed(String)
    case network(String)
    case server(message: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: "That address isn't a valid URL."
        case .unauthorized: "The unit wants an API key. Add it in Settings."
        case .invalidResponse(let code): "The unit answered with HTTP \(code)."
        case .decodingFailed(let detail): "The unit's answer didn't parse: \(detail)"
        case .network(let detail): "Couldn't reach the unit: \(detail)"
        case .server(let message): message
        }
    }
}
