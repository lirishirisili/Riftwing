class_name UpgradeScreen
extends CanvasLayer
## Production paused three-card upgrade choice (prompts/20_upgrade_cards_production.md).
##
## Dims frozen combat, presents rarity-framed UpgradeCards, and applies the pick
## through UpgradeManager. One free reroll per run re-draws the current choices.
## Animations run while the tree is paused. Branding: RIFTSTRIKE.

signal upgrade_selected(upgrade: UpgradeData)
signal closed()
## A chest reveal was dismissed (separate from `closed`, which consumes a level).
signal reveal_closed()

const _CARD_SCENE := preload("res://scenes/ui/upgrade_card.tscn")
const _GLOW_SCENE := preload("res://scenes/ui/chrome/glow_cta_button.tscn")

## Default free rerolls per run when the host supplies no RunRulesData.
const _DEFAULT_REROLLS := 1

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
var _rerolls_left := _DEFAULT_REROLLS
var _current_level := 1
## Banish: arm the mode, then tap a card to remove it from the run (redraws).
var _banishes_left := 0
var _banish_mode := false
var _banish_button: GlowCtaButton
## Chest reveal: cards are shown face-up (already applied); any tap collects.
var _reveal_mode := false


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
	_build_banish_button()
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


func configure(manager: UpgradeManager, rerolls_per_run: int = _DEFAULT_REROLLS, banishes_per_run: int = 0) -> void:
	_manager = manager
	# Free rerolls are per run; this screen is rebuilt each run so reset here.
	_rerolls_left = maxi(0, rerolls_per_run)
	_banishes_left = maxi(0, banishes_per_run)
	_banish_mode = false
	_refresh_reroll_button()
	_refresh_banish_button()


## Extra reroll granted from outside the card screen (e.g. a rewarded ad).
func grant_reroll(count: int = 1) -> void:
	_rerolls_left += maxi(0, count)
	_refresh_reroll_button()


func _build_banish_button() -> void:
	if _reroll_button == null:
		return
	_banish_button = _GLOW_SCENE.instantiate() as GlowCtaButton
	_banish_button.name = "BanishButton"
	_banish_button.custom_minimum_size = Vector2(360, 84)
	_banish_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var parent := _reroll_button.get_parent()
	parent.add_child(_banish_button)
	parent.move_child(_banish_button, _reroll_button.get_index() + 1)
	_banish_button.pressed.connect(_on_banish_pressed)
	_refresh_banish_button()


func _on_banish_pressed() -> void:
	if _selecting or _banishes_left <= 0:
		return
	_banish_mode = not _banish_mode
	_subtitle.text = "TAP A CARD TO BANISH IT" if _banish_mode else "CHOOSE AN UPGRADE"
	AudioManager.play_sfx("ui_click", Vector2.ZERO, AudioManager.PRIORITY_MEDIUM)
	_refresh_banish_button()


func _refresh_banish_button() -> void:
	if _banish_button == null:
		return
	_banish_button.visible = (_banishes_left > 0 or _banish_mode) and not _reveal_mode
	if _banish_mode:
		_banish_button.configure("CANCEL BANISH", "", GlowCtaButton.Variant.SECONDARY, GlowCtaButton.Pulse.MAGENTA, 84.0)
	else:
		_banish_button.configure("BANISH · %d" % _banishes_left, "", GlowCtaButton.Variant.SECONDARY, GlowCtaButton.Pulse.NONE, 84.0)
	_banish_button.chrome_modulate = Color(1.0, 0.55, 0.6, 1)


## Removes a card from the run and redraws the choices.
func _banish(upgrade: UpgradeData) -> void:
	_banish_mode = false
	_banishes_left -= 1
	_manager.banish(upgrade.id)
	_subtitle.text = "CHOOSE AN UPGRADE"
	var choices := _manager.roll_choices(3, _current_level)
	if not choices.is_empty():
		_build_cards(choices)
		_animate_cards_in()
	AudioManager.play_sfx("ui_back", Vector2.ZERO, AudioManager.PRIORITY_MEDIUM)
	GameFeel.haptic("medium")
	_refresh_banish_button()


