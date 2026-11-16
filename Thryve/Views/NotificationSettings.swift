import SwiftUI
import UIKit
import UserNotifications

/// Settings › Notifications: the switch, how notifications will reach this phone, and a test.
struct NotificationSettingsSection: View {
    @State private var registrar = PushRegistrar.shared
    @State private var on = UnitNotifier.isEnabled()
    @State private var testResult: String?
    @State private var busy = false

    var body: some View {
        Section {
            Toggle("Notifications", isOn: $on)
                .onChange(of: on) { _, value in
                    guard value != UnitNotifier.isEnabled() else { return }
                    Task {
                        busy = true
                        await registrar.setEnabled(value)
                        // Stays off if iOS permission was refused.
                        on = UnitNotifier.isEnabled()
                        busy = false
                    }
                }
                .disabled(busy)

            if on {
                LabeledContent("Delivery") {
                    Text(delivery).font(Theme.mono(13)).foregroundStyle(Theme.text2).multilineTextAlignment(.trailing)
                }
                Button("Send a test notification") {
                    Task { testResult = await registrar.sendTest() }
                }
                if let testResult {
                    Text(testResult).font(.footnote).foregroundStyle(Theme.text2)
                }
            }
            if registrar.authorization == .denied {
                Button("Allow notifications in iOS Settings") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text(footer)
        }
        .task { await registrar.refreshAuthorization() }
    }

    private var delivery: String {
        switch registrar.unitPush {
        case .ready: "Push (Apple)"
        case .registering: "Connecting…"
        case .checksOnly: "Background checks"
        case .unsupported: "Alerts only (update the unit)"
        case .failed: "Background checks"
        case .unknown: "—"
        }
    }

    private var footer: String {
        switch registrar.unitPush {
        case .ready:
            "Your unit's notification rules push straight to this iPhone through Apple, even when the app is closed."
        case .checksOnly where registrar.token == nil:
            "This build can't get push from Apple, so the app checks the unit in the background when iOS lets it. That can be minutes to hours apart. Banners show right away while the app is open."
        case .checksOnly:
            "Add an APNs key on the unit (Settings › Notifications on its web page) for instant push. Until then the app checks the unit in the background when iOS lets it."
        case .unsupported:
            "This unit's Thryve version has no notification rules, so you'll get its alerts. Update the unit for rules and push."
        case .failed(let message):
            "Couldn't register with the unit: \(message)"
        default:
            "Get your unit's notification rules (tank low, pump fault, ready to harvest…) on this iPhone. Rules are set up on the unit's web page."
        }
    }
}
