# RIFTSTRIKE LevelPlay iOS bridge

Godot iOS plugin that bridges Unity LevelPlay (IronSourceSDK **9.5.0.0**, new
`LPM*` ad-unit APIs) to the shared GDScript `LevelPlayAdsService`. It registers
the engine singleton `RiftstrikeLevelPlay` and emits the same signals as the
Android plugin, so no GDScript changes are needed per platform.

Mediation networks (loaded **only** through LevelPlay, never directly):
- Unity Ads — `IronSourceUnityAdsAdapter` `5.9.0.0`
- Meta Audience Network — `IronSourceFacebookAdapter` `5.4.0.0` + FAN SDK **6.22.0**

## CI build (preferred)

GitHub Actions builds the plugin on macOS during **iOS — Godot TestFlight** and
**iOS — Godot Appetize**:

1. `.github/scripts/build-ios-levelplay-plugin.sh` — Godot 4.7 headers + IronSource
   headers → `ios/plugins/riftstrike_levelplay.release.xcframework` + `.gdip`
2. Godot `--export-release` with `plugins/RiftstrikeLevelPlay=true`
3. `.github/scripts/ios-levelplay-pods.sh` — CocoaPods on the exported Xcode project
   (`IronSourceSDK` + Unity Ads + Meta adapters) → `.xcworkspace` for archive /

Artifacts under `ios/plugins/RiftstrikeLevelPlay*` are gitignored and restored from
Actions cache keyed by `native/levelplay/ios/**`.

## Files
- `riftstrike_levelplay.h` / `riftstrike_levelplay.mm` — the bridge + plugin
  registration hooks (`register_/unregister_riftstrike_levelplay_types`).
  ATT (`ATTrackingManager`) and `FBAdSettings.setAdvertiserTrackingEnabled`
  run **before** `LevelPlay init`.
- `RiftstrikeLevelPlay.gdip.template` — copied to `ios/plugins/RiftstrikeLevelPlay.gdip` by CI.

## Manual build (macOS only, if needed)
See historical steps below; prefer CI. You still need Godot `4.7-stable` source
headers, IronSourceSDK headers, device + simulator static libs, then
`xcodebuild -create-xcframework`.

## API surface
Init: ATT → `FBAdSettings.setAdvertiserTrackingEnabled` →
`[LevelPlay initWithRequest:[[LPMInitRequestBuilder alloc]
initWithAppKey:key] build] completion:...]`.
Ads: `LPMInterstitialAd`, `LPMRewardedAd`, `LPMBannerAdView` with their
`LPM*Delegate` protocols. No legacy `IronSource` init/load/show calls are used.
Rewarded grants emit only from `didRewardAdWithAdInfo` — never from close.

Banner sizing: phones use `createAdaptiveAdSize`; wide layouts (≥600 pt, iPad /
tablets) use fixed `bannerSize` (320×50) centered — same policy as Salino/PoofCam.
