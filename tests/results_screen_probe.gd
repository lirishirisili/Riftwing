extends SceneTree
## Validates production results screen branding, rewards dedupe, and navigation.
## godot --headless --path . --script res://tests/results_screen_probe.gd


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("results_screen_probe: start")
	var failed := 0
	failed += _check_resources()
	failed += await _check_runtime()
	if failed == 0:
		print("RESULTS_SCREEN_PROBE_OK")
		quit(0)
	else:
		printerr("RESULTS_SCREEN_PROBE_FAILED count=%d" % failed)
		quit(1)


func _check_resources() -> int:
	var scene_src := FileAccess.get_file_as_string("res://scenes/ui/results_screen.tscn")
	var script_src := FileAccess.get_file_as_string("res://scripts/ui/results_screen.gd")
	for blob in [scene_src, script_src]:
		if blob.find("Starforge") >= 0 or blob.find("Galaxy Rush") >= 0 or blob.find("STARFORGE") >= 0:
			printerr("legacy brand in results sources")
			return 1
	if scene_src.find("RIFTWING") < 0:
		printerr("RIFTWING missing from results scene")
		return 1
	if script_src.find("grant_run_rewards") < 0:
		printerr("reward grant path missing")
		return 1
	print("resources_ok")
	return 0


func _check_runtime() -> int:
	var fails := 0
	var sm := root.get_node("SaveManager")
	var router := root.get_node("SceneRouter")
	sm.call("reset")
	var holder := Node.new()
	root.add_child(holder)
	router.call("configure", holder)

	var stats := RunStats.new()
	stats.run_id = "probe_results_vic_%d" % Time.get_ticks_msec()
	stats.victory = true
	stats.sector = 1
	stats.stage_id = "1-1"
	stats.enemies_destroyed = 40
	stats.best_combo = 12
	stats.survival_seconds = 95.0
	stats.rift_energy_collected = 80
	var rules: RewardRulesData = load("res://resources/progression/reward_rules_default.tres")
	stats.finalize_score(rules)

	var energy_before := int(sm.call("get_rift_energy"))
	router.call("go_to", "results", {"stats": stats})
	await process_frame
	await process_frame
	await process_frame
	if String(router.call("get_current_screen_id")) != "results":
		printerr("results screen not active")
		return 1

	var screen: Node = holder.get_child(0)
	var brand := screen.find_child("Brand", true, false) as Label
	if brand == null or brand.text != "RIFTWING":
		printerr("brand missing")
		fails += 1
	var title := screen.find_child("Title", true, false) as Label
	if title == null or title.text.find("VICTORY") < 0:
		printerr("victory headline missing: %s" % (title.text if title else "?"))
		fails += 1
	var next_btn := screen.find_child("NextSector", true, false) as Button
	var upgrade_btn := screen.find_child("UpgradeShip", true, false) as Button
	var home_btn := screen.find_child("Home", true, false) as Button
	var replay_btn := screen.find_child("ReplayButton", true, false) as Button
	if next_btn == null or upgrade_btn == null or home_btn == null or replay_btn == null:
		printerr("action buttons incomplete")
		fails += 1
	if screen.find_child("Scroll", true, false) == null:
		printerr("results scroll layout missing")
		fails += 1

	var energy_after := int(sm.call("get_rift_energy"))
	if energy_after <= energy_before:
		printerr("victory rewards not granted")
		fails += 1

	# Re-open same run id — must not double-grant.
	var mid_energy := energy_after
	router.call("go_to", "results", {"stats": stats})
	await process_frame
	await process_frame
	if int(sm.call("get_rift_energy")) != mid_energy:
		printerr("duplicate reward grant detected")
		fails += 1

	# Defeat presentation + navigation.
	var defeat := RunStats.new()
	defeat.run_id = "probe_results_def_%d" % Time.get_ticks_msec()
	defeat.victory = false
	defeat.sector = 1
	defeat.stage_id = "1-2"
	defeat.enemies_destroyed = 5
	defeat.finalize_score(rules)
	router.call("go_to", "results", {"stats": defeat})
	await process_frame
	await process_frame
	screen = holder.get_child(0)
	title = screen.find_child("Title", true, false) as Label
	if title == null or title.text.find("DEFEAT") < 0:
		printerr("defeat headline missing")
		fails += 1

	screen.call("_on_home")
	await process_frame
	await process_frame
	if String(router.call("get_current_screen_id")) != "main_menu":
		printerr("Home navigation broken")
		fails += 1

	print("runtime_ok brand+dedupe+nav energy=%d→%d" % [energy_before, mid_energy])
	return fails
