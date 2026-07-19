class_name HangarScreen
extends Control
## Production ship hangar — visual fidelity pass toward references/03_hangar.png.
##
## Featured ship bay with hangar_pad hologram / engine glow, ship strip with
## locked·equipped states, clearer stat chips, and color-coded upgrade rows.
## Purchase logic stays in SaveManager — this screen only presents and requests.
## Branding is RIFTWING only.

const _CATALOG_PATH := "res://resources/ships/ship_catalog_default.tres"
const _ROW_SCENE := preload("res://scenes/ui/hangar_upgrade_row.tscn")
const _SCROLL_SPEED := 14.0
const _CAPTURE_SIZE := Vector2i(1080, 1920)
const _CAPTURE_PATH := "user://riftwing_hangar_1080x1920.png"

@onready var _shell: MetaScreenShell = %Shell
@onready var _legacy_safe: MarginContainer = %Safe
@onready var _parallax: ParallaxBackground = $Background
@onready var _ship_list: VBoxContainer = %ShipList
@onready var _hero_ship: TextureRect = %HeroShip
@onready var _engine_glow: TextureRect = %EngineGlow
@onready var _hangar_pad: TextureRect = %HangarPad
@onready var _ship_name: Label = %ShipName
@onready var _tier_label: Label = %TierLabel
@onready var _power_label: Label = %PowerLabel
@onready var _lock_banner: Label = %LockBanner
@onready var _attack_value: Label = %AttackValue
@onready var _defense_value: Label = %DefenseValue
@onready var _hp_value: Label = %HpValue
@onready var _crit_value: Label = %CritValue
@onready var _preview_label: Label = %PreviewLabel
@onready var _feedback_label: Label = %FeedbackLabel
@onready var _upgrade_box: VBoxContainer = %UpgradeBox
@onready var _upgrade_all_button: GlowCtaButton = %UpgradeAllButton
@onready var _back_button: GlowCtaButton = %BackButton
@onready var _equip_button: GlowCtaButton = %EquipButton

var _catalog: ShipCatalogData
var _viewed_ship_id: String = ""
var _rows: Dictionary = {} # track_id -> HangarUpgradeRow
var _ship_buttons: Dictionary = {} # ship_id -> Button
var _feedback_tween: Tween
var _hero_time := 0.0


func _ready() -> void:
	_catalog = load(_CATALOG_PATH) as ShipCatalogData
	if _catalog == null:
		_catalog = ShipCatalogData.new()

	_mount_meta_shell()
	_back_button.pressed.connect(_on_back)
	_equip_button.pressed.connect(_on_equip)
	# Placeholder CTA — no Upgrade All economy yet.
	_upgrade_all_button.configure("UPGRADE ALL · SOON", "", GlowCtaButton.Variant.SECONDARY, GlowCtaButton.Pulse.NONE, 88.0)
	_upgrade_all_button.set_enabled(false)
	SaveManager.currencies_changed.connect(_on_currencies_changed)
	SaveManager.hangar_changed.connect(_on_hangar_changed)
	get_viewport().size_changed.connect(_on_viewport_changed)
	_on_viewport_changed()

	_viewed_ship_id = SaveManager.get_selected_ship_id()
	_build_ship_list()
	_build_upgrade_rows()
	_refresh_all()
	GameFeel.debug_markers_enabled = false
	AudioManager.play_music("menu")


func _mount_meta_shell() -> void:
	for path in ["Base", "Background", "VignetteTop", "VignetteBottom"]:
		var n := get_node_or_null(path)
		if n != null:
			n.visible = false
	var root := _legacy_safe.get_node_or_null("Root") as VBoxContainer
	if root == null or _shell == null:
		return
	var body := _shell.get_body()
	var to_move: Array[Node] = []
	for child in root.get_children():
		if child.name != "TopBar":
			to_move.append(child)
	for child in to_move:
		root.remove_child(child)
		body.add_child(child)
		_adopt_owner(child)
	_legacy_safe.visible = false
	if _back_button.get_parent() != null:
		_back_button.get_parent().remove_child(_back_button)
	_back_button.configure("BACK", "", GlowCtaButton.Variant.NAV, GlowCtaButton.Pulse.NONE, 68.0)
	_shell.set_trailing(_back_button)
	_adopt_owner(_back_button)


func _adopt_owner(node: Node) -> void:
	if node is GlowCtaButton:
		node.owner = self
		for child in node.get_children():
			_set_subtree_owner(child, node)
		return
	node.owner = self
	for child in node.get_children():
		_adopt_owner(child)


