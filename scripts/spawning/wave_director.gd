class_name WaveDirector
extends Node2D
## Data-driven spawner: reads a WaveData and, at each event's time, pulls enemies
## from the pool into a formation, injecting the refs they need (enemy-projectile
## pool, pickup pool, player). Enemies drive their own entry/wait/exit.

signal wave_finished()
signal enemy_killed(enemy: Enemy)
## An ambient formation promoted one enemy to an elite (presentation hook).
signal elite_spawned(enemy: Enemy)

## Wave definition to run.
@export var wave: WaveData
## Logical screen size (used to place formations).
@export var screen_size: Vector2 = Vector2(1080, 1920)
## Offscreen cull rect for pickups dropped by enemies (expanded on tablets).
var despawn_bounds: Rect2 = Rect2(-200.0, -400.0, 1480.0, 2720.0)

## Injected dependencies.
var enemy_pool: NodePool
var enemy_projectile_pool: ProjectilePool
var pickup_pool: NodePool
var pickup_data: PickupData
var player: Node2D

var _time: float = 0.0
var _next_event: int = 0
var _running: bool = false
var _active_enemies: Array[Enemy] = []

## Per-run difficulty scaling (set by RunController). Neutral by default so the
## debug scene and probes keep the authored baseline.
var _hp_mult: float = 1.0
var _contact_damage_mult: float = 1.0
var _count_add: int = 0

## Ambient spawning (SpawnProfileData): budget-driven formations on top of the
## authored events. Null = authored events only.
var _ambient: SpawnProfileData = null
var _ambient_time: float = 0.0
var _budget: float = 0.0
var _elite_cooldown: float = 0.0
var _rng := RandomNumberGenerator.new()
var _force_elite: bool = false

## Bonus drops (injected by the run host; chances from RunRulesData).
var heal_data: PickupData
var magnet_data: PickupData
var chest_data: PickupData
var heal_drop_chance: float = 0.0
var magnet_drop_chance: float = 0.0


## Sets per-run difficulty scaling applied to every spawned enemy + density.
func set_difficulty(hp_mult: float, contact_damage_mult: float, count_add: int) -> void:
	_hp_mult = maxf(0.1, hp_mult)
	_contact_damage_mult = maxf(0.0, contact_damage_mult)
	_count_add = maxi(0, count_add)


func _ready() -> void:
	_rng.randomize()


## Starts budget-driven ambient spawning (null stops it). `start_time` resumes
## a ramp part-way (Endless keeps climbing across bosses).
func set_ambient(profile: SpawnProfileData, start_time: float = 0.0) -> void:
	_ambient = profile
	_ambient_time = maxf(0.0, start_time)
	_budget = 0.0
	_elite_cooldown = profile.elite_min_gap_seconds * 0.5 if profile != null else 0.0


func get_ambient() -> SpawnProfileData:
	return _ambient


## Begins the wave from t=0.
func start() -> void:
	_time = 0.0
	_next_event = 0
	_running = true


## Stops scheduling new events (active enemies keep fighting until cleared).
func stop() -> void:
	_running = false
	_ambient = null


## Stops the wave and releases every active enemy back to the pool.
func stop_and_clear() -> void:
	_running = false
	_ambient = null
	var snapshot := _active_enemies.duplicate()
	for enemy in snapshot:
		if is_instance_valid(enemy):
			enemy.pool_disable()
			if enemy_pool != null:
				enemy_pool.release(enemy)
	_active_enemies.clear()


## Swaps the authored wave and starts it from t=0.
func start_wave(next: WaveData) -> void:
	wave = next
	start()


func _process(delta: float) -> void:
	if _ambient != null:
		_tick_ambient(delta)
	if not _running or wave == null:
		return
	_time += delta
	while _next_event < wave.events.size() and wave.events[_next_event].time <= _time:
		_spawn_event(wave.events[_next_event])
		_next_event += 1
	if _next_event >= wave.events.size() and _active_enemies.is_empty() and _time >= wave.duration:
		_running = false
		wave_finished.emit()


## Live wave enemies (read-only; iterate a duplicate if a hit can kill).
func get_active_enemies() -> Array[Enemy]:
	return _active_enemies


func get_active_enemy_count() -> int:
	return _active_enemies.size()


## Nearest live enemy to a world point, or null. Used by secondary weapons for
## auto-aim without exposing the internal list for mutation.
func nearest_enemy(from: Vector2) -> Enemy:
	var best: Enemy = null
	var best_d := INF
	for enemy in _active_enemies:
		if not is_instance_valid(enemy):
			continue
		var d := from.distance_squared_to(enemy.global_position)
		if d < best_d:
			best_d = d
			best = enemy
	return best


