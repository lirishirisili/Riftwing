class_name SpawnProfileData
extends Resource
## Ambient spawning for a run phase: the WaveDirector earns a threat budget per
## second (ramping from start to end over `ramp_seconds`) and spends it on
## formations of weighted enemies, on top of any authored wave events. This
## keeps the field busy (no dead air) and makes pressure climb within a run.

## Enemy pool and matching relative weights (same length).
@export var enemies: Array[EnemyData] = []
@export var weights: PackedFloat32Array = PackedFloat32Array()

## Budget earned per second at the start / end of the ramp.
@export_range(0.0, 30.0, 0.05) var budget_per_second_start: float = 1.0
@export_range(0.0, 60.0, 0.05) var budget_per_second_end: float = 3.0
@export_range(1.0, 900.0, 1.0) var ramp_seconds: float = 90.0

## Never exceed this many live wave enemies (authored + ambient).
@export_range(1, 80) var max_alive: int = 18

## Elite chance per ambient formation (ramps like the budget) and the minimum
## seconds between two elites.
@export_range(0.0, 1.0, 0.01) var elite_chance_start: float = 0.03
@export_range(0.0, 1.0, 0.01) var elite_chance_end: float = 0.12
@export_range(0.0, 120.0, 1.0) var elite_min_gap_seconds: float = 14.0
## Elite HP multiplier (on top of difficulty).
@export_range(1.0, 20.0, 0.5) var elite_hp_mult: float = 4.0

## Vertical band (fraction of screen height) where formations hold.
@export_range(0.05, 0.6, 0.01) var hold_band_top: float = 0.16
@export_range(0.1, 0.7, 0.01) var hold_band_bottom: float = 0.4


## Budget per second at `t` seconds into the phase.
func budget_rate(t: float) -> float:
	return lerpf(budget_per_second_start, budget_per_second_end, clampf(t / ramp_seconds, 0.0, 1.0))


func elite_chance(t: float) -> float:
	return lerpf(elite_chance_start, elite_chance_end, clampf(t / ramp_seconds, 0.0, 1.0))
