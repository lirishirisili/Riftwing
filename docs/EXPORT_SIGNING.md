# Export Signing — Manual Steps

Riftwing `export_presets.cfg` intentionally contains **no** keystores, provisioning
profiles, team IDs, or store SDK credentials. Complete these steps locally before
any store submission. See also `docs/EXPORT_VALIDATION.md` and
`manifests/product_identity.json`.

## Android

### Debug APK (local device testing)

1. Install Godot **4.7-stable** Android export templates  
   (`Editor → Manage Export Templates…`).
2. Editor Settings → Export → Android:
   - Android SDK path
   - Java SDK (JDK 17+)
   - Debug keystore (editor default is fine; do not commit it)
3. Export preset **Android Debug**  
   (`Project → Export… → Android Debug → Export Project`)  
   → `build/android/riftwing-debug.apk`
4. Install:
   ```bash
   adb install -r build/android/riftwing-debug.apk
   ```
5. The Debug preset keeps keystore path/password fields **empty** so Godot uses
   the editor debug keystore. Never paste release passwords into
   `export_presets.cfg`.

### Release AAB (Play Console)

1. Create an upload keystore **once**, outside the repo:
   ```bash
   keytool -genkey -v -keystore riftwing-upload.keystore -alias riftwing \
     -keyalg RSA -keysize 2048 -validity 10000
   ```
2. Do **not** commit the keystore or passwords.
3. In Godot → Export → **Android Release**, set release keystore fields in the
   editor (stored in `.godot/export_credentials.cfg`, gitignored) **or** export
   unsigned and sign with `jarsigner` / Play App Signing as your process requires.
4. Ensure Gradle build is enabled (preset already sets `use_gradle_build=true`
   and AAB format). Install the Android build template if Godot prompts
   (`Project → Install Android Build Template…`).
5. Export to `build/android/riftwing-release.aab`.
6. Upload via Play Console. Use Play App Signing as required by Google.
7. Increment `version/code` in the preset (and `version_code` in
   `manifests/product_identity.json`) for every Play upload.

## iOS (macOS or GitHub Actions)

Windows cannot produce a signed iOS build locally. Options:

### A) GitHub Actions (recommended)

1. Configure secrets per [`.github/GITHUB_ACTIONS_SETUP.md`](../.github/GITHUB_ACTIONS_SETUP.md).
2. Ensure App Store Connect has an app for `com.lishistudio.riftwing`.
3. Bump `manifests/product_identity.json` + sync `export_presets.cfg` versions.
4. **Actions → iOS — Godot TestFlight → Run workflow.** Optional: check **Also build iOS Simulator zip for Appetize** when you need an Appetize.io simulator zip.

Signing uses `ios/exportOptions.plist` (`teamID` + bundle id) and Codemagic CLI on the runner — **not** `application/app_store_team_id` in committed `export_presets.cfg`.

### B) Local Mac

1. Install Godot 4.7-stable + iOS export templates.
2. Export preset **iOS** with **Export Project Only** (preset default) into
   `build/ios/`.
3. In Apple Developer:
   - App ID matching `com.lishistudio.riftwing` (or the approved final ID)
   - Development + Distribution certificates
   - Provisioning profiles for devices / App Store
4. Open the Xcode project. Select Team / signing. Keep portrait orientation.
5. Archive and upload with Organizer / Transporter / TestFlight.
6. Leave Team ID and provisioning fields empty in git; set them only on the Mac or via CI.

## What is intentionally missing

- No Firebase / Analytics / IAP / Play Games / Game Center / AdMob SDKs
- Ads go through Unity LevelPlay (`AdsService` / `LevelPlayAdsService`); Unity Ads and Meta FAN are mediated networks only
- No committed keystores, provisioning passwords, or App Store Connect `.p8` in the repo
- No claim of App Store or Play Console acceptance from CI/Windows alone

See: `docs/09_BRAND_AND_NAMING.md`, `prompts/14_export_validation.md`.
