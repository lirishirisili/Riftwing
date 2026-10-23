class_name MetaProgress
extends RefCounted
## Static meta-progression systems over SaveManager sections (save v7):
## daily / weekly missions + activity milestones, lifetime stats, pilot level,
## 7-day login streak, offline patrol income, achievements, and modules.
##
## All numbers come from MetaCatalogData (resources/meta/meta_catalog.tres).
## Time-gated rewards respect SaveManager.is_clock_trusted(). Every mutation is
## persisted through SaveManager.save_game().

const CATALOG_PATH := "res://resources/meta/meta_catalog.tres"
const SLOT_COUNT := 3

static var _catalog: MetaCatalogData = null


static func catalog() -> MetaCatalogData:
	if _catalog == null:
		_catalog = load(CATALOG_PATH) as MetaCatalogData
		if _catalog == null:
			_catalog = MetaCatalogData.new()
	return _catalog


# --- Time keys ------------------------------------------------------------------------

static func _local_unix(offset_seconds: int = 0) -> int:
	var bias := int(Time.get_time_zone_from_system().get("bias", 0))
	return int(Time.get_unix_time_from_system()) + bias * 60 + offset_seconds


static func day_key(offset_days: int = 0) -> String:
	var d := Time.get_date_dict_from_unix_time(_local_unix(offset_days * 86400))
	return "%04d-%02d-%02d" % [int(d["year"]), int(d["month"]), int(d["day"])]


## Monday-based week index since the epoch (1970-01-01 was a Thursday).
static func week_key() -> String:
	var days := int(floor(float(_local_unix()) / 86400.0))
	return "W%d" % int(floor(float(days + 3) / 7.0))


## Seconds until the next local midnight / Monday (for countdown labels).
static func seconds_to_next_day() -> int:
	var local := _local_unix()
	return 86400 - (local % 86400)


static func seconds_to_next_week() -> int:
	var days := int(floor(float(_local_unix()) / 86400.0))
	var into_week := (days + 3) % 7
	return (6 - into_week) * 86400 + seconds_to_next_day()


# --- Missions ---------------------------------------------------------------------------

## Rolls new daily / weekly missions when the period changed. Safe to call often.
static func refresh_missions() -> void:
	if not SaveManager.is_clock_trusted():
		return
	var m := SaveManager.section("missions")
	var changed := false
	var today := day_key()
	if String(m.get("day_key", "")) != today:
		m["day_key"] = today
		m["daily"] = _roll("daily", catalog().daily_count, today)
		m["activity"] = 0
		m["activity_claimed"] = []
		changed = true
	var week := week_key()
	if String(m.get("week_key", "")) != week:
		m["week_key"] = week
		m["weekly"] = _roll("weekly", catalog().weekly_count, week)
		changed = true
	if changed:
		SaveManager.save_game()


static func _roll(scope: String, count: int, seed_key: String) -> Array:
	var pool: Array[MissionData] = []
	for mission in catalog().missions:
		if mission != null and mission.scope == scope:
			pool.append(mission)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(hash(seed_key + scope)) & 0x7fffffff
	var out: Array = []
	var used_metrics := {}
	while out.size() < count and not pool.is_empty():
		var pick: MissionData = pool[rng.randi_range(0, pool.size() - 1)]
		pool.erase(pick)
		# Prefer variety: one mission per metric per period when possible.
		if used_metrics.has(pick.metric) and pool.size() >= count - out.size():
			continue
		used_metrics[pick.metric] = true
		out.append({"id": pick.id, "progress": 0, "claimed": false})
	return out


static func missions(scope: String) -> Array:
	refresh_missions()
	var m := SaveManager.section("missions")
	return m.get("daily" if scope == "daily" else "weekly", [])


static func mission_def(entry: Dictionary) -> MissionData:
	return catalog().find_mission(String(entry.get("id", "")))


