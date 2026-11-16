import Foundation
import Testing
@testable import Thryve

private final class RecordingPoster: NotificationPosting, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [FeedItem] = []
    var posted: [FeedItem] { lock.withLock { items } }
    func post(_ item: FeedItem) { lock.withLock { items.append(item) } }
}

private func item(_ id: Int, alert: Int? = nil) -> FeedItem {
    FeedItem(id: id, title: "Tank low", body: "Water at 12%", level: "warning", alertId: alert)
}

@Suite struct NotifierPlanTests {
    @Test func firstCheckOnlyTakesTheCursor() {
        let plan = UnitNotifier.plan(feed: NotificationFeed(items: [item(3), item(4)], latestId: 4), cursor: nil, pushActive: false)
        #expect(plan.post.isEmpty)
        #expect(plan.cursor == 4)
        // A unit with nothing sent yet still gets a cursor, so the first real one shows.
        #expect(UnitNotifier.plan(feed: NotificationFeed(items: [], latestId: nil), cursor: nil, pushActive: false).cursor == 0)
    }

    @Test func postsWhatIsNewInOrderCappedAtFive() {
        let feed = NotificationFeed(items: (5...12).reversed().map { item($0) }, latestId: 12)
        let plan = UnitNotifier.plan(feed: feed, cursor: 4, pushActive: false)
        #expect(plan.post.map(\.id) == [8, 9, 10, 11, 12])
        #expect(plan.cursor == 12)
    }

    @Test func pushActiveAdvancesWithoutPosting() {
        let plan = UnitNotifier.plan(feed: NotificationFeed(items: [item(5)], latestId: 5), cursor: 4, pushActive: true)
        #expect(plan.post.isEmpty)
        #expect(plan.cursor == 5)
    }

    @Test func followsAResetUnitDown() {
        let plan = UnitNotifier.plan(feed: NotificationFeed(items: [], latestId: 2), cursor: 40, pushActive: false)
        #expect(plan.cursor == 2)
        #expect(UnitNotifier.plan(feed: NotificationFeed(items: [], latestId: nil), cursor: 40, pushActive: false).cursor == 40)
    }
}

@Suite struct NotificationModelTests {
    @Test func tokenIsLowercaseHex() {
        #expect(PushToken.hex(Data([0x0a, 0xff, 0x10])) == "0aff10")
    }

    @Test func alertKindsReadAsTitles() {
        #expect(FeedItem.title(forAlertKind: "reminder_nutrients") == "Reminder: nutrients")
        #expect(FeedItem.title(forAlertKind: "pump_dry_run") == "Pump dry run")
        #expect(FeedItem.title(forAlertKind: "") == "Thryve")
    }

    @Test func missingProcedureIsRecognised() {
        #expect(APIError.server(message: #"No procedure found on path "notifications.feed""#).isMissingProcedure)
        #expect(APIError.invalidResponse(statusCode: 404).isMissingProcedure)
        #expect(!APIError.unauthorized.isMissingProcedure)
    }

    @Test func requestCarriesAlertForTheAcknowledgeAction() {
        let request = NotificationContent.request(for: item(7, alert: 3))
        #expect(request.identifier == "thryve-7")
        #expect(request.content.categoryIdentifier == NotificationContent.alertCategory)
        #expect(NotificationDelegate.alertId(in: request.content.userInfo) == 3)
        #expect(NotificationDelegate.alertId(in: ["alertId": "9"]) == 9)
        #expect(NotificationContent.request(for: item(8)).content.categoryIdentifier == NotificationContent.eventCategory)
    }

    @Test func registrationEncodesForCore() throws {
        let reg = DeviceRegistration(deviceId: "d1", name: "iPhone", token: nil, environment: "sandbox", bundleId: "com.thryve.app")
        let json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(reg)) as? [String: Any])
        #expect(json["platform"] as? String == "ios")
        #expect(json["token"] == nil)
        #expect(json["environment"] as? String == "sandbox")
    }
}

@Suite struct CoreClientNotificationTests {
    let base = URL(string: "http://unit.local:3000")!

