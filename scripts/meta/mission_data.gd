class_name MissionData
extends Resource
## One daily / weekly mission. Progress is measured from finished runs
## (MetaProgress.record_run) using `metric`.
##
## Metrics (summed per run unless noted): kills, elites, bosses, runs, victories,
## chests, novas, evolutions, seconds, energy, stage_clears, hard_clears,
## combo (best in one run, max), endless_seconds (one Endless run, max).

@export var id: String = ""
## Card text; "{goal}" is replaced with the goal number.
@export var title: String = "Destroy {goal} enemies"
@export var metric: String = "kills"
@export_range(1, 100000) var goal: int = 100
@export_enum("daily", "weekly") var scope: String = "daily"
@export_range(0, 100000) var reward_energy: int = 200
@export_range(0, 100) var reward_core: int = 0
## Activity points toward the daily / weekly milestone chests.
@export_range(0, 100) var activity: int = 20
## Metrics that keep the best single run instead of summing.
const MAX_METRICS := ["combo", "endless_seconds"]


func text() -> String:
	return title.replace("{goal}", str(goal))


func is_max_metric() -> bool:
	return metric in MAX_METRICS
