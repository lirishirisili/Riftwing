# Changelog

## CI: unique iOS build numbers + optional Appetize
- TestFlight upload no longer reuses `CFBundleVersion` 11. CI queries App Store Connect for the latest uploaded build, stamps `CURRENT_PROJECT_VERSION` on the Godot-exported Xcode project / `xcodebuild archive`, and fails the job if the archived plist does not match (Godot `GENERATE_INFOPLIST_FILE` ignores a static Info.plist patch).
- GitHub Actions **iOS — Godot TestFlight** has an optional **Also build iOS Simulator zip for Appetize** checkbox (off by default), same pattern as PEND.
- Fix CI: `ci_patch_xcode_project_versions` no longer references `$n_ver` in a bash-expanded Python print (unbound variable under `set -u`).
- Fix CI: Appetize simulator build forces `ARCHS=x86_64` (official Godot templates lack arm64-simulator `libgodot`, which caused undefined `_main` on Apple Silicon runners). Appetize steps soft-fail so TestFlight success stays green.
- Added **iOS — Godot Appetize** workflow (`.github/workflows/ios-appetize.yml`) to build only the Simulator zip — no ASC secrets, signing, or TestFlight.
- **iOS LevelPlay in GHA:** CI compiles `RiftstrikeLevelPlay` (`.xcframework` + `.gdip`), enables it on the iOS export preset, and installs IronSource + Unity Ads + Meta CocoaPods on the exported Xcode project so the main-menu banner can initialize on device.

## 0.1.10 (build 11)
- Production release: Meta Audience Network via LevelPlay mediation (Unity Ads + Meta FAN 6.22.0).
- Android: FAN app id, network security for localhost, androidx.browser pin for Godot AGP 8.6.1.
- iOS: ATT + Meta advertiser tracking before LevelPlay init.
- Rewarded grants remain exclusively from the official LevelPlay reward-earned callback (never close/dismiss).

## 0.1.9 (build 10)
- Tablet / large-screen banner: fixed `BANNER` (320×50) centered instead of stretched adaptive (Salino/PoofCam parity).
- Fixed player bolts vanishing on the expanded right play lane (`PlayfieldBounds` syncs pool cull rects with the viewport).
- Bumped store version for Play production.

## Wide-screen combat: bullets on the right edge
- Fixed player (and enemy) projectiles vanishing on the expanded right lane of tablets/iPads: `PlayfieldBounds.from_screen` now grows pool despawn rects with the viewport in `RunController` / `boss_debug`, matching the already-expanded ship playfield. Pickup cull bounds follow the same path.

## Banner layout on tablets / large screens
- Matched Salino/PoofCam: on wide layouts (≥600 dp/pt) the LevelPlay banner uses fixed `BANNER` (320×50) centered instead of full-bleed adaptive, so creatives are not stretched on iPad / tablets / foldables. Phones keep adaptive sizing.
- Android bridge also anchors the banner container with `Gravity.BOTTOM` (was missing).
- Touch: Android AAR rebuilt via `native/levelplay/android/build_and_install.ps1`. iOS needs a macOS rebuild of `riftstrike_levelplay.xcframework` from the updated `.mm`.

## 0.1.8 (build 9)
- Bumped store version for Play production after LevelPlay ads (banner / interstitial / rewarded) + Unity Ads mediation wiring.
- Store privacy/Data Safety declarations aligned with LevelPlay (not AdMob).

## Ads / monetization verification (2026-08-24)
- Confirmed LevelPlay Android/iOS app keys + Banner/Interstitial/Rewarded ad unit IDs match the live dashboard for `com.lishistudio.riftwing`.
- Android `.gdap` now pulls Unity Ads adapter + Play Services IDs (PoofCam/TOHAV parity) alongside LevelPlay mediation-sdk 9.6.0.
- Enabled `plugins/RiftstrikeLevelPlay` on the **Android Release** preset; excluded LevelPlay Gradle build intermediates from export packs.
- Built signed release artifacts for device/Play testing: `build/android/riftwing-release.apk` and `build/android/riftwing-release.aab`.

## 0.1.7 (build 8)
- Renamed the player-visible brand to **RIFTSTRIKE** (store title `Riftstrike: Space Survivor`). Package/bundle IDs stay `com.lishistudio.riftwing`; save path and theme filenames unchanged.
- New metallic main-menu wordmark `assets/branding/logo_riftstrike.png`; meta headers, pause, results/defeat, and brand chips now read RIFTSTRIKE. Centralized display copy in `scripts/core/brand.gd`.
- Bumped store version to `0.1.7` / code `8` for the next Play/App Store binary.

## 0.1.5 (build 6)
- Bumped store version to `0.1.5` (iOS/Android build `6`), covering the repair milestones below: progression integrity, responsive navigation, the hangar→combat bridge, 20 real run upgrades, graduated difficulty/HARD, and every former "Coming Soon" screen.
- Synced the version across `manifests/product_identity.json` (source of truth), `project.godot`, all three export presets, and `docs/EXPORT_VALIDATION.md`.
- `tests/export_validation_probe.gd` no longer pins literal `0.1.0`/build `1` (stale since the first bump, so the probe had been failing). It now reads the manifest and asserts `project.godot` and every preset agree with it, so a future bump either stays consistent or fails loudly.
- Verified a release build end-to-end on device-ready output: headless import clean, `coming_soon` / `progression` / `run_upgrades` probes green, then a gradle release APK signed with the debug keystore (`apksigner verify`: v2+v3) for sideloaded testing. Store submission still requires a real release keystore and the AAB preset.

## Every visible "Coming Soon" is now real
- REROLL: the in-run upgrade screen grants one free reroll per run (no third currency). The button shows the remaining count and re-draws the current level's three choices; it disables only once the run's reroll is spent. Reset per run via `UpgradeScreen.configure`.
- UPGRADE ALL: the hangar button is a two-tap preview→confirm. `SaveManager.plan_upgrade_all` computes exactly which non-maxed tracks fit the current Rift Energy budget and their combined cost; `purchase_upgrade_all` re-validates against the live budget and commits atomically (one deduction, one save) — never a surprise partial buy.
- SHIP UNLOCKS: replaced the "Coming soon" locked ships with data-driven requirements on `ShipData` (`unlock_stage_id` gate + `unlock_core_cost`). Void Strider (clear 1-3, 2 cores), Razor Wing (clear 1-5, 3 cores), Solar Lance (clear 1-8, 5 cores). `SaveManager.try_unlock_ship` atomically checks the gate + cost, spends Rift Cores, and persists; the hangar CTA becomes UNLOCK / NEED CORES / LOCKED with the real requirement label.
- DAILY CHALLENGE: new `DailyScreen` + `DailyChallenge` — a deterministic run seeded from the local date (stage + NORMAL/HARD modifier), launched through the normal run pipeline. `SaveManager` grants a one-time Rift Core bonus per local date (schema v6) on victory; replaying the same day awards no repeat bonus. No backend.
- VOID INVASION EVENT: new `EventScreen` + `EventData` recurring window (period/active days aligned to a fixed epoch) with a real, live countdown (no fake "2D 14H"). Enemies destroyed in runs during the active window accrue toward the goal (`SaveManager._accrue_event_progress`); the reward is claimable once per occurrence. The main-menu banner now shows the real remaining/next-window time.
- Removed the `PlaceholderScreen` route, scene, and script from the production UI now that Daily and the Event have real destinations. No SDKs, cloud, ads, or third currency were added.

