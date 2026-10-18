# iOS staging build setup

## Current scope

The `ios-staging-build` workflow now creates a **signed App Store distribution
IPA** on Codemagic, following the successful unsigned build. It uses the uploaded
certificate/private key and provisioning profile. A manual Start build now also
validates and uploads the IPA to App Store Connect using `altool` and an
app-specific password. It does not create signing identities, use the App Store
Connect API, or assign TestFlight testers. There are no automatic triggers or
Codemagic `publishing:` block.

- Bundle ID: `com.tkr.pelinesadmin` (RunnerTests: `.RunnerTests`).
- Display name: **Pelines Admin**.
- Version: Flutter `1.0.0+2`; retain Flutter's plist substitutions.
- Deployment target: **iOS 15.0**; iPhone and iPad supported.
- Native dependencies: **Swift Package Manager**, not a CocoaPods migration.
- Printer: manually entered IP/port, Dart TCP + ESC/POS, normally port **9100**.
- `NSLocalNetworkUsageDescription` explains printer connection/printing.
- `NSPhotoLibraryUsageDescription` explains choosing a menu product photo.
- No Bonjour services, multicast entitlement, ATS exceptions, camera/microphone
  permissions, Epson SDK, or background printing capability is added.
- A small STAGING strip appears on every route only for `APP_ENV=staging`.

## First manual Codemagic run

1. Give Codemagic access to this GitHub repository. Select configuration from
   `codemagic.yaml` on `main`, then workflow `ios-staging-build`.
2. Create an environment group named **pelines_staging**, available to this app.
   Set the following variables (mark the client key secure/encrypted):

   | Variable | Value/source |
   | --- | --- |
   | `APP_ENV` | `staging` |
   | `API_BASE_URL` | `https://pelines-api-staging.aiwithtalha.com/v1` |
   | `SUPABASE_URL` | `https://qrtuwjpofwtefueqtokp.supabase.co` |
   | `SUPABASE_ANON_KEY` | Staging anon/publishable client key from approved secure configuration |

3. Confirm the uploaded Apple Distribution certificate (reference
   `pelines_admin_distribution`) and matching App Store profile for
   `com.tkr.pelinesadmin` are available to this app's Codemagic team, unexpired,
   and belong to Apple Team **B4YBH74VKG**. The certificate includes its private
   key and the profile shows the green matching-certificate check.
   `environment.ios_signing` fetches uploaded identities by `app_store` and
   bundle identifier; no profile reference name or new secret variable is needed.
   Do not mix reference-name selectors with these selectors. No Apple API key
   is needed for this build using already uploaded identities.
4. After the reviewed YAML is available in Git, start `ios-staging-build` manually
   on the intended commit. It retains M2, Flutter **3.47.2**, Xcode **26.6**,
   locked dependencies, analyze/tests, and the existing staging JSON validation.
   `xcode-project use-profiles` applies signing to the CI checkout and generates
   `$HOME/export_options.plist`; export is pinned to team `B4YBH74VKG` and local
   `destination=export`. No manual Xcode project edits are needed in Git.
   Flutter regenerates configuration on macOS and SwiftPM resolves before:

   ```sh
   flutter build ipa --release \
     --export-options-plist="$HOME/export_options.plist" \
     --dart-define-from-file="$STAGING_DEFINE_FILE"
   ```

   The ephemeral JSON is deleted on shell exit, including ordinary build failures.
5. Success means the signed archive passes bundle/display-name and code-signature
   checks and a nonempty `build/ios/ipa/*.ipa` exists as a downloadable artifact.
   Signed IPA generation has already passed in Codemagic.
   This App Store IPA is not an ad-hoc installation package; downloading it does
   not distribute it through TestFlight. The next step uploads it to Apple. Review any
   separate pre-existing Codemagic UI workflows/webhooks before running.

Never commit `.env.staging.json`, generated xcconfig/plugin files, keys,
certificates, profiles, or build products. Do not print configuration values or
use verbose build logging to expose dart-defines. The client key is necessarily
embedded in the compiled app; encrypted CI storage does not make it a server
secret. Never use a service-role/secret key. The generator rejects wrong URLs
and non-anon/wrong-project legacy JWTs; publishable-key ownership must be
verified when setting the secure group.

