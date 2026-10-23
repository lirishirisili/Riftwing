extends SceneTree
## Proves the juice pass is wired: screen FX layer under the HUD, slow-motion
## that always recovers, crit feedback, combo multiplier + streak callouts, the
## Rift Nova screen clear, boss-kill beat + loot fountain, low-HP vignette.
## godot --headless --path . --script res://tests/juice_probe.gd


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("juice_probe: start")
	var failed := 0
	failed += await _check_time_scale()
	failed += await _check_run()
	if failed == 0:
		print("JUICE_PROBE_OK")
		quit(0)
	else:
		printerr("JUICE_PROBE_FAILED count=%d" % failed)
		quit(1)


func _check_time_scale() -> int:
	var feel: Node = root.get_node("GameFeel")
	feel.call("request_slowmo", 0.3, 0.15)
	if Engine.time_scale > 0.31:
		printerr("slowmo did not lower time scale: %f" % Engine.time_scale)
		return 1
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 400:
		await process_frame
	if not is_equal_approx(Engine.time_scale, 1.0):
		printerr("time scale did not recover: %f" % Engine.time_scale)
		return 1
	print("time_scale_ok")
	return 0


func _check_run() -> int:
	var fails := 0
	var feel: Node = root.get_node("GameFeel")
	var scene = load("res://scenes/gameplay/run_scene.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	var fx = scene.get_node_or_null("ScreenFX")
	var ui = scene.get_node("UI")
	if fx == null or int(fx.layer) >= int(ui.layer):
		printerr("ScreenFX missing or not under the HUD")
		fails += 1

	# Crit impact.
	var crit0 := int(feel.counters["crit"])
	feel.call("projectile_hit", Vector2(540, 600), 50.0, false, true)
	if int(feel.counters["crit"]) <= crit0:
		printerr("crit feedback did not fire")
		fails += 1

	# Combo multiplier + streak callout.
	var stats = scene.call("get_run_stats")
	for i in 20:
		scene.call("_register_kill")
	if int(stats.bonus_score) <= 0:
		printerr("combo multiplier added no bonus score")
		fails += 1
	var callout = scene.get_node("UI/GameplayHUD").get("_callout")
	if callout == null or not callout.visible:
		printerr("streak callout not shown")
		fails += 1

	# Rift Nova: charge, spawn a wave, detonate.
	var director = scene.get_node("WaveDirector")
	var wave = load("res://resources/waves/slice_wave_early.tres")
	director.start_wave(wave)
	for i in 240:
		await process_frame
		if director.get_active_enemy_count() >= 3:
			break
	var before: int = director.get_active_enemy_count()
	scene.call("_add_nova_charge", 1.0)
	var nova0 := int(feel.counters["nova"])
	scene.call("_on_nova_activated")
	await process_frame
	if int(feel.counters["nova"]) <= nova0:
		printerr("nova did not detonate")
		fails += 1
	if before > 0 and director.get_active_enemy_count() >= before:
		printerr("nova did not clear enemies (%d -> %d)" % [before, director.get_active_enemy_count()])
		fails += 1

	# Low-HP vignette.
	var player = scene.get_node("PlayerShip")
	scene.call("_on_player_health_changed", 10.0, 100.0)
	await process_frame
	if not fx.get("_overlay").visible:
		printerr("danger vignette not visible at 10% HP")
		fails += 1

	# Boss kill beat + loot fountain.
	scene.call("debug_skip_to_mini_boss")
	await process_frame
	var kills0 := int(feel.counters["boss_kill"])
	var pickups = scene.get_node("PickupPool")
	var boss = scene.get_node("Boss")
	boss.call("debug_defeat")
	await process_frame
	if int(feel.counters["boss_kill"]) <= kills0:
		printerr("boss kill beat did not fire")
		fails += 1
	if pickups.get_active_count() <= 0:
		printerr("boss loot fountain spawned nothing")
		fails += 1
	if player == null:
		fails += 1

	scene.queue_free()
	await process_frame
	await process_frame
	if not is_equal_approx(Engine.time_scale, 1.0):
		printerr("time scale left at %f after scene teardown" % Engine.time_scale)
		fails += 1
	if fails == 0:
		print("run_ok fx/crit/combo/streak/nova/vignette/boss-kill")
	return fails
