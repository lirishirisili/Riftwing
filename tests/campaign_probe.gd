extends SceneTree
## Proves the campaign pass: 3 sectors / 30 stages with cross-sector unlocks,
## every stage playable data (timeline + bosses + ambient), every boss pattern
## fires, 3-phase bosses reach phase 3, Endless laps and scales, Boss Rush runs
## its queue, and the Modes screen opens.
## godot --headless --path . --script res://tests/campaign_probe.gd

const STEP := 1.0 / 30.0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("campaign_probe: start")
	var failed := 0
	failed += _check_campaign_data()
	failed += await _check_bosses()
	failed += await _check_endless()
	failed += await _check_boss_rush()
	failed += await _check_modes_screen()
	if failed == 0:
		print("CAMPAIGN_PROBE_OK")
		quit(0)
	else:
		printerr("CAMPAIGN_PROBE_FAILED count=%d" % failed)
		quit(1)


func _campaign():
	return load("res://scripts/progression/campaign.gd")


func _check_campaign_data() -> int:
	var fails := 0
	var C = _campaign()
	if C.sectors().size() != 3 or C.total_stage_count() != 30:
		printerr("campaign shape: %d sectors / %d stages" % [C.sectors().size(), C.total_stage_count()])
		return 1
	for map in C.sectors():
		for stage in map.stages:
			var tl = stage.timeline
			if tl == null:
				# Nova 1-1..1-3 use the shared vertical-slice timeline by design.
				if map.sector_index != 1 or stage.index > 3:
					printerr("%s has no timeline" % stage.id)
					fails += 1
				continue
			if tl.mini_boss == null or tl.final_boss == null or tl.early_ambient == null or tl.mid_ambient == null:
				printerr("%s timeline incomplete" % stage.id)
				fails += 1
	if C.next_after("1-10") == null or C.next_after("1-10").id != "2-1":
		printerr("1-10 does not lead into 2-1")
		fails += 1
	if C.next_after("2-10") == null or C.next_after("2-10").id != "3-1":
		printerr("2-10 does not lead into 3-1")
		fails += 1
	if C.next_after("3-10") != null:
		printerr("3-10 should be the final stage")
		fails += 1
	if C.is_unlocked("2-1", ["1-9"]) or not C.is_unlocked("2-1", ["1-10"]):
		printerr("2-1 unlock is not gated on 1-10")
		fails += 1
	if C.sector_index_of("3-4") != 3:
		printerr("sector index of 3-4 wrong")
		fails += 1
	for track in ["run_ember", "boss_ember", "run_abyss", "boss_abyss"]:
		if not ResourceLoader.exists("res://assets/audio/music/music_%s.ogg" % track):
			printerr("missing music %s" % track)
			fails += 1
	if fails == 0:
		print("campaign_ok 3 sectors / 30 stages, cross-sector unlocks, music")
	return fails


func _mount_run(payload: Dictionary = {}) -> Node:
	var scene = load("res://scenes/gameplay/run_scene.tscn").instantiate()
	if not payload.is_empty():
		scene.call("receive_payload", payload)
	root.add_child(scene)
	await process_frame
	await process_frame
	return scene


