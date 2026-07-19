class_name HangarUpgradeRow
extends PanelContainer
## One hangar upgrade row: icon, title, level, next-benefit preview, cost button.
##
## Purchase uses a two-tap confirm so the player sees the preview before spending.
## The row never spends currency itself — it emits `upgrade_requested` and the
## hangar screen calls SaveManager.try_purchase_upgrade.
## Track chrome is color-coded: weapons purple, shield/engine cyan, drones green,
## ultimate orange. UPGRADE uses compact nav GlowCta.

signal upgrade_requested(track_id: String)
signal confirm_armed(track_id: String)

const _TOUCH_MIN := Vector2(0, 96)

var track: HangarUpgradeTrackData
var _level: int = 0
var _cost: int = 0
var _can_afford: bool = false
var _maxed: bool = false
var _locked_ship: bool = false
var _armed: bool = false

@onready var _icon: TextureRect = %Icon
@onready var _title: Label = %Title
@onready var _level_label: Label = %LevelLabel
@onready var _benefit: Label = %Benefit
@onready var _bar: ProgressBar = %Bar
@onready var _button: GlowCtaButton = %UpgradeButton


func _ready() -> void:
	custom_minimum_size = _TOUCH_MIN
	_button.pressed.connect(_on_button_pressed)
	if track != null:
		_apply_track_chrome()
		refresh(_level, _cost, _can_afford, _locked_ship)


func setup(track_data: HangarUpgradeTrackData) -> void:
	track = track_data
	if is_node_ready():
		_apply_track_chrome()


func _track_accent() -> Color:
	if track == null:
		return Palette.get_color("cyan", Color(0, 0.84, 1))
	match track.category:
		HangarUpgradeTrackData.Category.WEAPONS:
			return Palette.get_color("purple", Color(0.55, 0.26, 1))
		HangarUpgradeTrackData.Category.SHIELD, HangarUpgradeTrackData.Category.ENGINE:
			return Palette.get_color("cyan", Color(0, 0.84, 1))
		HangarUpgradeTrackData.Category.DRONES:
			return Palette.get_color("green", Color(0.21, 0.89, 0.44))
		HangarUpgradeTrackData.Category.ULTIMATE:
			return Palette.get_color("orange", Color(1, 0.48, 0.1))
		_:
			return Palette.get_color(track.accent_token, Color(0, 0.84, 1))


func _apply_track_chrome() -> void:
	if track == null:
		return
	_title.text = track.title
	if track.icon != null:
		_icon.texture = track.icon
	var accent := _track_accent()
	_title.add_theme_color_override("font_color", accent)
	_benefit.add_theme_color_override("font_color", accent.lightened(0.15))
	_bar.modulate = accent
	modulate = Color(
		lerpf(1.0, accent.r, 0.12),
		lerpf(1.0, accent.g, 0.12),
		lerpf(1.0, accent.b, 0.12),
		1.0)
	var style := get_theme_stylebox("panel")
	if style is StyleBoxFlat:
		var flat := (style as StyleBoxFlat).duplicate() as StyleBoxFlat
		flat.border_width_left = 5
		flat.border_width_top = 2
		flat.border_width_right = 2
		flat.border_width_bottom = 2
		flat.border_color = Color(accent.r, accent.g, accent.b, 0.85)
		flat.shadow_color = Color(accent.r, accent.g, accent.b, 0.28)
		flat.shadow_size = 6
		add_theme_stylebox_override("panel", flat)
	var fill := _bar.get_theme_stylebox("fill")
	if fill is StyleBoxFlat:
		var fill_flat := (fill as StyleBoxFlat).duplicate() as StyleBoxFlat
		fill_flat.bg_color = accent
		_bar.add_theme_stylebox_override("fill", fill_flat)


## Updates level / cost / affordability without rebuilding the row.
func refresh(level: int, cost: int, can_afford: bool, ship_locked: bool) -> void:
	_level = level
	_cost = cost
	_can_afford = can_afford
	_locked_ship = ship_locked
	_maxed = track != null and level >= track.max_level
	if not is_node_ready():
		return

	var max_level := track.max_level if track != null else 1
	_level_label.text = "LVL %d/%d" % [level, max_level]
	_bar.max_value = float(max_level)
	_bar.value = float(level)
	_benefit.text = track.next_benefit_label() if track != null and not _maxed else "MAXED"

	if _locked_ship:
		_armed = false
		_button.configure("LOCKED", "", GlowCtaButton.Variant.NAV, GlowCtaButton.Pulse.NONE, 76.0)
		_button.set_enabled(false)
		return

	if _maxed:
		_armed = false
		_button.configure("MAX", "", GlowCtaButton.Variant.NAV, GlowCtaButton.Pulse.NONE, 76.0)
		_button.set_enabled(false)
		return

	_button.set_enabled(true)
	if _armed:
		_button.configure(
			"BUY  %s" % _format_int(cost),
			"",
			GlowCtaButton.Variant.PRIMARY,
			GlowCtaButton.Pulse.NONE,
			76.0)
		_button.chrome_modulate = (
			Palette.get_color("gold", Color(1, 0.69, 0))
			if can_afford
			else Palette.get_color("danger", Color(1, 0.23, 0.31)))
	else:
		_button.configure(
			"UP  %s" % _format_int(cost),
			"",
			GlowCtaButton.Variant.NAV,
			GlowCtaButton.Pulse.NONE,
			76.0)
		var accent := _track_accent()
		_button.chrome_modulate = (
			Color(lerpf(1.0, accent.r, 0.35), lerpf(1.0, accent.g, 0.35), lerpf(1.0, accent.b, 0.35), 1.0)
			if can_afford
			else Color(0.55, 0.55, 0.6, 1))


func clear_arm() -> void:
	if not _armed:
		return
	_armed = false
	refresh(_level, _cost, _can_afford, _locked_ship)


func _on_button_pressed() -> void:
	if _locked_ship or _maxed or track == null:
		return
	if not _armed:
		_armed = true
		refresh(_level, _cost, _can_afford, _locked_ship)
		confirm_armed.emit(track.id)
		AudioManager.play_sfx("ui_confirm", Vector2.ZERO, AudioManager.PRIORITY_LOW)
		return
	upgrade_requested.emit(track.id)


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
