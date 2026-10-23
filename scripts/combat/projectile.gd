class_name Projectile
extends Area2D
## Pooled, data-driven projectile: straight, homing, piercing, or exploding.
##
## On expiry or when it leaves the despawn bounds, the projectile asks its pool
## to reclaim it via a release callback instead of freeing itself, so no node is
## destroyed at runtime. Homing / area blasts go through a `targeter` (the
## player SecondaryWeaponSystem) stamped by the pool: nearest_target_node(pos)
## and detonate(pos, radius, damage, pulses, interval).

var data: ProjectileData
## Set by the pool owner; called with self to return this node to the free list.
var release_callback: Callable = Callable()

## True for enemy-fired bolts (masked to the player). Set by the pool owner so
## impact feedback can be colored correctly; does not affect movement or damage.
var hits_player: bool = false
## Damage multiplier stamped by the owning pool at launch (difficulty scaling).
var damage_mult: float = 1.0
## Targeting / area-damage provider (player bolts only). Stamped by the pool.
var targeter: Object = null

const _RETARGET_SECONDS := 0.15

var _velocity: Vector2 = Vector2.ZERO
var _age: float = 0.0
var _bounds: Rect2
var _spent: bool = false
# Recent positions for a short motion trail (game-feel only). Length is driven
# by the quality budget; empty means no trail.
var _trail: PackedVector2Array = PackedVector2Array()
var _pierce_left: int = 0
## Last body hit, so a piercing bolt never damages the same target twice in a row.
var _last_hit: Object = null
var _homing_target: Node2D = null
var _retarget_timer: float = 0.0

@onready var _shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	# Own a private shape: the scene sub-resource is shared across the pool, so
	# resizing it per launch would resize every live bolt.
	if _shape != null and _shape.shape != null:
		_shape.shape = _shape.shape.duplicate()
	# Whatever this projectile is masked to hit (enemies or the player) is
	# damaged on overlap; the collision mask set in the scene decides the target.
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)


## Configures and activates the projectile. `direction` need not be normalized.
func launch(spawn_position: Vector2, direction: Vector2, projectile_data: ProjectileData, despawn_bounds: Rect2) -> void:
	data = projectile_data
	global_position = spawn_position
	_bounds = despawn_bounds
	_age = 0.0
	var dir := direction.normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.UP
	_velocity = dir * data.speed
	_spent = false
	_trail.clear()
	_pierce_left = data.pierce
	_last_hit = null
	_homing_target = null
	_retarget_timer = 0.0
	rotation = dir.angle() + PI * 0.5
	if _shape != null and _shape.shape is CircleShape2D:
		(_shape.shape as CircleShape2D).radius = data.radius
	visible = true
	# Deferred so that if this node was released and re-acquired in the same
	# frame, the enable is queued after the release's deferred disable (see
	# pool_disable) and wins, instead of being clobbered by it.
	set_deferred("monitoring", true)
	set_deferred("monitorable", true)
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	# A pooled node may exist in the tree before launch(); stay inert until armed.
	if data == null or _spent:
		return
	if data.homing_turn_rate > 0.0 and targeter != null and (data.homing_duration <= 0.0 or _age < data.homing_duration):
		_steer(delta)
	global_position += _velocity * delta
	_age += delta
	# Record a short trail in local space for the feel pass. The cap comes from
	# the quality budget (0 = trail disabled).
	var cap := GameFeel.trail_length()
	if cap > 0:
		_trail.append(global_position)
		while _trail.size() > cap:
			_trail.remove_at(0)
		queue_redraw()
	elif _trail.size() > 0:
		_trail.clear()
	if _age >= data.lifetime:
		if data.explode_on_expire:
			_detonate(global_position)
		_release()
	elif not _bounds.has_point(global_position):
		_release()


## Turns the velocity toward the tracked target at the data turn rate.
func _steer(delta: float) -> void:
	_retarget_timer -= delta
	if (_retarget_timer <= 0.0 or _homing_target == null or not is_instance_valid(_homing_target)
			or not _homing_target.visible):
		_retarget_timer = _RETARGET_SECONDS
		_homing_target = targeter.nearest_target_node(global_position)
	if _homing_target == null or not is_instance_valid(_homing_target):
		return
	var want := (_homing_target.global_position - global_position).angle()
	var have := _velocity.angle()
	var turn := clampf(wrapf(want - have, -PI, PI), -data.homing_turn_rate * delta, data.homing_turn_rate * delta)
	_velocity = _velocity.rotated(turn)
	rotation = _velocity.angle() + PI * 0.5


