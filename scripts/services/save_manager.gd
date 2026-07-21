extends Node
## Versioned, atomic local save (autoload).
##
## Owns persistent progression: currencies, hangar ships/upgrades, campaign stage
## clears/stars/selection, completed sectors, best score, and granted run ids.
## Writes are atomic (temp file + rename). Schema migrates forward
## (docs/04_ARCHITECTURE.md).

signal currencies_changed(rift_energy: int, rift_core: int)
signal hangar_changed(selected_ship_id: String)
signal campaign_changed(selected_stage_id: String)

const SCHEMA_VERSION := 4
const SAVE_PATH := "user://riftwing_save.json"
const _TEMP_PATH := "user://riftwing_save.json.tmp"
const _MAX_GRANTED_IDS := 256
const _MAX_DOUBLED_IDS := 64
const _DEFAULT_SHIP_ID := "vanguard_mk2"
const _DEFAULT_STAGE_ID := "1-1"
const _TRACK_IDS := ["weapons", "shield", "engine", "drones", "ultimate"]
const DIFFICULTY_NORMAL := "normal"
const DIFFICULTY_HARD := "hard"

var _data: Dictionary = {}


func _ready() -> void:
	_data = _default_data()
	load_game()


func _default_data() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"currencies": {"rift_energy": 0, "rift_core": 0},
		"progression": {"highest_sector_cleared": 0, "best_score": 0},
		"completed_sectors": [],
		"granted_run_ids": [],
		"ships": {
			"selected_ship_id": _DEFAULT_SHIP_ID,
			"unlocked_ship_ids": [_DEFAULT_SHIP_ID],
			"upgrade_levels": {
				_DEFAULT_SHIP_ID: _zero_levels(),
			},
		},
		"campaign": {
			"selected_stage_id": _DEFAULT_STAGE_ID,
			"difficulty": DIFFICULTY_NORMAL,
			"cleared_stage_ids": [],
			"stage_stars": {},
		},
		"monetization": {
			"completed_run_count": 0,
			"doubled_reward_run_ids": [],
		},
	}


func _zero_levels() -> Dictionary:
	return {
		"weapons": 0,
		"shield": 0,
		"engine": 0,
		"drones": 0,
		"ultimate": 0,
	}


# --- Reads ------------------------------------------------------------------

func get_rift_energy() -> int:
	return int(_data["currencies"]["rift_energy"])


func get_rift_core() -> int:
	return int(_data["currencies"]["rift_core"])


func get_best_score() -> int:
	return int(_data["progression"]["best_score"])


func get_highest_sector_cleared() -> int:
	return int(_data["progression"]["highest_sector_cleared"])


func is_sector_completed(sector: int) -> bool:
	return _data["completed_sectors"].has(sector)


func has_granted_run(run_id: String) -> bool:
	return run_id != "" and _data["granted_run_ids"].has(run_id)


func get_selected_ship_id() -> String:
	return String(_data["ships"]["selected_ship_id"])


func is_ship_unlocked(ship_id: String) -> bool:
	if ship_id == "":
		return false
	return _data["ships"]["unlocked_ship_ids"].has(ship_id)


func get_upgrade_levels(ship_id: String) -> Dictionary:
	var all: Dictionary = _data["ships"]["upgrade_levels"]
	if not all.has(ship_id):
		return _zero_levels()
	var raw: Variant = all[ship_id]
	if typeof(raw) != TYPE_DICTIONARY:
		return _zero_levels()
	var levels := _zero_levels()
	for key in _TRACK_IDS:
		levels[key] = int((raw as Dictionary).get(key, 0))
	return levels


func get_upgrade_level(ship_id: String, track_id: String) -> int:
	return int(get_upgrade_levels(ship_id).get(track_id, 0))


func get_selected_stage_id() -> String:
	return String(_data["campaign"]["selected_stage_id"])


func get_campaign_difficulty() -> String:
	return String(_data["campaign"]["difficulty"])


func get_cleared_stage_ids() -> Array:
	return (_data["campaign"]["cleared_stage_ids"] as Array).duplicate()


func is_stage_cleared(stage_id: String) -> bool:
	return stage_id != "" and _data["campaign"]["cleared_stage_ids"].has(stage_id)


func get_stage_stars(stage_id: String) -> int:
	var stars: Dictionary = _data["campaign"]["stage_stars"]
	return clampi(int(stars.get(stage_id, 0)), 0, 3)


