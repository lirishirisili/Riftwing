class_name MetaCatalogData
extends Resource
## Every authored meta-progression definition (missions, achievements, modules,
## login calendar, pilot curve, patrol rates). One resource so balance lives in
## data: resources/meta/meta_catalog.tres (built by tools/build_meta_content.gd).

@export var missions: Array[MissionData] = []
@export var achievements: Array[AchievementData] = []
@export var modules: Array[ModuleData] = []

## Daily / weekly missions drawn per period.
@export_range(1, 6) var daily_count: int = 3
@export_range(1, 6) var weekly_count: int = 3
## Activity milestones per period and their rewards [energy, core, module?].
@export var activity_milestones: PackedInt32Array = PackedInt32Array([40, 80, 120])
@export var activity_reward_energy: PackedInt32Array = PackedInt32Array([300, 600, 0])
@export var activity_reward_core: PackedInt32Array = PackedInt32Array([0, 1, 2])
## The last milestone also grants a module.
@export var activity_final_module: bool = true

## 7-day login calendar (energy, core per day).
@export var login_energy: PackedInt32Array = PackedInt32Array([200, 300, 0, 500, 0, 800, 0])
@export var login_core: PackedInt32Array = PackedInt32Array([0, 0, 1, 0, 2, 0, 5])

## Pilot XP: per run = score / xp_score_divisor + boss bonus + victory bonus.
@export_range(1, 1000) var xp_score_divisor: int = 50
@export_range(0, 1000) var xp_per_boss: int = 40
@export_range(0, 2000) var xp_per_victory: int = 100
## XP to go from level L to L+1 = xp_base + xp_step * (L - 1).
@export_range(10, 10000) var xp_base: int = 400
@export_range(0, 5000) var xp_step: int = 150
## Rift Core per pilot level-up (+ bonus every 5th level).
@export_range(0, 20) var level_core: int = 1
@export_range(0, 50) var level_core_every_5: int = 3

## Offline patrol: energy per minute = base + per_cleared_stage * clears; cap.
@export_range(0.0, 100.0, 0.1) var patrol_base_per_minute: float = 1.0
@export_range(0.0, 20.0, 0.05) var patrol_per_stage_per_minute: float = 0.4
@export_range(1.0, 48.0, 0.5) var patrol_cap_hours: float = 8.0
## Minimum minutes away before the patrol is worth showing.
@export_range(1.0, 120.0, 1.0) var patrol_min_minutes: float = 10.0

## Module drop chance per campaign victory and rarity weights for drops.
@export_range(0.0, 1.0, 0.01) var module_drop_chance: float = 0.6
@export var module_rarity_weights: PackedFloat32Array = PackedFloat32Array([0.7, 0.24, 0.05, 0.01])


func find_module(id: String) -> ModuleData:
	for m in modules:
		if m != null and m.id == id:
			return m
	return null


func find_mission(id: String) -> MissionData:
	for m in missions:
		if m != null and m.id == id:
			return m
	return null
