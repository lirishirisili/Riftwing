extends SceneTree
## Captures 1080×1920 review screenshots and validates brand / color roles.
## Capture requires a real renderer (not --headless dummy):
##   godot --path . --window-size 1080,1920 --script res://tests/visual_review_probe.gd
## Brand/color checks alone work under --headless.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("visual_review_probe: start")
	var failed := 0
	failed += _check_brand_and_colors()
	failed += await _capture_screens()
	if failed == 0:
		print("VISUAL_REVIEW_PROBE_OK")
		quit(0)
	else:
		printerr("VISUAL_REVIEW_PROBE_FAILED count=%d" % failed)
		quit(1)


func _check_brand_and_colors() -> int:
	# No legacy brand strings in production UI scripts/scenes.
	var forbidden := ["STARFORGE", "GALAXY RUSH", "Starforge", "Galaxy Rush"]
	var paths := [
		"res://scripts/ui/main_menu.gd",
		"res://scripts/ui/results_screen.gd",
		"res://scripts/ui/hangar_screen.gd",
		"res://scripts/ui/stage_map_screen.gd",
		"res://scenes/ui/main_menu.tscn",
		"res://scenes/ui/results_screen.tscn",
	]
	for path in paths:
		var text := FileAccess.get_file_as_string(path)
		for bad in forbidden:
			if text.find(bad) >= 0:
				printerr("legacy brand in %s: %s" % [path, bad])
				return 1
	var player: ProjectileData = load("res://resources/weapons/plasma_projectile.tres")
	var enemy: ProjectileData = load("res://resources/weapons/enemy_plasma_projectile.tres")
	if player == null or enemy == null:
		printerr("projectile resources missing")
		return 1
	# Player should be cyan-forward; enemy purple/magenta-forward.
	if player.color.b < 0.7 or player.color.g < 0.5:
		printerr("player bolt not cyan enough")
		return 1
	if enemy.color.r > 0.95 and enemy.color.g > 0.35 and enemy.color.b < 0.4:
		printerr("enemy bolt still orange-hazard role")
		return 1
	if enemy.color.b < 0.55:
		printerr("enemy bolt not purple/magenta enough")
		return 1
	print("brand_color_ok player=%s enemy=%s" % [player.color, enemy.color])
	return 0


func _capture_screens() -> int:
	# Dummy / headless renderer cannot read back viewport textures.
	if DisplayServer.get_name() == "headless" or OS.has_feature("headless"):
		print("capture_skipped (no GPU readback; re-run without --headless)")
		return await _smoke_portrait_sizes()
	DisplayServer.window_set_size(Vector2i(1080, 1920))
	var holder := Node.new()
	root.add_child(holder)
	var router := root.get_node("SceneRouter")
	router.call("configure", holder)

	var screens := [
		["main_menu", "user://review_main_menu_1080x1920.png"],
		["hangar", "user://review_hangar_1080x1920.png"],
		["stage_map", "user://review_stage_map_1080x1920.png"],
		["results", "user://review_results_1080x1920.png"],
	]
	for entry in screens:
		router.call("go_to", entry[0])
		await process_frame
		await process_frame
		await process_frame
		# Hide debug overlay if present.
		for node in get_nodes_in_group("debug_ui"):
			if "visible" in node:
				node.visible = false
		await process_frame
		var img: Image = root.get_texture().get_image()
		if img == null:
			printerr("capture failed for %s" % entry[0])
			return 1
		# Ensure portrait review size (stretch may keep logical size).
		if img.get_width() != 1080 or img.get_height() != 1920:
			img.resize(1080, 1920, Image.INTERPOLATE_BILINEAR)
		var err: Error = img.save_png(entry[1])
		if err != OK:
			printerr("save failed %s (%d)" % [entry[1], err])
			return 1
		# Convenience copy next to the gap report for side-by-side review.
		var copy_path := "res://docs/visual_review/%s" % entry[1].get_file()
		img.save_png(copy_path)
		print("captured %s -> %s (%dx%d)" % [
			entry[0], entry[1], img.get_width(), img.get_height()])
	var size_failed := await _smoke_portrait_sizes_with_router(router)
	return size_failed


func _smoke_portrait_sizes() -> int:
	var holder := Node.new()
	root.add_child(holder)
	var router := root.get_node("SceneRouter")
	router.call("configure", holder)
	return await _smoke_portrait_sizes_with_router(router)


func _smoke_portrait_sizes_with_router(router: Node) -> int:
	# 9:16, 19.5:9, 20:9 logical portrait widths at 1080 base.
	var sizes: Array[Vector2i] = [
		Vector2i(1080, 1920),
		Vector2i(1080, 2340),
		Vector2i(1080, 2400),
		Vector2i(1080, 2478),
	]
	var screen_ids := ["main_menu", "hangar", "stage_map", "results"]
	for size in sizes:
		DisplayServer.window_set_size(size)
		for screen_id in screen_ids:
			router.call("go_to", screen_id)
			await process_frame
			await process_frame
			var current: String = str(router.call("get_current_screen_id"))
			if current != screen_id:
				printerr("screen mismatch want=%s got=%s @ %s" % [screen_id, current, size])
				return 1
		print("portrait_ok %dx%d" % [size.x, size.y])
	return 0
