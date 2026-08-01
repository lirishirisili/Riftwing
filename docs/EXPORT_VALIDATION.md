# Export Validation — Milestone 14

Shared Godot 4.7 project for Android and iOS. No AdMob / tracking SDKs (ads removed). Still no IAP, analytics, Firebase, or store SDKs.

Provisional identity (change before submission): `manifests/product_identity.json`

| Field | Value |
|---|---|
| Brand | RIFTWING |
| Android application id | `com.lishistudio.riftwing` |
| iOS bundle id | `com.lishistudio.riftwing` |
| Version name | `0.1.2` |
| Version code / build | `3` (Android `version/code`; iOS `application/version`) |
| Orientation | Portrait (`project.godot` → `window/handheld/orientation=1`) |
| Android minSdk | 24 |
| Android targetSdk | 36 (Release/Gradle override; Debug APK verified same via template default) |
| iOS minimum | 15.0 |

---

## What this OS can validate

**Current environment used for this milestone: Windows.**

| Check | Windows | macOS + Xcode |
|---|---|---|
| Export preset syntax / IDs / versions | Yes | Yes |
| Portrait orientation in project settings | Yes | Yes |
| Android SDK / JDK presence | Yes (if installed) | Yes |
| Godot Android export templates | Yes (if installed) | Yes |
| Android Debug APK export | Yes (if SDK + templates) | Yes |
| Install APK via adb | Yes (device/emulator) | Yes |
| Android Release AAB (unsigned / locally signed) | Partial (Gradle + templates; signing local only) | Same |
| iOS Xcode project / IPA / Archive / TestFlight | **No** | **Required** |
| App Store Connect validation | **No** | **Required** |

**This milestone does not claim an iOS binary was built or tested.** iOS work on Windows stops at preset + documentation.

---

## Android validation

### Preset: Android Debug
- Output: `build/android/riftwing-debug.apk`
- Format: APK (`gradle_build/export_format=0`), classic template export (`use_gradle_build=false`)
- Package: `com.lishistudio.riftwing` / display name `RIFTWING`
- Version: name `0.1.2`, code `3`
- Arch: `arm64-v8a` only
- SDK: min/target left empty (Godot forbids overrides without Gradle); template default applies for local debug
- Icons / splash: `assets/branding/*`
- Permissions: **vibrate** only (haptics). No internet, location, camera, storage, notifications
- Signing: `package/signed=true` with **empty** preset keystore fields → Godot uses the **editor** debug keystore (`Editor Settings → Export → Android`). No passwords in the repo.
- Excludes review docs / tests from the PCK

### Preset: Android Release (AAB readiness)
- Output: `build/android/riftwing-release.aab`
- Format: AAB + Gradle (`use_gradle_build=true`, `export_format=1`)
- Same IDs / versions / icons / vibrate-only permissions
- `package/signed=false` and empty `keystore/release*` in `export_presets.cfg`
- Release signing is configured only in local `.godot/export_credentials.cfg` or the editor UI (gitignored). See `docs/EXPORT_SIGNING.md`.

### Portrait / pause / safe area (runtime, already in project)
- Portrait: `display/window/handheld/orientation=1`
- Safe areas: `SafeArea` helper + UI insets (milestone 11)
- Pause / focus: AppRoot saves + ducks audio on `APPLICATION_PAUSED` / focus loss

### How to export an Android test APK (Windows)

