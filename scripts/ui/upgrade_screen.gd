class_name UpgradeScreen
extends CanvasLayer
## Production paused three-card upgrade choice (prompts/20_upgrade_cards_production.md).
##
## Dims frozen combat, presents rarity-framed UpgradeCards, and applies the pick
## through UpgradeManager. One free reroll per run re-draws the current choices.
## Animations run while the tree is paused. Branding: RIFTSTRIKE.

signal upgrade_selected(upgrade: UpgradeData)
signal closed()

const _CARD_SCENE := preload("res://scenes/ui/upgrade_card.tscn")

## Free rerolls granted per run (no currency cost, per plan). Consumed across the
## whole run, not per level-up.
const _REROLLS_PER_RUN := 1

@onready var _veil: ColorRect = $Veil
@onready var _panel: Control = $Center
@onready var _title: Label = $Center/Layout/HeaderChip/HeaderCol/Title
@onready var _subtitle: Label = $Center/Layout/HeaderChip/HeaderCol/Subtitle
@onready var _card_row: HBoxContainer = $Center/Layout/Cards
@onready var _reroll_button: GlowCtaButton = %RerollButton
@onready var _divider: ColorRect = $Center/Layout/Divider

var _manager: UpgradeManager
var _cards: Array[UpgradeCard] = []
var _selecting: bool = false
var _pulse_time := 0.0
var _rerolls_left := _REROLLS_PER_RUN
var _current_level := 1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	layer = 64
	visible = false
	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()
	if _reroll_button != null:
		_reroll_button.chrome_modulate = Color(1.05, 0.9, 0.55, 1)
		_reroll_button.pressed.connect(_on_reroll_pressed)
		_refresh_reroll_button()
	set_process(true)


func _process(delta: float) -> void:
	if not visible:
		return
	_pulse_time += delta
	if _divider != null:
		_divider.modulate.a = 0.45 + absf(sin(_pulse_time * 1.6)) * 0.35


func _apply_safe_area() -> void:
	if _panel == null:
		return
	var safe := SafeArea.get_logical_rect(get_tree())
	var full := get_viewport().get_visible_rect().size
	_panel.add_theme_constant_override("margin_left", int(28.0 + safe.position.x))
	_panel.add_theme_constant_override("margin_right", int(28.0 + (full.x - (safe.position.x + safe.size.x))))
	_panel.add_theme_constant_override("margin_top", int(64.0 + safe.position.y))
	_panel.add_theme_constant_override("margin_bottom", int(64.0 + (full.y - (safe.position.y + safe.size.y))))
	call_deferred("_fit_card_widths")


## Shrink three-up cards so safe-area insets never clip horizontal edges.
func _fit_card_widths() -> void:
	if _card_row == null or _cards.is_empty():
		return
	var avail := _card_row.size.x
	if avail <= 1.0:
		avail = get_viewport().get_visible_rect().size.x - 80.0
	var sep := float(_card_row.get_theme_constant("separation"))
	var n := _cards.size()
	var width := floorf((avail - sep * float(n - 1)) / float(n))
	width = clampf(width, 260.0, 310.0)
	for card in _cards:
		card.custom_minimum_size = Vector2(width, card.custom_minimum_size.y)


func configure(manager: UpgradeManager) -> void:
	_manager = manager
	# One free reroll per run; this screen is rebuilt each run so reset here.
	_rerolls_left = _REROLLS_PER_RUN
	_refresh_reroll_button()


## Rolls three choices, pauses the game, and shows the cards.
func open(level: int) -> bool:
	if _manager == null:
		return false
	var choices := _manager.roll_choices(3, level)
	if choices.is_empty():
		return false

	_selecting = false
	_current_level = level
	_clear_cards()
	_title.text = "LEVEL %d" % level
	_subtitle.text = "CHOOSE AN UPGRADE"
	_build_cards(choices)
	_refresh_reroll_button()

	visible = true
	get_tree().paused = true
	AudioManager.set_fire_loop_suppressed(true)
	_animate_open()
	AudioManager.play_sfx("upgrade_open", Vector2.ZERO, AudioManager.PRIORITY_HIGH)
	var haptics: HapticsService = PlatformServices.haptics
	if GameFeel.haptics_enabled and haptics != null:
		haptics.light()
	_apply_safe_area()
	return true