static func is_mission_done(entry: Dictionary) -> bool:
	var def := mission_def(entry)
	return def != null and int(entry.get("progress", 0)) >= def.goal


static func claim_mission(scope: String, id: String) -> bool:
	for entry in missions(scope):
		if String(entry.get("id", "")) != id or bool(entry.get("claimed", false)) or not is_mission_done(entry):
			continue
		var def := mission_def(entry)
		entry["claimed"] = true
		var m := SaveManager.section("missions")
		m["activity"] = int(m.get("activity", 0)) + def.activity
		SaveManager.grant_currency(def.reward_energy, def.reward_core)
		return true
	return false


static func activity() -> int:
	refresh_missions()
	return int(SaveManager.section("missions").get("activity", 0))


static func is_activity_claimed(index: int) -> bool:
	return (SaveManager.section("missions").get("activity_claimed", []) as Array).has(index)


## Claims an activity milestone chest. Returns a reward summary ({} if not claimable).
static func claim_activity(index: int) -> Dictionary:
	var cat := catalog()
	if index < 0 or index >= cat.activity_milestones.size() or is_activity_claimed(index):
		return {}
	if activity() < cat.activity_milestones[index]:
		return {}
	(SaveManager.section("missions")["activity_claimed"] as Array).append(index)
	var energy := cat.activity_reward_energy[index] if index < cat.activity_reward_energy.size() else 0
	var core := cat.activity_reward_core[index] if index < cat.activity_reward_core.size() else 0
	SaveManager.grant_currency(energy, core)
	var summary := {"energy": energy, "core": core}
	if cat.activity_final_module and index == cat.activity_milestones.size() - 1:
		summary["module"] = add_module(_random_module_id(), _roll_rarity(1))
	return summary


# --- Runs ---------------------------------------------------------------------------------

## Applies a finished run to lifetime stats, missions, pilot XP, and module
## drops. Returns a summary for the Results screen. Called once per run
## (RunSettlement, after rewards are granted).
static func record_run(stats: RunStats) -> Dictionary:
	if stats == null:
		return {}
	refresh_missions()
	var values := _run_metrics(stats)
	# Lifetime.
	var life := SaveManager.section("lifetime")
	for key in ["kills", "elites", "bosses", "runs", "victories", "chests", "novas", "evolutions", "energy"]:
		life[key] = int(life.get(key, 0)) + int(values.get(key, 0))
	life["seconds"] = float(life.get("seconds", 0.0)) + stats.survival_seconds
	life["best_combo"] = maxi(int(life.get("best_combo", 0)), stats.best_combo)
	# Missions.
	var completed := 0
	for scope in ["daily", "weekly"]:
		for entry in missions(scope):
			var def := mission_def(entry)
			if def == null or bool(entry.get("claimed", false)):
				continue
			var was_done := is_mission_done(entry)
			var v := int(values.get(def.metric, 0))
			if def.is_max_metric():
				entry["progress"] = maxi(int(entry.get("progress", 0)), v)
			else:
				entry["progress"] = mini(def.goal, int(entry.get("progress", 0)) + v)
			if not was_done and is_mission_done(entry):
				completed += 1
	# Pilot XP.
	var cat := catalog()
	var xp := stats.score / maxi(1, cat.xp_score_divisor) + stats.bosses_defeated * cat.xp_per_boss
	if stats.victory:
		xp += cat.xp_per_victory
	var levels := add_pilot_xp(xp)
	# Module drop on a campaign victory.
	var module := {}
	if stats.victory and stats.mode == "campaign" and stats.stage_id != "":
		var rng := RandomNumberGenerator.new()
		rng.seed = int(hash(stats.run_id)) & 0x7fffffff
		if rng.randf() < cat.module_drop_chance:
			module = add_module(_random_module_id(rng), _roll_rarity(Campaign.sector_index_of(stats.stage_id) - 1, rng))
	SaveManager.save_game()
	return {"xp": xp, "levels": levels, "module": module, "missions_completed": completed}