## Graduated difficulty, distinct stages, and active HARD
- Added data-driven `RunDifficultyData` (`scripts/progression/run_difficulty_data.gd`) with `normal.tres` (all-neutral) and `hard.tres` profiles (enemy HP ×1.6, contact ×1.25, +1 density, boss HP ×1.5, ×1.5 payout, tighter timing, ×1.35 3-star bar). `RunController._apply_difficulty` resolves the profile (payload override or campaign setting) and applies scaling to the `WaveDirector`, `Boss`, boss timing, and the reward/star multipliers — never mutating shared resources.
- Per-stage graded ramp: `StageNodeData.difficulty_scalar` (1.0 → 1.6 across 1-1…1-8) multiplies enemy/boss durability on top of the difficulty profile, so pressure rises across the sector even on NORMAL while 1-1 stays approachable.
- HARD is now actually playable: unlocked per stage after clearing that stage on NORMAL, with separate clears/stars/best-score (composite `stage_id#hard` save keys) and boosted payouts. Stage Map highlights the selected difficulty (NORMAL cyan / HARD magenta) and gates the launch button with a clear "clear on NORMAL first" message.
- Completed the enemy archetypes from the spec: `Behavior` enum drives DIVER (hovers briefly then plunges at the player's column), TANK (durable slow wall), and SPLITTER (spawns pooled shards on death, deferred out of the physics callback so freshly spawned adds enable monitoring safely). Added `diver`/`tank`/`splitter`/`splitter_child` enemy resources. Contact damage is scaled per-run via `Enemy.get_contact_damage()` without mutating `EnemyData`.
- Distinct stages instead of one shared clock: `StageNodeData.timeline` lets a node author its own `StageTimelineData`; `RunController` resolves it from the map (falling back to the vertical-slice timeline for early stages). Added `nova_mid_timeline` (Diver & Splitter sweep, stages 1-4/1-5) and `nova_late_timeline` (Tank Line & Divers, stages 1-6…1-8) with earlier boss beats, plus two new authored waves.
- Void Wisp now has a real phase 2: dedicated denser `void_wisp_radial_p2` (34 bullets, 4 rings, faster spin) and a return-sweep `void_wisp_laser_p2`, replacing the phase-1 reuse. Telegraphs and safe gaps (≥2 gaps, ≥3 slots; thin beam) are preserved so difficulty comes from density/patterns, not unfair hits.

## Real run weapons, abilities, and 20 active upgrades
- Fixed acquired-but-inert weapons: added `SecondaryWeaponSystem` (`scripts/combat/secondary_weapon_system.gd`) + data-driven `SecondaryWeaponData`. Homing Missiles, Arc Laser, Guardian Drone, Chain Lightning, and Void Bomb now actually fire — pooled auto-aim bolts pulled from the shared player projectile pool (so hits resolve through the same collision path as plasma and damage enemies and the boss identically, with no unbounded pool growth). Bolts aim at the nearest live target; when none exist they fire straight up.
- The two HUD ability buttons are now real: left = Missile Barrage (homing burst), right = Arc Burst (wide fan). Cooldown/charges are gated by the existing HUD button state; `run_controller._on_ability_feedback` fires the bound ability weapon instead of only playing a flash.
- Extended `UpgradeEffectData` with weapon/defense/utility kinds (secondary damage/rate/count, armor, max-HP, move-speed, crit-chance) and routed them in `UpgradeManager` to the plasma weapon, secondary system, and player. `ACQUIRE_WEAPON` now spins up the real secondary weapon. Runtime mods stack on private duplicates so shared `.tres` files are never mutated.
- Grew the catalog to 20 meaningful upgrades (`resources/upgrades/`): 5 weapon acquisitions (incl. new Chain Lightning + Void Bomb), an expanded plasma line (Rapid Coils, Heavy Slugs, Twin Array, Targeting Matrix), secondary boosters (Missile Swarm, Arc Amplifier, Drone Overclock, Warhead Yield), survivability/agility (Reinforced Hull, Ablative Plating, Afterburner, Adrenaline Core), and a legendary Overcharged Core capstone. Every card produces a measurable runtime change — no no-op cards are offered.
- Added `tests/run_upgrades_probe.gd`: verifies the 20-card catalog (all have effects), and inside a live run proves each effect kind maps to a concrete change (plasma damage/rate/bolts/crit, weapon acquisition, secondary count/damage, ability bolt damage, max HP, armor, move speed), abilities fire, and the projectile pool stays under its hard cap under sustained plasma + secondary + ability fire. Regression suite (upgrade cards, vertical slice, hangar-combat, progression, HUD) still passes.

## Hangar → combat bridge (ATK / HP / DEF / CRIT / Engine)
- Added `CombatProfile` (`scripts/combat/combat_profile.gd`): the single runtime layer that turns the selected ship's authored ATK / DEF / HP / CRIT + hangar levels (via `HangarStats`) into concrete run modifiers — weapon damage multiplier, HP multiplier, crit chance/multiplier, incoming-damage reduction, and movement responsiveness. It is pure and never mutates a shared Resource.
- All modifiers are RELATIVE to the ship's level-0 baseline, so a fully un-upgraded ship yields neutral values (mult 1.0, 0 armor) and the run keeps its tuned baseline (the game is balanced around ~100 HP / small enemy damage). This avoided a scaling trap where the raw hangar HP (1600) and DEF (180) would have made a fresh ship ~16× tankier with 31% free armor.
- `run_controller` now derives the profile from the equipped ship + `SaveManager` levels at run start and applies it: player HP scales the baseline, `PlayerShip.take_damage` routes through centralized armor mitigation, `PlasmaWeapon` gets a damage multiplier and per-volley crit (cached crit-damage duplicate, no per-bolt allocation), and engine levels raise movement responsiveness. Player movement/combat data are duplicated at runtime so the shared `.tres` files are untouched.
- Added `tests/hangar_combat_probe.gd`: proves each track maps to a measurable stat (weapons→damage, shield→armor, engine→move speed, drones→crit, ultimate→HP), a level-0 ship reads neutral (1.0 / 1.0 / 0 armor), the shared `ShipData` is never mutated, and mitigate/crit resolution math is correct. Full-run regression (`vertical_slice_probe`) still passes with the profile applied.

## Responsive navigation (Back / safe area / contextual return)
- Fixed the cut-off / overlapping Back button: the meta-screen header previously crammed a full-size `GlowCtaButton` (NAV) into the crowded trailing slot, whose glow chrome bled over the Rift Core chip ("4BACK") and clipped against the header frame. Added a dedicated compact `HeaderBackButton` (`scripts/ui/chrome/header_back_button.gd`) — bounded 132×64 neon chip with a chevron, a real ≥48px touch target, and no glow bleed — mounted in the Stage Map and Hangar headers.
- Back is now contextual via a `return_to` / `return_payload` payload convention: Hangar returns to the screen it was opened from (Main Menu, Stage Map, or Results with its run stats) instead of always jumping to the menu. Stage Map honors an explicit return target and falls back to the menu.
- Settings now builds its rows inside a `ScrollContainer` so short / dense devices never clip the option rows or the Back-to-Menu button.
- Verified with the visual review probe: fresh 1080×1920 captures show no Back/currency/brand overlap, and screen smoke passes at 1080×1920, 1080×2340, 1080×2400, 1080×2478, and 1600×2560.

## Progression integrity (score / rewards / stars / save)
- Fixed the results screen crash: removed the leftover `_refresh_double_button()` call (a stub from the removed ad "x2 reward" button) that halted `_populate()` before the score, stars, and rewards were ever rendered. This was the root cause of "points don't accumulate and no stars".
- Live in-run SCORE now flows through one shared value: `RunStats.live_score()` uses the same weights as `finalize_score` (victory bonus excluded), and `GameplayHUD` reads it instead of recomputing a separate copy.
- Wired authored stage payouts into the real reward math: `RewardCalculator.calculate()` now adds `StageNodeData.reward_rift_energy`/`reward_rift_core` on victory plus a `first_clear_rift_core` bonus granted exactly once (first-clear state is decided before granting; `SaveManager` still dedupes the whole payout by run id).
- `SaveManager`: added per-stage best score (`get_stage_best_score`), schema migration to v5, and hardened persistence — the temp file is validated before replacing the live save, the previous good save is rolled into a `.bak` backup, a failed replace rolls back, and load falls back to the backup if the primary save is corrupt (Windows/mobile safe).
- Pause → Quit now requires a confirming second tap ("CONFIRM QUIT · Run progress is lost") so an accidental tap never discards an in-progress run. Normal victory/defeat still route through Results.
- Added `tests/progression_probe.gd` (E2E): live score is monotonic and below the finalized victory score; stage energy + first-clear core apply; replays keep the base per-victory core but never re-add first-clear; same run id never double-grants; energy/core/best/stage-best/stars/clear all survive reload.

## 0.1.4 (build 5)
- Bumped store version to `0.1.4` (iOS/Android build `5`).
- Fixed combat continuing under Pause and the level-up upgrade overlay: `CurrentScreen` is now `PROCESS_MODE_PAUSABLE` so it no longer inherits `AppRoot`’s `PROCESS_MODE_ALWAYS`.
- HUD pause chrome and `UpgradeScreen` still run while paused (`ALWAYS` / `WHEN_PAUSED`); enemies, projectiles, waves, and player simulation stop until resume / choice.

## iOS device family fix (iPhone + iPad)
- Corrected `application/targeted_device_family` from `1` (iPad-only in Godot’s enum) to `2` (iPhone & iPad).
- Previous value caused App Store to list the app as “Designed for iPad” with no iPhone availability.
- Docs in `EXPORT_VALIDATION.md` previously mislabeled `1` as iPhone; clarified Godot enum mapping (`0`/`1`/`2`).
- Bumped store version to `0.1.3` (iOS/Android build `4`) for App Store resubmission.

## Ads removed (App Store 5.1.2)
- Disabled AdMob end-to-end: no interstitial/rewarded/banner, no ATT purpose string, no iOS AdMob `.gdip` plugins in export.
- `PlatformServices` always uses no-op `AdsService`; Results no longer shows “Watch for x2” or auto interstitial.
- Removed `admob_ids.gd` / `admob_ads_service.gd`; editor plugin disabled in `project.godot`.
- Bumped store version to `0.1.2` (iOS/Android build `3`) for resubmission after privacy-label update.

## Codemagic iOS TestFlight (Godot)
- Added root `codemagic.yaml` workflow `ios-testflight` (Salino-style thin YAML): Codemagic CLI setup → `godot-ios-testflight-run.sh` → App Store Connect upload.
- Shared scripts hardened for dual host: `CM_BUILD_ID` skips manual Xcode select; `BUILD_DIR` / `BUILD_NUMBER` honor `CM_BUILD_DIR` + `PROJECT_BUILD_NUMBER`.
- Publishing uses `submit_to_testflight: false` (upload only; same ASC Beta App Information constraint as GHA).
- Setup: [`.github/GITHUB_ACTIONS_SETUP.md`](../.github/GITHUB_ACTIONS_SETUP.md). GitHub Actions workflow kept in parallel.

## iOS App Review — ATT Purpose String (0.1.1)
- Clarified `NSUserTrackingUsageDescription` in `export_presets.cfg` and `poing-godot-admob-ads.gdip` with a specific personalized-ads example for App Review.
- Bumped store version to `0.1.1` (iOS build `2`, Android versionCode `2`).

## GitHub Actions — iOS TestFlight (Godot)
- Fix CI: patch `export_presets.cfg` `app_store_team_id` from `APPLE_DEVELOPMENT_TEAM` before Godot export (empty team id is required in git but Godot blocks export); macOS `sed` uses `#` delimiters for paths with slashes.
- Fix CI: TestFlight publish uploads IPA without `--testflight` by default (external beta review needs Beta App Information in App Store Connect).
- Fix CI: `source install-godot-macos.sh` so `GODOT_BIN` is visible in the same pipeline step (subshell `bash` + `GITHUB_ENV` did not export back to `godot-ios-testflight-run.sh`).
- Added manual `workflow_dispatch` workflow `.github/workflows/ios-testflight.yml` on `macos-26`: Godot 4.7 export → Codemagic signing → archive → TestFlight (same App Store Connect API secrets pattern as GG).
- Scripts under `.github/scripts/` (`godot-ios-testflight-run.sh`, `install-godot-macos.sh`, `ci-env.sh`, etc.) and [`ios/exportOptions.plist`](ios/exportOptions.plist) for `com.lishistudio.riftwing`.
- Setup guide: [`.github/GITHUB_ACTIONS_SETUP.md`](../.github/GITHUB_ACTIONS_SETUP.md). Team ID stays out of `export_presets.cfg`; CI uses `APPLE_DEVELOPMENT_TEAM` + export options plist.

## iOS ATT / UMP Consent Before Ads
- `AdMobAdsService` gathers Google UMP consent (GDPR + IDFA explainer → ATT) before `MobileAds.initialize`.
- iOS `NSUserTrackingUsageDescription` added to `poing-godot-admob-ads.gdip` and the iOS export preset plist extras.
- Consent/form failures still proceed to SDK init so non-personalized ads remain available.
- Requires GDPR + IDFA messages published under AdMob → Privacy & messaging for the live App IDs.

## Planet Accent Transparency
- Fixed `planet_rift_accent.png`: baked checkerboard/black plate replaced with true circular alpha (main menu + run backdrop).

## AdMob Monetization (Interstitial / Rewarded)
- Integrated Poing Studios AdMob plugin (`addons/admob`, Android AARs + iOS plugins) behind `AdsService` / `AdMobAdsService` (no SDK calls from gameplay).
- Interstitial every 3 completed runs on Results; rewarded opt-in ×2 rewards on Results. Banner disabled (not shown).
- Save schema v4 adds `monetization.completed_run_count` + `doubled_reward_run_ids`.
- Debug builds use Google test ad units; production App IDs + unit IDs authored in `admob_ids.gd` / platform configs.
- Android Debug preset: Gradle build, minSdk 24, INTERNET + ACCESS_NETWORK_STATE. Probe: `tests/ads_service_probe.gd`.
- Local `android/` Gradle template is gitignored (install via Godot `--install-android-build-template` before export).

## Stage Map Node Visibility
- Fixed invisible stage nodes: buttons under a plain `Control` canvas now set explicit `size` (not only `custom_minimum_size`).
- Always draw planet discs + path chrome; every stage keeps an active/locked icon; brighter locked dashes; taller map scroll.

## Tablet Full-Bleed Stretch
- Restored `window/stretch/aspect=expand` (was `keep_width`) so wider/taller screens fill without black pillarbox bars.
- `MetaScreenShell` resizes keyart/parallax plates on viewport change to cover expanded logical size.
- Playfield insets preserved; playable width grows with viewport (no dead side lanes on tablets).
- Space backdrop: replaced hard 68%-width CenterDim column with a soft full-bleed gradient (no bright side bands / moon seams).
- Probes smoke `1600×2560` tablet portrait; SafeArea docs note expand stretch.

## Universal Glow UI Pass
- Shared kit: `GlowCtaButton` (hex/bar chrome + empty `ButtonChrome`) and `MetaScreenShell` (cinematic keyart, tech header, currency chips, `%Body`).
- Meta screens (stage map, hangar, results, settings, placeholder) use MetaShell + glow CTAs; pause RESUME/QUIT and upgrade REROLL use GlowCta (combat HUD vitals unchanged).
- Main menu CTA stack migrated to `GlowCtaButton` instances (START / DAILY / SHIPS / UPGRADES).
- Theme adds `ButtonChrome` empty styles. Probes: `glow_ui_kit_probe`, updated main_menu / stage_map / hangar / results probes.
- Brand remains **RIFTWING** only. Navigation and balance unchanged.

## Modern Audio Bank Refresh
- Regenerated all SFX + music OGGs via upgraded `tools/generate_audio_banks.gd` (modern sci-fi, not chiptune).
- Soft UI ticks, layered combat hits/explosions, deeper `fire_loop`, atmospheric menu/run/boss pads.
- Menu music retuned: deep ambient pad only (removed gliding mid leads that sounded like a whine).
- Cue IDs and `AudioManager` wiring unchanged. Python helper marked legacy; GD script is canonical.

## Android Back → Pause (In-Run)
- Disabled `application/config/quit_on_go_back` — default Godot was quitting right after pause opened.
- System Back owned by AppRoot: run → HUD pause (second Back resumes); upgrade/end absorbed; meta → home; main menu → quit.

## Main Menu Visual Fidelity
- Regenerated metallic `logo_riftwing.png` (true alpha) + cinematic `hero_vanguard_menu.png` matching the high-fi mockup ship.
- CTA chrome: full-bleed glow hex SVGs (`cta_start_hex` / `cta_daily_bar` / `cta_nav_hex`) stretched to slot; START RUN + `ENDLESS MODE` perfectly centered.
- Menu always uses dedicated hero PNG (no hangar SVG overwrite); `vanguard_mk2.tres` `hero_texture` points at menu art.
- SafeArea ignores Windows taskbar misreports; stretch `keep_width`; bottom pad keeps nav fully visible.
- Brand remains **RIFTWING** only (reference mockups may show legacy names — never in production).
- Target mockup: `references/01_main_menu_target.png`. Probe covers chrome assets + pad/timer.

## Game Icon Art
- Replaced prototype launcher/store icons with final ship+nebula art under `assets/branding/`.
- Generated `icon_main_192.png`, `icon_adaptive_fg_432.png`, `icon_adaptive_bg_432.png` (navy), `icon_ios_1024.png`, plus `icon_source.png` master.
- Paths unchanged in `project.godot` and `export_presets.cfg` (Android launcher/splash + iOS 1024).

## Fire SFX Comfort (Shmup Loop)
- Continuous autofire no longer spam one-shot `fire` cues every volley (Cave/aircraft-style sustain).
- Soft looping `fire_loop.ogg` on a dedicated channel (~−14 dB); `GameFeel.weapon_fire` keeps muzzle VFX only.
- Loop suppressed during upgrade pause / HUD pause; stopped on run end / quit. Hit voice cap tightened to 3.

## Audio Banks + Settings
- Synthesized neon arcade OGG banks under `assets/audio/sfx` and `assets/audio/music` (`tools/generate_audio_banks.gd`).
- `AudioManager` plays real streams via SFX pool + dual music players (crossfade), Master/Music/SFX buses, voice caps on fire/hit, and persisted prefs (`user://audio_prefs.cfg`).
- Music hooks: menu/hangar/map → menu; run → run; mini/final boss → boss; results stops music then fanfare/fail stingers.
- Settings: AUDIO mute + MUSIC/SFX volume steps (20%) persist across sessions. Validated via `tests/vfx_audio_polish_probe.gd`.

## Gameplay Space Backdrop Refresh
- New generated layers: rich purple/teal nebula (`parallax_nebula_rift.png`), soft spiral galaxy core, and a large purple planet accent.
- `SpaceBackground` rebuilt as world-space scrolling `Sprite2D` pairs (not `ParallaxBackground`/CanvasLayer) so the backdrop actually appears under the run camera — stars → nebula → galaxy → planet → debris, with a dimmer center lane for bolt readability.

## Upgrade Pacing — No Choice Cascade
- `ExperienceTracker` emits at most one `leveled_up` while a choice is pending; excess XP banks instead of flooding the queue.
- Closing the upgrade screen no longer immediately opens the next level — the next pick waits for fresh XP after combat.
- Guaranteed level-up grant retuned to 10 XP (one level), fixing the LEVEL 2→3→4→5→6 back-to-back cascade from the old 40 XP dump.

## Gameplay Fun Ladder (G1–G4)
- **G1:** Level curve retuned for first pick ~15–20s; `GameFeel.upgrade_applied` halo/muzzle after each card so power lands immediately.
- **G2:** Void Elite spawn ~45–50s in early/mid waves (fat energy drop + major death FX); combo HUD heat colors + scale pop; `GameFeel.combo_peak` on x5 milestones.
- **G3:** Stage stars are clear / ≥50% HP / score objectives (map + results copy); hangar track costs lowered so early runs can buy a meaningful upgrade.
- **G4:** Upgrade cards show synergy hints when partners are owned; early-run rarity weighting suppresses Legendary/Epic until mid levels.

## Upgrade Screen — Stack / Glow Bleed Fix
- Synchronous `_clear_cards()` kills card tweens, removes children immediately, and runs on open + close so sequential level-ups never leave ghost cards (no 6-card stack).
- `UpgradeCard` / Cards row `clip_contents`; glow overflow reduced to ±6px so rarity glow no longer bleeds into LEVEL header or REROLL.
- Header / brand / reroll `z_index` raised above the card row. Probe covers back-to-back level-ups (`tests/upgrade_cards_probe.gd`).

## Visual Fidelity — Results / Victory (H)
- Closer results fidelity to `references/07_victory.png`: larger VICTORY/DEFEAT title with cyan wing bar accents, framed RIFTWING brand chip, NeonPanel + outer double-border mission stats, stronger gold NEW BEST! badge, square glowing reward chrome slots.
- Victory CTAs: gold `ButtonReward` Next Sector, blue `ButtonPrimary` Upgrade Ship; defeat keeps `ButtonPrimary` Replay + `ButtonSecondary` Upgrade. Sticky scroll CTAs (`_ensure_scroll_layout`) kept. Optional victory-only `CPUParticles2D` confetti. Hero defaults to `vanguard_mk2.svg`. RewardCalculator / SaveManager grant dedupe unchanged. Validated via `tests/results_screen_probe.gd`.

## Visual Fidelity — Upgrade Cards (G)
- Stronger rarity glow (cyan / purple / gold outer+inner pulse); legendary pulses hardest.
- Hex icon plate via `hex_frame.svg`, centered NEW badge, clearer rarity pill under the icon, title tinted by rarity.
- Dim veil raised slightly (~0.70) while combat remains readable; disabled gold `ButtonReward` stub `REROLL · SOON` (no economy).
- Card width fit from prior milestone unchanged; UpgradeManager roll/apply untouched. Validated via `tests/upgrade_cards_probe.gd`.

## Visual Fidelity — Gameplay HUD (E)
- Bottom vitals use `bottom_hud_frame.svg` chrome; HP caption has `icon_health`; XP bar keeps progression wiring but reads as a purple shield slot with `icon_shield` (no shield combat system).
- Level badge sits on `hex_frame.svg`; pause uses a hex shell + stronger Chip/tertiary chrome; ability buttons stay ≥112 with wider bottom spacing.
- Boss bar keeps M23 chip-safe width; stronger VOID TITAN / segmented chrome plate. Presentation only — no combat logic changes. Validated via `tests/gameplay_hud_probe.gd`.

## Visual Fidelity — Hangar (D)
- Hangar bay uses `assets/art/env/hangar_pad.svg` under the featured ship (default hero art `vanguard_mk2.svg`).
- Stronger cyan EQUIPPED glow on the ship strip; clearer per-stat chips (accent borders, tinted icons, value glow).
- Upgrade rows color-coded by track (weapons purple, shield/engine cyan, drones green, ultimate orange) via border/modulate; shield track accent token set to cyan.
- Disabled stub CTA `UPGRADE ALL · SOON` (no economy). SaveManager purchase/select unchanged. Validated via `tests/hangar_probe.gd`.

## Visual Fidelity — Main Menu (B)
- Main menu presentation pass toward `references/01_main_menu.png`: hero title ~76px **RIFTWING**, subtitle **SPACE SURVIVOR**, purple NeonPanel event shell titled **VOID INVASION**.
- Hero uses Vanguard Mk2 art, larger engine glow, and a right-side `planet_accent` TextureRect; top chrome chips use `ChipPanel` with stronger caption contrast.
- CTA hierarchy unchanged in wiring: `ButtonPrimary` Start Run, `ButtonSecondary` Daily, `ButtonTertiary` Ships/Upgrades; SaveManager + SceneRouter navigation preserved.

## Visual Fidelity — Stage Map (C)
- Closer map fidelity to `references/02_stage_select.png`: stronger multi-ring pulse on selected/current nodes, `map_node_locked.svg` padlock on locked nodes, `map_node_active.svg` on current/selected, solid purple→cyan cleared paths and clearer dashed muted locked paths.
- Detail panel uses shared `NeonPanel` (corner-cut) + `ChipPanel` power chips; dominant `ButtonPrimary` LAUNCH; short titles like `1-5  VOID OUTPOST`. Unlock / HARD / Launch logic unchanged. Branding **RIFTWING** only.

## Visual Fidelity — Combat Actors / VFX (F)
- Player ship uses Vanguard key art with dual cyan engine plumes; enemies/bosses use new Void art.
- Space background: planet accent layer + deeper center dim for bolt readability under bloom.
- Damage numbers scale/tint by quality (larger orange pops on HIGH).

## Visual Fidelity — Design System (A)
- Shared neon/chamfer theme (`ButtonReward`, `NeonPanel`, sharper CTA corners, stronger glow shadows).
- `GlowController` on AppRoot (WorldEnvironment bloom gated by GameFeel LOW/MED/HIGH).
- Chrome kit: `assets/ui/chrome/*`, `HexChip`, neon `HudSegmentedBar` / `AbilityButton` rings.
- Key art folders + Vanguard / Void Scout / Shooter / Titan / hangar pad / planet SVGs wired into resources.
- Docs: `docs/01_VISUAL_DIRECTION.md`, `docs/visual_fidelity/DESIGN_SYSTEM.md`.

## Milestone 23 - Final Mobile Visual QA
- Audited the production vertical slice (menu / map / HUD / combat / upgrades / boss / results / hangar) at 1080×1920, 1080×2400, and 1080×2478; wrote `docs/FINAL_MOBILE_VISUAL_QA.md`.
- Fixed highest-impact issues: boss bar inset from HUD chips, HUD XP label, pause/theme consistency, tall-aspect camera centering, results sticky CTAs + scroll, upgrade card width fit, shorter map/hangar labels, clearer muted HUD type.
- Effects remain below bullets; no new gameplay systems. Validated via `tests/final_mobile_visual_qa_probe.gd`.

## Milestone 22 - VFX and Audio Polish
- Expanded `AudioManager` with a cue catalog (ui / combat / world / music groups), aliases (`weapon_fire` → `fire`), and catalog-default priorities while preserving focus ducking.
- Extended `GameFeel` intents: `weapon_fire`, `shield_impact`, `pickup_collected`, `ability_activated` (still feedback-only). Wired plasma muzzle/fire, invuln shield bursts, pickup collect, and HUD ability flashes through them.
- Polished pooled VFX: `HitFlash` styles (impact / muzzle / shield), richer explosions, clearer projectile trails, enemy entrance + telegraph rings, boss telegraph accents, engine low-HP pulse. Effects stay pooled and below bullets. Validated via `tests/vfx_audio_polish_probe.gd`.

## Milestone 21 - Production Results Screen
- Upgraded results into a production summary: parallax atmosphere (victory/defeat tint), featured ship + engine glow, VICTORY/DEFEAT headlines, run emblem badge, score with NEW BEST, icon-backed mission stats, richer reward chips, stage stars when cleared.
- Actions: dominant Next Sector (victory) / Replay (defeat), Upgrade Ship, Home; Replay relaunches the same stage. RewardCalculator + SaveManager dedupe unchanged. Validated via `tests/results_screen_probe.gd`.

## Milestone 20 - Production Upgrade Choice Cards
- Polished the in-run upgrade overlay: RIFTWING brand, combat-paused hint, header chip, pulsing divider, softer dim veil, and a disabled `REROLL · SOON` stub (no reroll economy yet).
- Production cards: rarity frames + glow (cyan rare / purple epic / gold legendary pulse), rarity badge, icon plate, NEW/UNLOCK labels, category emblem derived from effect kind, press/hover/selection feedback. UpgradeManager roll/apply logic unchanged. Validated via `tests/upgrade_cards_probe.gd`.

## Milestone 19 - Production Galaxy Map
- Upgraded stage select into a production sector map: deep-space parallax, glowing mission paths (cyan cleared / purple unlocked / dashed locked), pulsing selected + “current” node rings, gold completed markers, and a clearer cleared-count header.
- Mission panel uses production chrome (power chips, cyan-framed detail, dominant Launch CTA pulse) with shared theme button variations. Launch / unlock / HARD / save behavior unchanged. Branding remains **RIFTWING** / SECTOR MAP. Validated via `tests/stage_map_probe.gd`.

## Milestone 18 - Production Hangar
- Upgraded hangar to a production bay: parallax hangar atmosphere, holographic platform + engine glow under the featured ship, idle ship motion, identity column (name / tier / power / equip), icon-backed stat chips, and a clearer locked·owned·equipped ship strip.
- Polished upgrade rows (accent rim, framed icon, progress bar chrome, primary/secondary CTA states) without changing SaveManager purchase, lock, or persistence rules. Currencies / Back use shared theme chip + tertiary styles. Validated via existing `tests/hangar_probe.gd`.

## Milestone 17 - Production Main Menu
- Redesigned the home screen into a cinematic RIFTWING composition: layered parallax (stars / nebula / debris), vignettes, distant enemy atmosphere, engine-glow + featured ship idle motion, event banner pulse, and a dominant Start Run CTA.
- Added reusable theme type variations `ButtonPrimary` / `ButtonSecondary` / `ButtonTertiary` (+ `ChipPanel`) in `riftwing_theme.tres`; menu buttons use them instead of plain prototype blocks.
- Top chrome: commander profile (selected ship + power bar), currencies, settings. Brand wordmark remains **RIFTWING** with `SPACE SURVIVOR` subtitle. Navigation unchanged (map / daily placeholder / hangar / settings). Debug markers forced off on entry. Validated via `tests/main_menu_probe.gd` at 1080×1920 / 2400 / 2478.

## Milestone 16 - Production Gameplay HUD
- Built reusable in-run HUD components: `HudSegmentedBar`, `AbilityButton`, and `GameplayHUD` (`scenes/ui/gameplay_hud.tscn`) with safe-area margins for 1080×1920 / 2400 / 2478.
- Top: live score + rift-energy currency, wave/phase chip (hidden while boss bar is active), pause + combo; Bottom: HP bar (damage/low-health feedback), XP bar, level badge, left/right ability buttons with charge + cooldown rings (feedback hooks only — no combat loop change).
- Wired into `run_scene` / `RunController`; pause overlay Resume / Quit to Menu; boss bar compacted under the top chip row. Validated via `tests/gameplay_hud_probe.gd`. Meta screens untouched.

## Milestone 15 - Visual Foundation
- Raised gameplay visual quality without new features: parallax `space_background` (stars / nebula / debris + center dim) replaces flat ColorRect on run / boss / wave hosts; tall viewports expand playable sky via stretch+fit.
- Debug presentation: overlay **hidden by default**; F3 toggles overlay + collision markers; optional three-finger toggle; run/boss/wave cyan cores and verbose readouts gated. `Engine.max_fps = 60`.
- Scale / language: player ~189px + separate `engine_glow` pulse/tilt/spawn; enemies violet with orange cores; Titan/Wisp larger; friendly cyan needles vs hostile magenta orbs; pickups ~72px. Enemy bolt pool prewarm cut 512→256 on run/boss.
- Added `visual_foundation` validation scene + `tests/visual_foundation_probe.gd` (1080×1920 / 2400 / 2478). Gap notes in `docs/VISUAL_FOUNDATION_GAP.md`. Gameplay/save/navigation untouched beyond visuals.

## Milestone 14 - Export Validation
- Centralized provisional store identity in `manifests/product_identity.json` (`com.lishistudio.riftwing`, version `0.1.0` / code `1`, Android minSdk 24 / targetSdk 35, iOS 15.0, portrait). Synced `project.godot` `config/version` and launcher icon.
- Hardened `export_presets.cfg`: **Android Debug** (installable APK, arm64, vibrate-only permission, branding icons/splash, editor debug keystore only), **Android Release** (AAB + Gradle, empty release keystore fields), **iOS** (bundle id / versions / export-project-only, empty Team/provisioning). Review/docs/tests excluded from packs. Added `.gitignore` for `build/`, keystores, and `export_credentials.cfg`.
- Authored `docs/EXPORT_VALIDATION.md` (Windows vs macOS capability matrix, Play AAB + TestFlight checklists, honest “no iOS binary on Windows” statement) and refreshed `docs/EXPORT_SIGNING.md`. Prototype launcher PNGs under `assets/branding/`.
- Validated via `tests/export_validation_probe.gd`. On this Windows host: installed Godot 4.7 export templates, exported **Android Debug** successfully to `build/android/riftwing-debug.apk` (~80MB, signed with editor debug keystore only). iOS was **not** built (requires macOS/Xcode). No ads/IAP/analytics/Firebase.

## Milestone 13 - Vertical Slice Integration
- Unified the playable loop into one data-driven run host: Main Menu → Stage Map → `run` (`RunController` + `StageTimelineData`) → early waves → XP/upgrade choices → Void Wisp mini-boss → mid waves → Void Titan → Results → rewards/save → Home / Hangar / Next Stage. Stage Map Launch now targets `SceneRouter.SCREEN_RUN` (debug hosts remain available).
- Authored `vertical_slice_timeline.tres` (~60s mini-boss, ~150s boss warning per `docs/02_GAMEPLAY_SPEC.md`), `slice_wave_early/mid.tres`, and `void_wisp.tres`. WaveDirector gained `stop` / `stop_and_clear` / `start_wave`; Boss gained `prepare` + `debug_defeat` for mini→final reuse; pools expose `release_all` for phase handoffs.
- Confirmed reward granting stays idempotent per `run_id`; pause is cleared on every screen transition. Review captures land in `review/` (`.gdignore` + export `exclude_filter`). Validated via `tests/vertical_slice_probe.gd` (victory, defeat, save/load, replay, pool caps).
- Remaining highest-priority issues: hangar permanent stats not yet applied in combat; acquired non-plasma weapons still do not fire; full 3-minute play relies on authored density/balance tuning; ability HUD chrome still deferred.

## Milestone 12 - Visual Review
- Produced `docs/VISUAL_GAP_REPORT.md` comparing implemented screens to `references/` (hierarchy, spacing, typography, color, contrast, readability, animation, effects, safe areas). Branding remains **RIFTWING** only — no Starforge / Galaxy Rush in production UI. Stage map header copy is `SECTOR MAP` (not Galaxy Rush branding).
- Highest-impact visual fixes without new final art: expanded `riftwing_theme.tres` (cyan primary glow, purple secondary, gold reward); main-menu hero/event/Daily hierarchy; results CTA pair (Upgrade + gold Next Sector) with clearer celebration title; upgrade overlay “CHOOSE AN UPGRADE” + tighter cards; shortened upgrade descriptions for mobile readability.
- Gameplay readability: enemy plasma bolts retinted to purple/magenta (no longer orange-impact role); combat debug backgrounds darkened so hazards stay readable; effects layer z-order unchanged (`EffectsLayer` z_index = -5, still below bullets).
- Capture/validation: `tests/visual_review_probe.gd` asserts brand + projectile color roles, smokes main screens at 1080×1920 / 2340 / 2400, and (with a real GPU window) writes 1080×1920 PNGs to `user://review_*_1080x1920.png` plus `docs/visual_review/`. Remaining gaps (key art, hex frames, ability chrome, licensed fonts) documented as art-dependent.

## Milestone 11 - Mobile Hardening
- Audited and hardened mobile runtime paths without redesigning gameplay: app background now flushes `SaveManager.save_game()` and ducks audio focus via `AudioManager.set_has_focus` (AppRoot `APPLICATION_PAUSED` / resume; mobile focus-out also ducks). SFX hooks no longer record while unfocused.
- Capped object pools: `ObjectPool` takes a hard `max_total` (acquire returns null + blocked counter when full). `ProjectilePool` / `NodePool` / `EffectsLayer` default to 2× prewarm (exportable). Prevents unbounded growth under spawn spikes.
- Touch/playfield: `PlayerShip` ignores secondary fingers, honors `canceled` touches, clears drag on tree pause, and expands the play rect for taller/wider viewports (9:16 / 19.5:9 / 20:9) without mutating the shared Resource. Boss debug screen size tracks the viewport.
- Safe areas: results screen, boss health bar, and upgrade choice overlay now inset from `SafeArea` on resize (menus/hangar/map already did).
- Effects: quality + haptics prefs persist (`user://effects_quality.cfg` / `haptics_enabled.cfg`); GameFeel honors the haptics toggle. LOW remains the low-effects profile (no particles/trails/shake/damage numbers).
- Debug overlay: FPS, static memory, object/node counts, aspect, safe rect, effects quality, audio focus, and live pool active/total/peak/blocked from the `pool_stats` group.
- Export: split **Android Debug** (APK) / **Android Release** (AAB) / **iOS** presets with provisional IDs only; documented manual signing in `docs/EXPORT_SIGNING.md`. Switched project renderer to `mobile` and set asset imports to VRAM compress (mipmaps on large backgrounds).
- Validated via headless import + `tests/mobile_hardening_probe.gd`: pool cap blocks growth past max; audio focus gating; quality persistence; save flush integrity; main menu + results open. Remaining risks noted in the milestone report (real audio banks, device FPS profiling, release keystore).

## Milestone 10 - Galaxy Stage Map
- Added the campaign map data model: `StageNodeData` (id, index, label, title, enemy/objective copy, recommended power, reward previews, first-clear bonus, map position, planet tint, `starts_unlocked`, star thresholds) and `StageMapData` (sector identity + ordered stage list). Authored `nova_sector_map.tres` with eight connected stages — 1-1…1-3 start unlocked for testing, 1-4…1-8 locked until the previous stage is cleared. All mission numbers and copy stay in Resources.
- Added `StageProgress` pure helpers for unlock checks, victory star rating (from authored combo/score thresholds), and player power (from the equipped hangar ship). Extended `RunStats` with `stage_id` so a map launch can be recorded on the results grant path.
- Extended `SaveManager` to schema v3 with a `campaign` block (`selected_stage_id`, `difficulty`, `cleared_stage_ids`, `stage_stars`), `select_stage`, `set_campaign_difficulty`, `record_stage_clear` (keeps best stars), and `can_launch_stage` (requires unlock + NORMAL). Victory grants now record stage clear/stars when `stats.stage_id` is set. Older saves migrate without losing hangar or currency data.
- Added `StageMapScreen` (registered as `stage_map`): RIFTWING branding, currency chips, scrollable static-composition map with connected paths, locked padlock nodes, selected highlight, NORMAL/HARD difficulty (HARD locked), mission detail panel (objective, recommended vs your power, rewards, first clear, stars), and Launch into `boss_debug` with `{sector, stage_id}`. Locked stages and HARD cannot launch. Main menu Start Run and results Next Sector route here; Hangar remains reachable from the map.
- Validated via headless import and `tests/stage_map_probe.gd` (Godot 4.7-stable): 8 stages / 3 starts unlocked; locked stages reject launch; clearing 1-3 unlocks 1-4; stars persist and keep the best; HARD blocks launch; grant path clears 1-1; screen opens with RIFTWING and disables Launch on locked selection. Zero parser or runtime errors.

## Milestone 09 - Ship Hangar
- Added the permanent hangar data model: `HangarUpgradeTrackData` (category, max level, Rift Energy cost curve, per-level ATK/DEF/HP/CRIT deltas), `ShipData` (base stats, textures, `starts_unlocked` / unlock hint, five track refs), `ShipCatalogData` (ordered roster), and `HangarStats` (pure current/preview/power math with no I/O). Authored five shared tracks plus four ships in `resources/ships/` — Vanguard MK-II unlocked, Razor Wing / Void Strider / Solar Lance locked placeholders. Every cost and stat number stays in `.tres` files.
- Extended `SaveManager` to schema v2 with a `ships` block (`selected_ship_id`, `unlocked_ship_ids`, per-ship `upgrade_levels`), `select_ship`, `unlock_ship`, and atomic `try_purchase_upgrade` that checks unlock + max level + affordability before deducting Rift Energy and incrementing a level. Failed purchases (including repeated taps with insufficient currency) leave the bank and levels unchanged. v1 saves migrate forward without losing currencies.
- Added `HangarScreen` (registered in `SceneRouter` as `hangar`): safe-area layout with RIFTWING branding, local currency chips, ship sidebar (EQUIPPED / OWNED / LOCKED), hero ship + power, ATK/DEF/HP/CRIT readout, five upgrade rows with next-benefit preview, and two-tap confirm purchase feedback. Locked ships show a padlock state and unlock hint with no store/IAP path. Main menu Ships/Upgrades and results Upgrade Ship now route here. Prototype QA key `G` grants +1000 Rift Energy for purchase testing (local currency only).
- Validated via headless import and `tests/hangar_probe.gd` (Godot 4.7-stable): catalog loads 4 ships / 3 locked; purchase fails at 0 energy and at cost−1 even under spam presses; affordable purchase deducts energy, applies the track’s attack curve, and persists across reload; locked ships cannot be selected or upgraded; hangar screen opens with `RIFTWING` + Vanguard. Zero parser or runtime errors.

## Milestone 07 - Results, Rewards, and Persistence
- Added a `RunStats` value object accumulated live during a run (survival time, enemies destroyed, best combo, Rift Energy collected, victory flag, sector) with a pure static `score_for(...)` whose weights are all injected — no scoring constant lives in code. Scoring is deterministic: identical inputs always yield the same score.
- Added the reward layer: `RewardRulesData` (a Resource holding every score weight and payout number; authored in `reward_rules_default.tres`), `RunRewards` (a plain two-currency value object — Rift Energy common, Rift Core rare), and `RewardCalculator` (a pure static function turning a `RunStats` + rules into `RunRewards`, with no side effects or persistence). Balance stays entirely in resources (docs/04).
- Added the `SaveManager` autoload: a versioned (`schema_version`), atomically written (temp file + rename so a crash mid-write can't corrupt the live save) local save holding the two currencies, completed sectors, best score, and the set of run ids that have already banked rewards. `grant_run_rewards` applies a run's payout exactly once per run id — re-opening the results screen for the same run shows the earned totals without re-granting. Old/partial saves are merged onto current defaults and migrated forward; the granted-id history is capped so the save can't grow unbounded.
- Added the `ResultsScreen` (registered in `SceneRouter` as `results`): a celebration-first layout (title beat animates in before the numbers) showing `SECTOR CLEARED` / `RIFTWING DOWN`, the run score, a stats block (enemies destroyed, best combo, survival time, Rift Energy), reward chips (Rift Energy always, Rift Core only when earned), sector progression + best score, and three real navigation buttons (Next Sector / Upgrade Ship / Home). All text is real Godot Controls; branding reads `RIFTWING`. Rewards are computed and banked once on open; a re-opened same-run screen labels the payout as already claimed.
- Extended `SceneRouter.go_to` with an optional payload dictionary handed to the new screen via a `receive_payload` hook (so the results screen is built from real run data without a global singleton), and it now always clears `get_tree().paused` on a transition so a screen swapped in from a paused run starts running.
- Wired the boss run host (`boss_debug`) to accumulate `RunStats` during play: survival time ticks per frame, a combo counter rises per kill and resets after a ~2.5s quiet window (tracking the peak), and each summoned add's real kill increments the tally via a new `Boss.add_destroyed` signal (re-broadcast from the add's existing `died`, so exit-recycled adds never count). On boss defeat or player death it holds the beat briefly then routes to the results screen; the readout also shows sector, kills, combo, survival, and the live currency bank. `Next Sector` advances the sector and replays; `Upgrade Ship` and `Home` route to a fresh run as documented placeholders until the hangar and main-menu milestones exist.
- Registered `SaveManager` as an autoload (before `SceneRouter`).
- Validated via headless import and two headless probes (Godot 4.7-stable): (1) the pure layer — score is deterministic and matches hand-computed values for victory (6975) and defeat (1975), rewards compute as expected (energy 598 / core 1), `grant_run_rewards` applies once and returns false on a repeat id with the bank unchanged, a new id grants again, and the save persists across reload; (2) the full app flow — a boss run driven to victory routes to `results` showing `SECTOR CLEARED` with a formatted score, banks the reward once (energy/core/best updated), and pressing `Next Sector` returns to a run without double-granting. Zero parser or runtime errors.

## Milestone 06 - First Boss
- Added the boss data model: `BossPatternData` (a single Resource whose `Kind` enum — RADIAL_BURST / SWEEP_LASER / SUMMON_WAVE — selects which fields the runtime reads: telegraph/active/recover timing plus per-attack counts, angles, gaps, spins, laser arc/width/damage, and summon counts/spacing) and `BossData` (name, health, sprite/scale, hit radius, contact damage, health-bar segment count, warning/entry timing, hold position, the 40% phase threshold, and a separate ordered pattern list per phase). Every boss number is authored in `.tres`; no attack constants live in code.
- Authored the Void Titan encounter: `void_titan.tres` (2400 HP, 20 segments, holds in the upper screen) with phase-1 patterns `void_titan_radial` (28-bullet rings with 2 safe gaps, 3 rings, spin), `void_titan_laser` (130° sweep), `void_titan_summon` (2 waves of 4), and denser/faster phase-2 variants `void_titan_radial_p2` (36 bullets, 4 rings) + `void_titan_laser_p2` (150°, return sweep). Added the purple `boss_radial_projectile.tres` (pooled enemy bolt) and the `void_spawn.tres` add.
- Added `Boss` (Area2D): a data-driven encounter state machine (IDLE→WARNING→ENTER→FIGHT↔PHASE_TRANSITION→DEFEATED) with an inner pattern loop (TELEGRAPH→ACTIVE→RECOVER) that cycles the current phase's pattern list. All timing advances by `delta` (no `await`), so the fight is deterministic and pausable. Attack 1 fires pooled radial bullet rings with real angular safe gaps; attack 2 sweeps a beam whose damage is a point-to-ray distance test against the player (thin, so a safe side always exists), never damaging during telegraph; attack 3 summons pooled `void_spawn` adds in timed waves. Crossing 40% health triggers a one-time invulnerable phase flip (flash + shock ring + audio/haptic hooks) into the denser phase-2 list; death clears remaining adds, plays a staggered explosion sequence + hit-stop, then emits `defeated` once.
- Every attack is telegraphed with an affirmatively-drawn safe route (docs/02): radial shows a pulsing red predicted ring with the safe gaps highlighted in cyan; the laser shows a red aim line + faint swept-sector fan marking the danger zone; summons show red warning rings at the drop columns. All danger uses the red/purple enemy palette roles, never pickup/player-cyan.
- Added `BossHealthBar` (Control): a segmented bar drawn in the top safe area with a real boss-name Label and phase pip (text is real Godot Controls, never baked art), an eased right-to-left drain, a phase-2 color shift, and a separate pulsing WARNING entrance banner.
- Added the standalone `boss_debug` scene/script (registered in `SceneRouter`; `AppRoot` routes to it) wiring the player + auto weapon, pooled player/enemy bolts, enemy + pickup pools, effects, camera, boss, and health bar, with a live readout and debug keys (Q quality, K damage, R restart).
- Fixed a pre-existing latent bug surfaced by boss hits: pooled `Projectile`/`Enemy`/`Pickup` (and the boss) toggled `monitoring`/`monitorable` directly inside `area_entered` callbacks, which Godot blocks mid-signal. Switched those enable/disable toggles to `set_deferred` (enable deferred too, so a same-frame re-acquire wins over a pending release). This removed all "Function blocked during in/out signal" runtime errors, including the ~109/8s previously emitted by the enemy-wave scene.
- No menus, run results, or new audio assets added; balance stays entirely in resources.
- Validated via headless import and a headless probe driving the full encounter: WARNING→ENTER→FIGHT→PHASE_TRANSITION→DEFEATED all reached; all three attacks fire in phase 1 and phase 2 uses its own denser list; the phase transition triggers at hp fraction 0.3975 (just under the 0.40 threshold); defeat clears summoned adds to 0 active; every pool stayed at its prewarm size (no runtime allocation); and zero parser or runtime errors across both the boss and enemy-wave scenes.

## Phase 4 - Roguelite Upgrades
- Added data-driven run progression: `LevelCurveData` (per-level XP step costs + overflow step; `level_curve_default.tres` = 3/5/6/8/10 then 12) and `ExperienceTracker` (Node) that converts collected energy 1:1 into XP by listening to `PlayerShip.energy_changed`, rolls level-ups against the curve, and queues multiple levels earned in one burst so each shows its own choice. No pacing numbers live in code.
- Added the upgrade data model: `UpgradeData` (id, title, multiline description, icon, rarity RARE/EPIC/LEGENDARY, prerequisites, max level, selection weight, and a typed `effects` array) and `UpgradeEffectData` (kind + target + value) covering `ACQUIRE_WEAPON`, `FIRE_RATE_MULT`, `PROJECTILES_ADD`, `SPREAD_ADD`, `DAMAGE_MULT`. Every offered choice and every applied number is authored as a `.tres`.
- Authored five upgrades: `plasma_overcharge` (rare, ≤5, +18% fire rate & +12% damage), `plasma_spread_array` (epic, ≤3, +1 bolt & +8° spread), and the three weapon acquisitions `homing_missiles` (epic), `arc_laser` (epic), `guardian_drone` (legendary).
- Added `UpgradeManager` (Node): owns the catalog + run loadout, tracks per-upgrade levels, enforces prerequisites, max levels, and a four-weapon cap, and generates three distinct rarity-weighted choices (`roll_choices`, no reroll). `apply()` routes effects to runtime systems — plasma effects adjust live `PlasmaWeapon` modifiers so a plasma pick has an immediate, visible result; weapon acquisitions register into the loadout (their firing behavior is a later weapons milestone).
- Extended `PlasmaWeapon` with additive runtime modifiers (`fire_rate_mult`, `bonus_projectiles`, `bonus_spread_degrees`, `damage_mult`) applied on top of the shared `WeaponData` baseline; a damage multiplier fires a cached duplicated `ProjectileData` so the shared `.tres` is never mutated, and firing still allocates nothing.
- Added the paused three-card choice UI: `UpgradeScreen` (CanvasLayer, `PROCESS_MODE_WHEN_PAUSED`) pauses the tree, dims frozen combat behind a translucent veil, and lays out exactly three `UpgradeCard`s built from the rare/epic/legendary frame SVGs with real Godot text (title, description, rarity, level) — never baked art. Cards animate in (scale 0.92→1.0), and selection plays a scale/border pulse plus a sound hook (`upgrade_select`) and a haptic hook, dims the unpicked cards, applies the upgrade, then resumes. Animations run on unscaled, pause-independent tweens.
- Wired progression into `enemy_wave_debug.tscn`/`.gd`: `L` forces a level-up on demand (opens the screen immediately), pending levels present one choice at a time before combat resumes, and the readout gained a progression block (level, XP into/for next, pending, weapon count, last pick, and live plasma rate/bolts/damage multipliers).
- No bosses, menus, run results, or audio assets added; balance stays entirely in resources.
- Validated via headless import and headless probes (since removed): energy→XP→level-up pauses the tree and opens the screen; `roll_choices` returns three distinct rarity-weighted cards; selecting a plasma card applies its data effects to the live weapon (rate ×1.18, dmg ×1.12; spread +1 bolt/+8°) while the shared projectile resource stays unchanged; the four-weapon cap blocks a fifth acquisition and maxed upgrades stop being offered; picking resumes combat and drains the pending-level queue. A 1080×1920 render confirmed the three-card paused layout. No new parser or runtime errors.

## Phase 3 - Game Feel
- Added `GameFeel` (autoload), a central feedback facade with a small intent API — `projectile_hit`, `enemy_death`, `player_hit` — that fans out to the effects layer, camera shake, haptics, and audio. It owns a LOW/MEDIUM/HIGH effect-quality budget (particle counts, trail length, damage numbers, shake scale) and a real-time-gated hit-stop (30-60 ms `Engine.time_scale` dip that cannot stack or get stuck). This layer is purely additive feedback: it never changes damage, health, invulnerability, spawns, collision, or any balance value, and every route no-ops when no effects layer / camera is registered (e.g. the stress test).
- Added `AudioManager` (autoload): a priority-aware (`LOW/MEDIUM/HIGH`) `play_sfx(cue, world_pos, priority)` sound-hook facade with a master enable and per-cue counters. No audio banks ship yet, so playback is a recorded hook that gameplay callers already target.
- Added `CameraRig` (`Camera2D`) with restrained trauma-based screen shake (trauma², simplex-noise offset + tiny roll, per-frame decay), advanced on unscaled time so shake reads through hit-stop; registers itself with `GameFeel`.
- Added pooled effect nodes, all recycled and never freed at runtime: `HitFlash` (expanding ring + quality-scaled spark burst), `Explosion` (shockwave sprite ring + procedural shock ring + light flash core + particle burst, small vs large preset), and `DamageNumber` (rising, fading real `Label`). Owned by `EffectsLayer` (three `ObjectPool`s) which renders at a low `z_index` **below** enemies and bullets so effects can never hide an enemy projectile (QA: enemy bullets remain visible).
- Wired feedback into existing gameplay: projectile impacts flash + emit a damage number + light haptic + `hit` cue and draw a quality-gated motion trail; enemy deaths trigger a small/large explosion (large + hit-stop + heavy haptic for shooters/tough enemies, chosen by reading `max_health` read-only) with shake and an explosion cue; player hits flash red with strong shake, a short hit-stop, heavy haptic, and a `player_hit` cue. Added a `fires_at_player` flag on `ProjectilePool` (feedback coloring only; collision targeting still decided by the scene's mask).
- Extended `enemy_wave_debug.tscn` with the `EffectsLayer` + `CameraRig`, a `Q`-to-cycle live quality toggle, and a feel readout (quality, trauma, hit-stop count, per-pool effect active/total, fired counters, SFX count). Registered `AudioManager` + `GameFeel` autoloads.
- No new gameplay logic, upgrades, bosses, menus, or audio assets added.
- Validated via headless import and headless probes (since removed): over ~12s of the debug wave the feel systems fired (86 hit flashes / damage numbers, 88 shakes + haptics, small + large explosions, hit-stop) with every effect pool held at prewarm (no growth, no frees); at LOW quality damage numbers, shake, trails, and particles all dropped to zero while core hits still registered, confirming quality is feedback-only. No new parser or runtime errors (pre-existing collision `monitoring` toggle warnings unchanged).

## Milestone 03 - Enemy Waves
- Added data-driven enemy resources: `EnemyData` (health, contact damage, energy drop, sprite/scale/tint, hit radius, and shooter fields: telegraph/burst count/spread/rest + projectile) with `scout.tres` (fast, no fire) and `shooter.tres` (telegraphs then fires a 3-bolt spread); `PickupData` (`energy_small.tres`) and `PlayerCombatData` (`player_combat_default.tres`, 100 HP + 1s i-frames).
- Added `WaveData` / `WaveEventData` Resources describing timed spawn events (time, enemy, count, formation, center, spacing, hold Y, entry/wait/exit seconds); authored `debug_wave_45s.tres` — a 45s wave of five row/vee events mixing scouts and shooters.
- Added `Enemy` (Area2D) with an ENTER→WAIT→EXIT phase machine: flies in from off-screen, holds formation (shooters telegraph with a warning ring + aim line, then fire readable bursts), and exits downward; takes damage, flashes on hit, drops pooled energy on death, and returns to its pool (never freed). Survivors recycle silently on exit.
- Added `Pickup` (Area2D): pooled energy that drifts down, is collected once on player overlap, and returns to its pool on collection or lifetime/bounds expiry.
- Added `NodePool` (Node), a type-agnostic scene pool over the existing `ObjectPool`, used for enemies and pickups; and `WaveDirector` (Node2D) that reads a `WaveData`, spawns formations at event times, injects pooled/data dependencies, and re-broadcasts kills + wave completion.
- Extended `Projectile` with generic overlap damage (the scene's collision mask decides its target) and `PlayerShip` with health, 1s invulnerability + blink, contact damage from enemies, and energy pickup collection. Added a shared enemy projectile scene (`enemy_projectile.tscn`) reusing the projectile script. Collision layers: 1 player, 2 player-bolt, 3 enemy, 4 enemy-bolt, 5 pickup.
- Added `enemy_wave_debug.tscn` wiring the player + auto weapon, wave director, and four pools with a live readout (HP, energy, active/peak enemies, kills, per-pool active/total, first-wave-cleared); registered in `SceneRouter` and routed `AppRoot` to it.
- No upgrades, bosses, menus, HUD polish, or audio added.
- Validated via headless import and two headless probes (since removed): the wave spawns (peak 5 concurrent), enemies die and the pool recycles (reuse confirmed), shooters fire bursts and drop energy, and player Area2D wiring collects pickups (energy 0→1) and takes scout contact damage (100→88). No parser or runtime errors.

## Milestone 02 - Projectile Pool
- Added `ProjectileData` and `WeaponData` custom Resources; all projectile values (speed, lifetime, damage, radius, length, color) and weapon values (fire rate, per-shot count, spread, muzzle offset, projectile ref) are data-driven, with default instances `plasma_projectile.tres` and `plasma_cannon.tres`.
- Added a generic `ObjectPool` (RefCounted) that prewarms a configurable count, keeps pooled nodes in the tree, and exposes active/free/total/peak statistics. Acquire/release toggle process+visibility; no node is freed during a run. Growth (extra instantiate) happens only if demand exceeds prewarm, and grown nodes are recycled, never freed.
- Added `Projectile` (Area2D): data-driven movement, lifetime, and screen-bounds despawn; returns itself to the pool via a release callback instead of `queue_free`. Monitoring is off (no enemies this milestone). Guarded `_process` so a pooled-but-unlaunched node stays inert.
- Added `ProjectilePool` (Node) owning the pool for the projectile scene, exposing `spawn()` and `get_stats()`; and `PlasmaWeapon` (Node2D) that auto-fires on a data-driven interval while `firing_active` (the run-active gate), pulling from the pool — no per-shot instantiate/free.
- Added a projectile stress-test scene (`projectile_stress_test.tscn`) that holds ~430 concurrent bolts (>300 target) while displaying FPS and live pool stats (active/free/total/peak/prewarm) and a pool-growth indicator; registered it in `SceneRouter` and routed `AppRoot` to it for verification.
- No enemies, upgrades, bosses, or menus added.
- Validated via headless import, a windowed run, and headless harnesses (since removed) asserting: prewarm/acquire/release/reuse, controlled growth beyond prewarm with zero frees, ~430 concurrent with total held at prewarm (no growth), and full return-to-pool after lifetime expiry. No parser or runtime errors.

## Milestone 01 - Player Movement
- Added `PlayerShip` (`Area2D`): one-finger drag-follow movement with mouse/touch emulation, frame-rate-independent exponential smoothing, and a configurable vertical offset so the ship stays visible above the finger.
- Ship origin is clamped to a configurable gameplay rectangle; the scene includes a small `CollisionCore` (18px circle) independent of the ship art.
- Input is released safely on touch cancellation and on application focus-out / pause via `_notification`, so no drag remains stuck after backgrounding.
- Added `PlayerMovementData` Resource (smoothing, vertical offset, gameplay rect) with a default instance `resources/balance/player_movement_default.tres`; behavior stays in the node, balance in the resource.
- Added a `MovementDebug` scene drawing the gameplay bounds, the live pointer/touch marker (48px), and the highlighted collision core; registered it in `SceneRouter` and routed `AppRoot` to it for verification.
- No shooting, enemies, or HUD added.
- Added `scripts/player/` (parallel to the existing `scenes/player/`), a minor structural addition beyond the architecture folder list.
- Validated via headless import and a graceful windowed run (Godot 4.7-stable): no parser or runtime errors.

## Milestone 00 - Bootstrap
- Created the Godot 4.7 typed-GDScript project `Riftwing` (portrait 1080x1920, `canvas_items`/`expand` stretch, handheld portrait orientation).
- Added the architecture folder skeleton from `docs/04_ARCHITECTURE.md` (scenes/, scripts/, resources/, tests/ with subfolders; `resources/theme/` added for the theme foundation).
- Added `AppRoot` scene + script, a `SceneRouter` autoload that owns a single active screen, and a `UIOverlay` layer.
- Added six typed no-op platform-service interfaces (Store, Ads, Analytics, Haptics, CloudSave, Achievement) aggregated behind the `PlatformServices` autoload; gameplay never touches SDKs directly.
- Added a `VisualSandbox` screen showing the three parallax background layers (mirrored, depth-scaled scroll) and the placeholder player ship SVG.
- Added a `SafeArea` helper that converts native safe-area pixels to logical coordinates, and a debug overlay showing FPS, viewport size, safe-area rect, active screen, and platform, with a drawn safe-area outline.
- Added a `Palette` autoload sourced from `manifests/color_tokens.json` and a minimal reusable `riftwing_theme.tres`.
- Added input actions `drag_primary`, `pause`, `debug_toggle` (F3), `debug_toggle_safe_area` (F4); enabled touch-from-mouse emulation.
- Added `export_presets.cfg` as an Android/iOS export-readiness placeholder with provisional IDs only (no keystore/signing/SDK data).
- Validated via headless import and graceful headless + windowed runs (Godot 4.7-stable): no parser or runtime script/scene errors.

## Starter Kit v2
- Renamed canonical product identity to Riftwing.
- Added strict legacy-branding rules for concept screenshots.
- Added brand, naming, and reference implementation specifications.
- Added exact first Claude Code message and Hebrew quick-start guide.
- Strengthened milestone scope, validation, screenshot review, and stop conditions.
- Added vertical-slice integration and export-validation milestones.

## Starter Kit v1
- Initial architecture, assets, references, and milestone prompts.