1. Install **Godot 4.7-stable** export templates  
   Editor: `Editor → Manage Export Templates… → Download and Install`  
   Or extract `Godot_v4.7-stable_export_templates.tpz` into  
   `%APPDATA%\Godot\export_templates\4.7.stable\`
2. Confirm Editor Settings → Export → Android:
   - Android SDK path (e.g. `%LOCALAPPDATA%\Android\Sdk`)
   - Java SDK path (JDK 17+)
   - Debug keystore (Godot default is fine)
3. `Project → Export… → Android Debug → Export Project`  
   Or CLI:
   ```text
   godot --headless --path . --export-debug "Android Debug" build/android/riftwing-debug.apk
   ```
4. Install:
   ```text
   adb install -r build/android/riftwing-debug.apk
   ```
5. Smoke: portrait lock, main menu → run → background/resume still alive, no store SDKs.

### Google Play AAB checklist (preparation only)
- [ ] Final application id approved and unique
- [ ] `version/code` incremented per upload
- [ ] Upload keystore created **outside** the repo; release fields set only locally
- [ ] Export **Android Release** → `.aab`
- [ ] Play App Signing enrolled in Play Console
- [ ] Store listing, content rating, target audience, Data safety form
- [ ] No ads SDK; `AdsService` remains no-op; still no IAP/analytics/Firebase unless a later milestone adds them

---

## iOS validation (configuration only on Windows)

### Preset: iOS
- Bundle id: `com.lishistudio.riftwing`
- Name: `RIFTWING`
- `application/short_version`: `0.1.2`; `application/version` (build): `3`
- `application/min_ios_version`: `15.0`
- `application/targeted_device_family`: `1` (iPhone)
- `application/export_project_only=true` → export an Xcode project for Mac signing (no fake IPA success)
- Team id / provisioning / code-sign identities: **empty** (filled on Mac only)
- Push / Wi‑Fi capabilities: off
- Icon: `assets/branding/icon_ios_1024.png`
- Launch storyboard uses project dark blue background
- Portrait comes from shared `project.godot` orientation

### Exact steps that must be completed later on macOS

1. Install matching **Godot 4.7-stable** + iOS export templates on the Mac.
2. Open this same project; `Project → Export… → iOS`.
3. Set (locally, never commit):
   - Apple Team ID
   - Debug / Release code sign identities
   - Provisioning profile UUID or specifier for App ID `com.lishistudio.riftwing`
4. Prefer **Export Project Only**, then open the generated Xcode project under `build/ios/`.
5. In Xcode:
   - Select your Team; enable automatic signing **or** attach profiles
   - Confirm **Portrait** orientations; disable Landscape unless approved
   - Confirm bundle identifier matches the provisional (or final) id
   - Run on a device / simulator for smoke tests
6. **Product → Archive** → distribute to **TestFlight** or App Store Connect.
7. Complete privacy nutrition labels, encryption compliance, screenshots, and metadata in App Store Connect.

**Do not invent certificates, profiles, or a successful App Store validation from Windows.**

### CI (Codemagic + GitHub Actions)

Shared scripts under `.github/scripts/`; see [`.github/GITHUB_ACTIONS_SETUP.md`](../.github/GITHUB_ACTIONS_SETUP.md).

- **Codemagic:** root `codemagic.yaml` → workflow **iOS — Godot TestFlight** (env group `basic` with the three ASC API vars)
- **GitHub Actions:** manual `workflow_dispatch` → same pipeline scripts + `ios-publish-testflight.sh`
- Requires: `APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_KEY_IDENTIFIER`, `APP_STORE_CONNECT_PRIVATE_KEY` (same team as GG/Salino if shared)
- Does **not** replace App Store Connect metadata, screenshots, or privacy labels
- First-time scheme name: if archive fails on scheme, check CI log for `Discovered Xcode scheme:` and set `XCODE_SCHEME` in `.github/scripts/ci-env.sh` if needed

### App Store / TestFlight checklist (preparation only)
- [ ] Final bundle id registered in Apple Developer
- [ ] Distribution certificate + App Store / Ad Hoc profiles
- [ ] Xcode archive succeeds on macOS
- [ ] TestFlight internal build installed on a physical iPhone
- [ ] Portrait + safe area + background/resume verified on device
- [ ] No ads SDK; App Privacy in App Store Connect must not claim tracking / advertising data for ads
- [ ] No Game Center / push / tracking SDKs

---

## Automated config probe

```text
godot --headless --path . --script res://tests/export_validation_probe.gd
```

Expect `EXPORT_VALIDATION_PROBE_OK`. This checks identity sync, portrait, permissions posture, and template/SDK presence. It does **not** claim an iOS build.

---

## Remaining external dependencies

| Dependency | Needed for |
|---|---|
| Godot 4.7 Android export templates | Debug APK / Release AAB |
| Android SDK platforms + build-tools | Export / Gradle |
| JDK 17+ | Android export |
| Physical device or emulator | On-device smoke |
| macOS + Xcode + Apple Developer account | Any real iOS binary / TestFlight / App Store |