## Whether the stage can be launched right now (unlocked + NORMAL difficulty).
func can_launch_stage(map: StageMapData, stage_id: String) -> bool:
	if map == null or stage_id == "":
		return false
	if get_campaign_difficulty() != DIFFICULTY_NORMAL:
		return false
	var stage := map.find_by_id(stage_id)
	if stage == null:
		return false
	return StageProgress.is_unlocked(map, stage, get_cleared_stage_ids())


# --- Writes -----------------------------------------------------------------

func grant_run_rewards(run_id: String, rewards: RunRewards, stats: RunStats) -> bool:
	if run_id == "" or rewards == null:
		return false
	if has_granted_run(run_id):
		return false

	_data["granted_run_ids"].append(run_id)
	_trim_granted_ids()

	_data["currencies"]["rift_energy"] = get_rift_energy() + maxi(0, rewards.rift_energy)
	_data["currencies"]["rift_core"] = get_rift_core() + maxi(0, rewards.rift_core)

	if stats != null:
		if stats.score > get_best_score():
			_data["progression"]["best_score"] = stats.score
		if stats.victory:
			_mark_sector_completed(stats.sector)
			if stats.stage_id != "":
				_record_stage_clear_from_stats(stats)

	save_game()
	currencies_changed.emit(get_rift_energy(), get_rift_core())
	campaign_changed.emit(get_selected_stage_id())
	return true


## Counts a finished run for interstitial pacing (every N runs).
func note_run_completed() -> int:
	var monetization := _monetization()
	var count := int(monetization.get("completed_run_count", 0)) + 1
	monetization["completed_run_count"] = count
	_data["monetization"] = monetization
	save_game()
	return count


func get_completed_run_count() -> int:
	return int(_monetization().get("completed_run_count", 0))


## True when this completed-run count should show an interstitial.
func should_show_interstitial_for_latest_run() -> bool:
	var count := get_completed_run_count()
	if count <= 0:
		return false
	return count % AdMobIds.INTERSTITIAL_EVERY_N_RUNS == 0


func has_doubled_run_rewards(run_id: String) -> bool:
	if run_id == "":
		return true
	return (_monetization().get("doubled_reward_run_ids", []) as Array).has(run_id)


## Grants a second copy of run rewards after a completed rewarded ad (once per run).
func grant_doubled_run_rewards(run_id: String, rewards: RunRewards) -> bool:
	if run_id == "" or rewards == null:
		return false
	if not has_granted_run(run_id):
		return false
	if has_doubled_run_rewards(run_id):
		return false
	var monetization := _monetization()
	var doubled: Array = monetization.get("doubled_reward_run_ids", []) as Array
	doubled.append(run_id)
	while doubled.size() > _MAX_DOUBLED_IDS:
		doubled.pop_front()
	monetization["doubled_reward_run_ids"] = doubled
	_data["monetization"] = monetization
	_data["currencies"]["rift_energy"] = get_rift_energy() + maxi(0, rewards.rift_energy)
	_data["currencies"]["rift_core"] = get_rift_core() + maxi(0, rewards.rift_core)
	save_game()
	currencies_changed.emit(get_rift_energy(), get_rift_core())
	return true


func _monetization() -> Dictionary:
	if typeof(_data.get("monetization")) != TYPE_DICTIONARY:
		_data["monetization"] = _default_data()["monetization"]
	return _data["monetization"] as Dictionary


func select_ship(ship_id: String) -> bool:
	if not is_ship_unlocked(ship_id):
		return false
	if get_selected_ship_id() == ship_id:
		return true
	_data["ships"]["selected_ship_id"] = ship_id
	_ensure_upgrade_entry(ship_id)
	save_game()
	hangar_changed.emit(ship_id)
	return true


func unlock_ship(ship_id: String) -> void:
	if ship_id == "" or is_ship_unlocked(ship_id):
		return
	_data["ships"]["unlocked_ship_ids"].append(ship_id)
	_ensure_upgrade_entry(ship_id)
	save_game()
	hangar_changed.emit(get_selected_ship_id())