static func _run_metrics(stats: RunStats) -> Dictionary:
	var stage_clear := 1 if stats.victory and stats.stage_id != "" and not stats.is_daily else 0
	return {
		"kills": stats.enemies_destroyed,
		"elites": stats.elites_killed,
		"bosses": stats.bosses_defeated,
		"runs": 1,
		"victories": 1 if stats.victory else 0,
		"chests": stats.chests_opened,
		"novas": stats.novas_used,
		"evolutions": stats.evolutions,
		"seconds": int(stats.survival_seconds),
		"energy": stats.rift_energy_collected,
		"stage_clears": stage_clear,
		"hard_clears": stage_clear if stats.difficulty == SaveManager.DIFFICULTY_HARD else 0,
		"combo": stats.best_combo,
		"endless_seconds": int(stats.survival_seconds) if stats.mode == "endless" else 0,
	}


# --- Pilot ----------------------------------------------------------------------------------

static func pilot_level() -> int:
	return maxi(1, int(SaveManager.section("pilot").get("level", 1)))


static func pilot_xp() -> int:
	return maxi(0, int(SaveManager.section("pilot").get("xp", 0)))


static func xp_for_next(level: int = -1) -> int:
	var lvl := pilot_level() if level < 1 else level
	return catalog().xp_base + catalog().xp_step * (lvl - 1)


## Adds pilot XP, levelling up (with Rift Core rewards) as needed. Returns the
## number of levels gained.
static func add_pilot_xp(amount: int) -> int:
	if amount <= 0:
		return 0
	var p := SaveManager.section("pilot")
	var xp := pilot_xp() + amount
	var level := pilot_level()
	var gained := 0
	var core := 0
	while xp >= xp_for_next(level):
		xp -= xp_for_next(level)
		level += 1
		gained += 1
		core += catalog().level_core + (catalog().level_core_every_5 if level % 5 == 0 else 0)
	p["xp"] = xp
	p["level"] = level
	if core > 0:
		SaveManager.grant_currency(0, core)
	return gained


# --- Login streak ------------------------------------------------------------------------------

## {day: 1..7 (the day claimable today or next), can_claim: bool}
static func login_status() -> Dictionary:
	var l := SaveManager.section("login")
	var today := day_key()
	var claimed_today := String(l.get("claimed_day", "")) == today
	var streak := int(l.get("streak", 0))
	var continues := String(l.get("claimed_day", "")) == day_key(-1)
	var next_day := 1
	if claimed_today:
		next_day = (streak - 1) % 7 + 1
	elif continues:
		next_day = streak % 7 + 1
	return {"day": next_day, "can_claim": not claimed_today and SaveManager.is_clock_trusted()}


static func login_reward(day: int) -> Dictionary:
	var i := clampi(day - 1, 0, 6)
	var cat := catalog()
	return {
		"energy": cat.login_energy[i] if i < cat.login_energy.size() else 0,
		"core": cat.login_core[i] if i < cat.login_core.size() else 0,
	}


static func claim_login() -> Dictionary:
	var status := login_status()
	if not bool(status["can_claim"]):
		return {}
	var day := int(status["day"])
	var l := SaveManager.section("login")
	l["streak"] = int(l.get("streak", 0)) + 1 if day > 1 else 1
	l["claimed_day"] = day_key()
	l["last_day"] = day_key()
	var reward := login_reward(day)
	SaveManager.grant_currency(int(reward["energy"]), int(reward["core"]))
	reward["day"] = day
	return reward


# --- Patrol (offline income) ---------------------------------------------------------------------

static func patrol_rate_per_minute() -> float:
	var cat := catalog()
	return cat.patrol_base_per_minute + cat.patrol_per_stage_per_minute * float(SaveManager.get_cleared_stage_ids().size())


