class_name UpgradeCard
extends Button
## One selectable upgrade card on the choice screen.
##
## Renders a rarity frame (rare/epic/legendary SVG from assets/ui/) with real
## Godot text for the title, description, rarity, and level — never baked into
## the art (docs/CLAUDE.md: build all text as real controls). Emits `chosen`
## with its UpgradeData when pressed. Entrance and selection animations run on
## unscaled, pause-independent tweens so they play while combat is paused.

## Emitted when the player selects this card.
signal chosen(upgrade: UpgradeData)

const _FRAME_PATHS := {
	UpgradeData.Rarity.RARE: "res://assets/ui/upgrade_card_rare.svg",
	UpgradeData.Rarity.EPIC: "res://assets/ui/upgrade_card_epic.svg",
	UpgradeData.Rarity.LEGENDARY: "res://assets/ui/upgrade_card_legendary.svg",
}

@onready var _frame: TextureRect = $Frame
@onready var _rarity_label: Label = $Margin/Content/Rarity
@onready var _icon: TextureRect = $Margin/Content/Icon
@onready var _title: Label = $Margin/Content/Title
@onready var _description: Label = $Margin/Content/Description
@onready var _level: Label = $Margin/Content/Level

var _upgrade: UpgradeData
var _anim: Tween


func _ready() -> void:
	# The card animates while the tree is paused (combat is frozen for the choice).
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	pivot_offset = size * 0.5
	pressed.connect(_on_pressed)


## Fills the card from an UpgradeData and the level it would become if chosen.
func populate(upgrade: UpgradeData, next_level: int) -> void:
	_upgrade = upgrade
	var accent := Palette.get_color(upgrade.rarity_color_token())
	if _FRAME_PATHS.has(upgrade.rarity):
		_frame.texture = load(_FRAME_PATHS[upgrade.rarity])
	_rarity_label.text = upgrade.rarity_label()
	_rarity_label.add_theme_color_override("font_color", accent)
	_icon.texture = upgrade.icon
	_icon.modulate = accent
	_title.text = upgrade.title
	_description.text = upgrade.description
	if upgrade.max_level > 1:
		_level.text = "LV %d / %d" % [next_level, upgrade.max_level]
	else:
		_level.text = "NEW"


## Plays the entrance animation (scale 0.92 -> 1.0 with a short fade in).
func animate_in(delay: float = 0.0) -> void:
	pivot_offset = size * 0.5
	scale = Vector2(0.92, 0.92)
	modulate.a = 0.0
	if _anim != null and _anim.is_valid():
		_anim.kill()
	_anim = create_tween().set_ignore_time_scale(true)
	_anim.tween_interval(delay)
	_anim.tween_property(self, "modulate:a", 1.0, 0.16)
	_anim.parallel().tween_property(self, "scale", Vector2.ONE, 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func get_upgrade() -> UpgradeData:
	return _upgrade


func _on_pressed() -> void:
	chosen.emit(_upgrade)


## Selection feedback: a quick scale pulse + border-intensity flash. The screen
## triggers this before applying, alongside the sound and haptic hooks.
func play_selection() -> void:
	if _anim != null and _anim.is_valid():
		_anim.kill()
	_anim = create_tween().set_ignore_time_scale(true)
	_anim.tween_property(self, "scale", Vector2(1.08, 1.08), 0.08) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_anim.parallel().tween_property(_frame, "modulate", Color(1.6, 1.6, 1.6, 1.0), 0.08)
	_anim.tween_property(self, "scale", Vector2.ONE, 0.10)


## Dims a card that was not chosen (so the pick reads clearly).
func play_dismiss() -> void:
	if _anim != null and _anim.is_valid():
		_anim.kill()
	_anim = create_tween().set_ignore_time_scale(true)
	_anim.tween_property(self, "modulate:a", 0.25, 0.12)
	_anim.parallel().tween_property(self, "scale", Vector2(0.94, 0.94), 0.12)