The existing Windows-generated files are ignored. Do not hand-edit their paths
or copy them to CI. All current native plugins declare SwiftPM support; do not
add a Podfile unless a specific macOS dependency failure demonstrates a need.
The first Mac run must also check native dependency/privacy-manifest warnings.

## Icon source

`assets/branding/pelines_admin_icon.png` is the approved Desktop `appicon.png`
source (1579 x 996, transparent). Run `python3 tools/prepare_ios_icons.py`
(Pillow required) to regenerate both platforms. The complete artwork is scaled
proportionally and centered without cropping or redesign. iOS uses an opaque
black square, including the 1024px marketing icon. Android retains the existing
black adaptive background and generates normal, round, and adaptive foreground
icons for all five densities, with circular safe margins where required.

## Manual upload with app-specific password (provisional)

The workflow imports the existing secure group **apple_upload** with `APPLE_ID`
and `APPLE_APP_SPECIFIC_PASSWORD`. Keep both marked secret in Codemagic; never
put their values in Git. Use an app-specific password, not the Apple account's
normal password. The Apple account must have upload access to the app record,
with applicable agreements accepted. No ASC API key, issuer ID, or `.p8` is used.

After building, the upload step disables shell tracing, requires both variables,
and fails clearly unless exactly one nonempty regular `build/ios/ipa/*.ipa`
exists. It runs `xcrun altool --validate-app` followed by `--upload-app`, both with
`-t ios -u "$APPLE_ID" -p "$APPLE_APP_SPECIFIC_PASSWORD"`. `set -euo pipefail`
stops the step if validation fails, so upload is not attempted. Do not enable
shell tracing or verbose credential logging. The IPA remains a build artifact.

This is a provisional upload route; a future separately reviewed migration to
ASC API authentication would remove the dependency on an individual's Apple
account and app-specific password. It is not configured by this change.

Before pressing **Start build**, confirm the intended commit and app record,
secure group access, and a build number that Apple has not already accepted for
this version. Both Flutter commands currently request version **1.0.0**, build
**6**, and the archived app's version and build are checked before upload. Build
5 has already been used in App Store Connect. There is no automatic numbering
or ASC API integration configured; update both build-number arguments and the
archive check before a later upload, after confirming the latest number in ASC.
The shared `pubspec.yaml` version is not used for these explicit overrides.
Every manual run now attempts upload after validation;
there is no separate approval prompt within the run. No run/upload was performed
while preparing this configuration.

Upload acceptance is not the end of Apple processing or a public release. Check
App Store Connect for processing errors, export compliance, and build availability.
TestFlight tester assignment/distribution remains a separate manual decision.

Apple reference: [Validate and upload builds with altool](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds).

## Later TestFlight and physical smoke test

1. Use an iPad mini supporting the current TestFlight app (currently iPadOS 16+,
   mini 5th generation or newer). Install, confirm STAGING, login, verify admin,
   locations, Today, and Menu using read-only actions.
2. On the printer's reachable LAN, select Network Epson/ESC-POS, enter its IP and
   port 9100, and use Test Connection. Grant Local Network access; retry the
   connection test if the first prompt outlasts the four-second timeout.
3. After separate physical-test authorization, enable local printing and issue
   one Test Print. Verify one ticket, accents, wrapping, feed/cut, submitted queue
   state, and no duplicate after relaunch. Submitted is not physical confirmation;
   ambiguous delivery stays unknown and must not be blindly retried.

No Accept/Cancel/refund, menu upload, email, or other business mutation belongs
to this smoke test. Android-only foreground alert sound remains best-effort;
its missing iOS channel is caught and does not block printing.

References: [Flutter SwiftPM](https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-app-developers),
[Codemagic Flutter workflows](https://docs.codemagic.io/yaml-quick-start/building-a-flutter-app/),
[Apple local-network privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy),
[Apple upload requirements](https://developer.apple.com/news/upcoming-requirements/).

Signing reference: [Codemagic uploaded signing identities](https://docs.codemagic.io/yaml-code-signing/signing-ios/).
