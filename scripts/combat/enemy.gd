class_name Enemy
extends Area2D
## Pooled, data-driven enemy with an ENTER -> WAIT -> EXIT phase machine.
##
## Behavior is generic; archetype differences (Scout vs Shooter) come entirely
## from EnemyData. Shooters telegraph then fire readable bursts during WAIT.
## On death the enemy drops energy pickups and returns to its pool; it is never
## freed at runtime.

signal died(enemy: Enemy)
## Emitted when a SPLITTER dies so the WaveDirector can spawn its children from
## the shared enemy pool (the Enemy has no pool reference of its own).
signal split_requested(origin: Vector2, child_data: EnemyData, count: int)

enum Phase { IDLE, ENTER, WAIT, EXIT }

var data: EnemyData
## Injected by the WaveDirector.
var release_callback: Callable = Callable()
var enemy_projectile_pool: ProjectilePool
var pickup_pool: NodePool
var pickup_data: PickupData
var player: Node2D
## Offscreen cull for energy drops; set by WaveDirector / Boss for tablet expand.
var despawn_bounds: Rect2 = Rect2(-200.0, -400.0, 1480.0, 2720.0)

var _phase: int = Phase.IDLE
var _health: float = 0.0
var _phase_time: float = 0.0

var _enter_from: Vector2
var _hold_pos: Vector2
var _exit_to: Vector2
var _entry_seconds: float = 1.2
var _wait_seconds: float = 4.0
var _exit_seconds: float = 2.0

# Shooter cycle state (telegraph -> fire -> rest).
var _shoot_timer: float = 0.0
var _telegraphing: bool = false
var _flash: float = 0.0

## Difficulty scaling applied per run without mutating shared EnemyData.
var _contact_damage_mult: float = 1.0
## DIVER: set true once the dive begins so it only re-targets the player once.
var _diving: bool = false

@onready var _sprite: Sprite2D = $Sprite
@onready var _shape: CollisionShape2D = $CollisionShape2D


## Configures and activates an enemy for a formation slot.
func spawn(enemy_data: EnemyData, enter_from: Vector2, hold_pos: Vector2, exit_to: Vector2, entry_s: float, wait_s: float, exit_s: float) -> void:
	data = enemy_data
	_enter_from = enter_from
	_hold_pos = hold_pos
	_exit_to = exit_to
	_entry_seconds = maxf(0.01, entry_s)
	_wait_seconds = wait_s
	_exit_seconds = maxf(0.01, exit_s)
	_health = data.max_health
	_phase = Phase.ENTER
	_phase_time = 0.0
	_shoot_timer = data.shoot_rest
	_telegraphing = false
	_flash = 0.0
	_contact_damage_mult = 1.0
	_diving = false
	global_position = enter_from

	if _sprite != null:
		_sprite.texture = data.sprite
		_sprite.scale = Vector2(data.sprite_scale, data.sprite_scale)
		_sprite.modulate = data.tint
	if _shape != null and _shape.shape is CircleShape2D:
		(_shape.shape as CircleShape2D).radius = data.hit_radius

	visible = true
	monitoring = true
	monitorable = true
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	if data == null:
		return
	_phase_time += delta
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 4.0)
		_apply_tint()

	match _phase:
		Phase.ENTER:
			var t: float = clampf(_phase_time / _entry_seconds, 0.0, 1.0)
			global_position = _enter_from.lerp(_hold_pos, ease(t, 0.4))
			queue_redraw()
			if t >= 1.0:
				_enter_phase(Phase.WAIT)
		Phase.WAIT:
			# Soft hover so formations do not feel glued to a grid.
			var bob := sin(_phase_time * 2.4) * 6.0
			global_position = _hold_pos + Vector2(0.0, bob)
			if _sprite != null:
				_sprite.rotation = sin(_phase_time * 1.7) * 0.08
			if data.can_shoot:
				_update_shooting(delta)
			if _telegraphing:
				queue_redraw()
			# Divers commit to a plunge toward the player instead of waiting out.
			if data.behavior == EnemyData.Behavior.DIVER and _phase_time >= data.dive_delay:
				_begin_dive()
			elif _phase_time >= _wait_seconds:
				_enter_phase(Phase.EXIT)
		Phase.EXIT:
			var te: float = clampf(_phase_time / _exit_seconds, 0.0, 1.0)
			global_position = _hold_pos.lerp(_exit_to, ease(te, 2.2))
			if te >= 1.0:
				_release() # survived the wave; recycle quietly (no death drop)