static func patrol_minutes() -> float:
	var p := SaveManager.section("patrol")
	var last := int(p.get("last_collect_unix", 0))
	if last <= 0:
		# First launch starts the clock instead of paying out a lifetime.
		p["last_collect_unix"] = int(Time.get_unix_time_from_system())
		SaveManager.save_game()
		return 0.0
	var minutes := float(int(Time.get_unix_time_from_system()) - last) / 60.0
	return clampf(minutes, 0.0, catalog().patrol_cap_hours * 60.0)


static func patrol_pending() -> int:
	if not SaveManager.is_clock_trusted():
		return 0
	var minutes := patrol_minutes()
	if minutes < catalog().patrol_min_minutes:
		return 0
	return int(floor(minutes * patrol_rate_per_minute()))


## Collects the patrol income (x `mult`, e.g. 2 after a rewarded ad).
static func claim_patrol(mult: int = 1) -> int:
	var amount := patrol_pending() * maxi(1, mult)
	if amount <= 0:
		return 0
	SaveManager.section("patrol")["last_collect_unix"] = int(Time.get_unix_time_from_system())
	SaveManager.grant_currency(amount, 0)
	return amount


# --- Achievements -----------------------------------------------------------------------------------

static func achievement_progress(a: AchievementData) -> int:
	var life := SaveManager.section("lifetime")
	match a.metric:
		"stages_cleared":
			var n := 0
			for id in SaveManager.get_cleared_stage_ids():
				if not String(id).contains("@"):
					n += 1
			return n
		"stars":
			return SaveManager.get_total_stars()
		"sectors":
			var done := 0
			for map in Campaign.sectors():
				if map != null and map.last_stage() != null and SaveManager.is_stage_cleared(map.last_stage().id):
					done += 1
			return done
		"pilot_level":
			return pilot_level()
		"endless_seconds":
			return int(SaveManager.get_mode_best("endless").get("best_seconds", 0.0))
		"boss_rush_bosses":
			return int(SaveManager.get_mode_best("boss_rush").get("best_bosses", 0))
		_:
			return int(life.get(a.metric, 0))


static func is_achievement_claimed(id: String) -> bool:
	return (SaveManager.section("achievements").get("claimed", []) as Array).has(id)


static func claim_achievement(id: String) -> bool:
	for a in catalog().achievements:
		if a == null or a.id != id or is_achievement_claimed(id) or achievement_progress(a) < a.goal:
			continue
		(SaveManager.section("achievements")["claimed"] as Array).append(id)
		SaveManager.grant_currency(a.reward_energy, a.reward_core)
		var svc: AchievementService = PlatformServices.achievements
		if svc != null:
			svc.unlock(id)
		return true
	return false


# --- Claimables (badges) ---------------------------------------------------------------------------

static func claimable_count() -> int:
	var n := 0
	for scope in ["daily", "weekly"]:
		for entry in missions(scope):
			if is_mission_done(entry) and not bool(entry.get("claimed", false)):
				n += 1
	var cat := catalog()
	for i in cat.activity_milestones.size():
		if not is_activity_claimed(i) and activity() >= cat.activity_milestones[i]:
			n += 1
	for a in cat.achievements:
		if a != null and not is_achievement_claimed(a.id) and achievement_progress(a) >= a.goal:
			n += 1
	return n


# --- Modules -----------------------------------------------------------------------------------------

static func owned_modules() -> Array:
	return SaveManager.section("modules").get("owned", [])


static func equipped_uids() -> Array:
	var m := SaveManager.section("modules")
	var eq: Array = m.get("equipped", [])
	while eq.size() < SLOT_COUNT:
		eq.append("")
	m["equipped"] = eq
	return eq


static func find_owned(uid: String) -> Dictionary:
	for entry in owned_modules():
		if String(entry.get("uid", "")) == uid:
			return entry
	return {}


