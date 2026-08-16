extends SceneTree
## Headless galaxy-map validation.
## godot --headless --path . --script res://tests/stage_map_probe.gd


func _init() -> void:
	call_deferred("_run")


func _save() -> Node:
	return root.get_node("SaveManager")


func _router() -> Node:
	return root.get_node("SceneRouter")


func _run() -> void:
	print("stage_map_probe: start")
	var failed := 0
	failed += _check_map_data()
	failed += _check_unlock_and_progress()
	failed += await _check_screen_and_launch()
	if failed == 0:
		print("STAGE_MAP_PROBE_OK")
		quit(0)
	else:
		printerr("STAGE_MAP_PROBE_FAILED count=%d" % failed)
		quit(1)


func _check_map_data() -> int:
	var map: StageMapData = load("res://resources/stages/nova_sector_map.tres")
	if map == null or map.stages.size() != 8:
		printerr("map missing or not 8 stages")
		return 1
	var unlocked_starts := 0
	for stage in map.stages:
		if stage == null:
			printerr("null stage in map")
			return 1
		if stage.starts_unlocked:
			unlocked_starts += 1
		if stage.recommended_power <= 0 or stage.objective == "":
			printerr("stage %s missing data-driven fields" % stage.id)
			return 1
	if unlocked_starts != 3:
		printerr("expected 3 starts_unlocked, got %d" % unlocked_starts)
		return 1
	print("map_ok stages=8 starts_unlocked=3")
	return 0


func _check_unlock_and_progress() -> int:
	var sm := _save()
	sm.call("reset")
	var map: StageMapData = load("res://resources/stages/nova_sector_map.tres")
	var cleared: Array = sm.call("get_cleared_stage_ids")

	for id in ["1-1", "1-2", "1-3"]:
		var stage := map.find_by_id(id)
		if not StageProgress.is_unlocked(map, stage, cleared):
			printerr("%s should start unlocked" % id)
			return 1
		if not bool(sm.call("can_launch_stage", map, id)):
			printerr("%s should be launchable on NORMAL" % id)
			return 1

	for id in ["1-4", "1-5", "1-6", "1-7", "1-8"]:
		var stage := map.find_by_id(id)
		if StageProgress.is_unlocked(map, stage, cleared):
			printerr("%s should start locked" % id)
			return 1
		if bool(sm.call("can_launch_stage", map, id)):
			printerr("%s must not launch while locked" % id)
			return 1

	# Clearing 1-3 unlocks 1-4.
	sm.call("record_stage_clear", "1-3", 2)
	cleared = sm.call("get_cleared_stage_ids")
	if not StageProgress.is_unlocked(map, map.find_by_id("1-4"), cleared):
		printerr("1-4 should unlock after clearing 1-3")
		return 1
	if int(sm.call("get_stage_stars", "1-3")) != 2:
		printerr("stars not saved")
		return 1

	# Best stars kept.
	sm.call("record_stage_clear", "1-3", 1)
	if int(sm.call("get_stage_stars", "1-3")) != 2:
		printerr("best stars not preserved")
		return 1

	# HARD blocks launch even for unlocked stages.
	sm.call("set_campaign_difficulty", "hard")
	if bool(sm.call("can_launch_stage", map, "1-1")):
		printerr("HARD must block launch")
		return 1
	sm.call("set_campaign_difficulty", "normal")

	# Persist across reload.
	sm.call("load_game")
	if not bool(sm.call("is_stage_cleared", "1-3")):
		printerr("cleared stage not persisted")
		return 1
	if int(sm.call("get_stage_stars", "1-3")) != 2:
		printerr("stars not persisted")
		return 1

	# Victory grant path records stage clear.
	sm.call("reset")
	var stats := RunStats.new()
	stats.run_id = "probe_stage_1"
	stats.victory = true
	stats.sector = 1
	stats.stage_id = "1-1"
	stats.enemies_destroyed = 10
	stats.best_combo = 6
	stats.survival_seconds = 40.0
	stats.rift_energy_collected = 20
	var rules: RewardRulesData = load("res://resources/progression/reward_rules_default.tres")
	stats.finalize_score(rules)
	var rewards := RewardCalculator.calculate(stats, rules)
	if not bool(sm.call("grant_run_rewards", stats.run_id, rewards, stats)):
		printerr("grant failed")
		return 1
	if not bool(sm.call("is_stage_cleared", "1-1")):
		printerr("grant did not clear stage")
		return 1
	if int(sm.call("get_stage_stars", "1-1")) < 1:
		printerr("grant did not assign stars")
		return 1

	print("progress_ok unlocked_chain+hard_lock+persist+grant")
	return 0


func _check_screen_and_launch() -> int:
	var sm := _save()
	var router := _router()
	sm.call("reset")
	var holder := Node.new()
	root.add_child(holder)
	router.call("configure", holder)
	router.call("go_to", "stage_map")
	await process_frame
	await process_frame
	if String(router.call("get_current_screen_id")) != "stage_map":
		printerr("stage_map screen not active")
		return 1

	var screen: Node = null
	for child in holder.get_children():
		if child.get_script() != null and String(child.get_script().resource_path).ends_with("stage_map_screen.gd"):
			screen = child
			break
	if screen == null:
		printerr("StageMapScreen missing")
		return 1

	var brand := screen.find_child("BrandLabel", true, false) as Label
	if brand == null:
		brand = screen.find_child("Brand", true, false) as Label
	if brand == null or brand.text != "RIFTSTRIKE":
		printerr("branding missing")
		return 1

	var launch := screen.get_node_or_null("%LaunchButton") as GlowCtaButton
	if launch == null:
		printerr("launch button missing")
		return 1
	if screen.find_child("Shell", true, false) == null:
		printerr("MetaScreenShell missing on stage map")
		return 1
	# Every stage node must have a real hit target (plain Control parents do not
	# auto-size from custom_minimum_size — regression caused invisible stages).
	var visible_nodes := 0
	for child in screen.find_children("Node_*", "Button", true, false):
		var btn := child as Button
		if btn != null and btn.size.x >= 100.0 and btn.size.y >= 100.0:
			visible_nodes += 1
	if visible_nodes < 8:
		printerr("stage nodes undersized/missing: visible=%d" % visible_nodes)
		return 1
	# Default selection is unlocked 1-1 on NORMAL — Launch enabled.
	var launch_btn := launch.get_button()
	if launch_btn == null or launch_btn.disabled:
		printerr("launch should be enabled for unlocked stage")
		return 1

	# Select locked stage via save + refresh signal.
	sm.call("select_stage", "1-5")
	await process_frame
	await process_frame
	if launch_btn != null and not launch_btn.disabled:
		printerr("launch must be disabled for locked stage")
		return 1

	# Direct can_launch guard.
	var map: StageMapData = load("res://resources/stages/nova_sector_map.tres")
	if bool(sm.call("can_launch_stage", map, "1-8")):
		printerr("1-8 must not be launchable")
		return 1

	print("screen_ok brand=%s launch_guarded" % brand.text)
	return 0
