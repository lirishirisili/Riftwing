class_name StageTimelineData
extends Resource
## Data-driven ~3-minute stage clock for the vertical slice.
##
## Times follow docs/02_GAMEPLAY_SPEC.md (first-run timeline). The RunController
## owns the clock; WaveDirector / Boss nodes execute the authored segments.

@export var display_name: String = "Vertical Slice"

## Early combat (formations + pickups) before the mini-boss.
@export var early_wave: WaveData

## Combat between mini-boss and the final boss warning.
@export var mid_wave: WaveData

## Short mid-run boss encounter ("mini progression").
@export var mini_boss: BossData

## Climax boss (Void Titan for the first slice).
@export var final_boss: BossData

## Run-clock second when early waves stop and the mini-boss warning starts.
@export_range(10.0, 300.0, 1.0) var mini_boss_at: float = 60.0

## Run-clock second when mid waves stop and the final boss warning starts.
@export_range(30.0, 600.0, 1.0) var boss_warning_at: float = 150.0

## Optional XP grant at this time so the first upgrade choice lands ~15-20s
## even if pickup RNG is light (0 = disabled).
@export_range(0.0, 120.0, 0.5) var guaranteed_level_up_at: float = 18.0

## XP amount granted at guaranteed_level_up_at (one level on the default curve).
@export_range(0, 500) var guaranteed_level_up_xp: int = 10
