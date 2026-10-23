class_name SecondaryWeaponSystem
extends Node2D
## Runtime host for acquired secondary weapons and the two HUD abilities.
##
## Four delivery kinds (SecondaryWeaponData.Kind):
## - BOLT:  pooled projectiles (aimed, homing, piercing, exploding).
## - CHAIN: instant lightning that jumps between nearby targets.
## - BEAM:  a vertical piercing beam from the ship that ticks damage.
## - ORBIT: drones circling the ship (contact damage, aimed shots, optional
##          enemy-bolt blocking).
## Weapons level up (re-picking their card) and evolve into a stronger form.
## Also the player bolts' `targeter`: homing target lookup and area blasts
## (including multi-pulse vortexes) resolve here.
##
## Every bolt comes from the shared player ProjectilePool, so more weapons never
## grow pool memory unboundedly. All balance lives in SecondaryWeaponData /
## ProjectileData resources; this node holds behavior and per-run modifiers,
## and it never mutates a shared Resource (projectiles are duplicated per weapon).

## Every secondary weapon / ability that can exist this run. Ability entries are
## registered immediately on configure(); continuous weapons on acquire().
@export var catalog: Array[SecondaryWeaponData] = []

## Ability ids bound to the two HUD buttons.
const ABILITY_LEFT_ID := "ability_missiles"
const ABILITY_RIGHT_ID := "ability_arc"

## Minimum interval so a mis-authored resource can never busy-loop the fire tick.
const _MIN_INTERVAL := 0.05
## Contact / bolt-block cadence for orbiting drones.
const _ORBIT_TICK := 0.1
## Pending vortex pulses (fixed-size ring; extra requests are dropped).
const _MAX_PULSES := 12
## Area-hit damage numbers per blast (keeps the field readable).
const _MAX_NUMBERS_PER_BLAST := 6

var pool: ProjectilePool
var player: Node2D
var director: WaveDirector
var boss: Node2D
## Enemy bolt pool (drones that block bullets erase from it).
var enemy_bolts: ProjectilePool

## Hangar ATK damage multiplier applied on top of every secondary hit.
var _global_damage_mult: float = 1.0
var _rng := RandomNumberGenerator.new()
var _catalog_by_id: Dictionary = {}
## id -> entry Dictionary (see _register).
var _active: Dictionary = {}
var _enabled: bool = false
## Run-wide modifiers from "all"-targeted upgrades. Kept separately so weapons
## acquired AFTER the pick still receive the bonus.
var _all_damage_mult: float = 1.0
var _all_rate_mult: float = 1.0
var _all_count_add: int = 0
var _all_area_mult: float = 1.0

# Vortex pulses: parallel fixed arrays.
var _pulse_pos := PackedVector2Array()
var _pulse_radius := PackedFloat32Array()
var _pulse_damage := PackedFloat32Array()
var _pulse_left := PackedInt32Array()
var _pulse_timer := PackedFloat32Array()
var _pulse_interval := PackedFloat32Array()
## Reused hexagon buffer for drawing drones (no per-frame allocation).
var _hex := PackedVector2Array()


func _ready() -> void:
	_rng.randomize()
	z_index = 1
	for data in catalog:
		_index_catalog(data)
	_pulse_pos.resize(_MAX_PULSES)
	_pulse_radius.resize(_MAX_PULSES)
	_pulse_damage.resize(_MAX_PULSES)
	_pulse_left.resize(_MAX_PULSES)
	_pulse_timer.resize(_MAX_PULSES)
	_pulse_interval.resize(_MAX_PULSES)
	_hex.resize(7)
	set_process(false)


## Indexes a weapon and its evolution chain so evolved forms resolve by id.
func _index_catalog(data: SecondaryWeaponData) -> void:
	var d := data
	while d != null and d.id != "" and not _catalog_by_id.has(d.id):
		_catalog_by_id[d.id] = d
		d = d.evolves_into


