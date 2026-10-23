class_name StageMapData
extends Resource
## Ordered sector map: connected stage nodes for the galaxy map screen.

@export var sector_id: String = "nova"
@export var sector_code: String = "01"
@export var sector_name: String = "NOVA SECTOR"

@export var stages: Array[StageNodeData] = []


func find_by_id(stage_id: String) -> StageNodeData:
	for stage in stages:
		if stage != null and stage.id == stage_id:
			return stage
	return null


func find_by_index(index: int) -> StageNodeData:
	for stage in stages:
		if stage != null and stage.index == index:
			return stage
	return null


func next_after(stage_id: String) -> StageNodeData:
	var current := find_by_id(stage_id)
	if current == null:
		return null
	return find_by_index(current.index + 1)


## Default selection for a fresh save: first starts_unlocked stage.
func default_stage_id() -> String:
	for stage in stages:
		if stage != null and stage.starts_unlocked and stage.id != "":
			return stage.id
	if not stages.is_empty() and stages[0] != null:
		return stages[0].id
	return ""


# --- Sector presentation (campaign pass) ---------------------------------------

## 1-based sector number (drives stats.sector and cross-sector unlocks).
@export_range(1, 20) var sector_index: int = 1
## Run background tint and nebula modulate for this sector.
@export var background_tint: Color = Color(1, 1, 1, 1)
@export var nebula_modulate: Color = Color(1, 1, 1, 1)
## Music track ids (AudioManager.MUSIC_TRACKS) for waves / bosses.
@export var run_music: String = "run"
@export var boss_music: String = "boss"
## Map canvas height needed by this sector's node layout.
@export_range(600.0, 4000.0, 10.0) var map_height: float = 1180.0


## The last stage of the sector (highest index).
func last_stage() -> StageNodeData:
	var best: StageNodeData = null
	for stage in stages:
		if stage != null and (best == null or stage.index > best.index):
			best = stage
	return best
