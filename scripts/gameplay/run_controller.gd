extends Node2D
## Vertical-slice run host: waves → XP/upgrades → mini-boss → mid waves →
## final boss → results. Composes existing systems; timeline is data-driven
## (prompts/13_vertical_slice_integration.md, docs/02_GAMEPLAY_SPEC.md).

enum Phase {
	EARLY_WAVES,
	MINI_BOSS,
	MID_WAVES,
	FINAL_BOSS,
	ENDING,
}

@export var timeline: StageTimelineData

@onready var _player: PlayerShip = $PlayerShip
@onready var _weapon: PlasmaWeapon = $PlayerShip/PlasmaWeapon
@onready var _director: WaveDirector = $WaveDirector
@onready var _boss: Boss = $Boss
@onready var _player_bullet_pool: ProjectilePool = $PlayerProjectilePool
@onready var _enemy_bullet_pool: ProjectilePool = $EnemyProjectilePool
@onready var _enemy_pool: NodePool = $EnemyPool
@onready var _pickup_pool: NodePool = $PickupPool
@onready var _effects: EffectsLayer = $EffectsLayer
@onready var _camera: CameraRig = $CameraRig
@onready var _overlay: Control = $Overlay
@onready var _hud: GameplayHUD = $UI/GameplayHUD
@onready var _health_bar: BossHealthBar = $UI/BossHealthBar
@onready var _readout: Label = $UI/Readout
@onready var _banner: Label = $UI/PhaseBanner
@onready var _xp: ExperienceTracker = $ExperienceTracker
@onready var _upgrades: UpgradeManager = $UpgradeManager
@onready var _upgrade_screen: UpgradeScreen = $UpgradeScreen
@onready var _secondary: SecondaryWeaponSystem = $SecondaryWeaponSystem

const _PICKUP_DATA_PATH := "res://resources/pickups/energy_small.tres"
const _CATALOG_PATH := "res://resources/ships/ship_catalog_default.tres"
const _DEFAULT_TIMELINE := "res://resources/stages/vertical_slice_timeline.tres"
const _STAGE_MAP_PATH := "res://resources/stages/nova_sector_map.tres"
const _DIFFICULTY_DIR := "res://resources/difficulty/"
const _RULES_PATH := "res://resources/balance/run_rules_default.tres"
## Enemy damage scaling grows at half the rate of the stage durability scalar,
## so late stages hit harder without one-shotting the player.
const _STAGE_DAMAGE_SHARE := 0.5
const _PHASE_NAMES := ["EARLY", "MINI", "MID", "BOSS", "END"]

var _screen := Vector2(1080, 1920)
var _sector: int = 1
var _stage_id: String = ""
## When true, mini/boss times are compressed for automated probes.
var _fast: bool = false

var _phase: int = Phase.EARLY_WAVES
var _run_time: float = 0.0
var _stats: RunStats
var _combo: int = 0
var _combo_timer: float = 0.0
var _run_active: bool = false
var _run_over: bool = false
var _results_timer: float = 0.0
var _level_up_queue: int = 0
var _last_upgrade: String = "-"
var _guaranteed_level_done: bool = false
var _peak_enemy_bolts: int = 0
var _peak_enemies: int = 0
var _awaiting_boss_outcome: bool = false
var _profile: CombatProfile
var _difficulty_id: String = ""
var _difficulty: RunDifficultyData
var _reward_mult: float = 1.0
var _star_score_mult: float = 1.0
var _timing_scale: float = 1.0
var _is_daily: bool = false
var _daily_date: String = ""
var _daily_reward_core: int = 0
var _rules: RunRulesData
## Deferred "upgrade landed" beat, played once the card screen has unpaused.
var _pending_upgrade_tint: Color = Color(0, 0, 0, 0)


func receive_payload(payload: Dictionary) -> void:
	if payload.has("sector"):
		_sector = maxi(1, int(payload["sector"]))
	if payload.has("stage_id"):
		_stage_id = String(payload["stage_id"])
	if payload.has("fast"):
		_fast = bool(payload["fast"])
	if payload.has("difficulty"):
		_difficulty_id = String(payload["difficulty"])
	if payload.has("timeline") and payload["timeline"] is StageTimelineData:
		timeline = payload["timeline"] as StageTimelineData
	if payload.has("daily"):
		_is_daily = bool(payload["daily"])
	if payload.has("daily_date"):
		_daily_date = String(payload["daily_date"])
	if payload.has("daily_reward_core"):
		_daily_reward_core = int(payload["daily_reward_core"])


