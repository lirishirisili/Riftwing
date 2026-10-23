class_name ProgressScreen
extends Control
## Meta-progression hub: MISSIONS (daily / weekly + activity chests),
## ACHIEVEMENTS, and MODULES (3 equip slots, inventory, merging).
## Everything reads / writes through MetaProgress; this screen is UI only.

const _GLOW := preload("res://scenes/ui/chrome/glow_cta_button.tscn")
const TAB_MISSIONS := 0
const TAB_ACHIEVEMENTS := 1
const TAB_MODULES := 2

@onready var _shell: MetaScreenShell = %Shell

var _tab: int = TAB_MISSIONS
var _content: VBoxContainer
var _pilot_label: Label
var _pilot_bar: ProgressBar
var _tab_buttons: Array[GlowCtaButton] = []
var _header_back: HeaderBackButton
## Module selected for equipping (uid) — the next slot tap equips it.
var _pending_equip: String = ""


func receive_payload(payload: Dictionary) -> void:
	if payload.has("tab"):
		_tab = int(payload["tab"])


func _ready() -> void:
	MetaProgress.refresh_missions()
	var body := _shell.get_body()
	_header_back = HeaderBackButton.new()
	_header_back.pressed.connect(_on_back)
	_shell.set_trailing(_header_back)

	_pilot_label = Label.new()
	_pilot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pilot_label.add_theme_font_size_override("font_size", 34)
	body.add_child(_pilot_label)
	_pilot_bar = _make_bar(18.0, Palette.get_color("purple", Color(0.6, 0.35, 1.0)))
	body.add_child(_pilot_bar)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 10)
	body.add_child(tabs)
	for t in [["MISSIONS", TAB_MISSIONS], ["AWARDS", TAB_ACHIEVEMENTS], ["MODULES", TAB_MODULES]]:
		var b := _GLOW.instantiate() as GlowCtaButton
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tabs.add_child(b)
		b.pressed.connect(_select_tab.bind(int(t[1])))
		b.set_meta("tab_title", String(t[0]))
		_tab_buttons.append(b)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 12)
	scroll.add_child(_content)
	AudioManager.play_music("menu")
	_rebuild()


func _select_tab(tab: int) -> void:
	_tab = tab
	_pending_equip = ""
	AudioManager.play_sfx("ui_click", Vector2.ZERO, AudioManager.PRIORITY_MEDIUM)
	_rebuild()


func _rebuild() -> void:
	var level := MetaProgress.pilot_level()
	_pilot_label.text = "PILOT  LV %d" % level
	_pilot_bar.max_value = float(MetaProgress.xp_for_next())
	_pilot_bar.value = float(MetaProgress.pilot_xp())
	for i in _tab_buttons.size():
		var b := _tab_buttons[i]
		var title := String(b.get_meta("tab_title"))
		var badge := _badge_for(i)
		b.configure(title if badge == 0 else "%s · %d" % [title, badge], "",
			GlowCtaButton.Variant.PRIMARY if i == _tab else GlowCtaButton.Variant.NAV,
			GlowCtaButton.Pulse.CYAN if badge > 0 else GlowCtaButton.Pulse.NONE, 84.0)
	for child in _content.get_children():
		child.queue_free()
	match _tab:
		TAB_ACHIEVEMENTS:
			_build_achievements()
		TAB_MODULES:
			_build_modules()
		_:
			_build_missions()
	if _shell != null:
		_shell.refresh_currencies()


func _badge_for(tab: int) -> int:
	var n := 0
	match tab:
		TAB_MISSIONS:
			for scope in ["daily", "weekly"]:
				for entry in MetaProgress.missions(scope):
					if MetaProgress.is_mission_done(entry) and not bool(entry.get("claimed", false)):
						n += 1
			var cat := MetaProgress.catalog()
			for i in cat.activity_milestones.size():
				if not MetaProgress.is_activity_claimed(i) and MetaProgress.activity() >= cat.activity_milestones[i]:
					n += 1
		TAB_ACHIEVEMENTS:
			for a in MetaProgress.catalog().achievements:
				if not MetaProgress.is_achievement_claimed(a.id) and MetaProgress.achievement_progress(a) >= a.goal:
					n += 1
	return n