## Damages every live wave enemy (Rift Nova). Iterates a snapshot because a
## kill releases the enemy and edits the live list.
func damage_all(amount: float) -> void:
	for enemy in _active_enemies.duplicate():
		if is_instance_valid(enemy):
			enemy.take_damage(amount)


func is_running() -> bool:
	return _running


func _spawn_event(event: WaveEventData) -> void:
	if enemy_pool == null or event.enemy == null:
		return
	var total := maxi(1, event.count + _count_add)
	var positions := _formation_positions(event, total)
	for i in total:
		var hold: Vector2 = positions[i]
		# Enter from just above the top edge, exit downward past the bottom.
		var enter_from := Vector2(hold.x, -120.0)
		var exit_to := Vector2(hold.x, screen_size.y + 200.0)
		_spawn_one(event.enemy, enter_from, hold, exit_to,
			event.entry_seconds, event.wait_seconds, event.exit_seconds)


## Acquires and configures a single enemy, applying difficulty scaling. Shared by
## authored wave events and SPLITTER child spawns.
func _spawn_one(enemy_data: EnemyData, enter_from: Vector2, hold: Vector2, exit_to: Vector2,
		entry_s: float, wait_s: float, exit_s: float) -> void:
	var node := enemy_pool.acquire()
	var enemy := node as Enemy
	if enemy == null:
		return
	enemy.release_callback = Callable(self, "_on_enemy_released")
	enemy.enemy_projectile_pool = enemy_projectile_pool
	enemy.pickup_pool = pickup_pool
	enemy.pickup_data = pickup_data
	enemy.player = player
	enemy.despawn_bounds = despawn_bounds
	if not enemy.died.is_connected(_on_enemy_died):
		enemy.died.connect(_on_enemy_died)
	if not enemy.split_requested.is_connected(_on_split_requested):
		enemy.split_requested.connect(_on_split_requested)
	enemy.spawn(enemy_data, enter_from, hold, exit_to, entry_s, wait_s, exit_s)
	enemy.apply_scaling(_hp_mult, _contact_damage_mult)
	_active_enemies.append(enemy)


## Spawns a SPLITTER's children in a small fan around the death point. The death
## fires inside a projectile's area_entered callback, where enabling monitoring on
## a freshly spawned enemy is blocked; defer so the children appear next idle frame.
func _on_split_requested(origin: Vector2, child_data: EnemyData, count: int) -> void:
	if enemy_pool == null or child_data == null:
		return
	call_deferred("_do_split", origin, child_data, count)


func _do_split(origin: Vector2, child_data: EnemyData, count: int) -> void:
	if enemy_pool == null or child_data == null or (not _running and _ambient == null):
		return
	var n := clampi(count, 1, 6)
	for i in n:
		var spread := (float(i) - float(n - 1) * 0.5) * 90.0
		var hold := origin + Vector2(spread, 20.0)
		var exit_to := Vector2(hold.x, screen_size.y + 200.0)
		# Children pop in from the death point (very short entry), then dive out.
		_spawn_one(child_data, origin, hold, exit_to, 0.25, 0.6, 1.4)


func _formation_positions(event: WaveEventData, count: int) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var center_x := screen_size.x * event.center_x_ratio
	var mid := float(count - 1) * 0.5
	for i in count:
		var offset := float(i) - mid
		var x := center_x + offset * event.spacing
		var y := event.hold_y
		if event.formation == "vee":
			# Shallow V: outer slots sit lower.
			y += absf(offset) * 40.0
		out.append(Vector2(x, y))
	return out


func _on_enemy_died(enemy: Enemy) -> void:
	# Energy drops are handled by the enemy; bonus drops (chest from elites,
	# rare heal / magnet orbs) are rolled here. Re-broadcast for kill counts.
	_roll_bonus_drop(enemy)
	enemy_killed.emit(enemy)


func _on_enemy_released(enemy: Node) -> void:
	var e := enemy as Enemy
	if e != null:
		_active_enemies.erase(e)
	if enemy_pool != null:
		enemy_pool.release(enemy)


# --- Ambient spawning ------------------------------------------------------------

func _tick_ambient(delta: float) -> void:
	_ambient_time += delta
	_elite_cooldown = maxf(0.0, _elite_cooldown - delta)
	var mult := 1.0 + 0.25 * float(_count_add)
	_budget += _ambient.budget_rate(_ambient_time) * mult * delta
	if _active_enemies.size() >= _ambient.max_alive:
		# Bank at most a few seconds of budget so a cleared field refills fast
		# without a sudden flood.
		_budget = minf(_budget, _ambient.budget_rate(_ambient_time) * 3.0)
		return
	var pick := _pick_ambient_enemy()
	if pick == null:
		return
	var cost := maxf(0.1, pick.threat_cost)
	if _budget < cost:
		return
	var count := _formation_count(pick, int(_budget / cost))
	_budget -= cost * float(count)
	_spawn_ambient(pick, count)