func _ready() -> void:
	_rules = load(_RULES_PATH) as RunRulesData
	if _rules == null:
		_rules = RunRulesData.new()
	if timeline == null:
		timeline = _resolve_stage_timeline()
	if timeline == null:
		timeline = load(_DEFAULT_TIMELINE) as StageTimelineData
	var pickup_data: PickupData = load(_PICKUP_DATA_PATH)
	_weapon.pool = _player_bullet_pool
	_adapt_screen_size()
	get_viewport().size_changed.connect(_adapt_screen_size)

	_director.enemy_pool = _enemy_pool
	_director.enemy_projectile_pool = _enemy_bullet_pool
	_director.pickup_pool = _pickup_pool
	_director.pickup_data = pickup_data
	_director.player = _player
	_director.screen_size = _screen
	_director.enemy_killed.connect(_on_enemy_killed)
	_director.wave_finished.connect(_on_wave_finished)

	_boss.enemy_projectile_pool = _enemy_bullet_pool
	_boss.enemy_pool = _enemy_pool
	_boss.pickup_pool = _pickup_pool
	_boss.pickup_data = pickup_data
	_boss.player = _player
	_boss.screen_size = _screen
	_boss.warning_started.connect(_on_warning_started)
	_boss.entered.connect(_on_boss_entered)
	_boss.health_changed.connect(_on_boss_health_changed)
	_boss.phase_changed.connect(_on_boss_phase_changed)
	_boss.add_destroyed.connect(_on_add_destroyed)
	_boss.dying.connect(_on_boss_dying)
	_boss.defeated.connect(_on_boss_defeated)
	_player.died.connect(_on_player_died)

	_upgrades.bind_plasma_weapon(_weapon)
	_apply_hangar_profile()
	_apply_difficulty()
	if _secondary != null:
		var dmg_mult := _profile.weapon_damage_mult if _profile != null else 1.0
		_secondary.configure(_player_bullet_pool, _player, _director, _boss, dmg_mult)
		_upgrades.bind_combat(_player, _secondary)
	_upgrade_screen.configure(_upgrades, _rules.rerolls_per_run)
	_upgrade_screen.upgrade_selected.connect(_on_upgrade_selected)
	_upgrade_screen.closed.connect(_on_upgrade_screen_closed)
	_xp.track_player(_player)
	_xp.leveled_up.connect(_on_leveled_up)

	_health_bar.visible = false
	_banner.visible = false
	_overlay.draw.connect(_on_overlay_draw)
	_hud.quit_to_menu_requested.connect(_on_hud_quit_to_menu)
	_hud.pause_gate = _can_pause
	_hud.configure_abilities(_rules.ability_left_charges, _rules.ability_left_cooldown,
		_rules.ability_right_charges, _rules.ability_right_cooldown)
	_hud.ability_left_activated.connect(_on_ability_feedback.bind(true))
	_hud.ability_right_activated.connect(_on_ability_feedback.bind(false))
	_begin_run()


## Derives this run's combat stats from the selected ship + hangar levels and
## applies them to the player and weapon via runtime copies (no Resource writes).
func _apply_hangar_profile() -> void:
	var catalog: ShipCatalogData = load(_CATALOG_PATH) as ShipCatalogData
	if catalog == null:
		return
	var ship := catalog.find_by_id(SaveManager.get_selected_ship_id())
	if ship == null:
		return
	var levels := SaveManager.get_upgrade_levels(ship.id)
	# Stats are measured against the starter ship so better hulls really are better.
	var reference := catalog.find_by_id(catalog.default_ship_id())
	_profile = CombatProfile.from_hangar(ship, levels, reference)
	if _player != null:
		_player.apply_combat_profile(_profile)
	if _weapon != null:
		_weapon.add_damage_mult(_profile.weapon_damage_mult)
		_weapon.set_crit(_profile.crit_chance, _profile.crit_multiplier)