# --- Missions -----------------------------------------------------------------------

func _build_missions() -> void:
	if MetaProgress.supply_drop_available() and RewardedAd.is_ready():
		var cat := MetaProgress.catalog()
		_content.add_child(_row("DAILY SUPPLY DROP", _reward_text(cat.supply_drop_energy, cat.supply_drop_core), 1.0,
			"WATCH AD", true, func() -> void:
				RewardedAd.show("supply_drop", func() -> void:
					if MetaProgress.claim_supply_drop():
						_reward_feedback()
					_rebuild())))
	_content.add_child(_header("DAILY MISSIONS", "resets in %s" % _fmt_span(MetaProgress.seconds_to_next_day())))
	for entry in MetaProgress.missions("daily"):
		_content.add_child(_mission_row("daily", entry))
	_content.add_child(_activity_row())
	_content.add_child(_header("WEEKLY MISSIONS", "resets in %s" % _fmt_span(MetaProgress.seconds_to_next_week())))
	for entry in MetaProgress.missions("weekly"):
		_content.add_child(_mission_row("weekly", entry))


func _mission_row(scope: String, entry: Dictionary) -> Control:
	var def := MetaProgress.mission_def(entry)
	if def == null:
		return Control.new()
	var progress := mini(int(entry.get("progress", 0)), def.goal)
	var claimed := bool(entry.get("claimed", false))
	var done := progress >= def.goal
	var btn_text := "CLAIMED" if claimed else ("CLAIM" if done else "%d / %d" % [progress, def.goal])
	return _row(def.text(), _reward_text(def.reward_energy, def.reward_core), float(progress) / float(def.goal),
		btn_text, done and not claimed, func() -> void:
			if MetaProgress.claim_mission(scope, def.id):
				_reward_feedback()
			_rebuild())


func _activity_row() -> Control:
	var cat := MetaProgress.catalog()
	var panel := _panel()
	var col := VBoxContainer.new()
	panel.add_child(col)
	var act := MetaProgress.activity()
	var top := cat.activity_milestones[cat.activity_milestones.size() - 1] if not cat.activity_milestones.is_empty() else 1
	var l := _label("DAILY ACTIVITY  %d / %d" % [act, top], 28, Color(1, 0.85, 0.4))
	col.add_child(l)
	var bar := _make_bar(16.0, Palette.get_color("gold", Color(1, 0.8, 0.3)))
	bar.max_value = float(top)
	bar.value = float(act)
	col.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)
	for i in cat.activity_milestones.size():
		var need := cat.activity_milestones[i]
		var claimed := MetaProgress.is_activity_claimed(i)
		var b := _GLOW.instantiate() as GlowCtaButton
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
		var ready := act >= need and not claimed
		b.configure("✓" if claimed else ("OPEN" if ready else str(need)), "CHEST %d" % (i + 1),
			GlowCtaButton.Variant.PRIMARY if ready else GlowCtaButton.Variant.NAV,
			GlowCtaButton.Pulse.CYAN if ready else GlowCtaButton.Pulse.NONE, 84.0)
		b.set_enabled(ready)
		b.pressed.connect(func() -> void:
			var r := MetaProgress.claim_activity(i)
			if not r.is_empty():
				_reward_feedback()
			_rebuild())
	return panel


# --- Achievements ---------------------------------------------------------------------

