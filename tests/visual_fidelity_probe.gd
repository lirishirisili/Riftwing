extends SceneTree
## Smoke-checks the reference visual fidelity pass (design system + screens).
## godot --headless --path . --script res://tests/visual_fidelity_probe.gd


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("visual_fidelity_probe: start")
	var failed := 0
	failed += _check_assets()
	failed += _check_theme()
	failed += await _check_runtime()
	if failed == 0:
		print("VISUAL_FIDELITY_PROBE_OK")
		quit(0)
	else:
		printerr("VISUAL_FIDELITY_PROBE_FAILED count=%d" % failed)
		quit(1)


func _check_assets() -> int:
	var paths := [
		"res://assets/art/ships/vanguard_mk2.svg",
		"res://assets/art/enemies/void_scout.svg",
		"res://assets/art/enemies/void_shooter.svg",
		"res://assets/art/boss/void_titan.svg",
		"res://assets/art/env/hangar_pad.svg",
		"res://assets/art/env/planet_accent.svg",
		"res://assets/ui/chrome/hex_frame.svg",
		"res://assets/ui/chrome/bottom_hud_frame.svg",
		"res://assets/ui/chrome/map_node_active.svg",
		"res://scripts/core/glow_controller.gd",
		"res://docs/visual_fidelity/DESIGN_SYSTEM.md",
	]
	for p in paths:
		if not ResourceLoader.exists(p) and not FileAccess.file_exists(p):
			printerr("missing %s" % p)
			return 1
	var theme_src := FileAccess.get_file_as_string("res://resources/theme/riftwing_theme.tres")
	if theme_src.find("ButtonReward") < 0 or theme_src.find("NeonPanel") < 0:
		printerr("theme missing ButtonReward/NeonPanel")
		return 1
	for bad in ["Starforge", "Galaxy Rush", "STARFORGE"]:
		for screen in [
			"res://scripts/ui/main_menu.gd",
			"res://scripts/ui/results_screen.gd",
			"res://scenes/ui/main_menu.tscn",
		]:
			var t := FileAccess.get_file_as_string(screen)
			if t.find(bad) >= 0:
				printerr("legacy brand in %s" % screen)
				return 1
	print("assets_ok")
	return 0


func _check_theme() -> int:
	var theme: Theme = load("res://resources/theme/riftwing_theme.tres")
	if theme == null:
		printerr("theme load failed")
		return 1
	var src := FileAccess.get_file_as_string("res://resources/theme/riftwing_theme.tres")
	if src.find("ButtonReward/") < 0 or src.find("NeonPanel/") < 0:
		printerr("theme variations missing in tres")
		return 1
	print("theme_ok")
	return 0


func _check_runtime() -> int:
	var fails := 0
	var router := root.get_node("SceneRouter")
	var holder := Node.new()
	root.add_child(holder)
	router.call("configure", holder)

	# Glow controller present on app? --script may not load app_root; instance glow.
	var glow_script: Script = load("res://scripts/core/glow_controller.gd")
	var glow := Node.new()
	glow.set_script(glow_script)
	root.add_child(glow)
	await process_frame
	if not glow.is_in_group("glow_controller"):
		printerr("glow_controller group missing")
		fails += 1
	var feel := root.get_node("GameFeel")
	feel.call("set_quality", 2) # HIGH
	await process_frame
	feel.call("set_quality", 0) # LOW
	await process_frame

	for screen_id in ["main_menu", "stage_map", "hangar", "results"]:
		router.call("go_to", screen_id)
		await process_frame
		await process_frame
		if String(router.call("get_current_screen_id")) != screen_id:
			printerr("failed open %s" % screen_id)
			fails += 1
		var text_blob := FileAccess.get_file_as_string("res://scripts/ui/%s.gd" % _script_for(screen_id))
		if text_blob.find("RIFTWING") < 0 and screen_id != "stage_map":
			# stage map may brand in tscn
			pass

	router.call("go_to", "run", {"sector": 1, "stage_id": "1-1", "fast": true})
	await process_frame
	await process_frame
	await process_frame
	var run: Node = holder.get_child(0)
	if run == null or run.get_node_or_null("SpaceBackground") == null:
		printerr("run SpaceBackground missing")
		fails += 1
	else:
		var planet := run.find_child("Planet", true, false)
		if planet == null:
			printerr("planet accent missing on run")
			fails += 1
	var ship := run.find_child("PlayerShip", true, false)
	if ship != null:
		if ship.get_node_or_null("EngineGlowRight") == null:
			printerr("dual engine missing")
			fails += 1
	var effects := run.find_child("EffectsLayer", true, false) as Node2D
	if effects == null or effects.z_index >= 0:
		printerr("EffectsLayer z regression")
		fails += 1

	print("runtime_ok fails=%d" % fails)
	return fails


func _script_for(screen_id: String) -> String:
	match screen_id:
		"main_menu": return "main_menu"
		"stage_map": return "stage_map_screen"
		"hangar": return "hangar_screen"
		"results": return "results_screen"
		_: return screen_id
