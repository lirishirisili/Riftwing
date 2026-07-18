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