func _build_achievements() -> void:
	var rows: Array = []
	for a in MetaProgress.catalog().achievements:
		var progress := MetaProgress.achievement_progress(a)
		var claimed := MetaProgress.is_achievement_claimed(a.id)
		var order := 0 if (progress >= a.goal and not claimed) else (2 if claimed else 1)
		rows.append([order, a, progress, claimed])
	rows.sort_custom(func(x: Array, y: Array) -> bool: return int(x[0]) < int(y[0]))
	for r in rows:
		var a: AchievementData = r[1]
		var progress := mini(int(r[2]), a.goal)
		var claimed := bool(r[3])
		var done := progress >= a.goal
		_content.add_child(_row("%s — %s" % [a.title, a.description], _reward_text(a.reward_energy, a.reward_core),
			float(progress) / float(a.goal), "DONE" if claimed else ("CLAIM" if done else "%d / %d" % [progress, a.goal]),
			done and not claimed, func() -> void:
				if MetaProgress.claim_achievement(a.id):
					_reward_feedback()
				_rebuild()))


# --- Modules --------------------------------------------------------------------------------

func _build_modules() -> void:
	_content.add_child(_header("EQUIPPED", "tap a slot to %s" % ("place the selected module" if _pending_equip != "" else "clear it")))
	var slots := HBoxContainer.new()
	slots.add_theme_constant_override("separation", 10)
	_content.add_child(slots)
	var equipped := MetaProgress.equipped_uids()
	for i in MetaProgress.SLOT_COUNT:
		var entry := MetaProgress.find_owned(String(equipped[i]))
		var b := _GLOW.instantiate() as GlowCtaButton
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slots.add_child(b)
		if entry.is_empty():
			b.configure("EMPTY", "SLOT %d" % (i + 1), GlowCtaButton.Variant.NAV,
				GlowCtaButton.Pulse.CYAN if _pending_equip != "" else GlowCtaButton.Pulse.NONE, 104.0)
		else:
			var def := MetaProgress.catalog().find_module(String(entry["id"]))
			b.configure(def.title.to_upper() if def != null else "?", _bonus_text(entry), GlowCtaButton.Variant.SECONDARY,
				GlowCtaButton.Pulse.NONE, 104.0)
			b.chrome_modulate = ModuleData.rarity_color(int(entry["rarity"]))
		b.pressed.connect(func() -> void:
			if _pending_equip != "":
				MetaProgress.equip(_pending_equip, i)
				_pending_equip = ""
			else:
				MetaProgress.unequip(i)
			AudioManager.play_sfx("ui_confirm", Vector2.ZERO, AudioManager.PRIORITY_MEDIUM)
			_rebuild())

	var owned := MetaProgress.owned_modules()
	_content.add_child(_header("INVENTORY", "%d modules · 3 alike merge into a rarer one" % owned.size()))
	if owned.is_empty():
		_content.add_child(_label("Clear campaign stages and open activity chests to find modules.", 24, Color(0.7, 0.8, 0.95)))
		return
	var sorted := owned.duplicate()
	sorted.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		if int(x["rarity"]) != int(y["rarity"]):
			return int(x["rarity"]) > int(y["rarity"])
		return String(x["id"]) < String(y["id"]))
	for entry in sorted:
		_content.add_child(_module_row(entry))


func _module_row(entry: Dictionary) -> Control:
	var def := MetaProgress.catalog().find_module(String(entry["id"]))
	var uid := String(entry["uid"])
	var rarity := int(entry["rarity"])
	var panel := _panel()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var eq := "  · EQUIPPED" if MetaProgress.is_equipped(uid) else ""
	info.add_child(_label("%s  [%s]%s" % [def.title if def != null else "?", ModuleData.rarity_name(rarity), eq], 26,
		ModuleData.rarity_color(rarity)))
	info.add_child(_label(_bonus_text(entry), 22, Color(0.8, 0.88, 1)))
	if not MetaProgress.is_equipped(uid):
		var equip := _small_button("SELECT" if _pending_equip != uid else "CHOSEN", true)
		row.add_child(equip)
		equip.pressed.connect(func() -> void:
			_pending_equip = "" if _pending_equip == uid else uid
			AudioManager.play_sfx("ui_click", Vector2.ZERO, AudioManager.PRIORITY_MEDIUM)
			_rebuild())
	if MetaProgress.can_merge(uid):
		var merge := _small_button("MERGE", true)
		row.add_child(merge)
		merge.pressed.connect(func() -> void:
			var made := MetaProgress.merge(uid)
			if not made.is_empty():
				_reward_feedback()
			_rebuild())
	return panel


