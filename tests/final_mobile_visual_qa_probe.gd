extends SceneTree
## Milestone 23 — final mobile visual QA checks across portrait sizes.
## godot --headless --path . --script res://tests/final_mobile_visual_qa_probe.gd


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("final_mobile_visual_qa_probe: start")
	var failed := 0
	failed += _check_static()
	failed += await _check_runtime()
	if failed == 0:
		print("FINAL_MOBILE_VISUAL_QA_PROBE_OK")
		quit(0)
	else:
		printerr("FINAL_MOBILE_VISUAL_QA_PROBE_FAILED count=%d" % failed)
		quit(1)


func _check_static() -> int:
	var hud := FileAccess.get_file_as_string("res://scenes/ui/gameplay_hud.tscn")
	if hud.find('text = "XP"') < 0:
		printerr("HUD XP caption missing")
		return 1
	if hud.find('text = "ENERGY"') >= 0:
		printerr("HUD still labels XP bar as ENERGY")
		return 1
	if hud.find("ButtonPrimary") < 0 or hud.find("ButtonTertiary") < 0:
		printerr("HUD pause buttons missing theme variations")
		return 1
	var effects := FileAccess.get_file_as_string("res://scripts/effects/effects_layer.gd")
	if effects.find("EFFECTS_Z_INDEX := -5") < 0:
		printerr("EffectsLayer z-index regression")
		return 1
	var camera := FileAccess.get_file_as_string("res://scripts/core/camera_rig.gd")
	if camera.find("_center_on_viewport") < 0:
		printerr("CameraRig missing viewport centering")
		return 1
	var boss := FileAccess.get_file_as_string("res://scripts/ui/boss_health_bar.gd")
	if boss.find("0.5 - 250.0") < 0 and boss.find("vp.x * 0.5 - 250") < 0:
		printerr("Boss bar not inset for HUD chips")
		return 1
	var results := FileAccess.get_file_as_string("res://scripts/ui/results_screen.gd")
	if results.find("_ensure_scroll_layout") < 0:
		printerr("Results scroll layout missing")
		return 1
	var upgrade := FileAccess.get_file_as_string("res://scripts/ui/upgrade_screen.gd")
	if upgrade.find("_fit_card_widths") < 0:
		printerr("Upgrade card width fit missing")
		return 1
	for path in [
		"res://scripts/ui/main_menu.gd",
		"res://scripts/ui/stage_map_screen.gd",
		"res://scripts/ui/hangar_screen.gd",
		"res://scripts/ui/results_screen.gd",
		"res://scenes/ui/gameplay_hud.tscn",
	]:
		var text := FileAccess.get_file_as_string(path)
		if text.find("Starforge") >= 0 or text.find("Galaxy Rush") >= 0 or text.find("STARFORGE") >= 0:
			printerr("legacy brand in %s" % path)
			return 1
	if not FileAccess.file_exists("res://docs/FINAL_MOBILE_VISUAL_QA.md"):
		printerr("audit doc missing")
		return 1
	print("static_ok")
	return 0


