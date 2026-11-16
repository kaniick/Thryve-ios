import BackgroundTasks
import Foundation
import UserNotifications

/// Turns the unit's notification feed into banners on this phone.
///
/// It runs whenever Home refreshes (live, in the foreground) and from a
/// background app refresh task (best effort: iOS decides when, typically every
/// 15 minutes to a few hours). When the unit can push to this phone through
/// APNs, the feed only advances its cursor so nothing shows twice.
@MainActor
final class UnitNotifier {
    static let refreshTaskID = "com.thryve.app.refresh"

    private let unitKey: String
    private let defaults: UserDefaults
    private let poster: any NotificationPosting

    init(unitKey: String, defaults: UserDefaults = .standard, poster: any NotificationPosting = SystemNotificationPoster()) {
        self.unitKey = unitKey
        self.defaults = defaults
        self.poster = poster
    }

    /// Notifications switched on in the app's Settings.
    static func isEnabled(_ defaults: UserDefaults = .standard) -> Bool { defaults.bool(forKey: Keys.enabled) }
    static func setEnabled(_ on: Bool, _ defaults: UserDefaults = .standard) { defaults.set(on, forKey: Keys.enabled) }

    /// The unit pushes to this phone itself (APNs), so the feed shouldn't post too.
    static func isPushActive(_ defaults: UserDefaults = .standard) -> Bool { defaults.bool(forKey: Keys.pushActive) }
    static func setPushActive(_ on: Bool, _ defaults: UserDefaults = .standard) { defaults.set(on, forKey: Keys.pushActive) }

    var cursor: Int? {
        get { defaults.object(forKey: Keys.cursor(unitKey)) as? Int }
        set { defaults.set(newValue, forKey: Keys.cursor(unitKey)) }
    }

    /// Fetches what's new and posts it. Returns how many banners went up.
    @discardableResult
    func check(api: any ThryveAPI) async throws -> Int {
        guard Self.isEnabled(defaults) else { return 0 }
        let feed = try await api.notificationFeed(after: cursor)
        let plan = Self.plan(feed: feed, cursor: cursor, pushActive: Self.isPushActive(defaults))
        cursor = plan.cursor
        for item in plan.post { poster.post(item) }
        if !plan.post.isEmpty { Log.notify.info("posted \(plan.post.count) notification(s)") }
        return plan.post.count
    }

    /// What to show and where the cursor ends up. The first check only takes the
    /// cursor (no flood of old alerts), and a burst is capped at the newest five.
    nonisolated static func plan(feed: NotificationFeed, cursor: Int?, pushActive: Bool) -> (post: [FeedItem], cursor: Int?) {
        let newest = max(feed.latestId ?? 0, feed.items.map(\.id).max() ?? 0)
        guard let cursor else { return ([], newest) }
        let fresh = feed.items.filter { $0.id > cursor }.sorted { $0.id < $1.id }
        // A unit that was reset starts its ids again: follow it down rather than go quiet.
        let next = newest < cursor && feed.latestId != nil ? newest : max(cursor, newest)
        return (pushActive ? [] : Array(fresh.suffix(5)), next)
    }

    private enum Keys {
        static let enabled = "notify.enabled"
        static let pushActive = "notify.pushActive"
        static func cursor(_ unit: String) -> String { "notify.cursor.\(unit)" }
    }
}

protocol NotificationPosting: Sendable {
    func post(_ item: FeedItem)
}

struct SystemNotificationPoster: NotificationPosting {
    func post(_ item: FeedItem) {
        let center = UNUserNotificationCenter.current()
        center.add(NotificationContent.request(for: item), withCompletionHandler: nil)
    }
}

enum NotificationContent {
    static let alertCategory = "THRYVE_ALERT"
    static let eventCategory = "THRYVE_EVENT"
    static let acknowledgeAction = "THRYVE_ACK"

    static func request(for item: FeedItem) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = item.title
        content.body = item.body
        content.sound = .default
        content.threadIdentifier = "thryve"
        content.categoryIdentifier = item.alertId == nil ? eventCategory : alertCategory
        var info: [String: Any] = ["feedId": item.id]
        if let alertId = item.alertId { info["alertId"] = alertId }
        content.userInfo = info
        // Same identifier APNs pushes use as their collapse id, so a push and a check never stack.
        return UNNotificationRequest(identifier: "thryve-\(item.id)", content: content, trigger: nil)
    }

    /// "Acknowledge" on alert banners; it runs in the background without opening the app.
    static func registerCategories() {
        let ack = UNNotificationAction(identifier: acknowledgeAction, title: "Acknowledge", options: [])
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: alertCategory, actions: [ack], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: eventCategory, actions: [], intentIdentifiers: [], options: [])
        ])
    }
}

/// The background half: iOS wakes the app now and then, it checks the unit and asks to be woken again.
enum BackgroundRefresh {
    @MainActor static func schedule() {
        guard UnitNotifier.isEnabled() else { return }
        let request = BGAppRefreshTaskRequest(identifier: UnitNotifier.refreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            Log.notify.info("background refresh not scheduled: \(error.localizedDescription)")
        }
    }

    @MainActor static func run() async {
        schedule()
        let connection = Connection()
        guard case .unit(let url)? = connection.target, let api = connection.api else { return }
        do {
            try await UnitNotifier(unitKey: url.absoluteString).check(api: api)
        } catch {
            Log.notify.info("background check failed: \(error.localizedDescription)")
        }
    }
}