## Injects run dependencies and registers the always-available abilities.
func configure(p_pool: ProjectilePool, p_player: Node2D, p_director: WaveDirector,
		p_boss: Node2D, damage_mult: float = 1.0) -> void:
	pool = p_pool
	player = p_player
	director = p_director
	boss = p_boss
	_global_damage_mult = maxf(0.01, damage_mult)
	if pool != null:
		pool.targeter = self
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
	queue_redraw()


## True when a weapon/ability id is currently active this run.
func has_weapon(id: String) -> bool:
	return _active.has(id)


## Number of active continuous weapons (excludes abilities).
func active_weapon_count() -> int:
	var n := 0
	for id in _active:
		if not (_active[id]["data"] as SecondaryWeaponData).is_ability:
			n += 1
	return n


## Acquires a continuous secondary weapon by id (idempotent). Returns true when a
## new weapon was added.
func acquire(id: String) -> bool:
	if not _catalog_by_id.has(id) or _active.has(id):
		return false
	_register(id)
	return true


## Raises an owned weapon's level (damage, rate, and every few levels +1
## bolt / arc jump / drone). Returns the new level (0 if not owned).
func level_up(id: String) -> int:
	if not _active.has(id):
		return 0
	var entry: Dictionary = _active[id]
	var data := entry["data"] as SecondaryWeaponData
	entry["level"] = int(entry["level"]) + 1
	var lvl := int(entry["level"])
	entry["damage_mult"] = float(entry["damage_mult"]) * data.level_damage_mult
	entry["rate_mult"] = float(entry["rate_mult"]) * data.level_rate_mult
	if data.level_count_every > 0 and (lvl - 1) % data.level_count_every == 0:
		entry["bonus_count"] = int(entry["bonus_count"]) + 1
	_rebuild_projectile(entry)
	return lvl


## Level of an owned weapon (0 when not owned).
func weapon_level(id: String) -> int:
	return int(_active[id]["level"]) if _active.has(id) else 0


## Swaps an owned weapon for its evolved form, keeping its level and modifiers.
## The entry stays keyed by the original id so upgrades that target it still
## apply. Returns true when the weapon evolved.
func evolve(id: String) -> bool:
	if not _active.has(id):
		return false
	var entry: Dictionary = _active[id]
	var data := entry["data"] as SecondaryWeaponData
	if data.evolves_into == null or bool(entry["evolved"]):
		return false
	entry["data"] = data.evolves_into
	entry["evolved"] = true
	entry["timer"] = 0.0
	_rebuild_projectile(entry)
	if player != null:
		GameFeel.evolve(_ship_pos())
	return true


func is_evolved(id: String) -> bool:
	return _active.has(id) and bool(_active[id]["evolved"])


## Display name of the weapon currently held under `id` (evolved name if any).
func weapon_name(id: String) -> String:
	return (_active[id]["data"] as SecondaryWeaponData).display_name if _active.has(id) else ""


func _register(id: String) -> void:
	var data: SecondaryWeaponData = _catalog_by_id[id]
	var entry := {
		"data": data,
		"timer": data.interval * 0.5,
		"damage_mult": 1.0,
		"rate_mult": 1.0,
		"bonus_count": 0,
		"level": 1,
		"evolved": false,
		"proj": null,
		# BEAM state.
		"beam_left": 0.0,
		"beam_tick": 0.0,
		# ORBIT state.
		"angle": 0.0,
		"orbit_tick": 0.0,
	}
	_active[id] = entry
	_rebuild_projectile(entry)


# --- Upgrade hooks (called by UpgradeManager) --------------------------------

func add_damage_mult(target: String, mult: float) -> void:
	if target == "all":
		_all_damage_mult *= mult
		for id in _active:
			_rebuild_projectile(_active[id])
		return
	for entry in _entries_for(target):
		entry["damage_mult"] = float(entry["damage_mult"]) * mult
		_rebuild_projectile(entry)


func add_rate_mult(target: String, mult: float) -> void:
	if target == "all":
		_all_rate_mult *= mult
		return
	for entry in _entries_for(target):
		entry["rate_mult"] = float(entry["rate_mult"]) * mult


