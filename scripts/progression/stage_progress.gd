class_name StageProgress
extends RefCounted
## Pure helpers for galaxy-map unlock and star rating.
##
## No I/O and no autoload references — SaveManager owns persistence; the map UI
## and grant path call these with explicit inputs.


## A stage is playable when it starts unlocked or the previous index was cleared.
static func is_unlocked(map: StageMapData, stage: StageNodeData, cleared_ids: Array) -> bool:
	if map == null or stage == null:
		return false
	if stage.starts_unlocked:
		return true
	var prev := map.find_by_index(stage.index - 1)
	if prev == null:
		return false
	return cleared_ids.has(prev.id)


## Stars for a victorious run against authored thresholds. Defeat always yields 0.
static func stars_for_run(stage: StageNodeData, stats: RunStats) -> int:
	if stage == null or stats == null or not stats.victory:
		return 0
	var stars := 1
	if stats.best_combo >= stage.stars_combo_for_2:
		stars = 2
	if stats.score >= stage.stars_score_for_3:
		stars = 3
	return stars


## Player power from a hangar ship + level map (for the detail panel comparison).
static func player_power_from(ship: ShipData, levels: Dictionary) -> int:
	if ship == null:
		return 0
	return HangarStats.compute(ship, levels).power()