func _pick_ambient_enemy() -> EnemyData:
	var total := 0.0
	for i in _ambient.enemies.size():
		total += _weight_at(i)
	if total <= 0.0:
		return null
	var roll := _rng.randf() * total
	for i in _ambient.enemies.size():
		roll -= _weight_at(i)
		if roll <= 0.0:
			return _ambient.enemies[i]
	return _ambient.enemies[_ambient.enemies.size() - 1]


func _weight_at(i: int) -> float:
	return _ambient.weights[i] if i < _ambient.weights.size() else 1.0


## How many of an archetype go out together, capped by affordability and room.
func _formation_count(enemy: EnemyData, affordable: int) -> int:
	var want := 1
	match enemy.movement:
		EnemyData.Movement.SWOOP:
			want = 5
		EnemyData.Movement.WEAVE:
			want = 3
		EnemyData.Movement.FORMATION:
			want = 4 if enemy.threat_cost <= 1.5 else 2
		_:
			want = 1 if enemy.threat_cost >= 2.0 else 2
	var room := maxi(1, _ambient.max_alive - _active_enemies.size())
	return clampi(mini(want, affordable), 1, room)


func _spawn_ambient(enemy: EnemyData, count: int) -> void:
	var w := screen_size.x
	var hold_y := lerpf(_ambient.hold_band_top, _ambient.hold_band_bottom, _rng.randf()) * screen_size.y
	var first := _active_enemies.size()
	match enemy.movement:
		EnemyData.Movement.SWOOP:
			var from_left := _rng.randf() < 0.5
			var side := -180.0 if from_left else w + 180.0
			var other := w + 180.0 if from_left else -180.0
			for i in count:
				var lag := float(i) * 110.0 * (-1.0 if from_left else 1.0)
				var y0 := hold_y - 260.0
				_spawn_one(enemy, Vector2(side + lag, y0), Vector2(w * 0.5, hold_y + 320.0),
					Vector2(other + lag, y0 + 120.0), 1.4, 0.0, 1.4)
		EnemyData.Movement.WEAVE:
			var x := _rng.randf_range(w * 0.25, w * 0.75)
			for i in count:
				var start := Vector2(x, -120.0 - float(i) * 170.0)
				_spawn_one(enemy, start, start, start, 1.0, 0.0, 1.0)
		_:
			var center := _rng.randf_range(w * 0.25, w * 0.75)
			var spacing := clampf(enemy.hit_radius * 3.0, 120.0, 220.0)
			var mid := float(count - 1) * 0.5
			for i in count:
				var x := clampf(center + (float(i) - mid) * spacing, 90.0, w - 90.0)
				var hold := Vector2(x, hold_y + absf(float(i) - mid) * 30.0)
				_spawn_one(enemy, Vector2(x, -120.0), hold, Vector2(x, screen_size.y + 200.0),
					1.1, _rng.randf_range(3.5, 6.0), 2.0)
	_maybe_promote_elite(first)


## One member of a fresh ambient formation may become an elite.
func _maybe_promote_elite(first_index: int) -> void:
	if _elite_cooldown > 0.0 or first_index >= _active_enemies.size():
		return
	if not _force_elite and _rng.randf() >= _ambient.elite_chance(_ambient_time):
		return
	_force_elite = false
	var e: Enemy = _active_enemies[first_index]
	var affix := _rng.randi_range(Enemy.Affix.SHIELDED, Enemy.Affix.REGEN)
	e.make_elite(affix, _ambient.elite_hp_mult)
	_elite_cooldown = _ambient.elite_min_gap_seconds
	elite_spawned.emit(e)


## Forces an elite on the next ambient formation (probes / scripted beats).
## Never touches the shared SpawnProfileData.
func force_next_elite() -> void:
	_elite_cooldown = 0.0
	_force_elite = true


func _roll_bonus_drop(enemy: Enemy) -> void:
	if pickup_pool == null or enemy == null:
		return
	var data: PickupData = null
	if enemy.is_elite():
		data = chest_data
	elif _rng.randf() < heal_drop_chance:
		data = heal_data
	elif _rng.randf() < magnet_drop_chance:
		data = magnet_data
	if data == null:
		return
	var pickup := pickup_pool.acquire() as Pickup
	if pickup == null:
		return
	pickup.release_callback = Callable(pickup_pool, "release")
	pickup.magnet_target = player
	pickup.spawn(enemy.global_position, data, despawn_bounds)
