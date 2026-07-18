class_name UpgradeCard
extends Button
## Production upgrade-choice card (prompts/20_upgrade_cards_production.md).
##
## Rarity frame (rare=cyan / epic=purple / legendary=gold) with hex icon plate,
## NEW badge, and clear rarity pill. Entrance and selection animations use
## pause-independent tweens so they play while combat is frozen. Does not apply
## upgrades — the screen owns that.

signal chosen(upgrade: UpgradeData)

const _FRAME_PATHS := {
	UpgradeData.Rarity.RARE: "res://assets/ui/upgrade_card_rare.svg",
	UpgradeData.Rarity.EPIC: "res://assets/ui/upgrade_card_epic.svg",
	UpgradeData.Rarity.LEGENDARY: "res://assets/ui/upgrade_card_legendary.svg",
}

const _ICON_WEAPON := "res://assets/icons/icon_missile.svg"
const _ICON_POWER := "res://assets/icons/icon_energy.svg"
const _ICON_FIRE := "res://assets/icons/icon_laser.svg"
const _ICON_DRONE := "res://assets/icons/icon_drone.svg"

@onready var _glow: ColorRect = %Glow
@onready var _glow_inner: ColorRect = %GlowInner
@onready var _frame: TextureRect = %Frame
@onready var _rarity_label: Label = %Rarity
@onready var _rarity_badge: PanelContainer = %RarityBadge
@onready var _hex_frame: TextureRect = %HexFrame
@onready var _icon: TextureRect = %Icon
@onready var _title: Label = %Title
@onready var _description: Label = %Description
@onready var _level: Label = %Level
@onready var _new_badge: Label = %NewBadge
@onready var _category: Label = %Category
@onready var _category_icon: TextureRect = %CategoryIcon
@onready var _category_hex: TextureRect = %CategoryHex

var _upgrade: UpgradeData
var _accent: Color = Color(0, 0.84, 1, 1)
var _anim: Tween
var _pulse_time := 0.0
var _pressing := false
var _glow_boost := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	pivot_offset = size * 0.5
	pressed.connect(_on_pressed)
	button_down.connect(_on_button_down)
	button_up.connect(_on_button_up)
	mouse_entered.connect(_on_hover_enter)
	mouse_exited.connect(_on_hover_exit)
	set_process(true)


func _process(delta: float) -> void:
	_pulse_time += delta
	if _glow == null:
		return
	var base := 0.36
	var amp := 0.14
	var speed := 2.0
	if _upgrade != null:
		match _upgrade.rarity:
			UpgradeData.Rarity.LEGENDARY:
				base = 0.48
				amp = 0.3
				speed = 2.5
			UpgradeData.Rarity.EPIC:
				base = 0.42
				amp = 0.2
				speed = 2.2
			_:
				base = 0.38
				amp = 0.16
				speed = 2.0
	if _pressing:
		_glow.modulate.a = 0.72
		if _glow_inner != null:
			_glow_inner.modulate.a = 0.8
		return
	var pulse := base + absf(sin(_pulse_time * speed)) * amp + _glow_boost
	_glow.modulate.a = pulse
	if _glow_inner != null:
		_glow_inner.modulate.a = 0.4 + absf(sin(_pulse_time * speed * 0.85)) * 0.25 + _glow_boost * 0.5
	if _hex_frame != null:
		_hex_frame.modulate.a = 0.85 + absf(sin(_pulse_time * speed * 0.9)) * 0.15


## Fills the card from an UpgradeData and the level it would become if chosen.
func populate(upgrade: UpgradeData, next_level: int, synergy_hint: String = "") -> void:
	_upgrade = upgrade
	_accent = Palette.get_color(upgrade.rarity_color_token())
	if _FRAME_PATHS.has(upgrade.rarity):
		_frame.texture = load(_FRAME_PATHS[upgrade.rarity])
	_rarity_label.text = upgrade.rarity_label()
	_rarity_label.add_theme_color_override("font_color", _accent)
	_apply_badge_style(_rarity_badge, _accent)
	_glow.color = Color(_accent.r, _accent.g, _accent.b, 0.42)
	if _glow_inner != null:
		_glow_inner.color = Color(_accent.r, _accent.g, _accent.b, 0.22)
	if _hex_frame != null:
		_hex_frame.modulate = Color(_accent.r, _accent.g, _accent.b, 1.0)
	_icon.texture = upgrade.icon
	_icon.modulate = Color(1, 1, 1, 1)
	_title.text = upgrade.title
	_title.add_theme_color_override("font_color", _accent)
	if synergy_hint.strip_edges() != "":
		_description.text = "%s\n◆ %s" % [upgrade.description, synergy_hint]
		_description.add_theme_color_override("font_color", Palette.get_color("green", Color(0.3, 0.95, 0.55)))
	else:
		_description.text = upgrade.description
		_description.remove_theme_color_override("font_color")
	var is_new := next_level <= 1
	_new_badge.visible = is_new
	_new_badge.text = "NEW"
	_new_badge.add_theme_color_override("font_color", _accent)
	if upgrade.max_level > 1:
		_level.text = "LV %d / %d" % [next_level, upgrade.max_level]
	else:
		_level.text = "UNLOCK"
	var cat := _category_for(upgrade)
	_category.text = cat
	_category_icon.texture = load(_category_icon_path(cat)) as Texture2D
	_category_icon.modulate = _accent
	if _category_hex != null:
		_category_hex.modulate = Color(_accent.r, _accent.g, _accent.b, 0.95)


