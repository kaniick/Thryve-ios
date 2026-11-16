# Thryve for iPhone

> **Modified version.** Thryve is a rebranded, modified fork of
> [SeedyPod](https://github.com/seedypod) by Jonathan Ng and the SeedyPod contributors.
> This app is forked from [seedypod/ios](https://github.com/seedypod/ios) and remains
> under the AGPL-3.0 (see [LICENSE](LICENSE) and [NOTICE](NOTICE)).

Your Gardyn tower in 3D, run from your own network. The app talks straight to
[Thryve core](https://github.com/kaniick/Thryve) on your LAN. It has no
account, no cloud and no telemetry.

<p align="center">
  <img src="docs/screenshots/home.png" width="300" alt="Home: the tower in 3D on day 19, ready pods flagged" />
  <img src="docs/screenshots/pod.png" width="300" alt="A picked pod: Arugula, ready to harvest, with its harvest window" />
</p>

- **Home is the tower:** every pod colored by how it's doing, the plants sized
  by how far along they are, the tank showing its level and the light bars
  glowing at their brightness. Tap a pod for what's in it, where it is in its
  grow and what to do about it.
- **Light and water:** brightness and on/off (held for 30 minutes over the
  schedule, as on the web), and bounded pump runs.
- **Alerts:** acknowledge reminders and latched hardware faults.
- **Notifications:** the unit's notification rules on your phone, through Apple
  Push straight from the unit (no relay) or background checks on your Wi-Fi.
  Alerts can be acknowledged from the banner. See
  [docs/notifications.md](docs/notifications.md).
- **Watering Live Activity:** the pump's run on the lock screen and in the
  Dynamic Island, with the time left, progress, water rising up the tower, power
  and a Stop button.
- **Finds your unit:** Bonjour (`_thryve._tcp`), or type its address. An
  optional API key is kept in the Keychain.
- **Demo mode:** a simulated tower on day 19 of a grow, with no hardware
  needed.

## Install with TestFlight (no Mac needed)

GitHub Actions builds, signs and uploads the app to TestFlight with your Apple
Developer account. Setup: [docs/testflight.md](docs/testflight.md).

## Build

Requires Xcode 26+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen generate          # after adding or moving files; commit the regenerated project
open Thryve.xcodeproj
```

Signing: the bundle IDs are `com.thryve.app` and `com.thryve.app.widgets` (the Live
Activity extension) and `DEVELOPMENT_TEAM` is blank. Push needs a paid team; with a free
personal team, clear Code Signing Entitlements (see [docs/notifications.md](docs/notifications.md)). To run on a
device, pick your own team under Signing & Capabilities (or set `DEVELOPMENT_TEAM` in
`project.yml` and regenerate). If `com.thryve.app` is taken in your account, change
`PRODUCT_BUNDLE_IDENTIFIER` in `project.yml` and regenerate.

```sh
xcodebuild test -project Thryve.xcodeproj -scheme Thryve \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO
swiftlint --strict
```

To work against a unit without hardware, run core's simulator
(`pnpm dev:sim` in kaniick/Thryve) and connect to `<your Mac's IP>:3000`.

## How it fits

| Piece | Where |
|---|---|
| tRPC transport (`CoreClient`) | Ported from sleepypod/ios's `SleepypodCoreClient`, per [core ADR-0017](https://github.com/kaniick/Thryve/blob/dev/docs/adr/0017-ios-client.md), with `X-API-Key` added |
| Live updates (`EventStream`) | core's `/api/ws` CoreEvent frames trigger a batched refresh |
| Notifications (`Notifications/`) | core's "ios" channel: `notifications.feed` and APNs device tokens |
| Live Activity (`LiveActivity/`, `ThryveWidgets/`) | ActivityKit + WidgetKit; core pushes `liveactivity` updates |
| Discovery (`UnitDiscovery`) | `NWBrowser` for `_thryve._tcp`, TXT `id`/`v`/`auth` |
| Palette (`Theme`) | core's `web/src/globals.css` `--lp-*` tokens |

`dev` is the integration branch and `main` is for releases. Use conventional commits.

## License

[AGPL-3.0](LICENSE). IBM Plex Mono is under the SIL Open Font License (`Thryve/Resources/Fonts/OFL.txt`).