func add_count(target: String, amount: int) -> void:
	if target == "all":
		_all_count_add += amount
		return
	for entry in _entries_for(target):
		entry["bonus_count"] = int(entry["bonus_count"]) + amount


## Scales every secondary area (blast radius, beam width, chain reach, orbit).
func add_area_mult(mult: float) -> void:
	_all_area_mult *= maxf(0.1, mult)
	for id in _active:
		_rebuild_projectile(_active[id])


func get_area_mult() -> float:
	return _all_area_mult


## Runtime bolts-per-shot for a weapon (probe / debug).
func shots_per_volley(id: String) -> int:
	if not _active.has(id):
		return 0
	var e: Dictionary = _active[id]
	return (e["data"] as SecondaryWeaponData).projectiles_per_shot + int(e["bonus_count"]) + _all_count_add


## Effective damage of one hit for a weapon (probe / debug).
func bolt_damage(id: String) -> float:
	if not _active.has(id):
		return 0.0
	return _hit_damage(_active[id])


func _entries_for(target: String) -> Array:
	var out: Array = []
	if target == "all":
		for id in _active:
			out.append(_active[id])
	elif _active.has(target):
		out.append(_active[target])
	return out


func _hit_damage(entry: Dictionary) -> float:
	var data := entry["data"] as SecondaryWeaponData
	return data.damage * float(entry["damage_mult"]) * _all_damage_mult * _global_damage_mult


func _rebuild_projectile(entry: Dictionary) -> void:
	var data := entry["data"] as SecondaryWeaponData
	if data == null or data.projectile == null:
		entry["proj"] = null
		return
	var proj := data.projectile.duplicate() as ProjectileData
	proj.damage = _hit_damage(entry)
	proj.explode_radius = data.projectile.explode_radius * _all_area_mult
	entry["proj"] = proj


# --- Tick ---------------------------------------------------------------------

func _process(delta: float) -> void:
	if not _enabled or pool == null or player == null:
		return
	var redraw := false
	for id in _active:
		var entry: Dictionary = _active[id]
		var data := entry["data"] as SecondaryWeaponData
		if data.is_ability:
			continue
		match data.kind:
			SecondaryWeaponData.Kind.BEAM:
				_tick_beam(entry, data, delta)
				redraw = true
			SecondaryWeaponData.Kind.ORBIT:
				_tick_orbit(entry, data, delta)
				redraw = true
			_:
				_tick_interval(entry, data, delta)
	_tick_pulses(delta)
	if redraw:
		queue_redraw()


func _interval_of(entry: Dictionary, data: SecondaryWeaponData) -> float:
	return maxf(_MIN_INTERVAL, data.interval / maxf(0.01, float(entry["rate_mult"]) * _all_rate_mult))


func _tick_interval(entry: Dictionary, data: SecondaryWeaponData, delta: float) -> void:
	var interval := _interval_of(entry, data)
	entry["timer"] = float(entry["timer"]) - delta
	var guard := 0
	while float(entry["timer"]) <= 0.0 and guard < 8:
		_fire(entry, false)
		entry["timer"] = float(entry["timer"]) + interval
		guard += 1


## Fires the ability bound to a HUD button. Returns true when an ability fired.
func fire_ability(is_left: bool) -> bool:
	if not _enabled:
		return false
	var id := ABILITY_LEFT_ID if is_left else ABILITY_RIGHT_ID
	if not _active.has(id):
		return false
	_fire(_active[id], true)
	return true


func _fire(entry: Dictionary, is_ability: bool) -> void:
	var data := entry["data"] as SecondaryWeaponData
	if data == null:
		return
	if data.kind == SecondaryWeaponData.Kind.CHAIN:
		_fire_chain(entry, data)
		return
	var proj := entry["proj"] as ProjectileData
	if proj == null:
		return
	var origin := _muzzle(data)
	var count := maxi(1, data.projectiles_per_shot + int(entry["bonus_count"]) + _all_count_add)
	var base_dir := _aim_dir(origin) if data.homing else Vector2.UP
	if count <= 1:
		pool.spawn(origin, base_dir, proj)
	else:
		var spread := maxf(data.spread_degrees, 10.0 * float(count - 1)) if data.spread_degrees <= 0.0 else data.spread_degrees
		var step := spread / float(count - 1)
		var start := -spread * 0.5
		for i in count:
			var ang := deg_to_rad(start + step * float(i))
			pool.spawn(origin, base_dir.rotated(ang), proj)
	if is_ability:
		GameFeel.weapon_fire(origin)


