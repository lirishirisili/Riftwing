extends SceneTree
## Proves the meta-progression pass: missions roll + progress + claim, activity
## chests, pilot XP / levels, login streak, patrol income, achievements, modules
## (add / equip / merge / bonuses), ship signature loadouts, save v7, and the
## Progress / main-menu UI. Uses a scratch save copy and restores it.
## godot --headless --path . --script res://tests/meta_probe.gd

var _save: Node
var _backup: Dictionary


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("meta_probe: start")
	_save = root.get_node("SaveManager")
	_backup = (_save.get("_data") as Dictionary).duplicate(true)
	var failed := 0
	failed += _check_save_version()
	failed += _check_missions_and_pilot()
	failed += _check_login_and_patrol()
	failed += _check_modules()
	failed += _check_achievements()
	failed += await _check_ship_loadout()
	failed += await _check_ui()
	# Restore the developer's save exactly as it was.
	_save.set("_data", _backup)
	_save.call("save_game")
	if failed == 0:
		print("META_PROBE_OK")
		quit(0)
	else:
		printerr("META_PROBE_FAILED count=%d" % failed)
		quit(1)


func _meta():
	return load("res://scripts/meta/meta_progress.gd")


func _check_save_version() -> int:
	if int(_save.get("SCHEMA_VERSION")) != 7:
		printerr("schema version not 7")
		return 1
	for key in ["pilot", "lifetime", "missions", "login", "patrol", "achievements", "modules"]:
		if typeof(_save.call("section", key)) != TYPE_DICTIONARY:
			printerr("missing save section %s" % key)
			return 1
	# Migration recomputes sectors from real clears.
	var data := {"schema_version": 6, "completed_sectors": [1, 2, 3, 4, 5],
		"campaign": {"cleared_stage_ids": ["1-1", "1-2"]}, "progression": {"highest_sector_cleared": 5},
		"ships": {"selected_ship_id": "vanguard_mk2", "unlocked_ship_ids": ["vanguard_mk2"], "upgrade_levels": {}}}
	var migrated: Dictionary = _save.call("_migrate", _save.call("_merge_defaults", data))
	if (migrated["completed_sectors"] as Array).size() != 0:
		printerr("v7 migration kept bogus completed sectors: %s" % str(migrated["completed_sectors"]))
		return 1
	print("save_ok v7 sections + migration")
	return 0


func _check_missions_and_pilot() -> int:
	var fails := 0
	var M = _meta()
	var m: Dictionary = _save.call("section", "missions")
	m["day_key"] = ""
	m["week_key"] = ""
	M.refresh_missions()
	var daily: Array = M.missions("daily")
	var weekly: Array = M.missions("weekly")
	if daily.size() != 3 or weekly.size() != 3:
		printerr("mission roll sizes %d / %d" % [daily.size(), weekly.size()])
		return 1
	var stats = load("res://scripts/progression/run_stats.gd").new()
	stats.run_id = "meta_probe_%d" % Time.get_ticks_msec()
	stats.victory = true
	stats.enemies_destroyed = 5000
	stats.elites_killed = 50
	stats.bosses_defeated = 20
	stats.chests_opened = 20
	stats.novas_used = 20
	stats.evolutions = 6
	stats.best_combo = 200
	stats.survival_seconds = 4000.0
	stats.rift_energy_collected = 5000
	stats.score = 100000
	var level0: int = M.pilot_level()
	var summary: Dictionary = M.record_run(stats)
	if int(summary.get("xp", 0)) <= 0 or M.pilot_level() <= level0:
		printerr("pilot did not gain XP / levels: %s" % str(summary))
		fails += 1
	var claimed := 0
	for scope in ["daily", "weekly"]:
		for entry in M.missions(scope):
			if M.is_mission_done(entry) and M.claim_mission(scope, String(entry["id"])):
				claimed += 1
	if claimed < 3:
		printerr("only %d missions completed by a huge run" % claimed)
		fails += 1
	var energy0: int = _save.call("get_rift_energy")
	var chest: Dictionary = M.claim_activity(0)
	if M.activity() >= M.catalog().activity_milestones[0] and chest.is_empty():
		printerr("activity chest 1 not claimable")
		fails += 1
	if not chest.is_empty() and int(_save.call("get_rift_energy")) <= energy0 and int(chest.get("core", 0)) == 0:
		printerr("activity chest paid nothing")
		fails += 1
	if fails == 0:
		print("missions_ok roll/progress/claim + activity + pilot level %d" % M.pilot_level())
	return fails


