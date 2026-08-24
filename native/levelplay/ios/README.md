# RIFTSTRIKE LevelPlay iOS bridge

Godot iOS plugin that bridges Unity LevelPlay (IronSourceSDK **9.5.0.0**, new
`LPM*` ad-unit APIs) to the shared GDScript `LevelPlayAdsService`. It registers
the engine singleton `RiftstrikeLevelPlay` and emits the same signals as the
Android plugin, so no GDScript changes are needed per platform.

iOS artifacts **must be compiled on macOS** (Xcode 26+, per LevelPlay 9.5.0).
This directory holds source only; the build is left to macOS CI.

## Files
- `riftstrike_levelplay.h` / `riftstrike_levelplay.mm` — the bridge + plugin
  registration hooks (`register_/unregister_riftstrike_levelplay_types`).
- `RiftstrikeLevelPlay.gdip.template` — Godot iOS plugin descriptor. Copy to
  `ios/plugins/RiftstrikeLevelPlay.gdip` when enabling the iOS build.

## Build steps (macOS)
1. Clone the matching Godot source (`4.7-stable`) for engine headers.
2. Build a static library for device + simulator against those headers, then
   package as `riftstrike_levelplay.xcframework`:
   ```sh
   # device (arm64)
   clang++ -c riftstrike_levelplay.mm -o riftstrike_levelplay.arm64.o \
     -isysroot $(xcrun --sdk iphoneos --show-sdk-path) -arch arm64 \
     -fobjc-arc -std=c++17 -I<godot-src> -I<godot-src>/platform/ios
   libtool -static riftstrike_levelplay.arm64.o -o libriftstrike_levelplay.a
   xcodebuild -create-xcframework \
     -library libriftstrike_levelplay.a -output riftstrike_levelplay.xcframework
   ```
   (Add a simulator slice the same way if simulator testing is needed.)
3. Copy the `.xcframework` and the `.gdip` into `ios/plugins/`.
4. Add the LevelPlay SDK to the exported Xcode project (Godot exports a project,
   `export_project_only=true`):
   - CocoaPods: `pod 'IronSourceSDK','9.5.0.0'` plus Unity Ads bidding adapter
     `pod 'IronSourceUnityAdsAdapter','5.9.0.0'` (PoofCam/TOHAV parity), or
   - SPM: `https://github.com/ironsource-mobile/LevelPlay-Swift-Package` (Exact
     Version >= 9.5.0). Prefer also linking the Unity Ads adapter for bidding fill.
5. Ensure `-ObjC` is in Other Linker Flags (also set by the `.gdip`).
6. **Privacy**: MERGE the `.gdip` `SKAdNetworkItems` with the app's existing
   `SKAdNetworkItems` — never replace. Add remaining mediated-network ids from
   the LevelPlay dashboard plist generator. Include the LevelPlay SDK privacy
   manifest (`PrivacyInfo.xcprivacy`) shipped with the pod/package.
7. Do **not** add an `NSUserTrackingUsageDescription` / ATT prompt unless an
   approved consent flow + copy exists (see privacy gaps in the changelog).

## API surface
Init: `[LevelPlay initWithRequest:[[LPMInitRequestBuilder alloc]
initWithAppKey:key] build] completion:...]`.
Ads: `LPMInterstitialAd`, `LPMRewardedAd`, `LPMBannerAdView` with their
`LPM*Delegate` protocols. No legacy `IronSource` init/load/show calls are used.