# --- CHAIN --------------------------------------------------------------------

func _fire_chain(entry: Dictionary, data: SecondaryWeaponData) -> void:
	var origin := _ship_pos()
	var reach := data.chain_range * _all_area_mult
	var first := nearest_target_node(origin, reach)
	if first == null:
		return
	var jumps := data.chain_jumps + int(entry["bonus_count"]) + _all_count_add
	var hop := data.chain_jump_range * _all_area_mult
	var dmg := _hit_damage(entry)
	var points := PackedVector2Array([origin + data.muzzle_offset * 0.5])
	var hit: Array[Node2D] = []
	var current: Node2D = first
	while current != null:
		points.append(current.global_position)
		hit.append(current)
		_damage_target(current, dmg)
		GameFeel.area_hit(current.global_position, dmg)
		if hit.size() > jumps:
			break
		current = _nearest_excluding(current.global_position, hop, hit)
	GameFeel.lightning(points, data.color)


# --- BEAM ---------------------------------------------------------------------

func _tick_beam(entry: Dictionary, data: SecondaryWeaponData, delta: float) -> void:
	var always_on := data.beam_duration >= data.interval
	if float(entry["beam_left"]) <= 0.0 and not always_on:
		entry["timer"] = float(entry["timer"]) - delta
		if float(entry["timer"]) <= 0.0:
			entry["timer"] = _interval_of(entry, data)
			entry["beam_left"] = data.beam_duration
			AudioManager.play_sfx("ability", _ship_pos(), AudioManager.PRIORITY_LOW)
		return
	if not always_on:
		entry["beam_left"] = float(entry["beam_left"]) - delta
	entry["beam_tick"] = float(entry["beam_tick"]) - delta
	if float(entry["beam_tick"]) > 0.0:
		return
	entry["beam_tick"] = data.beam_tick
	var half := data.beam_half_width * _all_area_mult
	var muzzle := _muzzle(data)
	var dmg := _hit_damage(entry)
	for t in _targets_snapshot():
		var r := _target_radius(t)
		if t.global_position.y < muzzle.y + r and absf(t.global_position.x - muzzle.x) <= half + r:
			_damage_target(t, dmg)
			if _rng.randf() < 0.35:
				GameFeel.area_hit(t.global_position, dmg)


func _beam_active(entry: Dictionary, data: SecondaryWeaponData) -> bool:
	return data.beam_duration >= data.interval or float(entry["beam_left"]) > 0.0


# --- ORBIT --------------------------------------------------------------------

func _orbit_count(entry: Dictionary, data: SecondaryWeaponData) -> int:
	return clampi(data.orbit_count + int(entry["bonus_count"]) + _all_count_add, 1, 8)


func _orbit_pos(entry: Dictionary, data: SecondaryWeaponData, i: int, n: int) -> Vector2:
	var a := float(entry["angle"]) + TAU * float(i) / float(n)
	return _ship_pos() + Vector2.RIGHT.rotated(a) * data.orbit_radius * _all_area_mult