func _check_login_and_patrol() -> int:
	var fails := 0
	var M = _meta()
	var l: Dictionary = _save.call("section", "login")
	l["claimed_day"] = M.day_key(-1)
	l["streak"] = 2
	var status: Dictionary = M.login_status()
	if int(status["day"]) != 3 or not bool(status["can_claim"]):
		printerr("streak continuation wrong: %s" % str(status))
		fails += 1
	var reward: Dictionary = M.claim_login()
	if reward.is_empty() or bool(M.login_status()["can_claim"]):
		printerr("login claim failed or repeatable")
		fails += 1
	l["claimed_day"] = M.day_key(-3)
	if int(M.login_status()["day"]) != 1:
		printerr("missed day did not reset the streak")
		fails += 1
	var p: Dictionary = _save.call("section", "patrol")
	p["last_collect_unix"] = int(Time.get_unix_time_from_system()) - 3 * 3600
	var pending: int = M.patrol_pending()
	if pending <= 0:
		printerr("no patrol income after 3h")
		fails += 1
	if M.claim_patrol(2) != pending * 2 or M.patrol_pending() != 0:
		printerr("patrol x2 claim wrong")
		fails += 1
	if fails == 0:
		print("login_ok streak/reset + patrol_ok %d/3h" % pending)
	return fails


func _check_modules() -> int:
	var fails := 0
	var M = _meta()
	var mods: Dictionary = _save.call("section", "modules")
	mods["owned"] = []
	mods["equipped"] = ["", "", ""]
	var a: Dictionary = M.add_module("overclock_chip", 0)
	M.add_module("overclock_chip", 0)
	M.add_module("overclock_chip", 0)
	if not M.can_merge(String(a["uid"])):
		printerr("three commons cannot merge")
		fails += 1
	var rare: Dictionary = M.merge(String(a["uid"]))
	if int(rare.get("rarity", -1)) != 1 or M.owned_modules().size() != 1:
		printerr("merge did not produce one rare: %s" % str(rare))
		fails += 1
	M.equip(String(rare["uid"]), 0)
	var bonus: Dictionary = M.equipped_bonuses()
	if float(bonus.get("damage", 0.0)) <= 0.0:
		printerr("equipped module gives no bonus")
		fails += 1
	if fails == 0:
		print("modules_ok add/merge/equip/bonus")
	return fails


func _check_achievements() -> int:
	var M = _meta()
	var life: Dictionary = _save.call("section", "lifetime")
	life["kills"] = 200
	var claimed_list: Array = _save.call("section", "achievements")["claimed"]
	claimed_list.erase("a_kills_100")
	if not M.claim_achievement("a_kills_100"):
		printerr("achievement a_kills_100 not claimable at 200 kills")
		return 1
	if M.claim_achievement("a_kills_100"):
		printerr("achievement claimable twice")
		return 1
	print("achievements_ok")
	return 0


func _check_ship_loadout() -> int:
	_save.call("section", "ships")["selected_ship_id"] = "void_strider"
	(_save.call("section", "ships")["unlocked_ship_ids"] as Array).append("void_strider")
	var scene = load("res://scenes/gameplay/run_scene.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var ok: bool = scene.get_node("SecondaryWeaponSystem").has_weapon("guardian_drone")
	scene.queue_free()
	await process_frame
	if not ok:
		printerr("Void Strider did not launch with its Guardian Drone")
		return 1
	print("ship_loadout_ok")
	return 0


func _check_ui() -> int:
	var fails := 0
	var router: Node = root.get_node("SceneRouter")
	var holder := Node.new()
	root.add_child(holder)
	router.call("configure", holder)
	for tab in [0, 1, 2]:
		router.call("go_to", "progress", {"tab": tab})
		await process_frame
		await process_frame
		if String(router.call("get_current_screen_id")) != "progress":
			printerr("progress screen tab %d failed" % tab)
			fails += 1
	# Welcome-back modal appears when patrol income is waiting (after the
	# one-time privacy choice, which is asked first).
	_save.call("section", "privacy")["asked"] = true
	_save.call("section", "patrol")["last_collect_unix"] = int(Time.get_unix_time_from_system()) - 7200
	router.call("go_to", "main_menu")
	for i in 4:
		await process_frame
	var menu: Node = holder.get_child(holder.get_child_count() - 1)
	if menu.find_child("WelcomeBack", true, false) == null:
		printerr("welcome-back modal not shown with patrol income waiting")
		fails += 1
	if menu.find_child("ProgressButton", true, false) == null:
		printerr("main menu missing Progress button")
		fails += 1
	if fails == 0:
		print("ui_ok progress tabs + welcome modal + menu button")
	return fails
