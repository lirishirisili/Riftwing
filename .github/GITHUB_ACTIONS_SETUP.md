# CI/CD — RIFTWING (iOS / Godot)

Two hosts run the **same** Godot → sign → IPA pipeline (shared `.github/scripts/`). Android stays local (Godot export on your machine).

## Workflows

| Host | Config | Trigger | Output |
|------|--------|---------|--------|
| **Codemagic** | `codemagic.yaml` → `ios-testflight` | Start build in Codemagic UI | IPA → App Store Connect |
| **GitHub Actions** | `.github/workflows/ios-testflight.yml` | manual (`workflow_dispatch`) | IPA → App Store Connect |

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
4. Godot headless import (bounded) → `--export-release` iOS preset → `build/ios/riftwing.xcodeproj`
5. Patch marketing/build version from `manifests/product_identity.json` + `BUILD_NUMBER`
6. Fetch signing files → `xcode-project use-profiles` → resolve SPM (if any)
7. `xcodebuild archive` → export IPA
8. **Publish:** Codemagic YAML `publishing` · GHA `ios-publish-testflight.sh`

On GitHub Actions, publish **does not** pass `--testflight` by default (same reason as Codemagic). After Beta App Information is filled, set repository variable `SUBMIT_TESTFLIGHT_BETA_REVIEW=true` or workflow input **Submit external TestFlight beta review** to `true`.

**Skipped by default on GHA (saves macOS minutes):**

- Config probes (`run_probes` input, default `false`)
- Uploading IPA to GitHub Artifacts (`upload_ipa_artifact` — TestFlight does not need this)

**Signing:** purge Distribution certs (Apple quota) → `fetch-signing-files --create` → `xcode-project use-profiles`. Same App Store Connect API key pattern as Garden Guardians (GG). Do **not** use Codemagic `ios_signing` — profiles are created at build time via the API.

**Build number:**

| Host | Source |
|------|--------|
| Codemagic | `$PROJECT_BUILD_NUMBER` → `BUILD_NUMBER` |
| GitHub Actions | `github.run_number + 1` (`BUILD_NUMBER_OFFSET`) |

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
4. Bump version in `manifests/product_identity.json` and sync `export_presets.cfg` before release builds.
5. **Actions** → **iOS — Godot TestFlight** → **Run workflow**.
6. On first failure with scheme errors: check the log for `Discovered Xcode scheme:` — if wrong, set `XCODE_SCHEME` in `.github/scripts/ci-env.sh` to match `xcodebuild -list`.

## Privacy (App Store Connect)

With ads removed: App Privacy must **not** claim tracking, Device ID for tracking, or Advertising Data. No ATT / AdMob Privacy & messaging required.

## Local Android

See `docs/EXPORT_SIGNING.md` — Godot **Android Debug** / **Release** on your PC.