func _tick_orbit(entry: Dictionary, data: SecondaryWeaponData, delta: float) -> void:
	entry["angle"] = wrapf(float(entry["angle"]) + data.orbit_speed * delta, 0.0, TAU)
	var n := _orbit_count(entry, data)
	# Aimed shots from each drone on the weapon interval.
	var proj := entry["proj"] as ProjectileData
	entry["timer"] = float(entry["timer"]) - delta
	if float(entry["timer"]) <= 0.0:
		entry["timer"] = _interval_of(entry, data)
		if proj != null:
			for i in n:
				var p := _orbit_pos(entry, data, i, n)
				pool.spawn(p, _aim_dir(p), proj)
	# Contact damage + optional bolt blocking on a fixed cadence.
	entry["orbit_tick"] = float(entry["orbit_tick"]) - delta
	if float(entry["orbit_tick"]) > 0.0:
		return
	entry["orbit_tick"] = _ORBIT_TICK
	var body := data.orbit_body_radius * _all_area_mult
	var contact := _hit_damage(entry) * data.orbit_contact_dps_ratio * _ORBIT_TICK
	var targets := _targets_snapshot()
	for i in n:
		var p := _orbit_pos(entry, data, i, n)
		for t in targets:
			if is_instance_valid(t) and t.visible and p.distance_to(t.global_position) <= body + _target_radius(t):
				_damage_target(t, contact)
		if data.orbit_blocks_bullets and enemy_bolts != null:
			_block_bolts(p, body)


func _block_bolts(center: Vector2, radius: float) -> void:
	var r2 := radius * radius
	for node in enemy_bolts.get_active_nodes_snapshot():
		var bolt := node as Projectile
		if bolt != null and bolt.visible and bolt.global_position.distance_squared_to(center) <= r2:
			bolt.despawn()


# --- Area blasts / vortex pulses (targeter API for player bolts) --------------

## Area blast at `pos`; `pulses` > 1 leaves a vortex that re-detonates.
func detonate(pos: Vector2, radius: float, damage: float, pulses: int = 1, interval: float = 0.35) -> void:
	damage_area(pos, radius, damage)
	GameFeel.blast(pos, radius, Palette.get_color("magenta", Color(1.0, 0.22, 0.55)))
	if pulses > 1:
		_queue_pulse(pos, radius, damage, pulses - 1, interval)


## Damages every target within `radius` (+ its own hit radius) of `pos`.
func damage_area(pos: Vector2, radius: float, damage: float) -> void:
	var numbers := 0
	for t in _targets_snapshot():
		if not is_instance_valid(t) or not t.visible:
			continue
		if pos.distance_to(t.global_position) <= radius + _target_radius(t):
			_damage_target(t, damage)
			if numbers < _MAX_NUMBERS_PER_BLAST:
				GameFeel.area_hit(t.global_position, damage)
				numbers += 1


func _queue_pulse(pos: Vector2, radius: float, damage: float, left: int, interval: float) -> void:
	for i in _MAX_PULSES:
		if _pulse_left[i] <= 0:
			_pulse_pos[i] = pos
			_pulse_radius[i] = radius
			_pulse_damage[i] = damage
			_pulse_left[i] = left
			_pulse_interval[i] = interval
			_pulse_timer[i] = interval
			return


func _tick_pulses(delta: float) -> void:
	for i in _MAX_PULSES:
		if _pulse_left[i] <= 0:
			continue
		_pulse_timer[i] -= delta
		if _pulse_timer[i] > 0.0:
			continue
		_pulse_timer[i] = _pulse_interval[i]
		_pulse_left[i] -= 1
		damage_area(_pulse_pos[i], _pulse_radius[i], _pulse_damage[i])
		GameFeel.blast(_pulse_pos[i], _pulse_radius[i], Palette.get_color("purple", Color(0.7, 0.35, 1.0)))


# --- Targeting ----------------------------------------------------------------

## Nearest live target node (wave enemy, boss add, or the active boss) within
## `max_dist`, or null. Used for homing bolts, drone aim, and chain starts.
func nearest_target_node(from: Vector2, max_dist: float = INF) -> Node2D:
	var best: Node2D = null
	var best_d := max_dist * max_dist if max_dist < INF else INF
	if director != null:
		for e in director.get_active_enemies():
			if is_instance_valid(e) and e.visible:
				var d := from.distance_squared_to(e.global_position)
				if d < best_d:
					best_d = d
					best = e
	if boss != null and is_instance_valid(boss):
		for a in boss.get_adds():
			if is_instance_valid(a) and a.visible:
				var d := from.distance_squared_to(a.global_position)
				if d < best_d:
					best_d = d
					best = a
		if boss.is_active() and boss.get_health() > 0.0:
			var bd := from.distance_squared_to(boss.global_position)
			if bd < best_d:
				best = boss
	return best