func _draw() -> void:
	if data == null:
		return
	# Orange energy core (visual language: violet hull + warm core).
	var core_r := data.hit_radius * 0.28
	draw_circle(Vector2(0.0, 6.0), core_r * 1.6, Color(1.0, 0.45, 0.12, 0.35))
	draw_circle(Vector2(0.0, 6.0), core_r, Color(1.0, 0.55, 0.15, 0.9))
	# Entrance: soft expanding ring so arrivals read without covering bolts.
	if _phase == Phase.ENTER:
		var et := clampf(_phase_time / _entry_seconds, 0.0, 1.0)
		var er := data.hit_radius * (1.2 + 1.4 * et)
		draw_arc(Vector2.ZERO, er, 0.0, TAU, 32, Color(0.55, 0.25, 1.0, 0.55 * (1.0 - et)), 3.0, true)
	# Telegraph: warning ring + aim line toward the player (readable on phones).
	if _telegraphing:
		var r := data.hit_radius
		var pulse := 0.7 + 0.3 * absf(sin(Time.get_ticks_msec() * 0.02))
		draw_arc(Vector2.ZERO, r * 1.85, 0.0, TAU, 40, Color(1.0, 0.23, 0.3, pulse), 4.5, true)
		draw_arc(Vector2.ZERO, r * 1.35, 0.0, TAU, 28, Color(1.0, 0.85, 0.35, 0.55 * pulse), 2.0, true)
		if player != null:
			var aim := to_local(player.global_position).normalized()
			draw_line(aim * r * 1.2, aim * r * 4.6, Color(1.0, 0.23, 0.23, 0.8), 3.5, true)
			draw_circle(aim * r * 4.6, 5.0, Color(1.0, 0.9, 0.4, 0.85))


## Applies per-run difficulty scaling. Called by the WaveDirector right after
## spawn; multiplies current HP and stores the contact-damage multiplier so the
## shared EnemyData is never mutated.
func apply_scaling(hp_mult: float, contact_damage_mult: float) -> void:
	if hp_mult > 0.0:
		_health = maxf(1.0, _health * hp_mult)
	_contact_damage_mult = maxf(0.0, contact_damage_mult)


## Contact damage after difficulty scaling (read by the player on body overlap).
func get_contact_damage() -> float:
	if data == null:
		return 0.0
	return data.contact_damage * _contact_damage_mult


## Diver commit: aim the plunge at the player's column and speed up the exit.
func _begin_dive() -> void:
	_diving = true
	var target_x := _exit_to.x
	if player != null:
		target_x = player.global_position.x
	_exit_to = Vector2(target_x, _exit_to.y)
	_exit_seconds = maxf(0.2, _exit_seconds / maxf(1.0, data.dive_speed_mult))
	_enter_phase(Phase.EXIT)


## Applies damage from a player projectile. Handles death + drops once.
func take_damage(amount: float) -> void:
	if _phase == Phase.IDLE or _health <= 0.0:
		return
	_health -= amount
	_flash = 1.0
	_apply_tint()
	if _health <= 0.0:
		_die()


func pool_reset() -> void:
	_phase = Phase.IDLE
	_health = 0.0


func pool_disable() -> void:
	set_process(false)
	# Deferred: death/release can occur inside a projectile's area_entered signal,
	# where Godot blocks toggling monitoring/monitorable directly.
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	visible = false
	_phase = Phase.IDLE
	_telegraphing = false


func _enter_phase(next: int) -> void:
	_phase = next
	_phase_time = 0.0
	queue_redraw()


func _update_shooting(delta: float) -> void:
	_shoot_timer -= delta
	if _telegraphing:
		if _shoot_timer <= 0.0:
			_fire_burst()
			_telegraphing = false
			_shoot_timer = data.shoot_rest
			queue_redraw()
	else:
		if _shoot_timer <= 0.0:
			_telegraphing = true
			_shoot_timer = data.shoot_telegraph
			queue_redraw()


func _fire_burst() -> void:
	if enemy_projectile_pool == null or data.projectile == null:
		return
	# Aim the burst center at the player if known, else straight down.
	var base_dir := Vector2.DOWN
	if player != null:
		base_dir = (player.global_position - global_position).normalized()
	var count := data.burst_count
	if count <= 1:
		enemy_projectile_pool.spawn(global_position, base_dir, data.projectile)
		return
	var step := data.burst_spread_degrees / float(count - 1)
	var start := -data.burst_spread_degrees * 0.5
	for i in count:
		var dir := base_dir.rotated(deg_to_rad(start + step * float(i)))
		enemy_projectile_pool.spawn(global_position, dir, data.projectile)


func _die() -> void:
	# Feel: tougher enemies (shooters here) get a large explosion + hit-stop.
	# Reading max_health is read-only; it never changes balance.
	var is_major := data.is_elite or data.can_shoot or data.max_health >= 40.0
	GameFeel.enemy_death(global_position, is_major)
	_drop_energy()
	if data.behavior == EnemyData.Behavior.SPLITTER and data.split_into != null and data.split_count > 0:
		split_requested.emit(global_position, data.split_into, data.split_count)
	died.emit(self)
	_release()


func _drop_energy() -> void:
	if pickup_pool == null or pickup_data == null or data.energy_drop <= 0:
		return
	for i in data.energy_drop:
		var node := pickup_pool.acquire()
		var pickup := node as Pickup
		if pickup == null:
			continue
		var jitter := Vector2(randf_range(-24.0, 24.0), randf_range(-16.0, 16.0))
		pickup.release_callback = Callable(pickup_pool, "release")
		pickup.spawn(global_position + jitter, pickup_data, despawn_bounds)


func _apply_tint() -> void:
	if _sprite == null or data == null:
		return
	_sprite.modulate = data.tint.lerp(Color.WHITE, _flash)


func _release() -> void:
	# Deferred: _die() runs inside the player bolt's area_entered signal, where
	# directly toggling monitoring/monitorable is blocked by Godot.
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	if release_callback.is_valid():
		release_callback.call(self)
	else:
		pool_disable()
