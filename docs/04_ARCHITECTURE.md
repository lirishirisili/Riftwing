# Technical Architecture

## Top-level scene structure

```text
AppRoot
|- PlatformServices
|- AudioManager
|- SaveManager
|- SceneRouter
|- UIOverlay
`- CurrentScreen
```

Gameplay scene:

```text
RunScene
|- RunController
|- WorldRoot
|  |- BackgroundParallax
|  |- EnemyRoot
|  |- ProjectileRoot
|  |- PickupRoot
|  `- EffectsRoot
|- Player
|- WaveDirector
|- CameraRig
`- UI (CanvasLayer)
   |- GameplayHUD (score, currency, wave chip, pause, HP/XP bars, ability buttons)
   |- BossHealthBar (top-center when a boss is active)
   `- debug readout / phase banner
```

## Folder structure

```text
project/
|- assets/
|- scenes/
|  |- app/
|  |- gameplay/
|  |- player/
|  |- enemies/
|  |- bosses/
|  |- weapons/
|  |- effects/
|  `- ui/
|- scripts/
|  |- core/
|  |- combat/
|  |- spawning/
|  |- progression/
|  |- services/
|  `- utilities/
|- resources/
|  |- enemies/
|  |- weapons/
|  |- upgrades/
|  |- waves/
|  `- balance/
|- tests/
`- project.godot
```

## Core systems
- RunController (`scenes/gameplay/run_scene.tscn`): vertical-slice state machine — early waves → XP/upgrade choices → mini-boss → mid waves → final boss → results. Driven by `StageTimelineData`.
- StageTimelineData: authored clock + wave/boss refs for a ~3-minute stage (docs/02_GAMEPLAY_SPEC.md).
- WaveDirector: data-driven timed spawn instructions; supports `stop_and_clear` / `start_wave` for phase handoffs.
- PoolManager: pools bullets, enemies, effects, pickups, and damage labels.
- DamageSystem: hit data, armor, criticals, invulnerability, and death events.
- UpgradeManager: offered choices (rarity-weighted by run level), application, levels, and synergy hints.
- SaveManager: versioned local save with atomic writes.
- SceneRouter: transitions between menu, map, hangar, run, and results.
- AudioManager: named cue catalog with ui/combat/world/music groups, aliases, priorities, SFX player pool, Music/SFX buses, `play_music` crossfade, soft autofire `fire_loop` (not per-shot), focus ducking, and `user://audio_prefs.cfg` (enabled + volumes). Banks under `assets/audio/` are modern sci-fi procedural OGGs (regenerate with `tools/generate_audio_banks.gd`), not chiptune placeholders.
- GameFeel: feedback intents (`projectile_hit`, `enemy_death`, `player_hit`, `weapon_fire`, `shield_impact`, `pickup_collected`, `ability_activated`) routing to pooled effects, shake, haptics, and AudioManager; owns LOW/MEDIUM/HIGH effect budgets.
- `riftwing_theme.tres`: shared UI chrome including `ButtonPrimary` / `ButtonSecondary` / `ButtonTertiary` and empty-style `ButtonChrome` for glow plates.
- Shared meta UI kit: `scenes/ui/chrome/glow_cta_button.tscn` + `meta_screen_shell.tscn` — all player-facing meta screens compose these instead of undressed flat primary buttons.
- HangarScreen: production ship bay UI over SaveManager hangar data (select / unlock / `try_purchase_upgrade`); holographic `hangar_pad`, color-coded upgrade rows, and disabled Upgrade All stub remain presentation-only.
- StageMapScreen: production sector map UI over `StageMapData` + `StageProgress` / SaveManager campaign unlocks; Launch still routes to `SCREEN_RUN`. Mounts `MetaScreenShell` and glow LAUNCH/BACK/HANGAR CTAs; map-node SVGs + path/pulse rings unchanged — no gameplay systems in the map screen.
- UpgradeScreen / UpgradeCard: production rarity-framed choice overlay; UpgradeManager remains the only apply path.
- ResultsScreen: production run summary UI; grants remain `RewardCalculator` → `SaveManager.grant_run_rewards` (once per `run_id`). Scrollable summary with sticky CTAs for safe-area phones.
- CameraRig: rest position tracks viewport center (shake via offset) so tall 19.5:9 / 20:9 frames stay filled.
- GlowController: quality-gated WorldEnvironment bloom (LOW off / MED soft / HIGH restrained).
- Theme: `ButtonPrimary` / `Secondary` / `Tertiary` / `ButtonReward`, `ChipPanel`, `NeonPanel` chamfer neon chrome.
- Key art under `assets/art/` and UI chrome under `assets/ui/chrome/` — never full reference screenshots as UI.