func _check_bosses() -> int:
	var fails := 0
	var scene: Node = await _mount_run()
	scene.get_node("WaveDirector").stop_and_clear()
	var boss = scene.get_node("Boss")
	var bolts = scene.get_node("EnemyProjectilePool")
	var player = scene.get_node("PlayerShip")
	for id in ["cinder_warden", "ember_hydra", "abyss_sentinel", "rift_leviathan", "abyss_overmind", "void_titan_ascended"]:
		var data = load("res://resources/bosses/%s.tres" % id)
		if data == null:
			printerr("boss %s missing" % id)
			fails += 1
			continue
		# Every pattern in every phase must put bullets (or adds / a laser) on screen.
		var phases := [data.phase1_patterns, data.phase2_patterns, data.phase3_patterns]
		for p in phases:
			for pat in p:
				bolts.release_all()
				boss.prepare(data)
				boss.begin()
				boss.set("_state", 3) # FIGHT
				# Typed array: assigning an untyped [pat] to Array[BossPatternData]
				# silently fails, so build a typed one.
				var only: Array[BossPatternData] = []
				only.append(pat)
				boss.set("_patterns", only)
				if boss.get("_patterns").size() != 1:
					printerr("could not isolate pattern %s" % pat.display_name)
					fails += 1
				boss.call("_begin_pattern")
				for i in int((pat.telegraph_seconds + pat.active_seconds) / STEP) + 2:
					player.call("grant_invulnerability", 1.0)
					boss.call("_process", STEP)
				var produced: int = bolts.get_active_count() + boss.get_adds().size()
				if produced == 0 and pat.kind != 1:
					printerr("%s pattern %s produced nothing" % [id, pat.display_name])
					fails += 1
		if data.phase3_threshold > 0.0:
			boss.prepare(data)
			boss.begin()
			boss.set("_state", 3)
			boss.call("_begin_fight", 2)
			boss.take_damage(boss.get_max_health() * (1.0 - data.phase3_threshold) + 1.0)
			if boss.get("_pending_phase") != 3:
				printerr("%s did not transition to phase 3" % id)
				fails += 1
	scene.queue_free()
	await process_frame
	if fails == 0:
		print("bosses_ok every pattern fires, phase 3 transitions")
	return fails


func _check_endless() -> int:
	var fails := 0
	var scene: Node = await _mount_run({"mode": "endless"})
	if scene.call("get_mode") != "endless":
		printerr("endless payload ignored")
		scene.queue_free()
		return 1
	var director = scene.get_node("WaveDirector")
	if director.get_ambient() == null:
		printerr("endless did not start ambient spawning")
		fails += 1
	scene.set("_run_time", 1000.0)
	scene.call("_tick_timeline")
	if scene.get_phase_name() != "BOSS":
		printerr("endless boss did not start (phase %s)" % scene.get_phase_name())
		fails += 1
	var scale0: float = scene.get("_mode_scale")
	scene.get_node("Boss").call("debug_defeat")
	await process_frame
	if scene.get_phase_name() != "EARLY":
		printerr("endless did not return to waves after a boss")
		fails += 1
	if float(scene.get("_mode_scale")) <= scale0:
		printerr("endless did not scale up after a boss")
		fails += 1
	if scene.call("get_run_stats").bosses_defeated != 1:
		printerr("endless boss not counted")
		fails += 1
	scene.queue_free()
	await process_frame
	if fails == 0:
		print("endless_ok waves -> boss -> lap 2 scaled")
	return fails


func _check_boss_rush() -> int:
	var fails := 0
	var scene: Node = await _mount_run({"mode": "boss_rush"})
	var queue: Array = scene.get("_rush_queue")
	if queue.is_empty():
		printerr("boss rush queue empty")
		scene.queue_free()
		return 1
	for i in queue.size():
		# Close any free level-up card screens so the run clock advances.
		var screen = scene.get_node("UpgradeScreen")
		if screen.is_open():
			screen.call("_finish_close")
		scene.set("_run_time", float(scene.get("_next_boss_at")) + 0.1)
		scene.call("_tick_timeline")
		scene.get_node("Boss").call("debug_defeat")
		await process_frame
	if not bool(scene.get("_run_over")):
		printerr("boss rush did not end after its last boss")
		fails += 1
	if scene.call("get_run_stats").bosses_defeated != queue.size():
		printerr("boss rush counted %d of %d bosses" % [scene.call("get_run_stats").bosses_defeated, queue.size()])
		fails += 1
	scene.queue_free()
	await process_frame
	if fails == 0:
		print("boss_rush_ok %d bosses" % queue.size())
	return fails


func _check_modes_screen() -> int:
	var router: Node = root.get_node("SceneRouter")
	var holder := Node.new()
	root.add_child(holder)
	router.call("configure", holder)
	router.call("go_to", "modes")
	await process_frame
	await process_frame
	if String(router.call("get_current_screen_id")) != "modes":
		printerr("modes screen did not open")
		return 1
	print("modes_screen_ok")
	return 0