static func add_module(id: String, rarity: int) -> Dictionary:
	if catalog().find_module(id) == null:
		return {}
	var m := SaveManager.section("modules")
	var uid := "m%d" % int(m.get("next_uid", 1))
	m["next_uid"] = int(m.get("next_uid", 1)) + 1
	var entry := {"uid": uid, "id": id, "rarity": clampi(rarity, 0, 3)}
	(m["owned"] as Array).append(entry)
	SaveManager.save_game()
	return entry


static func equip(uid: String, slot: int) -> void:
	if slot < 0 or slot >= SLOT_COUNT or find_owned(uid).is_empty():
		return
	var eq := equipped_uids()
	for i in eq.size():
		if String(eq[i]) == uid:
			eq[i] = ""
	eq[slot] = uid
	SaveManager.save_game()


static func unequip(slot: int) -> void:
	var eq := equipped_uids()
	if slot >= 0 and slot < eq.size():
		eq[slot] = ""
		SaveManager.save_game()


static func is_equipped(uid: String) -> bool:
	return equipped_uids().has(uid)


## Three unequipped copies (same id + rarity, below LEGENDARY) can merge.
static func merge_candidates(uid: String) -> Array:
	var base := find_owned(uid)
	if base.is_empty() or int(base["rarity"]) >= ModuleData.Rarity.LEGENDARY:
		return []
	var out: Array = []
	for entry in owned_modules():
		if String(entry["id"]) == String(base["id"]) and int(entry["rarity"]) == int(base["rarity"]) \
				and not is_equipped(String(entry["uid"])):
			out.append(entry)
	return out


static func can_merge(uid: String) -> bool:
	return merge_candidates(uid).size() >= 3


## Consumes three copies and returns the new higher-rarity module.
static func merge(uid: String) -> Dictionary:
	var parts := merge_candidates(uid)
	if parts.size() < 3:
		return {}
	var owned := owned_modules()
	for i in 3:
		owned.erase(parts[i])
	return add_module(String(parts[0]["id"]), int(parts[0]["rarity"]) + 1)


## Summed bonuses of equipped modules: {stat: value}.
static func equipped_bonuses() -> Dictionary:
	var out := {}
	for uid in equipped_uids():
		var entry := find_owned(String(uid))
		if entry.is_empty():
			continue
		var def := catalog().find_module(String(entry["id"]))
		if def == null:
			continue
		out[def.stat] = float(out.get(def.stat, 0.0)) + def.value_at(int(entry["rarity"]))
	return out


static func _random_module_id(rng: RandomNumberGenerator = null) -> String:
	var mods := catalog().modules
	if mods.is_empty():
		return ""
	var i := rng.randi_range(0, mods.size() - 1) if rng != null else randi_range(0, mods.size() - 1)
	return mods[i].id


## Rarity roll; `bonus` shifts weight toward rarer tiers (later sectors / milestones).
static func _roll_rarity(bonus: int = 0, rng: RandomNumberGenerator = null) -> int:
	var w := catalog().module_rarity_weights
	var weights: Array[float] = []
	var total := 0.0
	for i in w.size():
		var v := w[i] * (1.0 + 0.8 * float(maxi(0, bonus)) * float(i))
		weights.append(v)
		total += v
	var roll := (rng.randf() if rng != null else randf()) * total
	for i in weights.size():
		roll -= weights[i]
		if roll <= 0.0:
			return i
	return 0


# --- Daily rewarded supply drop ---------------------------------------------------------

static func supply_drop_available() -> bool:
	return SaveManager.is_clock_trusted() and String(SaveManager.section("ads").get("supply_day", "")) != day_key()


## Reward callback for the daily rewarded supply drop.
static func claim_supply_drop() -> bool:
	if not supply_drop_available():
		return false
	SaveManager.section("ads")["supply_day"] = day_key()
	SaveManager.grant_currency(catalog().supply_drop_energy, catalog().supply_drop_core)
	return true