## Resolves the run's difficulty profile (payload override or campaign setting)
## and the stage's graded scalar, then applies scaling to enemies, the boss,
## boss timing, and the reward/star multipliers. Never mutates shared resources.
func _apply_difficulty() -> void:
	if _difficulty_id == "":
		_difficulty_id = SaveManager.get_campaign_difficulty()
	_difficulty = load(_DIFFICULTY_DIR + _difficulty_id + ".tres") as RunDifficultyData
	if _difficulty == null:
		_difficulty = load(_DIFFICULTY_DIR + "normal.tres") as RunDifficultyData
	if _difficulty == null:
		return
	var scalar := _stage_difficulty_scalar()
	var enemy_hp := _difficulty.enemy_hp_mult * scalar
	var boss_hp := _difficulty.boss_hp_mult * scalar
	# One enemy-damage multiplier drives contact, enemy bolts, and boss attacks.
	var enemy_dmg := _difficulty.enemy_contact_damage_mult * (1.0 + (scalar - 1.0) * _STAGE_DAMAGE_SHARE)
	if _director != null:
		_director.set_difficulty(enemy_hp, enemy_dmg, _difficulty.enemy_count_add)
	if _boss != null:
		_boss.set_scaling(boss_hp, enemy_dmg)
		_boss.set_add_scaling(enemy_hp, enemy_dmg)
	if _enemy_bullet_pool != null:
		_enemy_bullet_pool.damage_mult = enemy_dmg
	_reward_mult = _difficulty.reward_mult
	_star_score_mult = _difficulty.star_score_mult
	_timing_scale = clampf(_difficulty.timing_scale, 0.4, 1.0)


## Per-stage graded difficulty from the map node (1.0 when off-map / missing).
func _stage_difficulty_scalar() -> float:
	if _stage_id == "":
		return 1.0
	var map: StageMapData = load(_STAGE_MAP_PATH) as StageMapData
	if map == null:
		return 1.0
	var stage := map.find_by_id(_stage_id)
	return stage.difficulty_scalar if stage != null else 1.0


## Per-stage authored timeline from the map node (null when off-map / unset so the
## caller falls back to the shared vertical-slice timeline).
func _resolve_stage_timeline() -> StageTimelineData:
	if _stage_id == "":
		return null
	var map: StageMapData = load(_STAGE_MAP_PATH) as StageMapData
	if map == null:
		return null
	var stage := map.find_by_id(_stage_id)
	return stage.timeline if stage != null else null


func _adapt_screen_size() -> void:
	var vp := get_viewport().get_visible_rect().size
	_screen = Vector2(maxi(1080, int(vp.x)), maxi(1920, int(vp.y)))
	var bounds := PlayfieldBounds.from_screen(_screen)
	if _director != null:
		_director.screen_size = _screen
		_director.despawn_bounds = bounds
	if _boss != null:
		_boss.screen_size = _screen
		_boss.despawn_bounds = bounds
	if _player_bullet_pool != null:
		_player_bullet_pool.despawn_bounds = bounds
	if _enemy_bullet_pool != null:
		_enemy_bullet_pool.despawn_bounds = bounds


func _mini_at() -> float:
	if timeline == null:
		return 60.0
	return 12.0 if _fast else timeline.mini_boss_at * _timing_scale


func _boss_at() -> float:
	if timeline == null:
		return 150.0
	return 24.0 if _fast else timeline.boss_warning_at * _timing_scale


func _guaranteed_at() -> float:
	if timeline == null:
		return 0.0
	var t := timeline.guaranteed_level_up_at
	if t <= 0.0:
		return 0.0
	return 4.0 if _fast else t


func _begin_run() -> void:
	_stats = RunStats.new()
	_stats.run_id = "run_%d_%d" % [Time.get_ticks_msec(), randi()]
	_stats.sector = _sector
	_stats.stage_id = _stage_id
	_stats.difficulty = _difficulty_id if _difficulty_id != "" else SaveManager.get_campaign_difficulty()
	_stats.reward_mult = _reward_mult
	_stats.star_score_mult = _star_score_mult
	_stats.is_daily = _is_daily
	_stats.daily_date = _daily_date
	_stats.daily_reward_core = _daily_reward_core
	_combo = 0
	_combo_timer = 0.0
	_run_time = 0.0
	_run_over = false
	_run_active = true
	_results_timer = 0.0
	_level_up_queue = 0
	_guaranteed_level_done = false
	_peak_enemy_bolts = 0
	_peak_enemies = 0
	_awaiting_boss_outcome = false
	_phase = Phase.EARLY_WAVES
	_health_bar.visible = false
	_banner.visible = false
	_hud.force_resume()
	_hud.bind(_player, _xp, _stats)
	_hud.set_boss_bar_visible(false)
	_hud.set_wave_info(_wave_label_for_phase())
	_clear_arena_projectiles()
	_boss.prepare(timeline.mini_boss if timeline != null else null)
	if timeline != null and timeline.early_wave != null:
		_director.start_wave(timeline.early_wave)
	else:
		_director.start()
	AudioManager.play_music("run")
	_show_banner("ENTER THE RIFT", 1.4)


