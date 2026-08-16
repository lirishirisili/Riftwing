class_name SecondaryWeaponSystem
extends Node2D
## Runtime host for acquired secondary weapons and the two HUD abilities.
##
## Continuous weapons (homing missiles, arc laser, guardian drone, chain
## lightning) auto-fire on their data-driven interval; ability weapons fire on
## demand when the HUD ability buttons emit. Every bolt is pulled from the shared
## player ProjectilePool, so acquiring more weapons never grows pool memory
## unboundedly and hits resolve through the same collision path as the plasma
## cannon (enemies and the boss are damaged identically).
##
## All balance lives in SecondaryWeaponData resources. This node only holds
## behavior and per-run runtime modifiers (upgrade multipliers), and it never
## mutates a shared Resource — projectile copies are duplicated per weapon.

## Every secondary weapon / ability that can exist this run. Ability entries are
## registered immediately on configure(); continuous weapons on acquire().
@export var catalog: Array[SecondaryWeaponData] = []

## Ability ids bound to the two HUD buttons.
const ABILITY_LEFT_ID := "ability_missiles"
const ABILITY_RIGHT_ID := "ability_arc"

## Minimum interval so a mis-authored resource can never busy-loop the fire tick.
const _MIN_INTERVAL := 0.05

var pool: ProjectilePool
var player: Node2D
var director: WaveDirector
var boss: Node2D

## Hangar ATK damage multiplier applied on top of every secondary bolt.
var _global_damage_mult: float = 1.0
var _rng := RandomNumberGenerator.new()
var _catalog_by_id: Dictionary = {}
## id -> {data, timer, damage_mult, rate_mult, bonus_count, proj}
var _active: Dictionary = {}
var _enabled: bool = false


func _ready() -> void:
	_rng.randomize()
	for data in catalog:
		if data != null and data.id != "":
			_catalog_by_id[data.id] = data
	set_process(false)


## Injects run dependencies and registers the always-available abilities.
func configure(p_pool: ProjectilePool, p_player: Node2D, p_director: WaveDirector,
		p_boss: Node2D, damage_mult: float = 1.0) -> void:
	pool = p_pool
	player = p_player
	director = p_director
	boss = p_boss
	_global_damage_mult = maxf(0.01, damage_mult)
	for id in _catalog_by_id.keys():
		var data: SecondaryWeaponData = _catalog_by_id[id]
		if data.is_ability:
			_register(id)
	_enabled = true
	set_process(true)


## Deterministic seeding for probes.
func set_seed(seed_value: int) -> void:
	_rng.seed = seed_value


## Stops all firing (call at run end).
func disable() -> void:
	_enabled = false
	set_process(false)


## True when a weapon/ability id is currently active this run.
func has_weapon(id: String) -> bool:
	return _active.has(id)


## Number of active continuous weapons (excludes abilities).
func active_weapon_count() -> int:
	var n := 0
	for id in _active.keys():
		var e: Dictionary = _active[id]
		if not (e["data"] as SecondaryWeaponData).is_ability:
			n += 1
	return n


## Acquires a continuous secondary weapon by id (idempotent). Returns true when a
## new weapon was added.
func acquire(id: String) -> bool:
	if not _catalog_by_id.has(id) or _active.has(id):
		return false
	_register(id)
	return true


func _register(id: String) -> void:
	var data: SecondaryWeaponData = _catalog_by_id[id]
	var entry := {
		"data": data,
		"timer": data.interval,
		"damage_mult": 1.0,
		"rate_mult": 1.0,
		"bonus_count": 0,
		"proj": null,
	}
	_active[id] = entry
	_rebuild_projectile(entry)


# --- Upgrade hooks (called by UpgradeManager) --------------------------------

func add_damage_mult(target: String, mult: float) -> void:
	for entry in _entries_for(target):
		entry["damage_mult"] = float(entry["damage_mult"]) * mult
		_rebuild_projectile(entry)


func add_rate_mult(target: String, mult: float) -> void:
	for entry in _entries_for(target):
		entry["rate_mult"] = float(entry["rate_mult"]) * mult


