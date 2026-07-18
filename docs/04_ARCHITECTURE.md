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
`- HUD
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
- UpgradeManager: offered choices, application, levels, and synergies.
- SaveManager: versioned local save with atomic writes.
- SceneRouter: transitions between menu, map, hangar, run, and results.
- AudioManager: music snapshots, sound priorities, and volume groups.

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

Prototype implementations are no-op or local. Android and iOS adapters are added later without changing gameplay code.

## Performance strategy
- Object pooling is mandatory.
- Pool growth is hard-capped (`ObjectPool.max_total`); callers must tolerate a null acquire.
- Avoid per-frame searches through the scene tree.
- Cache references.
- Use collision layers intentionally.
- Use MultiMesh or simplified emitters if enemy counts become large.
- Provide effect budgets by quality level (LOW/MEDIUM/HIGH, persisted).
- App background flushes the save and ducks audio focus (AppRoot lifecycle).
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
- `stage_stars` — per-stage best star rating (0-3)

Mission copy, recommended power, reward previews, map positions, and unlock seeds are authored as `StageNodeData` / `StageMapData` Resources. Unlock rule: `starts_unlocked` or previous stage cleared.
