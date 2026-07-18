extends SceneTree
## Validates visual foundation: debug hidden, scales, parallax, multi-res.
## godot --headless --path . --script res://tests/visual_foundation_probe.gd


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("visual_foundation_probe: start")
	var failed := 0
	failed += _check_resources()
	failed += await _check_runtime()
	if failed == 0:
		print("VISUAL_FOUNDATION_PROBE_OK")
		quit(0)
	else:
		printerr("VISUAL_FOUNDATION_PROBE_FAILED count=%d" % failed)
		quit(1)


func _check_resources() -> int:
	var player: ProjectileData = load("res://resources/weapons/plasma_projectile.tres")
	var enemy: ProjectileData = load("res://resources/weapons/enemy_plasma_projectile.tres")
	if player.radius < 12.0 or enemy.radius < 18.0:
		printerr("projectile radii too small")
		return 1
	var scout: EnemyData = load("res://resources/enemies/scout.tres")
	var shooter: EnemyData = load("res://resources/enemies/shooter.tres")
	if scout.sprite_scale < 0.13 or shooter.sprite_scale < 0.16:
		printerr("enemy scales too small")
		return 1
	# Scout must not be cyan-player role.
	if scout.tint.b > 0.9 and scout.tint.r < 0.2:
		printerr("scout still cyan-player tint")
		return 1
	var titan: BossData = load("res://resources/bosses/void_titan.tres")
	if titan.sprite_scale < 0.65:
		printerr("boss scale below foundation target")
		return 1
	var pickup: PickupData = load("res://resources/pickups/energy_small.tres")
	if pickup.radius < 30.0:
		printerr("pickup too small")
		return 1
	if not ResourceLoader.exists("res://scenes/gameplay/space_background.tscn"):
		printerr("space_background missing")
		return 1
	print("resources_ok player_r=%.0f enemy_r=%.0f titan_s=%.2f" % [
		player.radius, enemy.radius, titan.sprite_scale])
	return 0


func _check_runtime() -> int:
	var router := root.get_node("SceneRouter")
	var holder := Node.new()
	root.add_child(holder)
	router.call("configure", holder)

	# --script probes do not load app_root; instance the overlay alone.
	var overlay_scene: PackedScene = load("res://scenes/ui/debug_overlay.tscn")
	var overlay: CanvasLayer = overlay_scene.instantiate()
	root.add_child(overlay)
	await process_frame
	if overlay.visible:
		printerr("debug overlay visible by default")
		return 1
	var feel := root.get_node("GameFeel")
	if bool(feel.get("debug_markers_enabled")):
		printerr("gameplay markers enabled by default")
		return 1
	overlay.queue_free()
	await process_frame

	for size in [Vector2i(1080, 1920), Vector2i(1080, 2400), Vector2i(1080, 2478)]:
		DisplayServer.window_set_size(size)
		router.call("go_to", "run", {"sector": 1, "stage_id": "1-1", "fast": true})
		await process_frame
		await process_frame
		await process_frame
		if String(router.call("get_current_screen_id")) != "run":
			printerr("run failed @ %s" % size)
			return 1
		var run: Node = null
		for child in holder.get_children():
			if child.get_script() != null and String(child.get_script().resource_path).ends_with("run_controller.gd"):
				run = child
				break
		if run == null:
			printerr("run controller missing @ %s" % size)
			return 1
		if run.get_node_or_null("SpaceBackground") == null:
			printerr("SpaceBackground missing @ %s" % size)
			return 1
		if run.get_node_or_null("Background") != null:
			printerr("flat Background ColorRect still present @ %s" % size)
			return 1
		var readout := run.get_node_or_null("UI/Readout") as CanvasItem
		if readout != null and readout.visible:
			printerr("run readout visible without debug @ %s" % size)
			return 1
		print("portrait_ok %dx%d" % [size.x, size.y])

	router.call("go_to", "visual_foundation")
	await process_frame
	await process_frame
	if String(router.call("get_current_screen_id")) != "visual_foundation":
		printerr("visual_foundation screen failed")
		return 1

	# Navigation still works.
	router.call("go_to", "main_menu")
	await process_frame
	if String(router.call("get_current_screen_id")) != "main_menu":
		printerr("main_menu navigation broken")
		return 1
	print("runtime_ok debug_hidden+parallax+multi_res+nav")
	return 0
