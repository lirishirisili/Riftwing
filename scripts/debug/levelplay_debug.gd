extends Control
## Development-only LevelPlay verification scene.
##
## Buttons drive each ad format and the LevelPlay Integration Test Suite so the
## integration can be verified on a real device WITHOUT clicking live production
## ads. A log panel mirrors the [LEVELPLAY]/[BANNER]/[INTERSTITIAL]/[REWARDED]
## signal stream. Not part of the shipping navigation graph.

var _log: RichTextLabel
var _status: Label


func _ready() -> void:
	var ads: AdsService = PlatformServices.ads

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 10)
	root.offset_left = 24
	root.offset_top = 48
	root.offset_right = -24
	root.offset_bottom = -24
	add_child(root)

	var title := Label.new()
	title.text = "LEVELPLAY DEBUG"
	title.add_theme_font_size_override("font_size", 40)
	root.add_child(title)

	_status = Label.new()
	_status.text = "available=%s" % str(ads.is_available())
	root.add_child(_status)

	_add_button(root, "Load Interstitial", func(): ads.load_interstitial())
	_add_button(root, "Show Interstitial", func(): _log_line("show_interstitial -> %s" % str(ads.show_interstitial())))
	_add_button(root, "Load Rewarded", func(): ads.load_rewarded())
	_add_button(root, "Show Rewarded", func(): _log_line("show_rewarded -> %s" % str(ads.show_rewarded())))
	_add_button(root, "Show Banner", func(): ads.show_banner())
	_add_button(root, "Hide Banner", func(): ads.hide_banner())
	_add_button(root, "Simulate Run Completed", func(): _log_line("handle_run_completed -> %s" % str(ads.handle_run_completed("debug_%d" % Time.get_ticks_msec()))))
	_add_button(root, "Launch Test Suite", func(): ads.launch_test_suite())

	_log = RichTextLabel.new()
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.scroll_following = true
	root.add_child(_log)

	_connect_ads_signals(ads)
	_log_line("ready. available=%s" % str(ads.is_available()))


func _add_button(parent: Node, label: String, on_press: Callable) -> void:
	var b := Button.new()
	b.text = label
	b.custom_minimum_size = Vector2(0, 64)
	b.pressed.connect(on_press)
	parent.add_child(b)


func _connect_ads_signals(ads: AdsService) -> void:
	ads.initialization_finished.connect(func(ok: bool): _log_line("init finished success=%s" % str(ok)); _refresh_status(ads))
	ads.banner_loaded.connect(func(): _log_line("banner loaded"))
	ads.banner_failed.connect(func(m): _log_line("banner failed: %s" % m))
	ads.interstitial_ready.connect(func(): _log_line("interstitial ready"); _refresh_status(ads))
	ads.interstitial_displayed.connect(func(): _log_line("interstitial displayed"))
	ads.interstitial_closed.connect(func(): _log_line("interstitial closed"); _refresh_status(ads))
	ads.interstitial_failed.connect(func(m): _log_line("interstitial failed: %s" % m))
	ads.rewarded_ready.connect(func(): _log_line("rewarded ready"); _refresh_status(ads))
	ads.rewarded_displayed.connect(func(): _log_line("rewarded displayed"))
	ads.rewarded_earned.connect(func(): _log_line("REWARD EARNED"))
	ads.rewarded_closed.connect(func(): _log_line("rewarded closed"); _refresh_status(ads))
	ads.rewarded_failed.connect(func(m): _log_line("rewarded failed: %s" % m))


func _refresh_status(ads: AdsService) -> void:
	_status.text = "available=%s  interstitial_ready=%s  rewarded_ready=%s" % [
		str(ads.is_available()), str(ads.is_interstitial_ready()), str(ads.is_rewarded_ready())]


func _log_line(text: String) -> void:
	if _log != null:
		_log.add_text("%s\n" % text)
	print("[DEBUG] %s" % text)