## Immediately removes prior cards so level-ups never stack ghost UI / glow.
func _clear_cards() -> void:
	for card in _cards:
		if card != null and is_instance_valid(card):
			if card.has_method("kill_anims"):
				card.call("kill_anims")
			card.modulate = Color.WHITE
			card.scale = Vector2.ONE
			var parent := card.get_parent()
			if parent != null:
				parent.remove_child(card)
			card.free()
	_cards.clear()
	if _card_row != null:
		for child in _card_row.get_children():
			_card_row.remove_child(child)
			child.free()


func _build_cards(choices: Array[UpgradeData]) -> void:
	_clear_cards()
	for upgrade in choices:
		var card := _CARD_SCENE.instantiate() as UpgradeCard
		_card_row.add_child(card)
		var next_level := _manager.level_of(upgrade.id) + 1
		var synergy := _manager.synergy_hint_for(upgrade)
		card.populate(upgrade, next_level, synergy)
		card.chosen.connect(_on_card_chosen)
		_cards.append(card)
	call_deferred("_fit_card_widths")


func _animate_open() -> void:
	_veil.color.a = 0.0
	var veil_tween := create_tween().set_ignore_time_scale(true)
	# Stronger dim for card focus; combat silhouette stays readable underneath.
	veil_tween.tween_property(_veil, "color:a", 0.7, 0.2)
	for i in _cards.size():
		_cards[i].animate_in(0.05 * float(i))


func _on_card_chosen(upgrade: UpgradeData) -> void:
	if _selecting:
		return
	_selecting = true

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

	var close_tween := create_tween().set_ignore_time_scale(true)
	close_tween.tween_interval(0.26)
	close_tween.tween_property(_veil, "color:a", 0.0, 0.16)
	close_tween.tween_callback(_finish_close)


func _finish_close() -> void:
	_clear_cards()
	visible = false
	get_tree().paused = false
	AudioManager.set_fire_loop_suppressed(false)
	closed.emit()


## Live card count for probes (children of Cards row only).
func get_card_count() -> int:
	if _card_row == null:
		return 0
	return _card_row.get_child_count()


func is_open() -> bool:
	return visible


## Re-draws the current level's three choices using one of the run's free
## rerolls. No currency involved; disabled once the run's rerolls are spent.
func _on_reroll_pressed() -> void:
	if _manager == null or _selecting or _rerolls_left <= 0:
		return
	var choices := _manager.roll_choices(3, _current_level)
	if choices.is_empty():
		return
	_rerolls_left -= 1
	_build_cards(choices)
	_animate_cards_in()
	_refresh_reroll_button()
	AudioManager.play_sfx("upgrade_open", Vector2.ZERO, AudioManager.PRIORITY_MEDIUM)
	var haptics: HapticsService = PlatformServices.haptics
	if GameFeel.haptics_enabled and haptics != null:
		haptics.light()


## Updates the reroll CTA label + enabled state from the remaining count.
func _refresh_reroll_button() -> void:
	if _reroll_button == null:
		return
	if _rerolls_left > 0:
		_reroll_button.configure(
			"REROLL · %d" % _rerolls_left, "",
			GlowCtaButton.Variant.SECONDARY, GlowCtaButton.Pulse.MAGENTA, 96.0)
		_reroll_button.set_enabled(true)
	else:
		_reroll_button.configure(
			"REROLL · USED", "",
			GlowCtaButton.Variant.SECONDARY, GlowCtaButton.Pulse.NONE, 96.0)
		_reroll_button.set_enabled(false)
	_reroll_button.chrome_modulate = Color(1.05, 0.9, 0.55, 1)


## Animates freshly built cards into view (used by reroll; veil already shown).
func _animate_cards_in() -> void:
	for i in _cards.size():
		_cards[i].animate_in(0.04 * float(i))
