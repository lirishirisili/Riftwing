class_name UpgradeScreen
extends CanvasLayer
## The paused three-card upgrade choice.
##
## Presented on level-up: it pauses the tree, dims the frozen combat behind a
## darkening veil, and lays out exactly three UpgradeCards built from the rolled
## UpgradeData. Selecting a card plays a selection animation plus a sound hook
## and a haptic hook, then emits `upgrade_selected` and hides. No reroll this
## milestone (docs/02_GAMEPLAY_SPEC.md).
##
## The layer processes while paused so its animations run with combat frozen.

## Emitted after the player picks a card and the selection animation begins.
signal upgrade_selected(upgrade: UpgradeData)
## Emitted once the screen has fully closed and gameplay may resume.
signal closed()

const _CARD_SCENE := preload("res://scenes/ui/upgrade_card.tscn")

@onready var _veil: ColorRect = $Veil
@onready var _panel: Control = $Center
@onready var _title: Label = $Center/Layout/Title
@onready var _subtitle: Label = $Center/Layout/Subtitle
@onready var _card_row: HBoxContainer = $Center/Layout/Cards

var _manager: UpgradeManager
var _cards: Array[UpgradeCard] = []
var _selecting: bool = false


func _ready() -> void:
	# Everything here must animate while the tree is paused for the choice.
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	layer = 64
	visible = false
	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()


## Keep the three-card row inside notches / home indicators on tall phones.
func _apply_safe_area() -> void:
	if _panel == null:
		return
	var safe := SafeArea.get_logical_rect(get_tree())
	var full := get_viewport().get_visible_rect().size
	_panel.add_theme_constant_override("margin_left", int(40.0 + safe.position.x))
	_panel.add_theme_constant_override("margin_right", int(40.0 + (full.x - (safe.position.x + safe.size.x))))
	_panel.add_theme_constant_override("margin_top", int(80.0 + safe.position.y))
	_panel.add_theme_constant_override("margin_bottom", int(80.0 + (full.y - (safe.position.y + safe.size.y))))


## Binds the manager that supplies choices and applies the pick.
func configure(manager: UpgradeManager) -> void:
	_manager = manager


## Rolls three choices, pauses the game, and shows the cards. Returns false when
## nothing is offerable (caller should then just resume).
func open(level: int) -> bool:
	if _manager == null:
		return false
	var choices := _manager.roll_choices(3)
	if choices.is_empty():
		return false

	_selecting = false
	_title.text = "LEVEL %d" % level
	_subtitle.text = "CHOOSE AN UPGRADE"
	_build_cards(choices)

	visible = true
	get_tree().paused = true
	_animate_open()
	# Sound + light haptic on the choice appearing.
	AudioManager.play_sfx("upgrade_open", Vector2.ZERO, AudioManager.PRIORITY_HIGH)
	var haptics: HapticsService = PlatformServices.haptics
	if GameFeel.haptics_enabled and haptics != null:
		haptics.light()
	_apply_safe_area()
	return true


func _build_cards(choices: Array[UpgradeData]) -> void:
	for card in _cards:
		card.queue_free()
	_cards.clear()
	for upgrade in choices:
		var card := _CARD_SCENE.instantiate() as UpgradeCard
		_card_row.add_child(card)
		var next_level := _manager.level_of(upgrade.id) + 1
		card.populate(upgrade, next_level)
		card.chosen.connect(_on_card_chosen)
		_cards.append(card)


func _animate_open() -> void:
	_veil.color.a = 0.0
	var veil_tween := create_tween().set_ignore_time_scale(true)
	# Slight dim, not a blackout, so frozen combat stays readable behind it.
	veil_tween.tween_property(_veil, "color:a", 0.62, 0.18)
	# Stagger the card entrances for a bit of life.
	for i in _cards.size():
		_cards[i].animate_in(0.04 * float(i))


func _on_card_chosen(upgrade: UpgradeData) -> void:
	if _selecting:
		return
	_selecting = true

	# Selection feedback: animation on the chosen card, dim the rest, plus the
	# sound and haptic hooks (docs/03_SCREEN_SPEC.md: scale, border, haptic, sound).
	for card in _cards:
		if card.get_upgrade() == upgrade:
			card.play_selection()
		else:
			card.play_dismiss()
	AudioManager.play_sfx("upgrade_select", Vector2.ZERO, AudioManager.PRIORITY_HIGH)
	var haptics: HapticsService = PlatformServices.haptics
	if GameFeel.haptics_enabled and haptics != null:
		haptics.medium()

	_manager.apply(upgrade)
	upgrade_selected.emit(upgrade)

	# Let the selection animation read before closing.
	var close_tween := create_tween().set_ignore_time_scale(true)
	close_tween.tween_interval(0.22)
	close_tween.tween_property(_veil, "color:a", 0.0, 0.14)
	close_tween.tween_callback(_finish_close)


func _finish_close() -> void:
	visible = false
	get_tree().paused = false
	closed.emit()


## Is a choice currently on screen?
func is_open() -> bool:
	return visible
