class_name WaveDirector
extends Node2D
## Data-driven spawner: reads a WaveData and, at each event's time, pulls enemies
## from the pool into a formation, injecting the refs they need (enemy-projectile
## pool, pickup pool, player). Enemies drive their own entry/wait/exit.

signal wave_finished()
signal enemy_killed(enemy: Enemy)

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


## Sets per-run difficulty scaling applied to every spawned enemy + density.
func set_difficulty(hp_mult: float, contact_damage_mult: float, count_add: int) -> void:
	_hp_mult = maxf(0.1, hp_mult)
	_contact_damage_mult = maxf(0.0, contact_damage_mult)
	_count_add = maxi(0, count_add)


## Begins the wave from t=0.
func start() -> void:
	_time = 0.0
	_next_event = 0
	_running = true


## Stops scheduling new events (active enemies keep fighting until cleared).
func stop() -> void:
	_running = false


## Stops the wave and releases every active enemy back to the pool.
func stop_and_clear() -> void:
	_running = false
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
	if not _running or wave == null:
		return
	_time += delta
	while _next_event < wave.events.size() and wave.events[_next_event].time <= _time:
		_spawn_event(wave.events[_next_event])
		_next_event += 1
	if _next_event >= wave.events.size() and _active_enemies.is_empty() and _time >= wave.duration:
		_running = false
		wave_finished.emit()


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
	if enemy_pool == null or child_data == null or not _running:
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
	# Death drops are handled by the enemy; re-broadcast for debug/kill counts.
	enemy_killed.emit(enemy)


func _on_enemy_released(enemy: Node) -> void:
	var e := enemy as Enemy
	if e != null:
		_active_enemies.erase(e)
	if enemy_pool != null:
		enemy_pool.release(enemy)
