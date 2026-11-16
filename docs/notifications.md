# Notifications and the watering Live Activity

The unit decides **when** to notify (its notification rules: IF something
happens THEN notify, with conditions, quiet hours and a cooldown). This app is
one of the places a rule can send to, next to Pushover, Pushbullet and Apprise.
Rules are set up on the unit's web page.

## Two ways a notification reaches the phone

| | Push (APNs) | Background checks |
|---|---|---|
| Needs | A paid Apple Developer account, an APNs key on the unit, the app from TestFlight or Xcode | Nothing extra |
| Speed | Seconds, even with the app closed | Instant while the app is open; otherwise whenever iOS wakes the app (often 15 min to hours, less if you rarely open it) |
| Path | Unit → Apple → phone. The unit talks to Apple directly with your key. No Thryve server, no relay | Phone → unit on your Wi-Fi |
| Away from home | Yes | No (the phone must reach the unit) |

The app always keeps both. When the unit can push, the background check only
moves its bookmark forward, so you never get a banner twice.

**Turn it on:** in the app, Settings › Notifications. iOS asks for permission.
The app then registers this iPhone with the unit as an "iOS" channel. The
**Delivery** row says what you'll get: *Push (Apple)*, *Background checks*, or
*Alerts only (update the unit)* when the unit's Thryve version is older than
notification rules (you'll still get its alerts). **Send a test notification**
asks the unit to push one, and shows a local one when push isn't set up.

Alert banners have an **Acknowledge** button. It acknowledges the alert on the
unit without opening the app.

## Watering Live Activity

While the pump runs, the lock screen and the Dynamic Island show the cycle:

- time left counting down, and time elapsed
- a progress bar, and water rising up a tower outline as the run goes on
- the pump power % and the soft-start ramp
- a **Stop** button (it calls the unit's pump stop and only closes the activity
  once the unit reports the pump off)

Compact Dynamic Island: a pulsing drop and the countdown. Minimal: a ring that
fills. Expanded: the tower, the countdown, power, the bar and Stop.

The countdown and fill are drawn by iOS from the run's start and end, so they
keep moving without updates. A run with no set length counts up instead.

It starts when the app sees the pump start (open, or in the background). With
push set up, the unit also starts it remotely (push-to-start), updates it when
the run changes, and ends it when the pump stops, even with the app closed.
A run that passes its end with no word from the unit shows as out of date.

## Unit side (core)

Core endpoints the app uses (tRPC, `/api/trpc`):

| Procedure | |
|---|---|
| `notifications.feed {afterId, limit}` | Notifications for iOS devices after a cursor. Older cores: the app falls back to `alerts.list` |
| `notifications.devices.register {deviceId, name, platform, token, environment, bundleId}` | This phone as an iOS channel; `token` is the APNs device token (hex) or absent |
| `notifications.devices.unregister {deviceId}` | |
| `notifications.devices.test {deviceId}` | `{sent, via: "apns" \| "feed"}` |
| `notifications.activities.register {deviceId, kind: "start" \| "update", activityId, token, environment}` | Live Activity push-to-start and update tokens |

Pushes core sends: `apns-push-type: alert` to topic `com.thryve.app` with
`aps.category` `THRYVE_ALERT` (with `alertId`) or `THRYVE_EVENT`, and
`apns-push-type: liveactivity` to `com.thryve.app.push-type.liveactivity`
with `content-state` `{startedAt, endsAt, powerPct, softStartS, running, fault}`
(Unix seconds) and, for push-to-start, `attributes-type: "WateringAttributes"`.

## Building it yourself

Push and Live Activity push need the Push Notifications capability, which needs
a paid team. The project turns it on (`Thryve/Thryve.entitlements`). With a free
personal team, clear **Code Signing Entitlements** for the Thryve target to
build. You then get background checks and local Live Activities only.

Debug builds from Xcode use the APNs **sandbox**; TestFlight and App Store builds
use **production**. The app tells the unit which one with each token.