## Rolls three choices, pauses the game, and shows the cards.
func open(level: int) -> bool:
	if _manager == null:
		return false
	var choices := _manager.roll_choices(3, level)
	if choices.is_empty():
		return false

	_selecting = false
	_banish_mode = false
	_refresh_banish_button()
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
	GameFeel.haptic("light")
	_apply_safe_area()
	return true


## Shows already-applied upgrades (chest contents). Pauses like a level-up;
## tapping a card or COLLECT dismisses and emits `reveal_closed`.
func open_reveal(title: String, subtitle: String, upgrades: Array[UpgradeData]) -> bool:
	if _manager == null or upgrades.is_empty():
		return false
	_selecting = false
	_reveal_mode = true
	_banish_mode = false
	_clear_cards()
	_title.text = title
	_subtitle.text = subtitle
	for upgrade in upgrades:
		var card := _CARD_SCENE.instantiate() as UpgradeCard
		_card_row.add_child(card)
		card.populate(upgrade, maxi(1, _manager.level_of(upgrade.id)), "")
		card.chosen.connect(_on_card_chosen)
		_cards.append(card)
	call_deferred("_fit_card_widths")
	_refresh_reroll_button()
	_refresh_banish_button()
	visible = true
	get_tree().paused = true
	AudioManager.set_fire_loop_suppressed(true)
	_animate_open()
	GameFeel.haptic("medium")
	_apply_safe_area()
	return true


func _close_reveal() -> void:
	if _selecting:
		return
	_selecting = true
	AudioManager.play_sfx("reward", Vector2.ZERO, AudioManager.PRIORITY_HIGH)
	var close_tween := create_tween().set_ignore_time_scale(true)
	close_tween.tween_property(_veil, "color:a", 0.0, 0.16)
	close_tween.tween_callback(func() -> void:
		_clear_cards()
		_reveal_mode = false
		visible = false
		get_tree().paused = false
		AudioManager.set_fire_loop_suppressed(false)
		_refresh_reroll_button()
		reveal_closed.emit()
	)


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
	if _reveal_mode:
		_close_reveal()
		return
	if _banish_mode:
		# Evolutions cannot be banished (they are the payoff of a build).
		if not upgrade.is_evolution:
			_banish(upgrade)
		return
	_selecting = true

	for card in _cards:
		if card.get_upgrade() == upgrade:
			card.play_selection()
		else:
			card.play_dismiss()
	AudioManager.play_sfx("upgrade_select", Vector2.ZERO, AudioManager.PRIORITY_HIGH)
	GameFeel.haptic("medium")

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


## Overrides the subtitle line (first-run onboarding text).
func set_subtitle(text: String) -> void:
	if _subtitle != null:
		_subtitle.text = text


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
	if _reveal_mode:
		_close_reveal()
		return
	if _manager == null or _selecting:
		return
	if _rerolls_left <= 0:
		# Out of free rerolls: one more for a rewarded ad (granted on reward only).
		RewardedAd.show("reroll", func() -> void:
			_rerolls_left += 1
			_on_reroll_pressed())
		return
	var choices := _manager.roll_choices(3, _current_level)
	if choices.is_empty():
		return
	_rerolls_left -= 1
	_build_cards(choices)
	_animate_cards_in()
	_refresh_reroll_button()
	AudioManager.play_sfx("upgrade_open", Vector2.ZERO, AudioManager.PRIORITY_MEDIUM)
	GameFeel.haptic("light")


## Updates the reroll CTA label + enabled state from the remaining count.
func _refresh_reroll_button() -> void:
	if _reroll_button == null:
		return
	if _reveal_mode:
		_reroll_button.configure("COLLECT", "", GlowCtaButton.Variant.PRIMARY, GlowCtaButton.Pulse.CYAN, 96.0)
		_reroll_button.set_enabled(true)
		return
	if _rerolls_left > 0:
		_reroll_button.configure(
			"REROLL · %d" % _rerolls_left, "",
			GlowCtaButton.Variant.SECONDARY, GlowCtaButton.Pulse.MAGENTA, 96.0)
		_reroll_button.set_enabled(true)
	elif RewardedAd.is_ready():
		_reroll_button.configure(
			"REROLL · AD", "WATCH AN AD",
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
