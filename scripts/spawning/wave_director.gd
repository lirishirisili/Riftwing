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


func is_running() -> bool:
	return _running


func _spawn_event(event: WaveEventData) -> void:
	if enemy_pool == null or event.enemy == null:
		return
	var positions := _formation_positions(event)
	for i in event.count:
		var node := enemy_pool.acquire()
		var enemy := node as Enemy
		if enemy == null:
			continue
		var hold: Vector2 = positions[i]
		# Enter from just above the top edge, exit downward past the bottom.
		var enter_from := Vector2(hold.x, -120.0)
		var exit_to := Vector2(hold.x, screen_size.y + 200.0)

		enemy.release_callback = Callable(self, "_on_enemy_released")
		enemy.enemy_projectile_pool = enemy_projectile_pool
		enemy.pickup_pool = pickup_pool
		enemy.pickup_data = pickup_data
		enemy.player = player
		if not enemy.died.is_connected(_on_enemy_died):
			enemy.died.connect(_on_enemy_died)
		enemy.spawn(event.enemy, enter_from, hold, exit_to, event.entry_seconds, event.wait_seconds, event.exit_seconds)
		_active_enemies.append(enemy)


func _formation_positions(event: WaveEventData) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var center_x := screen_size.x * event.center_x_ratio
	var mid := float(event.count - 1) * 0.5
	for i in event.count:
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
