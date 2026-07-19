extends SceneTree
## Validates production main menu branding, hierarchy, and navigation.
## godot --headless --path . --script res://tests/main_menu_probe.gd


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("main_menu_probe: start")
	var failed := 0
	failed += _check_resources()
	failed += await _check_runtime()
	if failed == 0:
		print("MAIN_MENU_PROBE_OK")
		quit(0)
	else:
		printerr("MAIN_MENU_PROBE_FAILED count=%d" % failed)
		quit(1)


func _check_resources() -> int:
	var scene_src := FileAccess.get_file_as_string("res://scenes/ui/main_menu.tscn")
	var script_src := FileAccess.get_file_as_string("res://scripts/ui/main_menu.gd")
	var theme_src := FileAccess.get_file_as_string("res://resources/theme/riftwing_theme.tres")
	for blob in [scene_src, script_src]:
		if blob.find("Starforge") >= 0 or blob.find("Galaxy Rush") >= 0 or blob.find("STARFORGE") >= 0:
			printerr("legacy brand found in main menu sources")
			return 1
	if scene_src.find("RIFTWING") < 0:
		printerr("RIFTWING missing from main menu scene")
		return 1
	if theme_src.find("ButtonPrimary") < 0 or theme_src.find("ButtonSecondary") < 0 or theme_src.find("ButtonTertiary") < 0:
		printerr("theme missing primary/secondary/tertiary button variations")
		return 1
	if theme_src.find("ButtonChrome") < 0:
		printerr("theme missing ButtonChrome empty-style variation")
		return 1
	if scene_src.find("glow_cta_button") < 0:
		printerr("main menu CTA stack not using GlowCtaButton")
		return 1
	for path in [
		"res://assets/backgrounds/menu_space_keyart.png",
		"res://assets/branding/logo_riftwing.png",
		"res://assets/art/ships/hero_vanguard_menu.png",
		"res://assets/ui/chrome/cta_start_hex.svg",
		"res://assets/ui/chrome/cta_daily_bar.svg",
		"res://assets/ui/chrome/cta_nav_hex.svg",
		"res://scenes/ui/chrome/glow_cta_button.tscn",
		"res://scenes/ui/chrome/meta_screen_shell.tscn",
		"res://assets/ui/chrome/menu_header_frame.svg",
		"res://assets/art/env/hangar_pad.svg",
		"res://assets/icons/icon_event_void.svg",
	]:
		if not ResourceLoader.exists(path):
			printerr("missing main menu chrome asset: %s" % path)
			return 1
	if scene_src.find("HoloPad") < 0 or scene_src.find("menu_space_keyart") < 0:
		printerr("main menu missing keyart / holo pad wiring")
		return 1
	if scene_src.find("logo_riftwing") < 0 or scene_src.find("hero_vanguard_menu") < 0:
		printerr("main menu missing logo / hero art wiring")
		return 1
	if scene_src.find("ENDLESS MODE") < 0:
		printerr("main menu missing START RUN endless copy")
		return 1
	print("resources_ok")
	return 0