func add_count(target: String, amount: int) -> void:
	for entry in _entries_for(target):
		entry["bonus_count"] = int(entry["bonus_count"]) + amount


## Runtime bolts-per-shot for a weapon (probe / debug).
func shots_per_volley(id: String) -> int:
	if not _active.has(id):
		return 0
	var e: Dictionary = _active[id]
	return (e["data"] as SecondaryWeaponData).projectiles_per_shot + int(e["bonus_count"])


## Effective damage of one bolt for a weapon (probe / debug).
func bolt_damage(id: String) -> float:
	if not _active.has(id):
		return 0.0
	var e: Dictionary = _active[id]
	var proj := e["proj"] as ProjectileData
	return proj.damage if proj != null else 0.0


func _entries_for(target: String) -> Array:
	var out: Array = []
	if target == "all":
		for id in _active.keys():
			out.append(_active[id])
	elif _active.has(target):
		out.append(_active[target])
	return out


func _rebuild_projectile(entry: Dictionary) -> void:
	var data := entry["data"] as SecondaryWeaponData
	if data == null or data.projectile == null:
		entry["proj"] = null
		return
	var proj := data.projectile.duplicate() as ProjectileData
	proj.damage = data.damage * float(entry["damage_mult"]) * _global_damage_mult
	entry["proj"] = proj


func _process(delta: float) -> void:
	if not _enabled or pool == null or player == null:
		return
	for id in _active.keys():
		var entry: Dictionary = _active[id]
		var data := entry["data"] as SecondaryWeaponData
		if data.is_ability:
			continue
		var interval := maxf(_MIN_INTERVAL, data.interval / maxf(0.01, float(entry["rate_mult"])))
		entry["timer"] = float(entry["timer"]) - delta
		var guard := 0
		while float(entry["timer"]) <= 0.0 and guard < 8:
			_fire(entry, false)
			entry["timer"] = float(entry["timer"]) + interval
			guard += 1


## Fires the ability bound to a HUD button. Returns true when an ability fired.
func fire_ability(is_left: bool) -> bool:
	var id := ABILITY_LEFT_ID if is_left else ABILITY_RIGHT_ID
	if not _active.has(id):
		return false
	_fire(_active[id], true)
	return true


func _fire(entry: Dictionary, is_ability: bool) -> void:
	var data := entry["data"] as SecondaryWeaponData
	var proj := entry["proj"] as ProjectileData
	if data == null or proj == null:
		return
	var origin := _muzzle(data)
	var count := maxi(1, data.projectiles_per_shot + int(entry["bonus_count"]))
	var base_dir := _aim_dir(origin) if data.homing else Vector2.UP
	if count <= 1:
		pool.spawn(origin, base_dir, proj)
	else:
		var step := data.spread_degrees / float(count - 1)
		var start := -data.spread_degrees * 0.5
		for i in count:
			var ang := deg_to_rad(start + step * float(i))
			pool.spawn(origin, base_dir.rotated(ang), proj)
	if is_ability:
		GameFeel.weapon_fire(origin)


func _muzzle(data: SecondaryWeaponData) -> Vector2:
	var base := Vector2.ZERO
	if player != null and player.has_method("get_core_global_position"):
		base = player.get_core_global_position()
	elif player != null:
		base = player.global_position
	return base + data.muzzle_offset


## Direction toward the nearest live target (enemy or boss), or straight up.
func _aim_dir(origin: Vector2) -> Vector2:
	var best := _nearest_target(origin)
	if best == Vector2.INF:
		return Vector2.UP
	var dir := best - origin
	return dir if dir.length() > 1.0 else Vector2.UP


func _nearest_target(origin: Vector2) -> Vector2:
	var best_pos := Vector2.INF
	var best_d := INF
	if director != null and director.has_method("nearest_enemy"):
		var e: Node2D = director.nearest_enemy(origin)
		if e != null:
			best_pos = e.global_position
			best_d = origin.distance_to(best_pos)
	if boss != null and is_instance_valid(boss) and boss.has_method("is_active") \
			and boss.is_active() and boss.get_health() > 0.0:
		var bd := origin.distance_to(boss.global_position)
		if bd < best_d:
			best_pos = boss.global_position
	return best_pos