## Data resources
Use custom Resources such as:
- WeaponData
- ProjectileData
- EnemyData
- WaveData
- UpgradeData
- BossPatternData
- ShipData

Data resources contain balance and references. Runtime nodes contain behavior.

## Platform services
Define interfaces for:
- StoreService
- AdsService
- AnalyticsService
- HapticsService
- CloudSaveService
- AchievementService

Prototype implementations are no-op or local on all platforms. `AdsService` remains as a typed interface but has no AdMob (or other ad) adapter wired — the game ships without ads or tracking SDKs.

### Ads (disabled)
- No interstitial, rewarded, or banner placement.
- Poing AdMob editor plugin is disabled in `project.godot`; iOS `.gdip` plugins are renamed to `.gdip.disabled`.
- No `NSUserTrackingUsageDescription` / ATT purpose string in the iOS export preset.
- Save schema may still contain legacy `monetization` fields for migration; they are unused at runtime.

## Performance strategy
- Object pooling is mandatory.
- Pool growth is hard-capped (`ObjectPool.max_total`); callers must tolerate a null acquire.
- Avoid per-frame searches through the scene tree.
- Cache references.
- Use collision layers intentionally.
- Use MultiMesh or simplified emitters if enemy counts become large.
- Provide effect budgets by quality level (LOW/MEDIUM/HIGH, persisted).
- App background flushes the save and ducks audio focus (AppRoot lifecycle).
- Android system Back is owned by AppRoot (`quit_on_go_back=false` + `NOTIFICATION_WM_GO_BACK_REQUEST`): run → HUD pause; meta screens → navigate home; main menu → quit. Screens opt in via `handle_system_back() -> bool`.
- Profile on real devices, not only desktop.
- Rendering method: `mobile` (see `project.godot`). Export signing steps: `docs/EXPORT_SIGNING.md`.

## Save schema
Save root includes `schema_version`, player progression, currencies, settings, unlocked ships, completed stages, and run statistics. Never store runtime nodes directly.

Hangar persistence (schema v2+) lives under `ships`:
- `selected_ship_id` — currently equipped ship
- `unlocked_ship_ids` — ships available without monetization (progression / `starts_unlocked`)
- `upgrade_levels` — per-ship map of track id → level (`weapons`, `shield`, `engine`, `drones`, `ultimate`)

Ship definitions, base stats, upgrade costs, and per-level stat curves are authored as `ShipData` / `HangarUpgradeTrackData` Resources. The save stores only ids and levels.

Campaign / galaxy map persistence (schema v3+) lives under `campaign`:
- `selected_stage_id` — last inspected / played stage
- `difficulty` — `normal` (playable) or `hard` (UI-locked in the prototype)
- `cleared_stage_ids` — stages beaten at least once
- `stage_stars` — per-stage best star rating (0-3); computed additively on victory from clear / end HP ratio / score thresholds on `StageNodeData`

Mission copy, recommended power, reward previews, map positions, and unlock seeds are authored as `StageNodeData` / `StageMapData` Resources. Unlock rule: `starts_unlocked` or previous stage cleared.
