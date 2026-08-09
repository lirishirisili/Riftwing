extends SceneTree
## Validates production gameplay HUD wiring across portrait sizes.
## godot --headless --path . --script res://tests/gameplay_hud_probe.gd


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("gameplay_hud_probe: start")
	var failed := 0
	failed += _check_resources()
	failed += await _check_runtime()
	if failed == 0:
		print("GAMEPLAY_HUD_PROBE_OK")
		quit(0)
	else:
		printerr("GAMEPLAY_HUD_PROBE_FAILED count=%d" % failed)
		quit(1)


func _check_resources() -> int:
	var paths := [
		"res://scenes/ui/gameplay_hud.tscn",
		"res://scenes/ui/ability_button.tscn",
		"res://scenes/ui/boss_health_bar.tscn",
		"res://scripts/ui/gameplay_hud.gd",
		"res://scripts/ui/hud_segmented_bar.gd",
		"res://scripts/ui/ability_button.gd",
		"res://scripts/ui/boss_health_bar.gd",
		"res://assets/ui/panel_dark_9slice.svg",
		"res://assets/ui/chrome/bottom_hud_frame.svg",
		"res://assets/ui/chrome/hex_frame.svg",
		"res://assets/icons/icon_health.svg",
		"res://assets/icons/icon_shield.svg",
		"res://assets/icons/icon_missile.svg",
		"res://assets/icons/icon_laser.svg",
	]
	for path in paths:
		if not ResourceLoader.exists(path):
			printerr("missing %s" % path)
			return 1
	var src := FileAccess.get_file_as_string("res://scripts/ui/gameplay_hud.gd")
	var scene_src := FileAccess.get_file_as_string("res://scenes/ui/gameplay_hud.tscn")
	if src.find("Starforge") >= 0 or src.find("Galaxy Rush") >= 0:
		printerr("legacy brand in gameplay_hud.gd")
		return 1
	if scene_src.find("Starforge") >= 0 or scene_src.find("Galaxy Rush") >= 0:
		printerr("legacy brand in gameplay_hud.tscn")
		return 1
	if scene_src.find("RIFTWING") < 0:
		printerr("RIFTWING brand missing from gameplay HUD scene")
		return 1
	if scene_src.find("bottom_hud_frame.svg") < 0:
		printerr("bottom_hud_frame missing from gameplay HUD scene")
		return 1
	if scene_src.find("hex_frame.svg") < 0:
		printerr("hex_frame missing from gameplay HUD scene")
		return 1
	if scene_src.find("icon_health.svg") < 0 or scene_src.find("icon_shield.svg") < 0:
		printerr("vitals icons missing from gameplay HUD scene")
		return 1
	print("resources_ok")
	return 0


func _check_runtime() -> int:
	var router := root.get_node("SceneRouter")
	var holder := Node.new()
	root.add_child(holder)
	router.call("configure", holder)
	var fails := 0
	for size in [Vector2i(1080, 1920), Vector2i(1080, 2400), Vector2i(1080, 2478)]:
		DisplayServer.window_set_size(size)
		router.call("go_to", "run", {"sector": 1, "stage_id": "1-1", "fast": true})
		await process_frame
		await process_frame
		await process_frame
		var screen: Node = holder.get_child(0)
		if screen == null:
			printerr("run screen missing at %s" % str(size))
			fails += 1
			continue
		var hud: Node = screen.get_node_or_null("UI/GameplayHUD")
		if hud == null:
			printerr("GameplayHUD missing at %s" % str(size))
			fails += 1
			continue
		var score: Label = hud.get_node_or_null("Safe/Root/Top/ScoreChip/VBox/ScoreValue") as Label
		var pause_btn: Button = hud.get_node_or_null("Safe/Root/Top/PauseCol/PauseShell/PauseButton") as Button
		var health: Control = hud.get_node_or_null("Safe/Root/Bottom/Vitals/Content/VitalsRow/Bars/HealthBar") as Control
		var xp_bar: Control = hud.get_node_or_null("Safe/Root/Bottom/Vitals/Content/VitalsRow/XpCol/EnergyBar") as Control
		var frame: TextureRect = hud.get_node_or_null("Safe/Root/Bottom/Vitals/BottomHudFrame") as TextureRect
		var level_hex: TextureRect = hud.get_node_or_null("Safe/Root/Bottom/Vitals/Content/VitalsRow/LevelBadge/HexBg") as TextureRect
		var left: Control = hud.get_node_or_null("Safe/Root/Bottom/AbilityLeft") as Control
		var right: Control = hud.get_node_or_null("Safe/Root/Bottom/AbilityRight") as Control
		if score == null or pause_btn == null or health == null or xp_bar == null or frame == null or level_hex == null or left == null or right == null:
			printerr("HUD children incomplete at %s" % str(size))
			fails += 1
			continue
		if pause_btn.get_combined_minimum_size().x < 48.0 and pause_btn.size.x < 48.0:
			printerr("pause touch target too small")
			fails += 1
		if left.custom_minimum_size.x < 112.0 or right.custom_minimum_size.x < 112.0:
			printerr("ability buttons too small")
			fails += 1
		# Pause must freeze the tree without stranding SceneRouter.
		hud.call("_on_pause_pressed")
		await process_frame
		if not paused:
			printerr("pause did not pause tree")
			fails += 1
		# Combat lives under the run host; it must not keep can_process while paused
		# (regression: AppRoot ALWAYS + INHERIT left the whole run simulating).
		var player: Node = screen.get_node_or_null("Player")
		if player != null and player.can_process():
			printerr("player still can_process while paused")
			fails += 1
		hud.call("force_resume")
		await process_frame
		if paused:
			printerr("resume left tree paused")
			fails += 1
		print("size_ok %dx%d score=%s" % [size.x, size.y, score.text])
	return fails
