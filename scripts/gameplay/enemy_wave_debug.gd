extends Node2D
## Debug harness for the enemy-wave milestone.
##
## Wires the player + auto weapon, the WaveDirector, and the enemy/enemy-bullet/
## pickup pools, then displays live stats (player HP, energy, active enemies,
## kills, and pool usage) so spawning, movement, damage, death, pickup drops,
## and pool reuse can all be verified. No upgrades, bosses, menus, or polish.

@onready var _player: PlayerShip = $PlayerShip
@onready var _weapon: PlasmaWeapon = $PlayerShip/PlasmaWeapon
@onready var _director: WaveDirector = $WaveDirector
@onready var _enemy_pool: NodePool = $EnemyPool
@onready var _enemy_bullet_pool: ProjectilePool = $EnemyProjectilePool
@onready var _pickup_pool: NodePool = $PickupPool
@onready var _effects: EffectsLayer = $EffectsLayer
@onready var _camera: CameraRig = $CameraRig
@onready var _overlay: Control = $Overlay
@onready var _readout: Label = $UI/Readout
@onready var _xp: ExperienceTracker = $ExperienceTracker
@onready var _upgrades: UpgradeManager = $UpgradeManager
@onready var _upgrade_screen: UpgradeScreen = $UpgradeScreen

const _PICKUP_DATA_PATH := "res://resources/pickups/energy_small.tres"

var _kills: int = 0
var _first_wave_cleared: bool = false
var _initial_wave_spawned: bool = false
var _peak_enemies: int = 0
## Level-ups earned but not yet resolved by an upgrade choice. The screen shows
## one at a time; combat only resumes once the queue is drained.
var _level_up_queue: int = 0
var _last_upgrade: String = "-"


func _ready() -> void:
	var pickup_data: PickupData = load(_PICKUP_DATA_PATH)

	# Inject the director's dependencies (data resources + pooled systems).
	_director.enemy_pool = _enemy_pool
	_director.enemy_projectile_pool = _enemy_bullet_pool
	_director.pickup_pool = _pickup_pool
	_director.pickup_data = pickup_data
	_director.player = _player
	_director.screen_size = Vector2(1080, 1920)

	# Count kills as enemies die so we can confirm destruction + wave clear.
	_director.enemy_killed.connect(_on_enemy_killed)

	_weapon.pool = $PlayerProjectilePool

	# Progression: energy collected becomes XP; each level offers three upgrades.
	_upgrades.bind_plasma_weapon(_weapon)
	_upgrade_screen.configure(_upgrades)
	_upgrade_screen.upgrade_selected.connect(_on_upgrade_selected)
	_upgrade_screen.closed.connect(_on_upgrade_screen_closed)
	_xp.track_player(_player)
	_xp.leveled_up.connect(_on_leveled_up)

	_director.start()
	_overlay.draw.connect(_on_overlay_draw)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		# Q cycles effect quality (LOW/MEDIUM/HIGH) live so the budget is observable.
		if event.keycode == KEY_Q:
			GameFeel.cycle_quality()
		# L forces a level-up immediately so the upgrade screen can be opened on
		# demand without collecting pickups (debug command from the prompt).
		elif event.keycode == KEY_L:
			_xp.add_experience(_xp.get_xp_for_next())


## Queues a level-up; opens the choice screen when combat is not already paused.
func _on_leveled_up(_new_level: int) -> void:
	_level_up_queue += 1
	_try_open_upgrade_screen()


func _try_open_upgrade_screen() -> void:
	if _upgrade_screen.is_open() or _level_up_queue <= 0:
		return
	# Present the level currently being consumed (current level minus what is
	# still queued behind this one).
	var level := _xp.get_level() - (_level_up_queue - 1)
	if not _upgrade_screen.open(level):
		# Nothing offerable (everything maxed): drop the queued levels and resume.
		_level_up_queue = 0


func _on_upgrade_selected(upgrade: UpgradeData) -> void:
	_last_upgrade = upgrade.id


func _on_upgrade_screen_closed() -> void:
	_level_up_queue = maxi(0, _level_up_queue - 1)
	_xp.consume_pending_level()
	# More levels pending (a big burst)? Show the next choice before resuming.
	if _level_up_queue > 0:
		_try_open_upgrade_screen()


func _process(_delta: float) -> void:
	var active := _director.get_active_enemy_count()
	_peak_enemies = maxi(_peak_enemies, active)
	if active > 0:
		_initial_wave_spawned = true
	elif _initial_wave_spawned and not _first_wave_cleared and _kills > 0:
		_first_wave_cleared = true

	_overlay.queue_redraw()
	_update_readout(active)


func _on_enemy_killed(_enemy: Enemy) -> void:
	_kills += 1


func _update_readout(active: int) -> void:
	var es := _enemy_pool.get_stats()
	var bs := _enemy_bullet_pool.get_stats()
	var ps := _pickup_pool.get_stats()
	var lines := PackedStringArray()
	lines.append("FPS %d" % Engine.get_frames_per_second())
	lines.append("HP %d / %d" % [int(_player.get_health()), int(_player.combat_data.max_health)])
	lines.append("Energy %d" % _player.get_energy())
	lines.append("Enemies active %d (peak %d)" % [active, _peak_enemies])
	lines.append("Kills %d" % _kills)
	lines.append("Enemy pool: active %d / total %d (prewarm %d)" % [es["active"], es["total"], es["prewarm"]])
	lines.append("Enemy bullets: active %d / total %d" % [bs["active"], bs["total"]])
	lines.append("Pickups: active %d / total %d" % [ps["active"], ps["total"]])
	lines.append("First wave cleared: %s" % ("YES" if _first_wave_cleared else "no"))
	# Game-feel surfaces (Q cycles quality).
	var fx := _effects.get_stats()
	var c := GameFeel.counters
	lines.append("--- feel ---")
	lines.append("Quality [Q]: %s" % GameFeel.quality_name())
	lines.append("Trauma %.2f  hitstop x%d" % [_camera.get_trauma(), c["hitstop"]])
	lines.append("Flash %d/%d  Boom %d/%d  Dmg# %d/%d" % [
		fx["flash_active"], fx["flash_total"],
		fx["explosion_active"], fx["explosion_total"],
		fx["damage_active"], fx["damage_total"]])
	lines.append("Fired: flash %d expS %d expL %d dmg# %d shake %d haptic %d" % [
		c["hit_flash"], c["explosion_small"], c["explosion_large"],
		c["damage_number"], c["shake"], c["haptic"]])
	lines.append("SFX: %d (%s x%d)" % [AudioManager.sfx_count, AudioManager.last_sfx, AudioManager.cue_count(AudioManager.last_sfx)])
	# Progression surfaces (L forces a level-up).
	lines.append("--- progression [L = level up] ---")
	lines.append("Level %d  XP %d / %d  (pending %d)" % [
		_xp.get_level(), _xp.get_xp_into_level(), _xp.get_xp_for_next(), _level_up_queue])
	lines.append("Weapons %d/%d  last pick: %s" % [
		_upgrades.weapon_count(), _upgrades.max_weapons, _last_upgrade])
	lines.append("Plasma: rate x%.2f  +%d bolts  dmg x%.2f" % [
		_weapon.fire_rate_mult, _weapon.bonus_projectiles, _weapon.damage_mult])
	if not _player.is_alive():
		lines.append("PLAYER DOWN")
	_readout.text = "\n".join(lines)


func _on_overlay_draw() -> void:
	# Mark the player's small collision core for clarity.
	var core := _player.get_core_global_position()
	_overlay.draw_circle(core, 6.0, Color(0, 0.84, 1, 0.9))
