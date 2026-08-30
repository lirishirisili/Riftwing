extends Node2D
## Standalone debug harness for the first boss (Void Titan).
##
## Wires the player + auto weapon, the pooled projectile/enemy/pickup systems,
## and the Boss + segmented health bar, then drives the encounter and shows live
## state so the whole flow can be verified fast: warning entrance, health bar,
## every attack pattern with its telegraph, player damage, the 40% phase
## transition, defeat/victory, and pooled cleanup. No menus, results, or later
## milestones.
##
## Debug keys: Q cycles effect quality, K deals a big chunk of boss damage,
## R restarts the encounter.

@onready var _player: PlayerShip = $PlayerShip
@onready var _weapon: PlasmaWeapon = $PlayerShip/PlasmaWeapon
@onready var _boss: Boss = $Boss
@onready var _player_bullet_pool: ProjectilePool = $PlayerProjectilePool
@onready var _enemy_bullet_pool: ProjectilePool = $EnemyProjectilePool
@onready var _enemy_pool: NodePool = $EnemyPool
@onready var _pickup_pool: NodePool = $PickupPool
@onready var _effects: EffectsLayer = $EffectsLayer
@onready var _camera: CameraRig = $CameraRig
@onready var _overlay: Control = $Overlay
@onready var _health_bar: BossHealthBar = $UI/BossHealthBar
@onready var _readout: Label = $UI/Readout
@onready var _victory: Label = $UI/Victory

const _PICKUP_DATA_PATH := "res://resources/pickups/energy_small.tres"
const _KIND_NAMES := ["RADIAL", "LASER", "SUMMON"]
const _STATE_NAMES := ["IDLE", "WARNING", "ENTER", "FIGHT", "PHASE_TRANSITION", "DEFEATED"]
## A combo resets if no kill lands within this window.
const _COMBO_WINDOW := 2.5
## Delay after a run ends before routing to results, so the victory/defeat beat
## reads before the screen swaps.
const _RESULTS_DELAY := 1.6

var _screen := Vector2(1080, 1920)
var _defeated: bool = false
var _last_attack: String = "-"

## Live run statistics for the results screen (accumulated during play).
var _stats: RunStats
var _combo: int = 0
var _combo_timer: float = 0.0
var _run_active: bool = false
var _run_over: bool = false
var _results_timer: float = 0.0
## Sector handed in by the galaxy map / results navigation (1 by default).
var _sector: int = 1
## Stage id from the galaxy map (empty when launched ad-hoc).
var _stage_id: String = ""


## Router handoff: the map / results screen pass which sector and stage to play.
func receive_payload(payload: Dictionary) -> void:
	if payload.has("sector"):
		_sector = maxi(1, int(payload["sector"]))
	if payload.has("stage_id"):
		_stage_id = String(payload["stage_id"])


func _ready() -> void:
	var pickup_data: PickupData = load(_PICKUP_DATA_PATH)
	_weapon.pool = _player_bullet_pool
	_adapt_screen_size()
	get_viewport().size_changed.connect(_adapt_screen_size)

	# Inject the boss's dependencies (mirrors how WaveDirector wires enemies).
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
	_boss.attack_started.connect(_on_boss_attack_started)
	_boss.add_destroyed.connect(_on_add_destroyed)
	_boss.defeated.connect(_on_boss_defeated)
	_player.died.connect(_on_player_died)

	_victory.visible = false
	_overlay.draw.connect(_on_overlay_draw)
	_begin_run()


func _adapt_screen_size() -> void:
	var vp := get_viewport().get_visible_rect().size
	_screen = Vector2(maxi(1080, int(vp.x)), maxi(1920, int(vp.y)))
	var bounds := PlayfieldBounds.from_screen(_screen)
	_player_bullet_pool.despawn_bounds = bounds
	_enemy_bullet_pool.despawn_bounds = bounds
	if _boss != null:
		_boss.screen_size = _screen
		_boss.despawn_bounds = bounds


func _begin_run() -> void:
	# Fresh statistics for this run, tagged with a unique id so the results screen
	# grants its rewards exactly once.
	_stats = RunStats.new()
	_stats.run_id = "run_%d_%d" % [Time.get_ticks_msec(), randi()]
	_stats.sector = _sector
	_stats.stage_id = _stage_id
	_combo = 0
	_combo_timer = 0.0
	_run_over = false
	_run_active = true
	_results_timer = 0.0
	_boss.begin()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_Q:
				GameFeel.cycle_quality()
			KEY_K:
				# Deal a readable chunk so phase/defeat can be reached on demand.
				_boss.take_damage(_boss.data.max_health * 0.12)
			KEY_R:
				_restart()