func _apply_badge_style(panel: PanelContainer, accent: Color) -> void:
	if panel == null:
		return
	var style := panel.get_theme_stylebox("panel")
	if style is StyleBoxFlat:
		var flat := (style as StyleBoxFlat).duplicate() as StyleBoxFlat
		flat.border_color = Color(accent.r, accent.g, accent.b, 0.98)
		flat.shadow_color = Color(accent.r, accent.g, accent.b, 0.55)
		flat.shadow_size = 10
		flat.bg_color = Color(accent.r * 0.08, accent.g * 0.08, accent.b * 0.12, 0.94)
		panel.add_theme_stylebox_override("panel", flat)


func _category_for(upgrade: UpgradeData) -> String:
	if upgrade == null or upgrade.effects.is_empty():
		return "BOOST"
	var kind: int = upgrade.effects[0].kind
	match kind:
		UpgradeEffectData.Kind.ACQUIRE_WEAPON:
			if upgrade.id.find("drone") >= 0:
				return "DRONE"
			return "WEAPON"
		UpgradeEffectData.Kind.PROJECTILES_ADD, UpgradeEffectData.Kind.SPREAD_ADD:
			return "FIRE"
		_:
			return "POWER"


func _category_icon_path(category: String) -> String:
	match category:
		"WEAPON":
			return _ICON_WEAPON
		"DRONE":
			return _ICON_DRONE
		"FIRE":
			return _ICON_FIRE
		_:
			return _ICON_POWER


## Entrance: scale + fade, staggered by the screen.
func kill_anims() -> void:
	if _anim != null and _anim.is_valid():
		_anim.kill()
	_anim = null
	modulate = Color.WHITE
	scale = Vector2.ONE


func animate_in(delay: float = 0.0) -> void:
	pivot_offset = size * 0.5
	scale = Vector2(0.9, 0.9)
	modulate.a = 0.0
	if _anim != null and _anim.is_valid():
		_anim.kill()
	_anim = create_tween().set_ignore_time_scale(true)
	_anim.tween_interval(delay)
	_anim.tween_property(self, "modulate:a", 1.0, 0.18)
	_anim.parallel().tween_property(self, "scale", Vector2.ONE, 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func get_upgrade() -> UpgradeData:
	return _upgrade


func _on_pressed() -> void:
	chosen.emit(_upgrade)


func _on_button_down() -> void:
	_pressing = true
	_glow_boost = 0.2
	pivot_offset = size * 0.5
	scale = Vector2(0.96, 0.96)


func _on_button_up() -> void:
	_pressing = false
	_glow_boost = 0.0
	if scale.x < 1.02:
		scale = Vector2.ONE


func _on_hover_enter() -> void:
	if _pressing:
		return
	_glow_boost = 0.12
	pivot_offset = size * 0.5
	scale = Vector2(1.03, 1.03)


func _on_hover_exit() -> void:
	if _pressing:
		return
	_glow_boost = 0.0
	scale = Vector2.ONE


## Selection feedback: scale pulse + frame flash.
func play_selection() -> void:
	if _anim != null and _anim.is_valid():
		_anim.kill()
	_anim = create_tween().set_ignore_time_scale(true)
	_anim.tween_property(self, "scale", Vector2(1.1, 1.1), 0.09) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_anim.parallel().tween_property(_frame, "modulate", Color(1.7, 1.7, 1.7, 1.0), 0.09)
	_anim.parallel().tween_property(_glow, "modulate:a", 0.9, 0.09)
	if _glow_inner != null:
		_anim.parallel().tween_property(_glow_inner, "modulate:a", 0.95, 0.09)
	_anim.tween_property(self, "scale", Vector2.ONE, 0.12)


## Dims a card that was not chosen.
func play_dismiss() -> void:
	if _anim != null and _anim.is_valid():
		_anim.kill()
	_anim = create_tween().set_ignore_time_scale(true)
	_anim.tween_property(self, "modulate:a", 0.22, 0.14)
	_anim.parallel().tween_property(self, "scale", Vector2(0.92, 0.92), 0.14)