func _set_subtree_owner(node: Node, new_owner: Node) -> void:
	node.owner = new_owner
	for child in node.get_children():
		_set_subtree_owner(child, new_owner)


func _process(delta: float) -> void:
	if _parallax != null and _parallax.visible:
		_parallax.scroll_offset.y += delta * _SCROLL_SPEED
	_hero_time += delta
	var pulse := 1.0 + sin(_hero_time * 1.45) * 0.02
	_hero_ship.scale = Vector2(pulse, pulse)
	_hero_ship.rotation = sin(_hero_time * 0.5) * 0.03
	_engine_glow.scale = Vector2(0.95 + sin(_hero_time * 3.1) * 0.08, 1.05 + sin(_hero_time * 2.3) * 0.05)
	_engine_glow.modulate.a = 0.5 + sin(_hero_time * 2.8) * 0.22
	var holo := 0.72 + absf(sin(_hero_time * 1.6)) * 0.22
	_hangar_pad.modulate = Color(0.55, 0.95, 1.0, holo)
	_hangar_pad.scale = Vector2(1.0 + sin(_hero_time * 1.2) * 0.035, 1.0 + sin(_hero_time * 1.2) * 0.02)


func handle_system_back() -> bool:
	_on_back()
	return true


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("screenshot_capture"):
		_capture_screenshot()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_G:
		# Prototype QA: grant local currency so upgrade purchases can be tested
		# without forcing a full run first. Not a monetization path.
		SaveManager.debug_add_currency(1000, 0)
		_show_feedback("Debug +1000 Rift Energy", false)
		_refresh_all()
		get_viewport().set_input_as_handled()


# --- Build ------------------------------------------------------------------

func _build_ship_list() -> void:
	for child in _ship_list.get_children():
		child.queue_free()
	_ship_buttons.clear()
	for ship in _catalog.ships:
		if ship == null:
			continue
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(132, 148)
		btn.focus_mode = Control.FOCUS_NONE
		btn.theme_type_variation = &"ButtonTertiary"
		btn.expand_icon = true
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		btn.add_theme_constant_override("icon_max_width", 78)
		btn.add_theme_font_size_override("font_size", 16)
		if ship.portrait != null:
			btn.icon = ship.portrait
		btn.pressed.connect(_on_ship_pressed.bind(ship.id))
		_ship_list.add_child(btn)
		_ship_buttons[ship.id] = btn


func _build_upgrade_rows() -> void:
	for child in _upgrade_box.get_children():
		child.queue_free()
	_rows.clear()
	var ship := _catalog.find_by_id(_viewed_ship_id)
	if ship == null:
		return
	for track in ship.tracks():
		var row: HangarUpgradeRow = _ROW_SCENE.instantiate()
		row.setup(track)
		row.upgrade_requested.connect(_on_upgrade_requested)
		row.confirm_armed.connect(_on_confirm_armed)
		_upgrade_box.add_child(row)
		_rows[track.id] = row


# --- Refresh ----------------------------------------------------------------

func _refresh_all() -> void:
	if _shell != null:
		_shell.refresh_currencies()
	_refresh_ship_list()
	_refresh_ship_panel()
	_refresh_upgrade_rows()


func _refresh_ship_list() -> void:
	var selected := SaveManager.get_selected_ship_id()
	var cyan := Palette.get_color("cyan", Color(0, 0.84, 1))
	for ship in _catalog.ships:
		if ship == null or not _ship_buttons.has(ship.id):
			continue
		var btn: Button = _ship_buttons[ship.id]
		var unlocked := SaveManager.is_ship_unlocked(ship.id)
		var viewing := ship.id == _viewed_ship_id
		var equipped := unlocked and ship.id == selected
		if not unlocked:
			btn.text = "LOCKED"
			btn.modulate = Color(0.5, 0.48, 0.55, 1) * ship.accent_modulate
			btn.self_modulate = Color(0.72, 0.72, 0.78, 1)
		elif equipped:
			btn.text = "EQUIPPED"
			# Strong cyan neon glow so the equipped strip reads like the reference.
			btn.modulate = Color(1.08, 1.12, 1.2, 1) * ship.accent_modulate
			btn.self_modulate = Color(cyan.r * 1.35, cyan.g * 1.2, cyan.b * 1.15, 1.0)
			if viewing:
				btn.self_modulate = Color(cyan.r * 1.55, cyan.g * 1.35, cyan.b * 1.25, 1.0)
		else:
			btn.text = "OWNED"
			btn.modulate = ship.accent_modulate
			btn.self_modulate = Color(cyan.r * 0.85, cyan.g * 0.95, cyan.b, 1.0) if viewing else Color.WHITE


