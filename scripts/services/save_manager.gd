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

const SCHEMA_VERSION := 6
const SAVE_PATH := "user://riftwing_save.json"
const _TEMP_PATH := "user://riftwing_save.json.tmp"
const _BACKUP_PATH := "user://riftwing_save.json.bak"
const _MAX_GRANTED_IDS := 256
const _DEFAULT_SHIP_ID := "vanguard_mk2"
const _DEFAULT_STAGE_ID := "1-1"
const _TRACK_IDS := ["weapons", "shield", "engine", "drones", "ultimate"]
const DIFFICULTY_NORMAL := "normal"
const DIFFICULTY_HARD := "hard"
const _EVENT_PATH := "res://resources/events/void_invasion.tres"

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
			"stage_best_scores": {},
		},
		"monetization": {
			# Legacy AdMob fields kept for save migration; unused at runtime.
			"completed_run_count": 0,
			"doubled_reward_run_ids": [],
		},
		"daily": {
			# Local-date key ("YYYY-MM-DD") of the last claimed Daily Challenge.
			"last_completed_date": "",
		},
		"events": {
			# Progress counters + one-time claim flags keyed by event id.
			"progress": {},
			"claimed_event_ids": [],
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


## Composite save key so HARD progress (stars / best / clears) is tracked apart
## from NORMAL. NORMAL keeps the bare stage id (no migration needed).
func _stage_key(stage_id: String, difficulty: String) -> String:
	if difficulty == DIFFICULTY_HARD:
		return "%s#%s" % [stage_id, DIFFICULTY_HARD]
	return stage_id


func is_stage_cleared(stage_id: String, difficulty: String = DIFFICULTY_NORMAL) -> bool:
	return stage_id != "" and _data["campaign"]["cleared_stage_ids"].has(_stage_key(stage_id, difficulty))


func get_stage_stars(stage_id: String, difficulty: String = DIFFICULTY_NORMAL) -> int:
	var stars: Dictionary = _data["campaign"]["stage_stars"]
	return clampi(int(stars.get(_stage_key(stage_id, difficulty), 0)), 0, 3)


func get_stage_best_score(stage_id: String, difficulty: String = DIFFICULTY_NORMAL) -> int:
	if stage_id == "":
		return 0
	var scores: Dictionary = _data["campaign"].get("stage_best_scores", {})
	return maxi(0, int(scores.get(_stage_key(stage_id, difficulty), 0)))


## Whether the stage can be launched right now. NORMAL needs the unlock chain;
## HARD additionally requires the stage to have been cleared on NORMAL first.
## --- Daily Challenge -------------------------------------------------------

func get_daily_last_completed() -> String:
	var daily: Dictionary = _data.get("daily", {})
	return String(daily.get("last_completed_date", ""))


func is_daily_completed(date_key: String) -> bool:
	return date_key != "" and get_daily_last_completed() == date_key


func _mark_daily_completed(date_key: String) -> void:
	if typeof(_data.get("daily")) != TYPE_DICTIONARY:
		_data["daily"] = _default_data()["daily"]
	_data["daily"]["last_completed_date"] = date_key


## --- Timed Events ----------------------------------------------------------

func get_event_progress(event_id: String) -> int:
	if event_id == "":
		return 0
	var events: Dictionary = _data.get("events", {})
	var progress: Dictionary = events.get("progress", {})
	return maxi(0, int(progress.get(event_id, 0)))


func is_event_claimed(event_id: String) -> bool:
	if event_id == "":
		return false
	var events: Dictionary = _data.get("events", {})
	return (events.get("claimed_event_ids", []) as Array).has(event_id)


## Adds progress toward an event goal (clamped at the goal) and persists. Returns
## the new progress value.
func add_event_progress(event_id: String, amount: int, goal: int) -> int:
	if event_id == "" or amount <= 0:
		return get_event_progress(event_id)
	if typeof(_data.get("events")) != TYPE_DICTIONARY:
		_data["events"] = _default_data()["events"]
	var progress: Dictionary = _data["events"]["progress"]
	var next := mini(maxi(0, goal), get_event_progress(event_id) + amount)
	progress[event_id] = next
	save_game()
	return next


## Grants an event's reward exactly once, when its goal has been reached. Returns
## true if the reward was banked by this call.
func claim_event_reward(event_id: String, goal: int, reward_energy: int, reward_core: int) -> bool:
	if event_id == "" or is_event_claimed(event_id):
		return false
	if get_event_progress(event_id) < maxi(1, goal):
		return false
	if typeof(_data.get("events")) != TYPE_DICTIONARY:
		_data["events"] = _default_data()["events"]
	(_data["events"]["claimed_event_ids"] as Array).append(event_id)
	_data["currencies"]["rift_energy"] = get_rift_energy() + maxi(0, reward_energy)
	_data["currencies"]["rift_core"] = get_rift_core() + maxi(0, reward_core)
	save_game()
	currencies_changed.emit(get_rift_energy(), get_rift_core())
	return true


func can_launch_stage(map: StageMapData, stage_id: String) -> bool:
	if map == null or stage_id == "":
		return false
	var stage := map.find_by_id(stage_id)
	if stage == null:
		return false
	if not StageProgress.is_unlocked(map, stage, get_cleared_stage_ids()):
		return false
	if get_campaign_difficulty() == DIFFICULTY_HARD:
		return is_stage_cleared(stage_id, DIFFICULTY_NORMAL)
	return true


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
		if stats.stage_id != "":
			_update_stage_best_score(stats.stage_id, stats.score, stats.difficulty)
		if stats.victory:
			_mark_sector_completed(stats.sector)
			if stats.stage_id != "":
				_record_stage_clear_from_stats(stats)
			# One-time Daily Challenge Rift Core bonus (per local date).
			if stats.is_daily and stats.daily_date != "" and not is_daily_completed(stats.daily_date):
				_data["currencies"]["rift_core"] = get_rift_core() + maxi(0, stats.daily_reward_core)
				_mark_daily_completed(stats.daily_date)
		# Timed event participation: enemies destroyed count toward the active window.
		_accrue_event_progress(stats)

	save_game()
	currencies_changed.emit(get_rift_energy(), get_rift_core())
	campaign_changed.emit(get_selected_stage_id())
	return true


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


## True when the ship's non-currency prerequisite is satisfied (its gate stage has
## been cleared on either difficulty). Ships with no stage gate are always eligible.
func ship_requirement_met(ship: ShipData) -> bool:
	if ship == null:
		return false
	if ship.unlock_stage_id == "":
		return true
	return is_stage_cleared(ship.unlock_stage_id, DIFFICULTY_NORMAL) \
		or is_stage_cleared(ship.unlock_stage_id, DIFFICULTY_HARD)


## True when the ship can be unlocked right now: locked, gate cleared, and enough
## Rift Cores banked to pay its unlock cost.
func can_unlock_ship(ship: ShipData) -> bool:
	if ship == null or is_ship_unlocked(ship.id):
		return false
	if not ship_requirement_met(ship):
		return false
	return get_rift_core() >= ship.unlock_core_cost


## Atomically unlocks a ship: re-validates the gate + cost, spends the Rift Cores,
## records the unlock, and saves once. Returns false (no charge) if not eligible.
func try_unlock_ship(ship: ShipData) -> bool:
	if not can_unlock_ship(ship):
		return false
	if ship.unlock_core_cost > 0:
		_data["currencies"]["rift_core"] = get_rift_core() - ship.unlock_core_cost
	_data["ships"]["unlocked_ship_ids"].append(ship.id)
	_ensure_upgrade_entry(ship.id)
	save_game()
	currencies_changed.emit(get_rift_energy(), get_rift_core())
	hangar_changed.emit(get_selected_ship_id())
	return true


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


## Plans an "Upgrade All" purchase: one level in each non-maxed track that fits the
## current Rift Energy budget (walked in track order, skipping any single level the
## budget can't cover). Returns the exact set of track ids and their combined cost so
## the hangar previews precisely what will happen — never a surprise partial buy.
func plan_upgrade_all(ship: ShipData) -> Dictionary:
	var result := {"track_ids": PackedStringArray(), "total_cost": 0}
	if ship == null or not is_ship_unlocked(ship.id):
		return result
	var levels := get_upgrade_levels(ship.id)
	var budget := get_rift_energy()
	var spent := 0
	var ids := PackedStringArray()
	for track in ship.tracks():
		if track == null or track.id == "":
			continue
		var current := int(levels.get(track.id, 0))
		var cost := track.cost_for_next_level(current)
		if cost < 0:
			continue
		if spent + cost > budget:
			continue
		spent += cost
		ids.append(track.id)
	result["track_ids"] = ids
	result["total_cost"] = spent
	return result


## Atomically buys one level in each listed track. Recomputes the cost from live
## state so a stale plan can never overspend: if the combined cost no longer fits the
## budget it commits nothing (returns 0). Otherwise it deducts once, bumps each track,
## and saves once. Returns the number of levels purchased.
func purchase_upgrade_all(ship: ShipData, track_ids: PackedStringArray) -> int:
	if ship == null or not is_ship_unlocked(ship.id) or track_ids.is_empty():
		return 0
	_ensure_upgrade_entry(ship.id)
	var levels: Dictionary = _data["ships"]["upgrade_levels"][ship.id]
	var total := 0
	var plan: Array = []
	for tid in track_ids:
		var track := ship.track_by_id(tid)
		if track == null:
			continue
		var current := int(levels.get(tid, 0))
		var cost := track.cost_for_next_level(current)
		if cost < 0:
			continue
		total += cost
		plan.append(tid)
	if plan.is_empty() or total > get_rift_energy():
		return 0
	_data["currencies"]["rift_energy"] = get_rift_energy() - total
	for tid in plan:
		levels[tid] = int(levels.get(tid, 0)) + 1
	save_game()
	currencies_changed.emit(get_rift_energy(), get_rift_core())
	hangar_changed.emit(get_selected_ship_id())
	return plan.size()


## Selects a stage for the detail panel. Locked stages may be inspected but not launched.
func select_stage(stage_id: String) -> void:
	if stage_id == "" or get_selected_stage_id() == stage_id:
		return
	_data["campaign"]["selected_stage_id"] = stage_id
	save_game()
	campaign_changed.emit(stage_id)


## Sets the campaign difficulty preference. Both NORMAL and HARD are playable;
## the per-stage launch gate (can_launch_stage) decides eligibility.
func set_campaign_difficulty(difficulty: String) -> void:
	if difficulty != DIFFICULTY_NORMAL and difficulty != DIFFICULTY_HARD:
		return
	if get_campaign_difficulty() == difficulty:
		return
	_data["campaign"]["difficulty"] = difficulty
	save_game()
	campaign_changed.emit(get_selected_stage_id())


## Records a stage clear + star rating (keeps the best stars) for a difficulty.
## Used by probes and by grant_run_rewards on victory.
func record_stage_clear(stage_id: String, stars: int, difficulty: String = DIFFICULTY_NORMAL) -> void:
	if stage_id == "":
		return
	var key := _stage_key(stage_id, difficulty)
	var cleared: Array = _data["campaign"]["cleared_stage_ids"]
	if not cleared.has(key):
		cleared.append(key)
	var star_map: Dictionary = _data["campaign"]["stage_stars"]
	var best := maxi(get_stage_stars(stage_id, difficulty), clampi(stars, 0, 3))
	star_map[key] = best
	_data["campaign"]["selected_stage_id"] = stage_id
	save_game()
	campaign_changed.emit(stage_id)


func debug_add_currency(rift_energy: int = 0, rift_core: int = 0) -> void:
	_data["currencies"]["rift_energy"] = get_rift_energy() + maxi(0, rift_energy)
	_data["currencies"]["rift_core"] = get_rift_core() + maxi(0, rift_core)
	save_game()
	currencies_changed.emit(get_rift_energy(), get_rift_core())


## Adds this run's enemy kills toward the active timed event's current window.
## Mutates _data only; grant_run_rewards persists once at the end of its call.
func _accrue_event_progress(stats: RunStats) -> void:
	if stats == null:
		return
	var kills := maxi(0, stats.enemies_destroyed)
	if kills <= 0:
		return
	var event := load(_EVENT_PATH) as EventData
	if event == null:
		return
	var now := int(Time.get_unix_time_from_system())
	if not event.is_active(now):
		return
	if typeof(_data.get("events")) != TYPE_DICTIONARY:
		_data["events"] = _default_data()["events"]
	var occ := event.occurrence_id(now)
	var progress: Dictionary = _data["events"]["progress"]
	progress[occ] = mini(maxi(1, event.goal), int(progress.get(occ, 0)) + kills)


func _record_stage_clear_from_stats(stats: RunStats) -> void:
	var map: StageMapData = load("res://resources/stages/nova_sector_map.tres")
	var stage: StageNodeData = null
	if map != null:
		stage = map.find_by_id(stats.stage_id)
	var stars := StageProgress.stars_for_run(stage, stats)
	record_stage_clear(stats.stage_id, stars, stats.difficulty)


func _ensure_upgrade_entry(ship_id: String) -> void:
	var all: Dictionary = _data["ships"]["upgrade_levels"]
	if not all.has(ship_id) or typeof(all[ship_id]) != TYPE_DICTIONARY:
		all[ship_id] = _zero_levels()
		return
	var levels: Dictionary = all[ship_id]
	for key in _TRACK_IDS:
		if not levels.has(key):
			levels[key] = 0


func _update_stage_best_score(stage_id: String, score: int, difficulty: String = DIFFICULTY_NORMAL) -> void:
	if stage_id == "":
		return
	var key := _stage_key(stage_id, difficulty)
	var scores: Dictionary = _data["campaign"]["stage_best_scores"]
	if score > int(scores.get(key, 0)):
		scores[key] = maxi(0, score)


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
	var loaded := _read_save_dict(SAVE_PATH)
	if loaded.is_empty():
		# Primary save missing/corrupt: fall back to the last known-good backup.
		loaded = _read_save_dict(_BACKUP_PATH)
		if not loaded.is_empty():
			push_warning("SaveManager: primary save unreadable; recovered from backup.")
	if loaded.is_empty():
		return
	_data = _migrate(_merge_defaults(loaded))


## Reads a save file into a Dictionary, or {} when missing / empty / not JSON.
func _read_save_dict(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("SaveManager: %s unreadable (invalid JSON)." % path)
		return {}
	return parsed as Dictionary


func save_game() -> void:
	var text := JSON.stringify(_data, "\t")
	var f := FileAccess.open(_TEMP_PATH, FileAccess.WRITE)
	if f == null:
		push_error("SaveManager: cannot open temp save for writing (%d)" % FileAccess.get_open_error())
		return
	f.store_string(text)
	f.close()

	# Validate the temp file before it is allowed to replace the live save.
	if _read_save_dict(_TEMP_PATH).is_empty():
		push_error("SaveManager: temp save failed validation; keeping previous save.")
		return

	var dir := DirAccess.open("user://")
	if dir == null:
		push_error("SaveManager: cannot open user:// to finalize save.")
		return

	# Roll the current good save into a backup first so a failed replace (e.g. a
	# Windows rename that refuses an existing destination) can be rolled back.
	if dir.file_exists(SAVE_PATH):
		if dir.file_exists(_BACKUP_PATH):
			dir.remove(_BACKUP_PATH)
		var back_err := dir.rename(SAVE_PATH, _BACKUP_PATH)
		if back_err != OK:
			push_warning("SaveManager: could not create backup (%d)." % back_err)

	var err := dir.rename(_TEMP_PATH, SAVE_PATH)
	if err != OK:
		push_error("SaveManager: atomic rename failed (%d); rolling back." % err)
		if dir.file_exists(_BACKUP_PATH) and not dir.file_exists(SAVE_PATH):
			dir.rename(_BACKUP_PATH, SAVE_PATH)


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
	if version < 5:
		if typeof(data.get("campaign")) != TYPE_DICTIONARY:
			data["campaign"] = _default_data()["campaign"]
		else:
			var camp5: Dictionary = data["campaign"]
			if typeof(camp5.get("stage_best_scores")) != TYPE_DICTIONARY:
				camp5["stage_best_scores"] = {}
			data["campaign"] = camp5
		data["schema_version"] = 5
		version = 5
	if version < 6:
		if typeof(data.get("daily")) != TYPE_DICTIONARY:
			data["daily"] = _default_data()["daily"]
		elif not (data["daily"] as Dictionary).has("last_completed_date"):
			(data["daily"] as Dictionary)["last_completed_date"] = ""
		if typeof(data.get("events")) != TYPE_DICTIONARY:
			data["events"] = _default_data()["events"]
		else:
			var ev: Dictionary = data["events"]
			if typeof(ev.get("progress")) != TYPE_DICTIONARY:
				ev["progress"] = {}
			if typeof(ev.get("claimed_event_ids")) != TYPE_ARRAY:
				ev["claimed_event_ids"] = []
			data["events"] = ev
		data["schema_version"] = 6
		version = 6
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
