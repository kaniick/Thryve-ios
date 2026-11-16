import Foundation

/// One notification core decided to send this phone: a rule firing (core's
/// notification rules, the "ios" channel) or, on units without them, an alert.
/// `id` only ever grows, so the app keeps the last one it saw as its cursor.
struct FeedItem: Codable, Sendable, Equatable, Identifiable {
    let id: Int
    let title: String
    let body: String
    /// "info", "warning" or "critical".
    var level: String?
    /// Set when the notification is about a core alert, so it can be acknowledged from the banner.
    var alertId: Int?
    var createdAt: String?
}

/// `notifications.feed`: what's new after a cursor, and the newest id core has.
struct NotificationFeed: Codable, Sendable, Equatable {
    let items: [FeedItem]
    let latestId: Int?
}

/// `notifications.devices.register`: this phone as an "ios" notification channel.
/// `token` is the APNs device token in hex, or nil when the phone only checks in
/// (local notifications) because push isn't available.
struct DeviceRegistration: Codable, Sendable, Equatable {
    let deviceId: String
    let name: String
    var platform = "ios"
    let token: String?
    /// "sandbox" for Xcode debug builds, "production" for TestFlight and App Store builds.
    let environment: String
    let bundleId: String
}

/// `notifications.activities.register`: an ActivityKit push token for the watering
/// Live Activity. "start" is the push-to-start token (one per phone), "update" the
/// token of one running activity.
struct ActivityTokenRegistration: Codable, Sendable, Equatable {
    let deviceId: String
    let kind: String
    let activityId: String?
    let token: String
    let environment: String
}

struct DeviceStatus: Codable, Sendable, Equatable {
    /// True when the unit has an APNs key saved, so it can push to this phone directly.
    let apnsConfigured: Bool
}

/// `notifications.devices.test`: whether core pushed the test through APNs or only queued it in the feed.
struct TestResult: Codable, Sendable, Equatable {
    let sent: Bool
    let via: String
}

enum PushToken {
    /// APNs device tokens are sent to providers as lowercase hex.
    static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    static var environment: String {
        #if DEBUG
        "sandbox"
        #else
        "production"
        #endif
    }
}

extension APIError {
    /// Core answers an unknown tRPC path with 404 and "No procedure found on path …":
    /// the unit runs a version without notification rules yet.
    var isMissingProcedure: Bool {
        switch self {
        case .invalidResponse(let code): code == 404
        case .server(let message): message.localizedCaseInsensitiveContains("no procedure found")
        default: false
        }
    }
}

extension FeedItem {
    /// An alert as a notification, for units whose core predates `notifications.feed`.
    init(alert: CoreAlert) {
        self.init(id: alert.id, title: Self.title(forAlertKind: alert.kind), body: alert.detail,
                  level: alert.kind.hasPrefix("reminder") ? "info" : "warning", alertId: alert.id, createdAt: alert.raisedAt)
    }

    /// "reminder_nutrients" → "Reminder: nutrients", "pump_dry_run" → "Pump dry run".
    static func title(forAlertKind kind: String) -> String {
        let words = kind.split(separator: "_").map(String.init)
        guard let first = words.first else { return "Thryve" }
        if first == "reminder", words.count > 1 { return "Reminder: " + words.dropFirst().joined(separator: " ") }
        return ([first.capitalized] + words.dropFirst()).joined(separator: " ")
    }
}
