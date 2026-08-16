extends SceneTree
## Regression coverage for the former "Coming Soon" systems now made real:
## Upgrade All (atomic), ship unlocks (gate + cost), Daily Challenge (deterministic
## + one-time reward), and the Void Invasion event (window math + progress + claim).
## godot --headless --path . --script res://tests/coming_soon_probe.gd

const _CATALOG_PATH := "res://resources/ships/ship_catalog_default.tres"
const _RULES_PATH := "res://resources/progression/reward_rules_default.tres"
const _MAP_PATH := "res://resources/stages/nova_sector_map.tres"
const _EVENT_PATH := "res://resources/events/void_invasion.tres"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("coming_soon_probe: start")
	var failed := 0
	failed += _check_upgrade_all()
	failed += _check_ship_unlock()
	failed += _check_daily()
	failed += _check_event()
	if failed == 0:
		print("COMING_SOON_PROBE_OK")
		quit(0)
	else:
		printerr("COMING_SOON_PROBE_FAILED count=%d" % failed)
		quit(1)


func _sm() -> Node:
	return root.get_node("SaveManager")


func _check_upgrade_all() -> int:
	var fails := 0
	var sm := _sm()
	var catalog: ShipCatalogData = load(_CATALOG_PATH)
	sm.call("reset")
	sm.call("debug_add_currency", 1000000, 0)
	var ship: ShipData = catalog.find_by_id(String(sm.call("get_selected_ship_id")))
	var plan: Dictionary = sm.call("plan_upgrade_all", ship)
	var ids: PackedStringArray = plan["track_ids"]
	var total := int(plan["total_cost"])
	if ids.size() != ship.tracks().size():
		printerr("upgrade-all plan should include every track with a big budget (%d/%d)" % [ids.size(), ship.tracks().size()])
		fails += 1
	var energy_before := int(sm.call("get_rift_energy"))
	var before := {}
	for t in ship.tracks():
		before[t.id] = int(sm.call("get_upgrade_level", ship.id, t.id))
	var bought := int(sm.call("purchase_upgrade_all", ship, ids))
	if bought != ids.size():
		printerr("upgrade-all purchased %d, expected %d" % [bought, ids.size()])
		fails += 1
	if int(sm.call("get_rift_energy")) != energy_before - total:
		printerr("upgrade-all did not deduct exactly the planned total")
		fails += 1
	for t in ship.tracks():
		if int(sm.call("get_upgrade_level", ship.id, t.id)) != int(before[t.id]) + 1:
			printerr("track %s not bumped by exactly one level" % t.id)
			fails += 1

	# No-budget: nothing planned, and a fabricated plan buys nothing (no partial buy).
	sm.call("reset")
	var plan0: Dictionary = sm.call("plan_upgrade_all", ship)
	if int(plan0["total_cost"]) != 0 or (plan0["track_ids"] as PackedStringArray).size() != 0:
		printerr("zero-budget plan should be empty")
		fails += 1
	if int(sm.call("purchase_upgrade_all", ship, PackedStringArray(["weapons"]))) != 0:
		printerr("purchase with no budget should buy nothing")
		fails += 1
	if int(sm.call("get_rift_energy")) != 0:
		printerr("failed upgrade-all must not spend energy")
		fails += 1
	if fails == 0:
		print("upgrade_all_ok tracks=%d total=%d" % [ids.size(), total])
	return fails


func _check_ship_unlock() -> int:
	var fails := 0
	var sm := _sm()
	var catalog: ShipCatalogData = load(_CATALOG_PATH)
	sm.call("reset")
	var vs: ShipData = catalog.find_by_id("void_strider")
	if vs == null:
		printerr("void_strider missing")
		return fails + 1
	if bool(sm.call("is_ship_unlocked", "void_strider")):
		printerr("void_strider should start locked")
		fails += 1
	sm.call("debug_add_currency", 0, 10)
	if bool(sm.call("can_unlock_ship", vs)):
		printerr("should not unlock before clearing gate stage")
		fails += 1
	sm.call("record_stage_clear", vs.unlock_stage_id, 3, "normal")
	if not bool(sm.call("ship_requirement_met", vs)):
		printerr("requirement should be met after gate clear")
		fails += 1
	if not bool(sm.call("can_unlock_ship", vs)):
		printerr("should be unlockable with gate cleared + enough cores")
		fails += 1
	var core_before := int(sm.call("get_rift_core"))
	if not bool(sm.call("try_unlock_ship", vs)):
		printerr("unlock should succeed")
		fails += 1
	if not bool(sm.call("is_ship_unlocked", "void_strider")):
		printerr("ship not unlocked after purchase")
		fails += 1
	if int(sm.call("get_rift_core")) != core_before - vs.unlock_core_cost:
		printerr("unlock did not spend the core cost")
		fails += 1
	if bool(sm.call("try_unlock_ship", vs)):
		printerr("re-unlock should return false")
		fails += 1
	if fails == 0:
		print("ship_unlock_ok gate=%s cost=%d" % [vs.unlock_stage_id, vs.unlock_core_cost])
	return fails