func _check_runtime() -> int:
	var router := root.get_node("SceneRouter")
	var holder := Node.new()
	root.add_child(holder)
	router.call("configure", holder)
	var fails := 0
	# 9:16 phones, tall phones, and wider tablet portrait (expand stretch).
	for size in [Vector2i(1080, 1920), Vector2i(1080, 2400), Vector2i(1080, 2478), Vector2i(1600, 2560)]:
		DisplayServer.window_set_size(size)
		router.call("go_to", "main_menu")
		await process_frame
		await process_frame
		await process_frame
		if String(router.call("get_current_screen_id")) != "main_menu":
			printerr("main_menu not active @ %s" % str(size))
			fails += 1
			continue
		var menu: Node = holder.get_child(0)
		if menu == null:
			printerr("menu node missing")
			fails += 1
			continue
		var title: Label = menu.get_node_or_null("%Title") as Label
		var start: Control = menu.get_node_or_null("%StartButton") as Control
		var daily: Control = menu.get_node_or_null("%DailyButton") as Control
		var ships: Control = menu.get_node_or_null("%ShipsButton") as Control
		var upgrades: Control = menu.get_node_or_null("%UpgradesButton") as Control
		var settings: Button = menu.get_node_or_null("%SettingsButton") as Button
		var hero: TextureRect = menu.get_node_or_null("%HeroShip") as TextureRect
		var pad: TextureRect = menu.get_node_or_null("%HoloPad") as TextureRect
		var timer: Label = menu.get_node_or_null("%EventTimer") as Label
		if title == null or start == null or daily == null or ships == null or upgrades == null or settings == null or hero == null:
			printerr("menu controls incomplete @ %s" % str(size))
			fails += 1
			continue
		if not (start is GlowCtaButton) or not (daily is GlowCtaButton):
			printerr("primary CTAs are not GlowCtaButton @ %s" % str(size))
			fails += 1
		if title.text != "RIFTWING":
			printerr("title is not RIFTWING: %s" % title.text)
			fails += 1
		if start.custom_minimum_size.y < daily.custom_minimum_size.y:
			printerr("primary CTA is not taller than daily")
			fails += 1
		if hero.texture == null:
			printerr("hero ship texture missing")
			fails += 1
		if pad == null or pad.texture == null:
			printerr("holo pad missing")
			fails += 1
		if timer == null or timer.text.strip_edges() == "":
			printerr("event timer chrome missing")
			fails += 1
		var feel := root.get_node("GameFeel")
		if bool(feel.get("debug_markers_enabled")):
			printerr("debug markers left enabled on main menu")
			fails += 1
		# CTAs must sit fully inside the viewport (SafeArea must not crush the stack).
		var ships_bottom := ships.global_position.y + ships.size.y
		var view_h := float(menu.get_viewport_rect().size.y)
		if ships_bottom > view_h - 24.0:
			printerr("SHIPS clipped at bottom: ships_bottom=%.0f view_h=%.0f" % [ships_bottom, view_h])
			fails += 1
		var safe_m: Control = menu.get_node_or_null("Safe") as Control
		if safe_m != null and safe_m.get_theme_constant("margin_bottom") > 160:
			printerr("safe bottom margin too large: %d" % safe_m.get_theme_constant("margin_bottom"))
			fails += 1
		# With expand stretch, wider windows grow the logical viewport (no black bars).
		var logical_size: Vector2 = menu.get_viewport_rect().size
		var logical_w: float = logical_size.x
		if size.x > 1080 and logical_w <= 1080.0:
			printerr("expand stretch not widening viewport @ %s logical_w=%.0f" % [str(size), logical_w])
			fails += 1
		print("size_ok %dx%d logical_w=%.0f title=%s start_h=%.0f ships_bottom=%.0f" % [
			size.x, size.y, logical_w, title.text, start.custom_minimum_size.y, ships_bottom])

	# Navigation smoke.
	router.call("go_to", "main_menu")
	await process_frame
	var menu2: Node = holder.get_child(0)
	menu2.call("_on_start_run")
	await process_frame
	await process_frame
	if String(router.call("get_current_screen_id")) != "stage_map":
		printerr("Start Run did not open stage_map")
		fails += 1
	router.call("go_to", "main_menu")
	await process_frame
	menu2 = holder.get_child(0)
	menu2.call("_on_ships")
	await process_frame
	await process_frame
	if String(router.call("get_current_screen_id")) != "hangar":
		printerr("Ships did not open hangar")
		fails += 1
	router.call("go_to", "main_menu")
	await process_frame
	menu2 = holder.get_child(0)
	menu2.call("_on_settings")
	await process_frame
	await process_frame
	if String(router.call("get_current_screen_id")) != "settings":
		printerr("Settings navigation broken")
		fails += 1
	return fails