func _check_runtime() -> int:
	var fails := 0
	var router := root.get_node("SceneRouter")
	var holder := Node.new()
	root.add_child(holder)
	router.call("configure", holder)

	var sizes: Array[Vector2i] = [
		Vector2i(1080, 1920),
		Vector2i(1080, 2400),
		Vector2i(1080, 2478),
	]
	var screens := ["main_menu", "stage_map", "hangar", "results"]
	for size in sizes:
		DisplayServer.window_set_size(size)
		await process_frame
		for screen_id in screens:
			router.call("go_to", screen_id)
			await process_frame
			await process_frame
			await process_frame
			if String(router.call("get_current_screen_id")) != screen_id:
				printerr("screen %s failed @ %s" % [screen_id, size])
				fails += 1
				continue
			var screen: Node = holder.get_child(0)
			var safe := screen.find_child("Safe", true, false) as MarginContainer
			if safe == null:
				printerr("Safe missing on %s @ %s" % [screen_id, size])
				fails += 1
				continue
			# Results rebuilds Safe children into Column/Scroll/Buttons.
			if screen_id == "results":
				if screen.find_child("Column", true, false) == null:
					printerr("results Column missing @ %s" % size)
					fails += 1
				if screen.find_child("Scroll", true, false) == null:
					printerr("results Scroll missing @ %s" % size)
					fails += 1
				var next_btn := screen.find_child("NextSector", true, false) as Button
				var upgrade_btn := screen.find_child("UpgradeShip", true, false) as Button
				if next_btn == null or upgrade_btn == null:
					printerr("results CTAs missing @ %s" % size)
					fails += 1
				elif next_btn.custom_minimum_size.y < 48.0 or upgrade_btn.custom_minimum_size.y < 48.0:
					printerr("results CTA min size @ %s next=%s up=%s" % [
						size, next_btn.custom_minimum_size, upgrade_btn.custom_minimum_size])
					fails += 1
		print("meta_ok %dx%d" % [size.x, size.y])

	# Run host: HUD XP label + camera center + effects under bullets.
	DisplayServer.window_set_size(Vector2i(1080, 2478))
	router.call("go_to", "run", {"sector": 1, "stage_id": "1-1", "fast": true})
	await process_frame
	await process_frame
	await process_frame
	if String(router.call("get_current_screen_id")) != "run":
		printerr("run failed to open")
		return fails + 1

	var run: Node = holder.get_child(0)
	var camera := run.get_node_or_null("CameraRig") as Camera2D
	if camera == null:
		printerr("CameraRig missing")
		fails += 1
	elif not camera.has_method("_center_on_viewport"):
		printerr("CameraRig missing _center_on_viewport")
		fails += 1
	else:
		camera.call("_center_on_viewport")
		await process_frame
		var vp := camera.get_viewport().get_visible_rect().size
		if absf(camera.position.x - vp.x * 0.5) > 2.0 or absf(camera.position.y - vp.y * 0.5) > 2.0:
			printerr("camera not centered on viewport %s -> %s" % [vp, camera.position])
			fails += 1

	var hud := run.find_child("GameplayHUD", true, false)
	if hud == null:
		printerr("GameplayHUD missing")
		fails += 1
	else:
		var xp_cap := hud.find_child("EnergyCaption", true, false) as Label
		if xp_cap == null or xp_cap.text != "XP":
			printerr("runtime XP caption wrong: %s" % (xp_cap.text if xp_cap else "?"))
			fails += 1
		var resume := hud.find_child("ResumeButton", true, false) as Button
		var quit_btn := hud.find_child("QuitButton", true, false) as Button
		if resume == null or String(resume.theme_type_variation) != "ButtonPrimary":
			printerr("Resume missing ButtonPrimary")
			fails += 1
		if quit_btn == null or String(quit_btn.theme_type_variation) != "ButtonTertiary":
			printerr("Quit missing ButtonTertiary")
			fails += 1
		var pause_shell := hud.find_child("PauseShell", true, false) as Control
		var pause := hud.find_child("PauseButton", true, false) as Button
		var pause_ok := pause != null and (
			(pause_shell != null and pause_shell.custom_minimum_size.x >= 48.0 and pause_shell.custom_minimum_size.y >= 48.0)
			or (pause.custom_minimum_size.x >= 48.0 and pause.custom_minimum_size.y >= 48.0)
			or (pause.size.x >= 48.0 and pause.size.y >= 48.0)
		)
		if not pause_ok:
			printerr("pause touch target too small")
			fails += 1

	var effects := run.find_child("EffectsLayer", true, false) as Node2D
	if effects == null or effects.z_index >= 0:
		printerr("EffectsLayer not below bullets")
		fails += 1

	# Boss bar width leaves chip lanes (~250px/side).
	var bar_scene: PackedScene = load("res://scenes/ui/boss_health_bar.tscn")
	var bar: Control = bar_scene.instantiate()
	root.add_child(bar)
	await process_frame
	await process_frame
	var half := bar.offset_right
	if half > 300.5:
		printerr("boss bar too wide: half=%s" % half)
		fails += 1
	bar.queue_free()

	print("runtime_ok fails=%d" % fails)
	return fails