func _check_daily() -> int:
	var fails := 0
	var sm := _sm()
	var rules: RewardRulesData = load(_RULES_PATH)
	var map: StageMapData = load(_MAP_PATH)
	var d1 := DailyChallenge.build()
	var d2 := DailyChallenge.build()
	if String(d1["stage_id"]) != String(d2["stage_id"]) or String(d1["difficulty"]) != String(d2["difficulty"]) or String(d1["date_key"]) != String(d2["date_key"]):
		printerr("daily challenge not deterministic for the same day")
		fails += 1

	sm.call("reset")
	var date := String(d1["date_key"])
	if bool(sm.call("is_daily_completed", date)):
		printerr("fresh save should not have today's daily completed")
		fails += 1

	var stage: StageNodeData = map.find_by_id(String(d1["stage_id"]))
	var reward_core := int(d1["reward_core"])
	var ds := RunStats.new()
	ds.run_id = "probe_daily_%d" % Time.get_ticks_msec()
	ds.victory = true
	ds.sector = 1
	ds.stage_id = String(d1["stage_id"])
	ds.difficulty = String(d1["difficulty"])
	ds.is_daily = true
	ds.daily_date = date
	ds.daily_reward_core = reward_core
	ds.enemies_destroyed = 40
	ds.survival_seconds = 90.0
	ds.finalize_score(rules)
	var is_first := not bool(sm.call("is_stage_cleared", ds.stage_id, ds.difficulty))
	var rewards: RunRewards = RewardCalculator.calculate(ds, rules, stage, is_first)
	var core_before := int(sm.call("get_rift_core"))
	sm.call("grant_run_rewards", ds.run_id, rewards, ds)
	if not bool(sm.call("is_daily_completed", date)):
		printerr("daily not marked completed after victory")
		fails += 1
	if int(sm.call("get_rift_core")) < core_before + reward_core:
		printerr("daily bonus core not granted")
		fails += 1

	# Second daily run on the same date must not re-grant the daily bonus.
	var ds2 := RunStats.new()
	ds2.run_id = "probe_daily2_%d" % Time.get_ticks_msec()
	ds2.victory = true
	ds2.sector = 1
	ds2.stage_id = String(d1["stage_id"])
	ds2.difficulty = String(d1["difficulty"])
	ds2.is_daily = true
	ds2.daily_date = date
	ds2.daily_reward_core = reward_core
	ds2.enemies_destroyed = 5
	ds2.finalize_score(rules)
	var base2: RunRewards = RewardCalculator.calculate(ds2, rules)
	var core_b2 := int(sm.call("get_rift_core"))
	sm.call("grant_run_rewards", ds2.run_id, base2, ds2)
	if int(sm.call("get_rift_core")) != core_b2 + base2.rift_core:
		printerr("daily bonus wrongly granted twice on the same date")
		fails += 1
	if fails == 0:
		print("daily_ok stage=%s diff=%s reward_core=%d" % [String(d1["stage_id"]), String(d1["difficulty"]), reward_core])
	return fails


func _check_event() -> int:
	var fails := 0
	var sm := _sm()
	var ev: EventData = load(_EVENT_PATH)
	if ev == null:
		printerr("void_invasion event missing")
		return fails + 1
	var now := int(Time.get_unix_time_from_system())
	if ev.remaining_seconds(now) <= 0:
		printerr("event remaining time should be positive")
		fails += 1
	var occ := ev.occurrence_id(now)
	sm.call("reset")
	if int(sm.call("get_event_progress", occ)) != 0:
		printerr("fresh event progress should be zero")
		fails += 1
	var goal := ev.goal
	sm.call("add_event_progress", occ, goal + 100, goal)
	if int(sm.call("get_event_progress", occ)) != goal:
		printerr("event progress should clamp at the goal")
		fails += 1
	var e_before := int(sm.call("get_rift_energy"))
	if not bool(sm.call("claim_event_reward", occ, goal, ev.reward_energy, ev.reward_core)):
		printerr("event reward should be claimable at goal")
		fails += 1
	if int(sm.call("get_rift_energy")) != e_before + ev.reward_energy:
		printerr("event reward energy not banked")
		fails += 1
	if bool(sm.call("claim_event_reward", occ, goal, ev.reward_energy, ev.reward_core)):
		printerr("event reward should only be claimable once")
		fails += 1
	if fails == 0:
		print("event_ok goal=%d occ=%s" % [goal, occ])
	return fails