func try_purchase_upgrade(ship_id: String, track: HangarUpgradeTrackData) -> bool:
	if ship_id == "" or track == null or track.id == "":
		return false
	if not is_ship_unlocked(ship_id):
		return false

	_ensure_upgrade_entry(ship_id)
	var levels: Dictionary = _data["ships"]["upgrade_levels"][ship_id]
	var current := int(levels.get(track.id, 0))
	var cost := track.cost_for_next_level(current)
	if cost < 0:
		return false
	if get_rift_energy() < cost:
		return false

	_data["currencies"]["rift_energy"] = get_rift_energy() - cost
	levels[track.id] = current + 1
	save_game()
	currencies_changed.emit(get_rift_energy(), get_rift_core())
	hangar_changed.emit(get_selected_ship_id())
	return true


## Selects a stage for the detail panel. Locked stages may be inspected but not launched.
func select_stage(stage_id: String) -> void:
	if stage_id == "" or get_selected_stage_id() == stage_id:
		return
	_data["campaign"]["selected_stage_id"] = stage_id
	save_game()
	campaign_changed.emit(stage_id)


## NORMAL is the only playable difficulty in this milestone. HARD is stored as
## preference for the UI lock state but launch always requires NORMAL.
func set_campaign_difficulty(difficulty: String) -> void:
	if difficulty != DIFFICULTY_NORMAL and difficulty != DIFFICULTY_HARD:
		return
	if get_campaign_difficulty() == difficulty:
		return
	_data["campaign"]["difficulty"] = difficulty
	save_game()
	campaign_changed.emit(get_selected_stage_id())


## Records a stage clear + star rating (keeps the best stars). Used by probes and
## by grant_run_rewards on victory.
func record_stage_clear(stage_id: String, stars: int) -> void:
	if stage_id == "":
		return
	var cleared: Array = _data["campaign"]["cleared_stage_ids"]
	if not cleared.has(stage_id):
		cleared.append(stage_id)
	var star_map: Dictionary = _data["campaign"]["stage_stars"]
	var best := maxi(get_stage_stars(stage_id), clampi(stars, 0, 3))
	star_map[stage_id] = best
	_data["campaign"]["selected_stage_id"] = stage_id
	save_game()
	campaign_changed.emit(stage_id)


func debug_add_currency(rift_energy: int = 0, rift_core: int = 0) -> void:
	_data["currencies"]["rift_energy"] = get_rift_energy() + maxi(0, rift_energy)
	_data["currencies"]["rift_core"] = get_rift_core() + maxi(0, rift_core)
	save_game()
	currencies_changed.emit(get_rift_energy(), get_rift_core())


func _record_stage_clear_from_stats(stats: RunStats) -> void:
	var map: StageMapData = load("res://resources/stages/nova_sector_map.tres")
	var stage: StageNodeData = null
	if map != null:
		stage = map.find_by_id(stats.stage_id)
	var stars := StageProgress.stars_for_run(stage, stats)
	record_stage_clear(stats.stage_id, stars)


func _ensure_upgrade_entry(ship_id: String) -> void:
	var all: Dictionary = _data["ships"]["upgrade_levels"]
	if not all.has(ship_id) or typeof(all[ship_id]) != TYPE_DICTIONARY:
		all[ship_id] = _zero_levels()
		return
	var levels: Dictionary = all[ship_id]
	for key in _TRACK_IDS:
		if not levels.has(key):
			levels[key] = 0


func _mark_sector_completed(sector: int) -> void:
	if not _data["completed_sectors"].has(sector):
		_data["completed_sectors"].append(sector)
	if sector > get_highest_sector_cleared():
		_data["progression"]["highest_sector_cleared"] = sector


func _trim_granted_ids() -> void:
	var ids: Array = _data["granted_run_ids"]
	if ids.size() > _MAX_GRANTED_IDS:
		_data["granted_run_ids"] = ids.slice(ids.size() - _MAX_GRANTED_IDS)


# --- Persistence ------------------------------------------------------------

func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var text := FileAccess.get_file_as_string(SAVE_PATH)
	if text.is_empty():
		return
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("SaveManager: save file unreadable; keeping defaults.")
		return
	_data = _migrate(_merge_defaults(parsed as Dictionary))


func save_game() -> void:
	var text := JSON.stringify(_data, "\t")
	var f := FileAccess.open(_TEMP_PATH, FileAccess.WRITE)
	if f == null:
		push_error("SaveManager: cannot open temp save for writing (%d)" % FileAccess.get_open_error())
		return
	f.store_string(text)
	f.close()

	var dir := DirAccess.open("user://")
	if dir == null:
		push_error("SaveManager: cannot open user:// to finalize save.")
		return
	var err := dir.rename(_TEMP_PATH, SAVE_PATH)
	if err != OK:
		push_error("SaveManager: atomic rename failed (%d)." % err)


