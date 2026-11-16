# Installing Thryve on your iPhone with TestFlight

You don't need a Mac that runs Xcode 26. GitHub Actions builds the app on its
own Mac, signs it with your Apple Developer account and uploads it to
TestFlight. You install it from the TestFlight app on your iPhone.

The workflow is `.github/workflows/testflight.yml`. It runs when you start it by
hand (Actions › TestFlight › Run workflow) or when you push a `v*` tag. Until the
four secrets below exist it skips the upload and passes.

## One-time setup

You need a paid Apple Developer Program membership ($99/year). Sign in at
<https://developer.apple.com/account> and <https://appstoreconnect.apple.com>
with the same Apple ID.

### 1. Find your Team ID

developer.apple.com › Account › Membership details › **Team ID** (10 characters,
like `A1B2C3D4E5`). This is `APPLE_TEAM_ID`.

### 2. Register the bundle IDs (optional, CI can do it)

The build registers them itself the first time, but you can create them first at
developer.apple.com › Certificates, Identifiers & Profiles › Identifiers › **+** ›
App IDs › App:

- `com.thryve.app`, with **Push Notifications** checked.
- `com.thryve.app.widgets` (the Live Activity extension), no extra capabilities.

If `com.thryve.app` is taken, pick your own (for example
`com.yourname.thryve`), change `bundleIdPrefix`/`PRODUCT_BUNDLE_IDENTIFIER` in
`project.yml` (and `com.thryve.app.widgets` to match), and use the same bundle ID
for the unit's APNs settings.

### 3. Create the app record

App Store Connect › Apps › **+** › New App:

- Platform: iOS
- Name: Thryve (it must be unique on the App Store; if it's taken, try
  "Thryve Garden". This name isn't shown under the icon)
- Primary language: English (U.S.)
- Bundle ID: `com.thryve.app`
- SKU: `thryve-ios` (anything)
- User access: Full access

### 4. Create the App Store Connect API key (for the build)

App Store Connect › Users and Access › Integrations › App Store Connect API ›
Team Keys › **+**:

- Name: `GitHub TestFlight`
- Access: **Admin**. With App Manager the archive works, but the upload fails with
  "Cloud signing permission error", because only Admin keys may create the cloud
  distribution certificate.

Download the `AuthKey_XXXXXXXXXX.p8` file. You can only download it once. Note
the **Key ID** in the key's row and the **Issuer ID** above the list.

### 5. Add the repository secrets

github.com/kaniick/Thryve-ios › Settings › Secrets and variables › Actions ›
New repository secret:

| Secret | Value |
|---|---|
| `ASC_KEY_ID` | the API key's Key ID |
| `ASC_ISSUER_ID` | the Issuer ID |
| `ASC_KEY_P8` | the .p8 file, base64: `base64 -i AuthKey_XXXXXXXXXX.p8 \| pbcopy` on a Mac |
| `APPLE_TEAM_ID` | your Team ID |

### 6. Run it

Actions › TestFlight › Run workflow (branch `dev`). After about 15 minutes the
build is uploaded. Apple then processes it for 5–30 minutes. Then:

1. In App Store Connect › your app › TestFlight, answer the export compliance
   question if asked. The app already declares no non-exempt encryption.
2. Add yourself under **Internal Testing** (create a group and add your Apple ID).
3. Install **TestFlight** from the App Store on your iPhone, open the invite and
   install Thryve.

TestFlight builds expire after 90 days. Run the workflow again for a fresh one.

## The push key for your unit (different key)

The API key above is only for building. To let the **unit** push to your
iPhone, create an APNs key as well:

developer.apple.com › Certificates, Identifiers & Profiles › Keys › **+** ›
name `Thryve push`, check **Apple Push Notifications service (APNs)**, environment
**Sandbox & Production**, Continue › Register › Download `AuthKey_YYYYYYYYYY.p8`.

Paste it into the unit's web page under Settings › Notifications › iPhone (APNs)
with its Key ID, your Team ID and bundle ID `com.thryve.app`. See
[notifications.md](notifications.md).