## Android system Back / AppRoot routing: pause the run instead of quitting.
## Returns true when the event is consumed. Uses request_pause (not toggle) so a
## same-frame KEY_BACK cannot immediately undo the pause overlay.
func handle_system_back() -> bool:
	if _run_over or _phase == Phase.ENDING:
		# Absorb during end sequence so Back cannot kill the process mid-results.
		return true
	if _upgrade_screen != null and _upgrade_screen.visible:
		# Keep the level-up choice open; never exit the app from here.
		return true
	if _hud == null:
		return true
	if _hud.is_hud_paused():
		_hud.force_resume()
	else:
		_hud.request_pause()
	return true


func _unhandled_input(event: InputEvent) -> void:
	# QA hotkeys only exist in debug builds; a store build with a hardware
	# keyboard (Chromebook, Bluetooth) must not be able to skip or win runs.
	if not OS.is_debug_build():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_Q:
				GameFeel.cycle_quality()
			KEY_L:
				_xp.add_experience(_xp.get_xp_for_next())
			KEY_K:
				if _awaiting_boss_outcome and _boss.get_state() != Boss.State.IDLE:
					_boss.take_damage(_boss.data.max_health * 0.15)
			KEY_F6:
				debug_skip_to_mini_boss()
			KEY_F7:
				debug_skip_to_final_boss()
			KEY_F8:
				debug_force_victory()
			KEY_F9:
				debug_force_defeat()


## Probe / QA: jump the run clock to the mini-boss beat.
func debug_skip_to_mini_boss() -> void:
	if _run_over or _phase == Phase.ENDING:
		return
	if _phase == Phase.EARLY_WAVES:
		_run_time = _mini_at()
		_enter_mini_boss()


## Probe / QA: jump to the final boss warning.
func debug_skip_to_final_boss() -> void:
	if _run_over or _phase == Phase.ENDING or _phase == Phase.FINAL_BOSS:
		return
	_run_time = _boss_at()
	_enter_final_boss()


func debug_force_victory() -> void:
	if _run_over:
		return
	if _phase == Phase.MINI_BOSS or _phase == Phase.FINAL_BOSS:
		# Defeat sequence is async (~1.2s). If the boss never entered FIGHT
		# (still WARNING), debug_defeat still runs the DEFEATED beat.
		if _boss.get_state() == Boss.State.IDLE:
			_boss.prepare(timeline.mini_boss if _phase == Phase.MINI_BOSS else timeline.final_boss)
			_boss.begin()
		_boss.debug_defeat()
	else:
		_end_run(true)


func debug_force_defeat() -> void:
	if _run_over:
		return
	if _player.is_alive():
		_player.take_damage(_player.combat_data.max_health * 10.0)
	else:
		_end_run(false)


func get_phase_name() -> String:
	return _PHASE_NAMES[_phase] if _phase >= 0 and _phase < _PHASE_NAMES.size() else str(_phase)


func get_run_stats() -> RunStats:
	return _stats


func get_pool_snapshot() -> Dictionary:
	return {
		"enemy_bolts_peak": _peak_enemy_bolts,
		"enemies_peak": _peak_enemies,
		"enemy_pool": _enemy_pool.get_stats(),
		"enemy_bolts": _enemy_bullet_pool.get_stats(),
		"player_bolts": _player_bullet_pool.get_stats(),
		"pickups": _pickup_pool.get_stats(),
		"effects": _effects.get_stats(),
	}


