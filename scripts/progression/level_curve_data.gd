class_name LevelCurveData
extends Resource
## Data-driven experience thresholds for run leveling.
##
## The player earns experience by collecting energy pickups. This resource maps
## a level to the cumulative XP needed to reach it, so pacing is tuned in a .tres
## and never hard-coded (docs/02_GAMEPLAY_SPEC.md: XP and level thresholds are
## data-driven).

## Per-level XP cost, in order. Index 0 is the XP to advance from level 1 to
## level 2, index 1 from level 2 to level 3, and so on. The player starts at
## level 1 with 0 XP-into-level.
@export var step_costs: PackedInt32Array = PackedInt32Array([3, 5, 6, 8, 10])

## Once past the authored curve, each further level costs this much (keeps
## leveling going indefinitely without more authored entries).
@export_range(1, 100) var overflow_step: int = 12


## XP required to advance from `level` to `level + 1`. `level` is 1-based.
func xp_to_reach_next(level: int) -> int:
	var index := maxi(0, level - 1)
	if index < step_costs.size():
		return step_costs[index]
	return overflow_step
