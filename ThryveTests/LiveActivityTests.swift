import Foundation
import Testing
@testable import Thryve

@Suite struct WateringActivityTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func runningPumpBecomesAState() throws {
        let pump = ActuatorState(on: true, level: 100, since: ISO.string(now.addingTimeInterval(-30)), fault: nil, remainingS: 90)
        let state = try #require(WateringActivities.state(for: pump, now: now))
        #expect(state.startedAt == now.timeIntervalSince1970 - 30)
        #expect(state.endsAt == now.timeIntervalSince1970 + 90)
        #expect(state.powerPct == 100)
        #expect(state.running)
        #expect(state.progress(at: now) == 0.25)
        #expect(state.interval != nil)
    }

    @Test func stoppedOrMissingPumpHasNoState() {
        #expect(WateringActivities.state(for: nil, now: now) == nil)
        #expect(WateringActivities.state(for: ActuatorState(on: false, level: 0, since: ISO.string(now)), now: now) == nil)
    }

    @Test func keepsWhatTheUnitPushedWhenTheReadingLacksIt() throws {
        let previous = WateringAttributes.ContentState(startedAt: 100, endsAt: 400, powerPct: 30, softStartS: 1.5, running: true, fault: nil)
        let pump = ActuatorState(on: true, level: 30, since: "not a date", fault: nil, remainingS: nil)
        let state = try #require(WateringActivities.state(for: pump, now: now, previous: previous))
        #expect(state.startedAt == 100 && state.endsAt == 400 && state.softStartS == 1.5)
    }

    @Test func onlyRealChangesUpdateTheActivity() {
        let a = WateringAttributes.ContentState(startedAt: 0, endsAt: 120, powerPct: 100, softStartS: 0, running: true, fault: nil)
        var b = a
        b.endsAt = 121.5
        #expect(!WateringActivities.differs(a, b))
        b.endsAt = 180
        #expect(WateringActivities.differs(a, b))
        var c = a
        c.fault = "dry run"
        #expect(WateringActivities.differs(a, c))
    }

    @Test func rampingAndOpenEndedRuns() {
        let s = WateringAttributes.ContentState(startedAt: now.timeIntervalSince1970, endsAt: nil, powerPct: 100, softStartS: 2, running: true, fault: nil)
        #expect(s.isRamping(at: now.addingTimeInterval(1)))
        #expect(!s.isRamping(at: now.addingTimeInterval(3)))
        #expect(s.interval == nil && s.progress(at: now) == nil)
    }

    @Test func contentStateMatchesCorePushJSON() throws {
        // What core puts in an APNs liveactivity push's "content-state".
        let json = #"{"startedAt":1800000000,"endsAt":1800000120,"powerPct":100,"softStartS":1.5,"running":true,"fault":null}"#
        let state = try JSONDecoder().decode(WateringAttributes.ContentState.self, from: Data(json.utf8))
        #expect(state.end == Date(timeIntervalSince1970: 1_800_000_120))
        #expect(state.softStartS == 1.5)
    }

    @Test func activityTokenEncodesForCore() throws {
        let reg = ActivityTokenRegistration(deviceId: "d1", kind: "start", activityId: nil, token: "beef", environment: "production")
        let json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(reg)) as? [String: Any])
        #expect(json["kind"] as? String == "start")
        #expect(json["activityId"] == nil)
    }
}
