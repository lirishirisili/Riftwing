extends SceneTree
## End-to-end vertical-slice validation.
## Prefer a GPU window for screenshots:
##   godot --path . --window-size 1080,1920 --script res://tests/vertical_slice_probe.gd
## Headless still validates navigation, victory/defeat, save, and reward idempotency.


func _init() -> void:
	call_deferred("_run")


func _save() -> Node:
	return root.get_node("SaveManager")


func _router() -> Node:
	return root.get_node("SceneRouter")


func _run() -> void:
	print("vertical_slice_probe: start")
	var failed := 0
	failed += _check_timeline_data()
	failed += await _check_full_flow()
	if failed == 0:
		print("VERTICAL_SLICE_PROBE_OK")
		quit(0)
	else:
		printerr("VERTICAL_SLICE_PROBE_FAILED count=%d" % failed)
		quit(1)


func _check_timeline_data() -> int:
	var tl: StageTimelineData = load("res://resources/stages/vertical_slice_timeline.tres")
	if tl == null:
		printerr("timeline missing")
		return 1
	if tl.early_wave == null or tl.mid_wave == null:
		printerr("timeline waves missing")
		return 1
	if tl.mini_boss == null or tl.final_boss == null:
		printerr("timeline bosses missing")
		return 1
	if tl.mini_boss_at < 30.0 or tl.boss_warning_at <= tl.mini_boss_at:
		printerr("timeline times invalid")
		return 1
	if not ResourceLoader.exists("res://scenes/gameplay/run_scene.tscn"):
		printerr("run_scene missing")
		return 1
	print("timeline_ok mini_at=%.0f boss_at=%.0f" % [tl.mini_boss_at, tl.boss_warning_at])
	return 0


