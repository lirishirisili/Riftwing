class_name HangarUpgradeRow
extends PanelContainer
## One hangar upgrade row: icon, title, level, next-benefit preview, cost button.
##
## Purchase uses a two-tap confirm so the player sees the preview before spending.
## The row never spends currency itself — it emits `upgrade_requested` and the
## hangar screen calls SaveManager.try_purchase_upgrade.

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
@onready var _button: Button = %UpgradeButton


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


func _apply_track_chrome() -> void:
	if track == null:
		return
	_title.text = track.title
	if track.icon != null:
		_icon.texture = track.icon
	var accent := Palette.get_color(track.accent_token, Color(0, 0.84, 1))
	_title.add_theme_color_override("font_color", accent)
	_bar.modulate = accent


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
		_button.disabled = true
		_button.text = "LOCKED"
		return

	if _maxed:
		_armed = false
		_button.disabled = true
		_button.text = "MAX"
		return

	_button.disabled = false
	if _armed:
		_button.text = "CONFIRM  %s" % _format_int(cost)
		_button.modulate = Palette.get_color("gold", Color(1, 0.69, 0)) if can_afford else Palette.get_color("danger", Color(1, 0.23, 0.31))
	else:
		_button.text = "UPGRADE  %s" % _format_int(cost)
		_button.modulate = Color.WHITE if can_afford else Color(0.55, 0.55, 0.6, 1)


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
	# Second tap: request the purchase. Hangar clears arm after SaveManager answers.
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
