class_name Campaign
extends RefCounted
## Static access to the whole campaign (every sector's StageMapData).
##
## Replaces the many hard-coded `nova_sector_map.tres` loads: stage lookups,
## sector of a stage, the next stage across sector boundaries, and unlocks.
## Pure data access; unlock / clear state still comes from SaveManager.

const PATH := "res://resources/stages/campaign.tres"

static var _data: CampaignData = null


static func data() -> CampaignData:
	if _data == null:
		_data = load(PATH) as CampaignData
		if _data == null:
			_data = CampaignData.new()
	return _data


static func sectors() -> Array[StageMapData]:
	return data().sectors


static func sector(index_1_based: int) -> StageMapData:
	var list := sectors()
	if index_1_based < 1 or index_1_based > list.size():
		return null
	return list[index_1_based - 1]


static func map_for_stage(stage_id: String) -> StageMapData:
	for map in sectors():
		if map != null and map.find_by_id(stage_id) != null:
			return map
	return null


static func find_stage(stage_id: String) -> StageNodeData:
	var map := map_for_stage(stage_id)
	return map.find_by_id(stage_id) if map != null else null


## 1-based sector index of a stage (1 when unknown).
static func sector_index_of(stage_id: String) -> int:
	var map := map_for_stage(stage_id)
	return map.sector_index if map != null else 1


## Next stage in play order: next index in the sector, else the first stage of
## the following sector. Null after the final stage.
static func next_after(stage_id: String) -> StageNodeData:
	var map := map_for_stage(stage_id)
	if map == null:
		return null
	var nxt := map.next_after(stage_id)
	if nxt != null:
		return nxt
	var following := sector(map.sector_index + 1)
	return following.find_by_index(1) if following != null else null


static func is_unlocked(stage_id: String, cleared_ids: Array) -> bool:
	var map := map_for_stage(stage_id)
	if map == null:
		return false
	return StageProgress.is_unlocked(map, map.find_by_id(stage_id), cleared_ids)


## Every stage id the player can launch on NORMAL right now.
static func unlocked_stage_ids(cleared_ids: Array) -> Array:
	var out: Array = []
	for map in sectors():
		if map == null:
			continue
		for stage in map.stages:
			if stage != null and StageProgress.is_unlocked(map, stage, cleared_ids):
				out.append(stage.id)
	return out


static func total_stage_count() -> int:
	var n := 0
	for map in sectors():
		if map != null:
			n += map.stages.size()
	return n