func _refresh_ship_panel() -> void:
	var ship := _catalog.find_by_id(_viewed_ship_id)
	if ship == null:
		_ship_name.text = "UNKNOWN"
		_tier_label.text = ""
		_power_label.text = "POWER  —"
		_lock_banner.visible = true
		_lock_banner.text = "No ship data"
		_equip_button.set_enabled(false)
		return

	var unlocked := SaveManager.is_ship_unlocked(ship.id)
	var levels := SaveManager.get_upgrade_levels(ship.id) if unlocked else {}
	# Locked ships still show base stats (preview), not purchased levels.
	var stats := HangarStats.compute(ship, levels if unlocked else {})
	_ship_name.text = ship.display_name
	_tier_label.text = ship.tier_label
	_power_label.text = "POWER  %s" % _format_int(stats.power())
	_attack_value.text = _format_int(stats.attack)
	_defense_value.text = _format_int(stats.defense)
	_hp_value.text = _format_int(stats.hp)
	_crit_value.text = stats.critical_display()
	if ship.hero_texture != null:
		_hero_ship.texture = ship.hero_texture
	elif ship.portrait != null:
		_hero_ship.texture = ship.portrait
	_hero_ship.modulate = ship.accent_modulate if unlocked else ship.accent_modulate * Color(0.4, 0.4, 0.45, 1)
	_engine_glow.visible = unlocked
	_hangar_pad.modulate.a = 0.9 if unlocked else 0.28

	if unlocked:
		_lock_banner.visible = false
		var is_selected := SaveManager.get_selected_ship_id() == ship.id
		if is_selected:
			_equip_button.configure("EQUIPPED", "", GlowCtaButton.Variant.SECONDARY, GlowCtaButton.Pulse.NONE, 96.0)
			_equip_button.set_enabled(false)
		else:
			_equip_button.configure("EQUIP SHIP", "", GlowCtaButton.Variant.PRIMARY, GlowCtaButton.Pulse.CYAN, 96.0)
			_equip_button.set_enabled(true)
	else:
		_lock_banner.visible = true
		_lock_banner.text = "LOCKED  ·  %s" % ship.unlock_hint
		_equip_button.configure("LOCKED", "", GlowCtaButton.Variant.NAV, GlowCtaButton.Pulse.NONE, 96.0)
		_equip_button.set_enabled(false)


func _refresh_upgrade_rows() -> void:
	var ship := _catalog.find_by_id(_viewed_ship_id)
	if ship == null:
		return
	# Rebuild rows when switching ships (tracks differ per ShipData).
	var needs_rebuild := _rows.is_empty()
	if not needs_rebuild:
		for track in ship.tracks():
			if not _rows.has(track.id):
				needs_rebuild = true
				break
	if needs_rebuild:
		_build_upgrade_rows()

	var unlocked := SaveManager.is_ship_unlocked(ship.id)
	var levels := SaveManager.get_upgrade_levels(ship.id) if unlocked else {}
	var energy := SaveManager.get_rift_energy()
	for track in ship.tracks():
		if not _rows.has(track.id):
			continue
		var row: HangarUpgradeRow = _rows[track.id]
		var level := int(levels.get(track.id, 0))
		var cost := track.cost_for_next_level(level)
		var can_afford := unlocked and cost >= 0 and energy >= cost
		row.refresh(level, maxi(0, cost), can_afford, not unlocked)


# --- Interactions -----------------------------------------------------------

func _on_ship_pressed(ship_id: String) -> void:
	_clear_all_arms()
	_viewed_ship_id = ship_id
	_click()
	_refresh_all()
	_preview_label.text = "Tap a ship to inspect. Equip unlocked ships. Locked ships have no purchase path."
	_preview_label.add_theme_color_override("font_color", Palette.get_color("muted", Color(0.46, 0.57, 0.71)))


func _on_equip() -> void:
	if SaveManager.select_ship(_viewed_ship_id):
		_click()
		_show_feedback("Equipped %s" % _viewed_ship_id, false)
		_refresh_all()
	else:
		_show_feedback("Ship is locked", true)


