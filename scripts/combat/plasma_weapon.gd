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

var _cooldown: float = 0.0
## A private duplicate of the weapon's projectile so a damage multiplier scales
## this run's bolts without mutating the shared .tres. Rebuilt only when the
## multiplier changes, so firing itself allocates nothing.
var _effective_projectile: ProjectileData = null


func _process(delta: float) -> void:
	if not firing_active or data == null or pool == null:
		return
	_cooldown -= delta
	# while-loop keeps fire cadence stable even if a frame is long, without
	# allocating; each iteration reuses a pooled projectile.
	var interval := 1.0 / (data.fire_rate * fire_rate_mult)
	while _cooldown <= 0.0:
		_fire()
		_cooldown += interval


func _fire() -> void:
	if data.projectile == null:
		return
	var projectile := _current_projectile()
	var origin := to_global(data.muzzle_offset)
	var count := data.projectiles_per_shot + bonus_projectiles
	var spread := data.spread_degrees + bonus_spread_degrees
	if count <= 1:
		pool.spawn(origin, Vector2.UP, projectile)
		return
	# Even fan centered on straight-up.
	var step := spread / float(count - 1)
	var start := -spread * 0.5
	for i in count:
		var angle_deg := start + step * float(i)
		var dir := Vector2.UP.rotated(deg_to_rad(angle_deg))
		pool.spawn(origin, dir, projectile)


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


## The projectile to fire this shot: the shared resource when damage is
## unmodified, otherwise a cached scaled duplicate.
func _current_projectile() -> ProjectileData:
	if is_equal_approx(damage_mult, 1.0):
		return data.projectile
	if _effective_projectile == null:
		_effective_projectile = data.projectile.duplicate() as ProjectileData
		_effective_projectile.damage = data.projectile.damage * damage_mult
	return _effective_projectile