func _bonus_text(entry: Dictionary) -> String:
	var def := MetaProgress.catalog().find_module(String(entry["id"]))
	if def == null:
		return ""
	var v := def.value_at(int(entry["rarity"]))
	var names := {"damage": "damage", "hp": "max HP", "crit": "crit", "magnet": "magnet range", "xp": "XP",
		"fire_rate": "fire rate", "armor": "armor", "energy_find": "Rift Energy"}
	return "+%d%% %s" % [int(round(v * 100.0)), String(names.get(def.stat, def.stat))]


# --- Widgets ----------------------------------------------------------------------------------

func _row(title: String, reward: String, frac: float, button_text: String, enabled: bool, on_press: Callable) -> Control:
	var panel := _panel()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var t := _label(title, 25, Color(0.95, 0.97, 1))
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(t)
	info.add_child(_label(reward, 21, Color(1, 0.85, 0.4)))
	var bar := _make_bar(12.0, Palette.get_color("cyan", Color(0.2, 0.9, 1.0)))
	bar.max_value = 1.0
	bar.value = clampf(frac, 0.0, 1.0)
	info.add_child(bar)
	var b := _small_button(button_text, enabled)
	row.add_child(b)
	b.pressed.connect(on_press)
	return panel


## Progress bar with explicit styles (the shared theme has none for bars).
func _make_bar(height: float, fill: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, height)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.03, 0.06, 0.12, 0.9)
	bg.set_corner_radius_all(int(height * 0.5))
	bg.border_color = Color(fill, 0.35)
	bg.set_border_width_all(1)
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill
	fg.set_corner_radius_all(int(height * 0.5))
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)
	return bar


func _small_button(text: String, enabled: bool) -> GlowCtaButton:
	var b := _GLOW.instantiate() as GlowCtaButton
	b.custom_minimum_size = Vector2(220, 80)
	b.configure(text, "", GlowCtaButton.Variant.PRIMARY if enabled else GlowCtaButton.Variant.NAV,
		GlowCtaButton.Pulse.CYAN if enabled else GlowCtaButton.Pulse.NONE, 80.0)
	b.set_enabled(enabled)
	return b


func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = &"NeonPanel"
	return p


func _header(title: String, sub: String) -> Control:
	var row := HBoxContainer.new()
	var t := _label(title, 30, Palette.get_color("cyan", Color(0.2, 0.9, 1)))
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(t)
	row.add_child(_label(sub, 22, Color(0.6, 0.72, 0.9)))
	return row


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _reward_text(energy: int, core: int) -> String:
	var parts: PackedStringArray = []
	if energy > 0:
		parts.append("+%d RIFT ENERGY" % energy)
	if core > 0:
		parts.append("+%d RIFT CORE" % core)
	return "  ·  ".join(parts)


func _reward_feedback() -> void:
	AudioManager.play_sfx("reward", Vector2.ZERO, AudioManager.PRIORITY_HIGH)
	GameFeel.haptic("medium")


func _fmt_span(seconds: int) -> String:
	var s := maxi(0, seconds)
	if s >= 86400:
		return "%dd %dh" % [s / 86400, (s % 86400) / 3600]
	return "%dh %02dm" % [s / 3600, (s % 3600) / 60]


func handle_system_back() -> bool:
	_on_back()
	return true


func _on_back() -> void:
	AudioManager.play_sfx("ui_back", Vector2.ZERO, AudioManager.PRIORITY_MEDIUM)
	SceneRouter.go_to(SceneRouter.SCREEN_MAIN_MENU)