func _check_full_flow() -> int:
	var sm := _save()
	var router := _router()
	sm.call("reset")
	var holder := Node.new()
	root.add_child(holder)
	router.call("configure", holder)

	# --- Clean launch: menu → map → launch → run ---
	router.call("go_to", "main_menu")
	await process_frame
	await process_frame
	_capture_if_possible("review/slice_main_menu_1080x1920.png")
	if String(router.call("get_current_screen_id")) != "main_menu":
		printerr("main_menu not active")
		return 1

	router.call("go_to", "stage_map")
	await process_frame
	await process_frame
	_capture_if_possible("review/slice_stage_map_1080x1920.png")

	# Launch path must enter the unified run host (not boss_debug alone).
	router.call("go_to", "run", {"sector": 1, "stage_id": "1-1", "fast": true})
	await process_frame
	await process_frame
	await process_frame
	if String(router.call("get_current_screen_id")) != "run":
		printerr("run screen not active after launch")
		return 1
	var run := _find_run(holder)
	if run == null:
		printerr("RunController missing")
		return 1
	_capture_if_possible("review/slice_run_early_1080x1920.png")

	# --- Mini progression → final boss → victory ---
	run.call("debug_skip_to_mini_boss")
	await _wait_seconds(0.2)
	if String(run.call("get_phase_name")) != "MINI":
		printerr("expected MINI phase, got %s" % run.call("get_phase_name"))
		return 1
	_capture_if_possible("review/slice_mini_boss_1080x1920.png")
	run.call("debug_force_victory")
	# Mini victory: death beat (~1.2s) then MID (or BOSS if fast clock advanced).
	var left_mini := await _wait_until(func() -> bool:
		var phase := String(run.call("get_phase_name"))
		return phase == "MID" or phase == "BOSS"
	, 4.0)
	if not left_mini:
		printerr("expected MID or BOSS after mini, got %s" % run.call("get_phase_name"))
		return 1
	if String(router.call("get_current_screen_id")) == "results":
		printerr("mini-boss must not end the run")
		return 1

	run.call("debug_skip_to_final_boss")
	await _wait_seconds(0.2)
	if String(run.call("get_phase_name")) != "BOSS":
		printerr("expected BOSS phase")
		return 1
	_capture_if_possible("review/slice_final_boss_1080x1920.png")

	var energy_before: int = int(sm.call("get_rift_energy"))
	var victory_stats: RunStats = run.call("get_run_stats") as RunStats
	var victory_run_id := victory_stats.run_id
	run.call("debug_force_victory")
	# Hold beat + route to results.
	var to_results := await _wait_until(func() -> bool:
		return String(router.call("get_current_screen_id")) == "results"
	, 5.0)
	if not to_results:
		printerr("victory did not reach results (got %s)" % router.call("get_current_screen_id"))
		return 1
	_capture_if_possible("review/slice_results_victory_1080x1920.png")

	var energy_after_win: int = int(sm.call("get_rift_energy"))
	if energy_after_win <= energy_before:
		printerr("victory did not grant rewards")
		return 1
	if not bool(sm.call("is_stage_cleared", "1-1")):
		printerr("victory did not clear stage 1-1")
		return 1

	# Same run id must not double-grant.
	var rules: RewardRulesData = load("res://resources/progression/reward_rules_default.tres")
	victory_stats.finalize_score(rules)
	var rewards := RewardCalculator.calculate(victory_stats, rules)
	if bool(sm.call("grant_run_rewards", victory_run_id, rewards, victory_stats)):
		printerr("duplicate grant allowed for %s" % victory_run_id)
		return 1
	var energy_after_dup: int = int(sm.call("get_rift_energy"))
	if energy_after_dup != energy_after_win:
		printerr("duplicate grant changed bank")
		return 1

	# Persist + reload.
	sm.call("save_game")
	sm.call("load_game")
	if not bool(sm.call("is_stage_cleared", "1-1")):
		printerr("cleared stage lost after reload")
		return 1
	if int(sm.call("get_rift_energy")) != energy_after_win:
		printerr("currency lost after reload")
		return 1

	# Home → second run → defeat (no stage clear regression / no crash).
	router.call("go_to", "main_menu")
	await process_frame
	router.call("go_to", "run", {"sector": 1, "stage_id": "1-2", "fast": true})
	await _wait_frames(6)
	run = _find_run(holder)
	if run == null:
		printerr("second run missing")
		return 1
	run.call("debug_force_defeat")
	var to_defeat := await _wait_until(func() -> bool:
		return String(router.call("get_current_screen_id")) == "results"
	, 5.0)
	if not to_defeat:
		printerr("defeat did not reach results")
		return 1
	_capture_if_possible("review/slice_results_defeat_1080x1920.png")
	if bool(sm.call("is_stage_cleared", "1-2")):
		printerr("defeat must not clear stage 1-2")
		return 1

	# Navigation still valid from results.
	router.call("go_to", "stage_map")
	await process_frame
	if String(router.call("get_current_screen_id")) != "stage_map":
		printerr("return to stage_map broken")
		return 1
	router.call("go_to", "main_menu")
	await process_frame
	if String(router.call("get_current_screen_id")) != "main_menu":
		printerr("return to main_menu broken")
		return 1

	# Third quick victory to confirm replay stability + pool snapshot path.
	router.call("go_to", "run", {"sector": 2, "stage_id": "1-3", "fast": true})
	await _wait_frames(4)
	run = _find_run(holder)
	run.call("debug_skip_to_final_boss")
	await _wait_frames(6)
	var snap: Dictionary = run.call("get_pool_snapshot")
	print("pool_snapshot peak_bolts=%s peak_enemies=%s enemy_total=%s" % [
		snap.get("enemy_bolts_peak", -1),
		snap.get("enemies_peak", -1),
		(snap.get("enemy_bolts", {}) as Dictionary).get("total", -1),
	])
	var total_bolts := int((snap.get("enemy_bolts", {}) as Dictionary).get("total", 0))
	var max_bolts := int((snap.get("enemy_bolts", {}) as Dictionary).get("max", 0))
	if max_bolts > 0 and total_bolts > max_bolts:
		printerr("enemy bolt pool exceeded cap")
		return 1
	run.call("debug_force_victory")
	var to_third := await _wait_until(func() -> bool:
		return String(router.call("get_current_screen_id")) == "results"
	, 5.0)
	if not to_third:
		printerr("third victory failed")
		return 1

	print("flow_ok menu→map→run→mini→boss→results×2 + save/load + defeat + replay")
	return 0


func _find_run(holder: Node) -> Node:
	for child in holder.get_children():
		if child.get_script() != null and String(child.get_script().resource_path).ends_with("run_controller.gd"):
			return child
	return null


func _find_results(holder: Node) -> Node:
	for child in holder.get_children():
		if child.get_script() != null and String(child.get_script().resource_path).ends_with("results_screen.gd"):
			return child
	return null


func _wait_frames(n: int) -> void:
	for _i in n:
		await process_frame


func _wait_seconds(seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		await process_frame
		left -= 1.0 / 60.0


func _wait_until(predicate: Callable, timeout_sec: float) -> bool:
	var left := timeout_sec
	while left > 0.0:
		if bool(predicate.call()):
			return true
		await process_frame
		left -= 1.0 / 60.0
	return false


func _capture_if_possible(path: String) -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("headless"):
		return
	var img: Image = root.get_texture().get_image()
	if img == null:
		return
	if img.get_width() != 1080 or img.get_height() != 1920:
		img.resize(1080, 1920, Image.INTERPOLATE_BILINEAR)
	var abs_path := ProjectSettings.globalize_path("res://review")
	DirAccess.make_dir_recursive_absolute(abs_path)
	var out := path if path.begins_with("res://") else "res://%s" % path
	var err: Error = img.save_png(out)
	if err != OK:
		printerr("capture save failed %s (%d)" % [out, err])
		return
	print("captured %s" % out)