func _restart() -> void:
	_defeated = false
	_victory.visible = false
	_begin_run()


func _process(delta: float) -> void:
	if _run_active:
		_stats.survival_seconds += delta
		if _combo_timer > 0.0:
			_combo_timer = maxf(0.0, _combo_timer - delta)
			if _combo_timer == 0.0:
				_combo = 0
	# Once a run ends, hold the beat briefly, then route to the results screen.
	if _run_over:
		_results_timer -= delta
		if _results_timer <= 0.0:
			_go_to_results()
	_overlay.queue_redraw()
	_update_readout()


func _register_kill() -> void:
	_stats.enemies_destroyed += 1
	_combo += 1
	_combo_timer = _COMBO_WINDOW
	if _combo > _stats.best_combo:
		_stats.best_combo = _combo


func _end_run(victory: bool) -> void:
	if _run_over:
		return
	_run_active = false
	_run_over = true
	_stats.victory = victory
	_stats.rift_energy_collected = _player.get_energy()
	_results_timer = _RESULTS_DELAY


func _go_to_results() -> void:
	_run_over = false
	SceneRouter.go_to(SceneRouter.SCREEN_RESULTS, {"stats": _stats})


func _on_warning_started(boss_name: String) -> void:
	_health_bar.setup(boss_name, _boss.data.health_segments)
	_health_bar.show_warning(boss_name)


func _on_boss_entered() -> void:
	_health_bar.hide_warning()


func _on_boss_health_changed(current: float, maximum: float) -> void:
	_health_bar.set_health(current, maximum)


func _on_boss_phase_changed(phase: int) -> void:
	_health_bar.set_phase(phase)


func _on_boss_attack_started(kind: int, _phase: int) -> void:
	_last_attack = _KIND_NAMES[kind] if kind >= 0 and kind < _KIND_NAMES.size() else str(kind)


func _on_add_destroyed() -> void:
	_register_kill()


func _on_boss_defeated() -> void:
	_defeated = true
	_victory.visible = true
	_end_run(true)


func _on_player_died() -> void:
	_end_run(false)


func _update_readout() -> void:
	_readout.visible = GameFeel.debug_markers_enabled
	if not _readout.visible:
		return
	var lines: Array[String] = []
	lines.append("BOSS DEBUG  [Q quality  K damage  R restart]")
	lines.append("FPS %d" % Engine.get_frames_per_second())
	var st: int = _boss.get_state()
	lines.append("State: %s  Phase %d" % [_STATE_NAMES[st] if st < _STATE_NAMES.size() else str(st), _boss.get_phase()])
	lines.append("Boss HP %d / %d  (%.0f%%)" % [
		int(_boss.get_health()), int(_boss.data.max_health), _boss.get_health_fraction() * 100.0])
	lines.append("Last attack: %s" % _last_attack)
	lines.append("Player HP %d / %d" % [int(_player.get_health()), int(_player.combat_data.max_health)])
	var pb := _player_bullet_pool.get_stats()
	var eb := _enemy_bullet_pool.get_stats()
	var ep := _enemy_pool.get_stats()
	lines.append("Player bolts %d/%d  Enemy bolts %d/%d" % [pb["active"], pb["total"], eb["active"], eb["total"]])
	lines.append("Adds active %d/%d (peak %d)" % [ep["active"], ep["total"], ep["peak"]])
	lines.append("Quality [Q]: %s" % GameFeel.quality_name())
	lines.append("Sector %d  Kills %d  Combo x%d (best x%d)" % [
		_stats.sector, _stats.enemies_destroyed, _combo, _stats.best_combo])
	lines.append("Survival %.1fs  Energy %d" % [_stats.survival_seconds, _player.get_energy()])
	lines.append("Bank: Energy %d  Core %d  Best %d" % [
		SaveManager.get_rift_energy(), SaveManager.get_rift_core(), SaveManager.get_best_score()])
	if _run_over:
		lines.append("%s - opening results..." % ("VICTORY" if _stats.victory else "DEFEAT"))
	elif _defeated:
		lines.append("VICTORY - boss defeated")
	if not _player.is_alive():
		lines.append("PLAYER DOWN")
	_readout.text = "\n".join(lines)


func _on_overlay_draw() -> void:
	if not GameFeel.debug_markers_enabled:
		return
	var core := _player.get_core_global_position()
	_overlay.draw_circle(core, 6.0, Color(0, 0.84, 1, 0.9))