func _on_confirm_armed(track_id: String) -> void:
	# Only one row stays armed at a time.
	for id in _rows:
		if id != track_id:
			(_rows[id] as HangarUpgradeRow).clear_arm()
	var ship := _catalog.find_by_id(_viewed_ship_id)
	if ship == null:
		return
	var track := ship.track_by_id(track_id)
	if track == null:
		return
	var levels := SaveManager.get_upgrade_levels(ship.id)
	var current := HangarStats.compute(ship, levels)
	var preview := HangarStats.preview_after(ship, levels, track_id)
	_preview_label.text = "PREVIEW  ATK %d→%d  DEF %d→%d  HP %d→%d  CRIT %s→%s" % [
		current.attack, preview.attack,
		current.defense, preview.defense,
		current.hp, preview.hp,
		current.critical_display(), preview.critical_display(),
	]
	_preview_label.add_theme_color_override("font_color", Palette.get_color("gold", Color(1, 0.69, 0)))


func _on_upgrade_requested(track_id: String) -> void:
	var ship := _catalog.find_by_id(_viewed_ship_id)
	if ship == null:
		return
	var track := ship.track_by_id(track_id)
	if track == null:
		return
	var ok := SaveManager.try_purchase_upgrade(ship.id, track)
	_clear_all_arms()
	if ok:
		_click()
		var haptics: HapticsService = PlatformServices.haptics
		if haptics != null and GameFeel.haptics_enabled:
			haptics.medium()
		_show_feedback("%s upgraded" % track.title, false)
		_preview_label.text = "Upgrade applied. Stats updated."
		_preview_label.add_theme_color_override("font_color", Palette.get_color("green", Color(0.21, 0.89, 0.44)))
	else:
		AudioManager.play_sfx("ui_back", Vector2.ZERO, AudioManager.PRIORITY_LOW)
		_show_feedback("Not enough Rift Energy", true)
		_preview_label.text = "Need more Rift Energy — finish a run to earn more."
		_preview_label.add_theme_color_override("font_color", Palette.get_color("danger", Color(1, 0.23, 0.31)))
	_refresh_all()


func _clear_all_arms() -> void:
	for id in _rows:
		(_rows[id] as HangarUpgradeRow).clear_arm()


func _on_back() -> void:
	AudioManager.play_sfx("ui_back", Vector2.ZERO, AudioManager.PRIORITY_MEDIUM)
	SceneRouter.go_to(SceneRouter.SCREEN_MAIN_MENU)


func _on_currencies_changed(_energy: int, _core: int) -> void:
	if _shell != null:
		_shell.refresh_currencies()
	_refresh_upgrade_rows()


func _on_hangar_changed(_selected: String) -> void:
	_refresh_all()


func _click() -> void:
	AudioManager.play_sfx("ui_confirm", Vector2.ZERO, AudioManager.PRIORITY_MEDIUM)
	var haptics: HapticsService = PlatformServices.haptics
	if haptics != null and GameFeel.haptics_enabled:
		haptics.light()


func _show_feedback(text: String, is_error: bool) -> void:
	_feedback_label.text = text
	_feedback_label.add_theme_color_override(
		"font_color",
		Palette.get_color("danger", Color(1, 0.23, 0.31)) if is_error else Palette.get_color("green", Color(0.21, 0.89, 0.44)))
	_feedback_label.modulate.a = 1.0
	if _feedback_tween != null:
		_feedback_tween.kill()
	_feedback_tween = create_tween()
	_feedback_tween.tween_interval(1.4)
	_feedback_tween.tween_property(_feedback_label, "modulate:a", 0.0, 0.45)


func _format_int(value: int) -> String:
	var s := str(absi(value))
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if value < 0 else "") + out


func _on_viewport_changed() -> void:
	call_deferred("_recenter_hero_pivot")


func _recenter_hero_pivot() -> void:
	if _hero_ship != null:
		_hero_ship.pivot_offset = _hero_ship.size * 0.5
	if _engine_glow != null:
		_engine_glow.pivot_offset = _engine_glow.size * 0.5
	if _hangar_pad != null:
		_hangar_pad.pivot_offset = _hangar_pad.size * 0.5


func _capture_screenshot() -> void:
	var tree := get_tree()
	var debuggers := tree.get_nodes_in_group("debug_ui")
	var restore: Array = []
	for node in debuggers:
		if "visible" in node:
			restore.append([node, node.visible])
			node.visible = false
	var prev_size := DisplayServer.window_get_size()
	DisplayServer.window_set_size(_CAPTURE_SIZE)
	await tree.process_frame
	await tree.process_frame
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(_CAPTURE_PATH)
	if err != OK:
		push_warning("HangarScreen: screenshot save failed (%d)" % err)
	else:
		print("HangarScreen: saved %dx%d screenshot to %s" % [
			image.get_width(), image.get_height(), _CAPTURE_PATH])
	DisplayServer.window_set_size(prev_size)
	for entry in restore:
		entry[0].visible = entry[1]