func _merge_defaults(loaded: Dictionary) -> Dictionary:
	var base := _default_data()
	for key in loaded:
		base[key] = loaded[key]
	for sub in ["currencies", "progression"]:
		if typeof(loaded.get(sub)) == TYPE_DICTIONARY:
			var merged: Dictionary = base[sub]
			for k in (loaded[sub] as Dictionary):
				merged[k] = loaded[sub][k]
			base[sub] = merged
	if typeof(loaded.get("ships")) == TYPE_DICTIONARY:
		var ships_base: Dictionary = base["ships"]
		var ships_loaded: Dictionary = loaded["ships"]
		for k in ships_loaded:
			ships_base[k] = ships_loaded[k]
		base["ships"] = ships_base
	if typeof(loaded.get("campaign")) == TYPE_DICTIONARY:
		var camp_base: Dictionary = base["campaign"]
		var camp_loaded: Dictionary = loaded["campaign"]
		for k in camp_loaded:
			camp_base[k] = camp_loaded[k]
		base["campaign"] = camp_base
	if typeof(loaded.get("monetization")) == TYPE_DICTIONARY:
		var mon_base: Dictionary = base["monetization"]
		var mon_loaded: Dictionary = loaded["monetization"]
		for k in mon_loaded:
			mon_base[k] = mon_loaded[k]
		base["monetization"] = mon_base
	return base


func _migrate(data: Dictionary) -> Dictionary:
	var version := int(data.get("schema_version", 0))
	if version < 2:
		if typeof(data.get("ships")) != TYPE_DICTIONARY:
			data["ships"] = _default_data()["ships"]
		else:
			var ships: Dictionary = data["ships"]
			if not ships.has("selected_ship_id") or String(ships["selected_ship_id"]) == "":
				ships["selected_ship_id"] = _DEFAULT_SHIP_ID
			if typeof(ships.get("unlocked_ship_ids")) != TYPE_ARRAY:
				ships["unlocked_ship_ids"] = [_DEFAULT_SHIP_ID]
			elif not (ships["unlocked_ship_ids"] as Array).has(_DEFAULT_SHIP_ID):
				(ships["unlocked_ship_ids"] as Array).append(_DEFAULT_SHIP_ID)
			if typeof(ships.get("upgrade_levels")) != TYPE_DICTIONARY:
				ships["upgrade_levels"] = {_DEFAULT_SHIP_ID: _zero_levels()}
			data["ships"] = ships
		data["schema_version"] = 2
		version = 2
	if version < 3:
		if typeof(data.get("campaign")) != TYPE_DICTIONARY:
			data["campaign"] = _default_data()["campaign"]
		else:
			var camp: Dictionary = data["campaign"]
			if not camp.has("selected_stage_id") or String(camp["selected_stage_id"]) == "":
				camp["selected_stage_id"] = _DEFAULT_STAGE_ID
			if not camp.has("difficulty"):
				camp["difficulty"] = DIFFICULTY_NORMAL
			if typeof(camp.get("cleared_stage_ids")) != TYPE_ARRAY:
				camp["cleared_stage_ids"] = []
			if typeof(camp.get("stage_stars")) != TYPE_DICTIONARY:
				camp["stage_stars"] = {}
			data["campaign"] = camp
		data["schema_version"] = 3
		version = 3
	if version < 4:
		if typeof(data.get("monetization")) != TYPE_DICTIONARY:
			data["monetization"] = _default_data()["monetization"]
		else:
			var mon: Dictionary = data["monetization"]
			if not mon.has("completed_run_count"):
				mon["completed_run_count"] = 0
			if typeof(mon.get("doubled_reward_run_ids")) != TYPE_ARRAY:
				mon["doubled_reward_run_ids"] = []
			data["monetization"] = mon
		data["schema_version"] = 4
		version = 4
	if version < SCHEMA_VERSION:
		data["schema_version"] = SCHEMA_VERSION
	_ensure_upgrade_entry(String(data["ships"]["selected_ship_id"]))
	return data


func reset() -> void:
	_data = _default_data()
	save_game()
	currencies_changed.emit(get_rift_energy(), get_rift_core())
	hangar_changed.emit(get_selected_ship_id())
	campaign_changed.emit(get_selected_stage_id())
