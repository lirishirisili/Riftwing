extends SceneTree
## Validates GlowCtaButton + MetaScreenShell kit assets.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("glow_ui_kit_probe: start")
	for path in [
		"res://scenes/ui/chrome/glow_cta_button.tscn",
		"res://scenes/ui/chrome/meta_screen_shell.tscn",
		"res://scripts/ui/chrome/glow_cta_button.gd",
		"res://scripts/ui/chrome/meta_screen_shell.gd",
		"res://assets/ui/chrome/cta_start_hex.svg",
		"res://assets/ui/chrome/cta_daily_bar.svg",
		"res://assets/ui/chrome/cta_nav_hex.svg",
		"res://assets/ui/chrome/menu_header_frame.svg",
	]:
		if not ResourceLoader.exists(path):
			printerr("missing kit asset: %s" % path)
			quit(1)
			return

	var glow_script := load("res://scripts/ui/chrome/glow_cta_button.gd") as Script
	var shell_script := load("res://scripts/ui/chrome/meta_screen_shell.gd") as Script
	if glow_script == null or shell_script == null:
		printerr("failed to load kit scripts")
		quit(1)
		return

	var glow_scene := load("res://scenes/ui/chrome/glow_cta_button.tscn") as PackedScene
	var shell_scene := load("res://scenes/ui/chrome/meta_screen_shell.tscn") as PackedScene
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.size = Vector2(1080, 1920)
	root.add_child(shell_scene.instantiate())
	get_root().add_child(root)
	await process_frame

	var shell: Node = root.get_child(0)
	var body: VBoxContainer = shell.call("get_body") as VBoxContainer
	if body == null:
		printerr("MetaScreenShell missing Body")
		quit(1)
		return

	var primary: Control = glow_scene.instantiate() as Control
	body.add_child(primary)
	primary.call("configure", "LAUNCH", "ENTER STAGE", 0, 1)
	await process_frame
	if primary.custom_minimum_size.y < 140.0:
		printerr("primary CTA height too small")
		quit(1)
		return

	var nav: Control = glow_scene.instantiate() as Control
	body.add_child(nav)
	nav.call("configure", "BACK", "", 2, 0)
	await process_frame
	if nav.custom_minimum_size.y < 96.0:
		printerr("nav CTA height too small")
		quit(1)
		return

	print("GLOW_UI_KIT_PROBE_OK")
	quit(0)