func _detonate(pos: Vector2) -> void:
	if targeter != null and data.explode_radius > 0.0:
		targeter.detonate(pos, data.explode_radius, data.damage * damage_mult * data.explode_damage_ratio,
			data.explode_pulses, data.pulse_interval)


func _on_area_entered(area: Area2D) -> void:
	if _spent or data == null:
		return
	if area == _last_hit:
		return
	if area.has_method("take_damage"):
		var hit_pos := global_position
		var dmg := data.damage * damage_mult
		area.call("take_damage", dmg)
		GameFeel.projectile_hit(hit_pos, dmg, hits_player, data.is_crit)
		if data.explode_radius > 0.0:
			_detonate(hit_pos)
		if _pierce_left > 0:
			_pierce_left -= 1
			_last_hit = area
			return
		_spent = true
		_release()


func _draw() -> void:
	if data == null:
		return
	# Lifetime fade near expiry keeps the field readable.
	var life_f := 1.0
	if data.lifetime > 0.0:
		life_f = clampf(1.0 - (_age / data.lifetime), 0.15, 1.0)
	# Motion trail (feel only). Hostile trails stay short/soft so they never mask cores.
	if _trail.size() >= 2:
		var n := _trail.size()
		for i in range(n - 1):
			var a := to_local(_trail[i])
			var b := to_local(_trail[i + 1])
			var f := float(i) / float(n)
			var trail_a := (0.06 + 0.22 * f) if hits_player else (0.1 + 0.32 * f)
			var trail_w := data.radius * ((0.55 + 1.0 * f) if hits_player else (0.75 + 1.35 * f))
			draw_line(a, b, Color(data.color, trail_a * life_f), trail_w, true)
	var half := data.length * 0.5
	if hits_player:
		# Hostile: round orb + warm core (shape distinct from cyan needles).
		draw_circle(Vector2.ZERO, data.radius * 1.9, Color(data.color, 0.22 * life_f))
		draw_circle(Vector2.ZERO, data.radius * 1.1, Color(data.color, life_f))
		draw_circle(Vector2.ZERO, data.radius * 0.45, Color(1.0, 0.78, 0.35, 0.98 * life_f))
	else:
		# Friendly: bright head + soft body + hot tip.
		var glow := Color(data.color, 0.36 * life_f)
		draw_line(Vector2(0.0, half), Vector2(0.0, -half), glow, data.radius * 2.8, true)
		draw_line(Vector2(0.0, half * 0.85), Vector2(0.0, -half), Color(data.color, life_f), data.radius * 1.2, true)
		draw_circle(Vector2(0.0, -half), data.radius * 1.2, Color(data.color, life_f))
		draw_circle(Vector2(0.0, -half), data.radius * 0.5, Color(1.0, 1.0, 1.0, 0.95 * life_f))
		if data.is_crit:
			# Crit volley: gold halo on the head so big hits read in flight.
			draw_circle(Vector2(0.0, -half), data.radius * 2.2, Color(1.0, 0.8, 0.2, 0.35 * life_f))


## Returns this bolt to its pool now (e.g. erased by a shield drone).
func despawn() -> void:
	if not _spent:
		_spent = true
		_release()


## Called by the pool on acquire.
func pool_reset() -> void:
	_age = 0.0
	_spent = false


## Called by the pool on release: park the node without freeing it.
func pool_disable() -> void:
	set_process(false)
	# Deferred: release often happens inside an area_entered signal (on hit), and
	# Godot blocks toggling monitoring/monitorable mid-signal. Deferring applies
	# them safely once the physics callback unwinds.
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	visible = false
	_velocity = Vector2.ZERO
	_spent = true
	_trail.clear()


func _release() -> void:
	if release_callback.is_valid():
		release_callback.call(self)
	else:
		pool_disable()
