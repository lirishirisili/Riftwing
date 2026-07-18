class_name Projectile
extends Area2D
## Pooled, data-driven projectile (movement + lifetime only this milestone).
##
## An Area2D so the combat milestone can enable collision without restructuring;
## monitoring stays off here because there are no enemies yet. On expiry or when
## it leaves the despawn bounds, the projectile asks its pool to reclaim it via a
## release callback instead of freeing itself, so no node is destroyed at runtime.

var data: ProjectileData
## Set by the pool owner; called with self to return this node to the free list.
var release_callback: Callable = Callable()

## True for enemy-fired bolts (masked to the player). Set by the pool owner so
## impact feedback can be colored correctly; does not affect movement or damage.
var hits_player: bool = false

var _velocity: Vector2 = Vector2.ZERO
var _age: float = 0.0
var _bounds: Rect2
var _spent: bool = false
# Recent positions for a short motion trail (game-feel only). Length is driven
# by the quality budget; empty means no trail.
var _trail: PackedVector2Array = PackedVector2Array()

@onready var _shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
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
	if _age >= data.lifetime or not _bounds.has_point(global_position):
		_release()


func _on_area_entered(area: Area2D) -> void:
	if _spent or data == null:
		return
	if area.has_method("take_damage"):
		_spent = true
		var hit_pos := global_position
		area.call("take_damage", data.damage)
		GameFeel.projectile_hit(hit_pos, data.damage, hits_player)
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