    @Test func readsTheFeed() async throws {
        let session = StubProtocol.session("feed") { _ in
            (200, #"{"result":{"data":{"json":{"items":[{"id":9,"title":"Pump fault","body":"Dry run","level":"critical","alertId":4,"createdAt":"2026-11-16T10:00:00.000Z"}],"latestId":9}}}}"#)
        }
        let feed = try await CoreClient(baseURL: base, session: session).notificationFeed(after: 8)
        #expect(feed.items.first?.alertId == 4)
        #expect(feed.latestId == 9)
        let req = try #require(StubProtocol.requests("feed").first)
        #expect(req.url?.path == "/api/trpc/notifications.feed")
        #expect(req.url?.query?.removingPercentEncoding == #"input={"json":{"afterId":8,"limit":20}}"#)
    }

    @Test func fallsBackToAlertsOnOlderCores() async throws {
        let session = StubProtocol.session("feed-old") { req in
            if req.url?.path == "/api/trpc/notifications.feed" {
                return (404, #"{"error":{"json":{"message":"No procedure found on path \"notifications.feed\"","code":-32004}}}"#)
            }
            return (200, #"{"result":{"data":{"json":[{"id":5,"kind":"reminder_nutrients","active":true,"detail":"Add nutrients","raisedAt":"x","clearedAt":null,"acknowledgedAt":null,"dismissedAt":null},{"id":3,"kind":"tank_low","active":true,"detail":"Tank low","raisedAt":"x","clearedAt":null,"acknowledgedAt":null,"dismissedAt":null}]}}}"#)
        }
        let client = CoreClient(baseURL: base, session: session)
        let first = try await client.notificationFeed(after: nil)
        #expect(first.items.isEmpty && first.latestId == 5)
        let next = try await client.notificationFeed(after: 3)
        #expect(next.items.map(\.id) == [5])
        #expect(next.items.first?.title == "Reminder: nutrients")
        #expect(next.items.first?.alertId == 5)
    }

    @Test func registersTheDevice() async throws {
        let session = StubProtocol.session("register") { _ in (200, #"{"result":{"data":{"json":{"apnsConfigured":true}}}}"#) }
        let reg = DeviceRegistration(deviceId: "d1", name: "iPhone", token: "ab12", environment: "production", bundleId: "com.thryve.app")
        let status = try await CoreClient(baseURL: base, session: session).registerDevice(reg)
        #expect(status.apnsConfigured)
        let req = try #require(StubProtocol.requests("register").first)
        #expect(req.url?.path == "/api/trpc/notifications.devices.register")
        let body = try #require(req.httpBody.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        let json = try #require(body["json"] as? [String: Any])
        #expect(json["token"] as? String == "ab12")
    }

    @MainActor @Test func checkPostsNewItemsAfterTheFirstLook() async throws {
        let session = StubProtocol.session("check") { req in
            let after = req.url?.query?.removingPercentEncoding?.contains(#""afterId":2"#) == true
            return (200, after
                ? #"{"result":{"data":{"json":{"items":[{"id":3,"title":"Ready","body":"Pod 4 is ready to harvest"}],"latestId":3}}}}"#
                : #"{"result":{"data":{"json":{"items":[],"latestId":2}}}}"#)
        }
        let defaults = try #require(UserDefaults(suiteName: "test.\(UUID())"))
        UnitNotifier.setEnabled(true, defaults)
        let poster = RecordingPoster()
        let notifier = UnitNotifier(unitKey: "u", defaults: defaults, poster: poster)
        let api = CoreClient(baseURL: base, session: session)
        #expect(try await notifier.check(api: api) == 0)
        #expect(notifier.cursor == 2)
        #expect(try await notifier.check(api: api) == 1)
        #expect(poster.posted.map(\.body) == ["Pod 4 is ready to harvest"])
        #expect(notifier.cursor == 3)
    }

    @MainActor @Test func disabledNotifierDoesNothing() async throws {
        let defaults = try #require(UserDefaults(suiteName: "test.\(UUID())"))
        let poster = RecordingPoster()
        let notifier = UnitNotifier(unitKey: "u", defaults: defaults, poster: poster)
        #expect(try await notifier.check(api: DemoClient()) == 0)
        #expect(notifier.cursor == nil)
    }
}