func _nearest_excluding(from: Vector2, max_dist: float, exclude: Array[Node2D]) -> Node2D:
	var best: Node2D = null
	var best_d := max_dist * max_dist
	for t in _targets_snapshot():
		if not is_instance_valid(t) or not t.visible or exclude.has(t):
			continue
		var d := from.distance_squared_to(t.global_position)
		if d < best_d:
			best_d = d
			best = t
	return best


## Snapshot of every damageable target (enemies can die while iterating).
func _targets_snapshot() -> Array[Node2D]:
	var out: Array[Node2D] = []
	if director != null:
		for e in director.get_active_enemies():
			out.append(e)
	if boss != null and is_instance_valid(boss):
		for a in boss.get_adds():
			out.append(a)
		if boss.is_active() and boss.get_health() > 0.0:
			out.append(boss)
	return out


func _target_radius(t: Node2D) -> float:
	if t is Enemy and (t as Enemy).data != null:
		return (t as Enemy).data.hit_radius
	if t is Boss and (t as Boss).data != null:
		return (t as Boss).data.hit_radius
	return 24.0


func _damage_target(t: Node2D, amount: float) -> void:
	if is_instance_valid(t) and t.has_method("take_damage"):
		t.call("take_damage", amount)


func _ship_pos() -> Vector2:
	if player != null and player.has_method("get_core_global_position"):
		return player.get_core_global_position()
	return player.global_position if player != null else Vector2.ZERO


func _muzzle(data: SecondaryWeaponData) -> Vector2:
	return _ship_pos() + data.muzzle_offset


## Direction toward the nearest live target, or straight up.
func _aim_dir(origin: Vector2) -> Vector2:
	var t := nearest_target_node(origin)
	if t == null:
		return Vector2.UP
	var dir := t.global_position - origin
	return dir if dir.length() > 1.0 else Vector2.UP


# --- Presentation -------------------------------------------------------------

func _draw() -> void:
	if not _enabled or player == null:
		return
	var time := Time.get_ticks_msec() * 0.001
	for id in _active:
		var entry: Dictionary = _active[id]
		var data := entry["data"] as SecondaryWeaponData
		match data.kind:
			SecondaryWeaponData.Kind.BEAM:
				if _beam_active(entry, data):
					_draw_beam(data, time)
			SecondaryWeaponData.Kind.ORBIT:
				_draw_drones(entry, data, time)


func _draw_beam(data: SecondaryWeaponData, time: float) -> void:
	var from := _muzzle(data)
	var to := Vector2(from.x, -200.0)
	var half := data.beam_half_width * _all_area_mult
	var flicker := 0.85 + 0.15 * sin(time * 40.0)
	draw_line(from, to, Color(data.color, 0.22 * flicker), half * 2.6, true)
	draw_line(from, to, Color(data.color, 0.65 * flicker), half * 1.2, true)
	draw_line(from, to, Color(1, 1, 1, 0.9), maxf(3.0, half * 0.35), true)
	draw_circle(from, half * 0.9, Color(data.color, 0.8))


func _draw_drones(entry: Dictionary, data: SecondaryWeaponData, time: float) -> void:
	var n := _orbit_count(entry, data)
	var body := data.orbit_body_radius * _all_area_mult
	for i in n:
		var p := _orbit_pos(entry, data, i, n)
		if data.orbit_blocks_bullets:
			draw_arc(p, body * 1.35, 0.0, TAU, 24, Color(data.color, 0.35 + 0.15 * sin(time * 6.0 + i)), 3.0, true)
		draw_circle(p, body * 0.95, Color(data.color, 0.25))
		for k in 7:
			_hex[k] = p + Vector2.RIGHT.rotated(float(entry["angle"]) * 2.0 + TAU * float(k % 6) / 6.0) * body * 0.7
		draw_polyline(_hex, data.color, 2.5, true)
		draw_circle(p, body * 0.22, Color(1, 1, 1, 0.95))
