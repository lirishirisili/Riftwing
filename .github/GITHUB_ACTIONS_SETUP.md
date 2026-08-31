# CI/CD — RIFTWING (iOS / Godot)

Two hosts run the **same** Godot → sign → IPA pipeline (shared `.github/scripts/`). Android stays local (Godot export on your machine).

## Workflows

| Host | Config | Trigger | Output |
|------|--------|---------|--------|
| **Codemagic** | `codemagic.yaml` → `ios-testflight` | Start build in Codemagic UI | IPA → App Store Connect |
| **GitHub Actions** | `.github/workflows/ios-testflight.yml` | manual (`workflow_dispatch`) | IPA → App Store Connect |
| **GitHub Actions** | `.github/workflows/ios-appetize.yml` | manual (`workflow_dispatch`) | Simulator `.app` / zip for Appetize only (no ASC secrets) |

## Codemagic setup

1. Add the app in Codemagic (project type **Other** / custom) and select root [`codemagic.yaml`](../codemagic.yaml).
2. Create (or reuse) environment group **`basic`** with the three App Store Connect API vars (same values as GitHub Secrets below).
3. Enable Codemagic **build number** for the app so `$PROJECT_BUILD_NUMBER` increments (wired as `BUILD_NUMBER` in the YAML).
4. Start workflow **iOS — Godot TestFlight**.

Scripts: `setup-codemagic-cli.sh` → `godot-ios-testflight-run.sh`. Upload uses YAML `publishing.app_store_connect` (not the GHA publish script).