func _process(delta: float) -> void:
	if _run_active and not _upgrade_screen.is_open():
		# The phase clock only advances while waves run, so a slow mini-boss fight
		# can never eat the mid waves or trigger the final boss early.
		if _phase == Phase.EARLY_WAVES or _phase == Phase.MID_WAVES:
			_run_time += delta
		_stats.survival_seconds += delta
		if _combo_timer > 0.0:
			_combo_timer = maxf(0.0, _combo_timer - delta)
			if _combo_timer == 0.0:
				_combo = 0
		_tick_timeline()
	if _run_over:
		_results_timer -= delta
		if _results_timer <= 0.0:
			_go_to_results()
	_peak_enemy_bolts = maxi(_peak_enemy_bolts, _enemy_bullet_pool.get_active_count())
	_peak_enemies = maxi(_peak_enemies, _director.get_active_enemy_count())
	if GameFeel.debug_markers_enabled:
		_overlay.queue_redraw()
	_update_readout()
	_update_hud()


func _tick_timeline() -> void:
	if not _guaranteed_level_done and _guaranteed_at() > 0.0 and _run_time >= _guaranteed_at():
		_guaranteed_level_done = true
		if timeline != null:
			_xp.add_experience(timeline.guaranteed_level_up_xp)
	match _phase:
		Phase.EARLY_WAVES:
			if _run_time >= _mini_at():
				_enter_mini_boss()
		Phase.MID_WAVES:
			if _run_time >= _boss_at():
				_enter_final_boss()


func _enter_mini_boss() -> void:
	if _phase != Phase.EARLY_WAVES:
		return
	_phase = Phase.MINI_BOSS
	_director.stop_and_clear()
	_clear_arena_projectiles()
	_awaiting_boss_outcome = true
	_hud.set_wave_info(_wave_label_for_phase())
	_boss.prepare(timeline.mini_boss)
	_boss.begin()
	AudioManager.play_music("boss")
	_show_banner("MINI-BOSS", 1.2)


func _enter_mid_waves() -> void:
	_phase = Phase.MID_WAVES
	_awaiting_boss_outcome = false
	_health_bar.visible = false
	_hud.set_boss_bar_visible(false)
	_hud.set_wave_info(_wave_label_for_phase())
	_clear_arena_projectiles()
	_boss.prepare(timeline.final_boss)
	if timeline != null and timeline.mid_wave != null:
		_director.start_wave(timeline.mid_wave)
	AudioManager.play_music("run")
	_show_banner("PUSH FORWARD", 1.0)


func _enter_final_boss() -> void:
	if _phase == Phase.FINAL_BOSS or _phase == Phase.ENDING:
		return
	_phase = Phase.FINAL_BOSS
	_director.stop_and_clear()
	_clear_arena_projectiles()
	_awaiting_boss_outcome = true
	_hud.set_wave_info(_wave_label_for_phase())
	_boss.prepare(timeline.final_boss)
	_boss.begin()
	AudioManager.play_music("boss")
	_show_banner("BOSS INCOMING", 1.4)


func _clear_arena_projectiles() -> void:
	_enemy_bullet_pool.release_all()
	_vacuum_pickups()


## Pulls every live energy pickup to the ship (phase changes used to delete
## uncollected energy, silently costing the player XP).
func _vacuum_pickups() -> void:
	for node in _pickup_pool.get_active_nodes():
		var pickup := node as Pickup
		if pickup != null:
			pickup.magnet_target = _player
			pickup.attract()


func _show_banner(text: String, seconds: float) -> void:
	_banner.text = text
	_banner.visible = true
	var tree := get_tree()
	if tree == null:
		return
	# Banner hide is time-based; ignore if the run already ended.
	await tree.create_timer(seconds).timeout
	if is_instance_valid(_banner) and _banner.text == text:
		_banner.visible = false


func _on_leveled_up(_new_level: int) -> void:
	_level_up_queue += 1
	_try_open_upgrade_screen()


func _try_open_upgrade_screen() -> void:
	if _upgrade_screen.is_open() or _level_up_queue <= 0 or _run_over:
		return
	# Do not open choices during boss warning entrance — wait until fight or mid.
	if _phase == Phase.MINI_BOSS or _phase == Phase.FINAL_BOSS:
		var st: int = _boss.get_state()
		if st == Boss.State.WARNING or st == Boss.State.ENTER:
			return
	_hud.force_resume()
	var level := _xp.get_level() - (_level_up_queue - 1)
	if not _upgrade_screen.open(level):
		_level_up_queue = 0


