import ActivityKit
import AppIntents
import Foundation

/// The Stop button on the watering Live Activity. A `LiveActivityIntent` runs in
/// the app's process, so it uses the app's own pump stop call (`pump.stop`), then
/// confirms with the unit's answer: the activity only ends once the unit reports
/// the pump off. Stopping is always the safe direction; nothing here starts it.
struct StopPumpIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop watering"
    static let description = IntentDescription("Stops the Gardyn's pump.")
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        #if !THRYVE_WIDGET
        try await WateringActivities.stopFromActivity()
        #endif
        return .result()
    }
}
