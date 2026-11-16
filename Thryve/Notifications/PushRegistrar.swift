import Foundation
import Observation
import UIKit
import UserNotifications

/// This phone as a notification channel on the unit: permission, the APNs
/// device token, and registering both with core (`notifications.devices.register`).
@MainActor
@Observable
final class PushRegistrar {
    static let shared = PushRegistrar()

    enum UnitPush: Equatable {
        case unknown
        case registering
        /// The unit has an APNs key and this phone's token: real push, even when the app is closed.
        case ready
        /// Registered, but the unit has no APNs key (or the phone has no token yet): background checks only.
        case checksOnly
        /// The unit's core predates notification rules.
        case unsupported
        case failed(String)
    }

    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    private(set) var token: String?
    private(set) var tokenError: String?
    private(set) var unitPush: UnitPush = .unknown
    var enabled: Bool { UnitNotifier.isEnabled(defaults) }

    private let defaults: UserDefaults
    private var api: (any ThryveAPI)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        token = defaults.string(forKey: Keys.token)
    }

    /// A random id for this install, so the unit can tell phones apart and forget one.
    var deviceId: String {
        if let id = defaults.string(forKey: Keys.deviceId) { return id }
        let id = UUID().uuidString.lowercased()
        defaults.set(id, forKey: Keys.deviceId)
        return id
    }

    /// The unit the app is talking to now (nil when disconnected or in the demo).
    func attach(_ api: (any ThryveAPI)?) async {
        self.api = api
        await refreshAuthorization()
        if enabled { await sync() }
    }

    func refreshAuthorization() async {
        authorization = await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { continuation.resume(returning: $0.authorizationStatus) }
        }
    }

    /// The Settings switch: ask iOS, get a token, tell the unit.
    func setEnabled(_ on: Bool) async {
        UnitNotifier.setEnabled(on, defaults)
        if on {
            let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            await refreshAuthorization()
            guard granted else {
                UnitNotifier.setEnabled(false, defaults)
                return
            }
            UIApplication.shared.registerForRemoteNotifications()
            BackgroundRefresh.schedule()
            await sync()
        } else {
            UnitNotifier.setPushActive(false, defaults)
            if let api { try? await api.unregisterDevice(id: deviceId) }
            unitPush = .unknown
        }
    }

    func tokenArrived(_ data: Data) {
        let hex = PushToken.hex(data)
        tokenError = nil
        guard hex != token else { return }
        token = hex
        defaults.set(hex, forKey: Keys.token)
        Task { await sync() }
    }

    func tokenFailed(_ error: any Error) {
        // Simulators and builds signed without the Push Notifications capability land here.
        tokenError = error.localizedDescription
        Log.notify.info("no APNs token: \(error.localizedDescription)")
        Task { await sync() }
    }

    /// Registers (or re-registers) this phone with the unit and records whether pushes will come.
    func sync() async {
        guard enabled, let api else { return }
        unitPush = .registering
        let registration = DeviceRegistration(deviceId: deviceId, name: UIDevice.current.name, token: token,
                                              environment: PushToken.environment, bundleId: Bundle.main.bundleIdentifier ?? "com.thryve.app")
        do {
            let status = try await api.registerDevice(registration)
            let push = status.apnsConfigured && token != nil
            UnitNotifier.setPushActive(push, defaults)
            unitPush = push ? .ready : .checksOnly
        } catch let error as APIError where error.isMissingProcedure {
            UnitNotifier.setPushActive(false, defaults)
            unitPush = .unsupported
        } catch {
            UnitNotifier.setPushActive(false, defaults)
            unitPush = .failed(error.localizedDescription)
        }
    }

    /// Asks the unit to send a test through every route it has; falls back to a local banner.
    func sendTest() async -> String {
        guard let api else { return "Connect to a unit first." }
        do {
            let result = try await api.testNotification(deviceId: deviceId)
            if result.via == "apns", result.sent { return "Sent through Apple Push. It should arrive in a few seconds." }
        } catch {
            Log.notify.info("unit test failed: \(error.localizedDescription)")
        }
        SystemNotificationPoster().post(FeedItem(id: Int(Date().timeIntervalSince1970), title: "Thryve", body: "Notifications are working on this iPhone."))
        return "Showed a local test notification. Push from the unit isn't set up."
    }

    private enum Keys {
        static let token = "notify.apnsToken"
        static let deviceId = "notify.deviceId"
    }
}
