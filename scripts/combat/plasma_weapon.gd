class_name PlasmaWeapon
extends Node2D
## Auto-firing weapon driven by WeaponData.
##
## While firing is active it emits shots on a fixed data-driven interval, pulling
## projectiles from a ProjectilePool (no per-shot instantiate/free). Firing is
## gated by `firing_active` so it only runs while the run state is active.

@export var data: WeaponData
@export var pool: ProjectilePool
## When true, the weapon auto-fires. Later the RunController drives this.
@export var firing_active: bool = true

## Runtime upgrade modifiers, layered on top of the WeaponData baseline so the
## resource stays the shared source of truth and upgrades never mutate it.
## UpgradeManager writes these through the add_* methods when plasma is upgraded.
var fire_rate_mult: float = 1.0
var bonus_projectiles: int = 0
var bonus_spread_degrees: float = 0.0
var damage_mult: float = 1.0
## Per-volley critical chance (0..1) and multiplier, supplied by the run's
## CombatProfile (hangar CRIT stat). A crit volley fires boosted bolts.
var crit_chance: float = 0.0
var crit_multiplier: float = 1.75

var _cooldown: float = 0.0
## A private duplicate of the weapon's projectile so a damage multiplier scales
## this run's bolts without mutating the shared .tres. Rebuilt only when the
## multiplier changes, so firing itself allocates nothing.
var _effective_projectile: ProjectileData = null
## Cached crit-damage duplicate (base effective damage * crit_multiplier).
var _crit_projectile: ProjectileData = null
var _rng := RandomNumberGenerator.new()
var _fire_loop_held: bool = false


func _process(delta: float) -> void:
	if not firing_active or data == null or pool == null:
		_release_fire_loop()
		return
	_ensure_fire_loop()
	_cooldown -= delta
	# while-loop keeps fire cadence stable even if a frame is long, without
	# allocating; each iteration reuses a pooled projectile.
	var interval := 1.0 / (data.fire_rate * fire_rate_mult)
	while _cooldown <= 0.0:
		_fire()
		_cooldown += interval


func _ensure_fire_loop() -> void:
	if _fire_loop_held:
		return
	AudioManager.start_fire_loop()
	_fire_loop_held = true


func _release_fire_loop() -> void:
	if not _fire_loop_held:
		return
	AudioManager.stop_fire_loop()
	_fire_loop_held = false


func _exit_tree() -> void:
	_release_fire_loop()


func _fire() -> void:
	if data.projectile == null:
		return
	var is_crit := crit_chance > 0.0 and _rng.randf() < crit_chance
	var projectile := _crit_projectile_for() if is_crit else _current_projectile()
	var origin := to_global(data.muzzle_offset)
	var count := data.projectiles_per_shot + bonus_projectiles
	var spread := data.spread_degrees + bonus_spread_degrees
	if count <= 1:
		pool.spawn(origin, Vector2.UP, projectile)
	else:
		# Even fan centered on straight-up.
		var step := spread / float(count - 1)
		var start := -spread * 0.5
		for i in count:
			var angle_deg := start + step * float(i)
			var dir := Vector2.UP.rotated(deg_to_rad(angle_deg))
			pool.spawn(origin, dir, projectile)
	# One muzzle + fire cue per volley (not per bolt).
	GameFeel.weapon_fire(origin)


# --- Upgrade hooks (called by UpgradeManager) --------------------------------

func add_fire_rate_mult(mult: float) -> void:
	fire_rate_mult *= mult


func add_projectiles(count: int) -> void:
	bonus_projectiles += count


func add_spread_degrees(degrees: float) -> void:
	bonus_spread_degrees += degrees


func add_damage_mult(mult: float) -> void:
	damage_mult *= mult
	_effective_projectile = null  # rebuilt lazily on next fire
	_crit_projectile = null


## Sets per-volley crit from the run's CombatProfile (hangar CRIT stat).
func set_crit(chance: float, multiplier: float) -> void:
	crit_chance = clampf(chance, 0.0, 1.0)
	crit_multiplier = maxf(1.0, multiplier)
	_crit_projectile = null


## Adds crit chance from a run upgrade, stacking on the hangar baseline.
func add_crit_chance(amount: float) -> void:
	crit_chance = clampf(crit_chance + amount, 0.0, 0.95)
	_crit_projectile = null


## The projectile to fire this shot: the shared resource when damage is
## unmodified, otherwise a cached scaled duplicate.
func _current_projectile() -> ProjectileData:
	if is_equal_approx(damage_mult, 1.0):
		return data.projectile
	if _effective_projectile == null:
		_effective_projectile = data.projectile.duplicate() as ProjectileData
		_effective_projectile.damage = data.projectile.damage * damage_mult
	return _effective_projectile


## A cached duplicate carrying crit-boosted damage, so crit volleys allocate
## nothing after the first crit and never mutate the shared .tres.
func _crit_projectile_for() -> ProjectileData:
	if _crit_projectile == null:
		var base := _current_projectile()
		_crit_projectile = base.duplicate() as ProjectileData
		_crit_projectile.damage = base.damage * crit_multiplier
	return _crit_projectile