func _on_upgrade_selected(upgrade: UpgradeData) -> void:
	_last_upgrade = upgrade.id
	# Instant power-fantasy beat once combat unpauses (GameFeel only).
	var tint := Palette.get_color("cyan", Color(0.2, 0.95, 1.0))
	if upgrade != null:
		tint = Palette.get_color(upgrade.rarity_color_token(), tint)
	# Played from _on_upgrade_screen_closed, i.e. after the card screen has
	# unpaused the tree (a deferred call here still ran while paused).
	_pending_upgrade_tint = tint


func _on_upgrade_screen_closed() -> void:
	_level_up_queue = maxi(0, _level_up_queue - 1)
	_xp.consume_pending_level()
	if _pending_upgrade_tint.a > 0.0 and _player != null:
		GameFeel.upgrade_applied(_player.get_core_global_position(), _pending_upgrade_tint)
	_pending_upgrade_tint = Color(0, 0, 0, 0)
	# Do not auto-chain another choice here. Banked XP only levels on the next
	# energy gain so the player always gets combat between picks.


func _register_kill() -> void:
	_stats.enemies_destroyed += 1
	_combo += 1
	_combo_timer = _rules.combo_window_seconds
	if _combo > _stats.best_combo:
		_stats.best_combo = _combo
	# Milestone juice every 5 kills in the chain (feedback only).
	if _combo >= 5 and _combo % 5 == 0 and _player != null:
		GameFeel.combo_peak(_player.get_core_global_position(), _combo)


func _on_enemy_killed(_enemy: Enemy) -> void:
	_register_kill()


func _on_add_destroyed() -> void:
	_register_kill()


func _on_warning_started(boss_name: String) -> void:
	_health_bar.visible = true
	_hud.set_boss_bar_visible(true)
	_health_bar.setup(boss_name, _boss.data.health_segments)
	_health_bar.show_warning(boss_name)


func _on_boss_entered() -> void:
	_health_bar.hide_warning()
	_try_open_upgrade_screen()


func _on_boss_health_changed(current: float, maximum: float) -> void:
	_health_bar.set_health(current, maximum)


func _on_boss_phase_changed(phase: int) -> void:
	_health_bar.set_phase(phase)


## HP hit zero: the death beat still runs ~1.2s, so clear hostile fire and
## shield the player so a won fight can never flip into a defeat.
func _on_boss_dying() -> void:
	_enemy_bullet_pool.release_all()
	if _player != null:
		_player.grant_invulnerability(_rules.boss_kill_invuln_seconds)


## Wave ran dry before the phase clock reached its next beat: restart it when
## enough time remains, otherwise jump the clock forward (no dead air).
func _on_wave_finished() -> void:
	if _run_over:
		return
	var next_beat := -1.0
	var wave: WaveData = null
	if _phase == Phase.EARLY_WAVES:
		next_beat = _mini_at()
		wave = timeline.early_wave if timeline != null else null
	elif _phase == Phase.MID_WAVES:
		next_beat = _boss_at()
		wave = timeline.mid_wave if timeline != null else null
	else:
		return
	if wave != null and next_beat - _run_time >= _rules.wave_refill_min_seconds:
		_director.start_wave(wave)
	else:
		_run_time = maxf(_run_time, next_beat)


## Pause guard for the HUD: the upgrade cards own the tree pause while open.
func _can_pause() -> bool:
	return not _run_over and not _upgrade_screen.is_open()


## AppRoot calls this when the app goes to the background (home button, call,
## notification shade): open the pause overlay so combat never runs unattended.
func on_app_backgrounded() -> void:
	if _run_active and not _run_over and _hud != null:
		_hud.request_pause()


func _on_boss_defeated() -> void:
	if _phase == Phase.MINI_BOSS:
		_awaiting_boss_outcome = false
		_health_bar.visible = false
		_hud.set_boss_bar_visible(false)
		_enter_mid_waves()
		return
	if _phase == Phase.FINAL_BOSS:
		_end_run(true)


func _on_player_died() -> void:
	_end_run(false)


