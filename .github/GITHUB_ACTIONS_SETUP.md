# GitHub Actions CI/CD — RIFTWING (iOS / Godot)

GitHub Actions builds and uploads an **IPA to TestFlight**. Android stays local (Godot export on your machine).

## Workflow

| File | Trigger | Output |
|------|---------|--------|
| `ios-testflight.yml` | manual (`workflow_dispatch`) | IPA → TestFlight |

## Fast TestFlight path (default)

Script: `.github/scripts/godot-ios-testflight-run.sh`

1. Select Xcode 26 + install Codemagic CLI (signing / ASC API)
2. Install/cache Godot **4.7-stable** + iOS export templates
3. Optional probes (`run_probes`): `export_validation_probe.gd`, `ads_service_probe.gd`
4. Godot headless import (bounded) → `--export-release` iOS preset → `build/ios/riftwing.xcodeproj`
5. Patch marketing/build version from `manifests/product_identity.json` + `BUILD_NUMBER`
6. Fetch signing files → `xcode-project use-profiles` → resolve SPM (AdMob)
7. `xcodebuild archive` → export IPA
8. `ios-publish-testflight.sh` → App Store Connect upload (build shows in TestFlight after processing)

By default the publish step **does not** pass `--testflight` (external beta review). That avoids CI failures when Beta App Information is empty in App Store Connect. After you fill [TestFlight test information](https://appstoreconnect.apple.com/) (feedback email + beta review contact), set repository variable `SUBMIT_TESTFLIGHT_BETA_REVIEW=true` or workflow input **Submit external TestFlight beta review** to `true`.

**Skipped by default (saves macOS minutes):**

- Config probes (`run_probes` input, default `false`)
- Uploading IPA to GitHub Artifacts (`upload_ipa_artifact` — TestFlight does not need this)

**Signing:** purge Distribution certs (Apple quota) → `fetch-signing-files --create` → `xcode-project use-profiles`. Same App Store Connect API key pattern as Garden Guardians (GG).

**Build number:** `github.run_number + 1` (workflow env `BUILD_NUMBER_OFFSET`).

## Secrets (repository → Actions)

Copy from your GG repo if you use the same Apple team:

| Secret | Value |
|--------|--------|
| `APP_STORE_CONNECT_ISSUER_ID` | App Store Connect API issuer |
| `APP_STORE_CONNECT_KEY_IDENTIFIER` | Key ID |
| `APP_STORE_CONNECT_PRIVATE_KEY` | Full `.p8` (multiline) |

## Repo constants (not secrets)

| Variable | Value |
|----------|--------|
| `BUNDLE_ID` | `com.lishistudio.riftwing` |
| `APPLE_DEVELOPMENT_TEAM` | `7BLH4NFZDD` |
| `GODOT_VERSION` | `4.7-stable` |
| iOS export preset name | `iOS` |
| `ios/exportOptions.plist` | App Store manual signing seed |

`export_presets.cfg` keeps `application/app_store_team_id=""` in git; CI patches it from `APPLE_DEVELOPMENT_TEAM` immediately before Godot export, then applies signing via Codemagic CLI + `ios/exportOptions.plist`.

## Caching

- Godot binary (`.ci-godot`) + export templates (`~/Library/Application Support/Godot/export_templates/4.7.stable`)
- Xcode DerivedData (`build/DerivedData`)
- Codemagic CLI venv (`.ci-venv`)

## Runner / billing

`macos-26` + Xcode 26 (App Store uploads). Private repos bill macOS minutes at a higher multiplier — run manually when you need a build.

## How to run

1. Push this repo to GitHub with `.github/` present.
2. Add the three App Store Connect secrets (see above).
3. Ensure **App Store Connect** has an app record for `com.lishistudio.riftwing`.
4. Bump version in `manifests/product_identity.json` and sync `export_presets.cfg` before release builds.
5. **Actions** → **iOS — Godot TestFlight** → **Run workflow**.
6. On first failure with scheme errors: check the log for `Discovered Xcode scheme:` — if wrong, set `XCODE_SCHEME` in `.github/scripts/ci-env.sh` to match `xcodebuild -list`.

## AdMob / privacy (not CI-blocking)

Publish GDPR + IDFA messages in AdMob **Privacy & messaging** for production ad behavior and ATT on device.

## Local Android

See `docs/EXPORT_SIGNING.md` — Godot **Android Debug** / **Release** on your PC.