`submit_to_testflight` is **`false`** (upload only). External beta review needs [TestFlight test information](https://appstoreconnect.apple.com/) (feedback email + beta contact). After that is filled, set `submit_to_testflight: true` in `codemagic.yaml`.

There is no GitHub→Codemagic API trigger; start builds from the Codemagic UI (or Codemagic webhooks you configure there).

## Fast TestFlight path (shared scripts)

Script: `.github/scripts/godot-ios-testflight-run.sh`

1. Select Xcode (GHA: Xcode 26; Codemagic: image `xcode: latest`) + install Codemagic CLI (signing / ASC API)
2. Install/cache Godot **4.7-stable** + iOS export templates
3. Optional probes (`run_probes`, GHA only): `export_validation_probe.gd`, `ads_service_probe.gd`
4. Resolve unique `CFBundleVersion` (`ios-resolve-versions.sh`, queries App Store Connect)
5. Build iOS LevelPlay plugin (`.github/scripts/build-ios-levelplay-plugin.sh`) → `ios/plugins/`
6. Godot headless import (bounded) → patch iOS `application/version` → `--export-release` iOS preset → `build/ios/riftwing.xcodeproj`
7. Stamp `CURRENT_PROJECT_VERSION` on the Xcode project; CocoaPods LevelPlay (`ios-levelplay-pods.sh`)
8. Fetch signing files → `xcode-project use-profiles` → resolve SPM/Pods
9. `xcodebuild archive` (workspace when pods present) → verify archived plist → export IPA
10. **Publish:** Codemagic YAML `publishing` · GHA `ios-publish-testflight.sh`
11. Optional: Simulator zip for Appetize (`build_appetize`)

On GitHub Actions, publish **does not** pass `--testflight` by default (same reason as Codemagic). After Beta App Information is filled, set repository variable `SUBMIT_TESTFLIGHT_BETA_REVIEW=true` or workflow input **Submit external TestFlight beta review** to `true`.

**Skipped by default on GHA (saves macOS minutes):**

- Config probes (`run_probes` input, default `false`)
- Uploading IPA to GitHub Artifacts (`upload_ipa_artifact` — TestFlight does not need this)
- iOS Simulator zip for Appetize (`build_appetize` input, default `false`)

**Signing:** purge Distribution certs (Apple quota) → `fetch-signing-files --create` → `xcode-project use-profiles`. Same App Store Connect API key pattern as Garden Guardians (GG). Do **not** use Codemagic `ios_signing` — profiles are created at build time via the API.

**Build number (`CFBundleVersion`):** CI must stamp a value strictly higher than any previously uploaded build. Godot 4 generates Info.plist from `CURRENT_PROJECT_VERSION`, so patching Info.plist alone does not stick.

| Host | Source |
|------|--------|
| Both | `ios-resolve-versions.sh` → `max(TestFlight latest + 1, IOS_BUILD_NUMBER_FLOOR, run number)` |
| Codemagic | `$PROJECT_BUILD_NUMBER` is a candidate, then raised against Apple + floor |
| GitHub Actions | `github.run_number` is a candidate, then raised against Apple + floor |

`APP_STORE_APPLE_ID` is `6792694067` (Riftstrike). Floor is `12` while Apple already has build `11`.

### Optional Appetize (same iOS run)

On **iOS — Godot TestFlight → Run workflow**, leave **Also build iOS Simulator zip for Appetize** unchecked (default). Check it only when you need [Appetize.io](https://appetize.io/) *in the same TestFlight job*.

### Appetize-only workflow (preferred when you only need the simulator zip)

**Actions → iOS — Godot Appetize → Run workflow**

- Godot export → unsigned Simulator `.app` → artifacts
- **No** App Store Connect secrets, signing, archive, or TestFlight upload
- Script: `.github/scripts/godot-ios-appetize-run.sh`

Then download either:
1. **`ios-simulator-appetize-<run>`** — preferred; unzip once so `riftwing.app` is at the root, upload that folder/zip to Appetize
2. **`appetize-zip-<run>`** — contains `riftwing-simulator-appetize.zip`; upload **that inner zip** (not the GitHub wrapper) to Appetize

No extra secrets required for Appetize packaging.

**Godot note:** Official iOS export templates only ship an **x86_64** simulator `libgodot` (no arm64-simulator slice). CI therefore links the Appetize `.app` as `ARCHS=x86_64`. On the TestFlight workflow, Appetize packaging is soft-fail so a Simulator build problem does not fail the TestFlight upload.

## Secrets (same values on both hosts)

| Variable | GitHub | Codemagic |
|----------|--------|-----------|
| `APP_STORE_CONNECT_ISSUER_ID` | Actions secret | Env group `basic` |
| `APP_STORE_CONNECT_KEY_IDENTIFIER` | Actions secret | Env group `basic` |
| `APP_STORE_CONNECT_PRIVATE_KEY` | Actions secret (full multiline `.p8`) | Env group `basic` |

Copy from your GG / Salino project if you use the same Apple team.

## Repo constants (not secrets)

| Variable | Value |
|----------|--------|
| `BUNDLE_ID` | `com.lishistudio.riftwing` |
| `APPLE_DEVELOPMENT_TEAM` | `7BLH4NFZDD` |
| `GODOT_VERSION` | `4.7-stable` |
| iOS export preset name | `iOS` |
| `ios/exportOptions.plist` | App Store manual signing seed |

`export_presets.cfg` keeps `application/app_store_team_id=""` in git; CI patches it from `APPLE_DEVELOPMENT_TEAM` immediately before Godot export, then applies signing via Codemagic CLI + `ios/exportOptions.plist`.

## Caching (GitHub Actions)

- Godot binary (`.ci-godot`) + export templates (`~/Library/Application Support/Godot/export_templates/4.7.stable`)
- Xcode DerivedData (`build/DerivedData`)
- Codemagic CLI venv (`.ci-venv`)

## Runner / billing

- **GHA:** `macos-26` + Xcode 26. Private repos bill macOS minutes at a higher multiplier — run manually when you need a build.
- **Codemagic:** `mac_mini_m2`, billed on your Codemagic plan.

## How to run (GitHub Actions)

1. Push this repo to GitHub with `.github/` present.
2. Add the three App Store Connect secrets (see above).
3. Ensure **App Store Connect** has an app record for `com.lishistudio.riftwing`.
4. Marketing version still comes from `manifests/product_identity.json`; CI auto-increments `CFBundleVersion` above Apple's last upload.
5. **Actions** → **iOS — Godot TestFlight** → **Run workflow**. Check **Also build iOS Simulator zip for Appetize** only when you need Appetize.
6. On first failure with scheme errors: check the log for `Discovered Xcode scheme:` — if wrong, set `XCODE_SCHEME` in `.github/scripts/ci-env.sh` to match `xcodebuild -list`.

## Privacy (App Store Connect)

With ads removed: App Privacy must **not** claim tracking, Device ID for tracking, or Advertising Data. No ATT / AdMob Privacy & messaging required.

## Local Android

See `docs/EXPORT_SIGNING.md` — Godot **Android Debug** / **Release** on your PC.