func _end_run(victory: bool) -> void:
	if _run_over:
		return
	_run_active = false
	_run_over = true
	_phase = Phase.ENDING
	_awaiting_boss_outcome = false
	if _weapon != null:
		_weapon.firing_active = false
	if _secondary != null:
		_secondary.disable()
	AudioManager.set_fire_loop_suppressed(false)
	AudioManager.stop_fire_loop()
	_hud.force_resume()
	_hud.set_boss_bar_visible(false)
	_stats.victory = victory
	if _player != null:
		_stats.rift_energy_collected = _player.get_energy()
	if _player != null and _player.combat_data != null and _player.combat_data.max_health > 0.0:
		_stats.hp_ratio_end = clampf(
			float(_player.get_health()) / float(_player.combat_data.max_health), 0.0, 1.0)
	else:
		_stats.hp_ratio_end = 0.0
	_director.stop()
	# Bank the run now (not when Results opens) so closing the app during the
	# end banner can never lose earned rewards.
	RunSettlement.settle(_stats)
	_results_timer = _rules.results_delay_seconds
	_banner.text = "SECTOR CLEARED" if victory else Brand.DEFEAT_LINE
	_banner.visible = true


func _go_to_results() -> void:
	_run_over = false
	_hud.force_resume()
	SceneRouter.go_to(SceneRouter.SCREEN_RESULTS, {"stats": _stats})


func _update_hud() -> void:
	if _hud == null or _stats == null:
		return
	_hud.set_combo(_combo)
	if not _boss_bar_showing():
		_hud.set_wave_info(_wave_label_for_phase())


func _boss_bar_showing() -> bool:
	return _health_bar != null and _health_bar.visible


func _wave_label_for_phase() -> String:
	match _phase:
		Phase.EARLY_WAVES:
			return "WAVE · EARLY"
		Phase.MINI_BOSS:
			return "MINI-BOSS"
		Phase.MID_WAVES:
			return "WAVE · MID"
		Phase.FINAL_BOSS:
			return "BOSS"
		Phase.ENDING:
			return "COMPLETE" if _stats != null and _stats.victory else "DEFEAT"
		_:
			return Brand.DISPLAY


func _on_hud_quit_to_menu() -> void:
	_run_active = false
	_run_over = true
	_director.stop()
	if _secondary != null:
		_secondary.disable()
	SceneRouter.go_to(SceneRouter.SCREEN_MAIN_MENU)


func _on_ability_feedback(is_left: bool) -> void:
	if _run_over or not _run_active:
		return
	# Real combat: fire the bound ability weapon (Missile Barrage / Arc Burst),
	# plus the presentation beat. Cooldown/charges are gated by the HUD button.
	if _secondary != null:
		_secondary.fire_ability(is_left)
	var pos := _player.get_core_global_position() + Vector2(0, -80)
	var tint := Palette.get_color("cyan") if is_left else Palette.get_color("purple")
	GameFeel.ability_activated(pos, tint)


func _update_readout() -> void:
	if _stats == null or _player == null:
		return
	_readout.visible = GameFeel.debug_markers_enabled
	if not _readout.visible:
		return
	var lines: Array[String] = []
	lines.append("%s RUN  [F6 mini  F7 boss  F8 win  F9 lose]" % Brand.DISPLAY)
	lines.append("FPS %d  t=%.1fs  phase=%s" % [
		Engine.get_frames_per_second(), _run_time, get_phase_name()])
	lines.append("HP %d/%d  Lv %d  XP %d/%d  last=%s" % [
		int(_player.get_health()), int(_player.combat_data.max_health),
		_xp.get_level(), _xp.get_xp_into_level(), _xp.get_xp_for_next(), _last_upgrade])
	lines.append("Kills %d  Combo x%d  Energy %d" % [
		_stats.enemies_destroyed, _combo, _player.get_energy()])
	var eb := _enemy_bullet_pool.get_stats()
	var ep := _enemy_pool.get_stats()
	lines.append("Enemies %d (peak %d)  Bolts %d (peak %d)  Pool total %d" % [
		_director.get_active_enemy_count(), _peak_enemies,
		int(eb["active"]), _peak_enemy_bolts, int(eb["total"])])
	lines.append("Adds/enemies pooled %d/%d  Quality %s" % [
		int(ep["active"]), int(ep["total"]), GameFeel.quality_name()])
	if _awaiting_boss_outcome:
		lines.append("Boss HP %d/%d" % [int(_boss.get_health()), int(_boss.data.max_health)])
	if _run_over:
		lines.append("%s → results..." % ("VICTORY" if _stats.victory else "DEFEAT"))
	_readout.text = "\n".join(lines)


func _on_overlay_draw() -> void:
	if not GameFeel.debug_markers_enabled:
		return
	var core := _player.get_core_global_position()
	_overlay.draw_circle(core, 6.0, Color(0, 0.84, 1, 0.9))
