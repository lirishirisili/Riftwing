class_name Pickup
extends Area2D
## Pooled energy pickup. Drifts down, is collected on player overlap, and
## returns to its pool on collection or lifetime expiry (never freed at runtime).
##
## Magnet: when a target is set and the pickup falls inside the target's magnet
## radius (or `attract()` is called, e.g. a phase-change vacuum), it homes in on
## the target with accelerating speed and ignores its lifetime until collected.

var data: PickupData
## Called with self to return this node to its pool.
var release_callback: Callable = Callable()
## Node that pulls this pickup in (the player). Optional.
var magnet_target: Node2D = null

const _MAGNET_START_SPEED := 420.0
const _MAGNET_ACCEL := 2600.0
const _MAGNET_MAX_SPEED := 2400.0

var _age: float = 0.0
var _collected: bool = false
var _bounds: Rect2 = Rect2(-200, -400, 1480, 2720)
var _attracted: bool = false
var _magnet_speed: float = 0.0
## Loot-fountain launch: outward velocity with drag, then auto-attract.
var _burst_vel: Vector2 = Vector2.ZERO
var _attract_at: float = -1.0
const _BURST_DRAG := 3.5

@onready var _shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	# Private shape per pooled pickup (scene sub-resources are shared).
	if _shape != null and _shape.shape != null:
		_shape.shape = _shape.shape.duplicate()


## Activates the pickup at a world position.
func spawn(world_position: Vector2, pickup_data: PickupData, bounds: Rect2) -> void:
	data = pickup_data
	global_position = world_position
	_age = 0.0
	_collected = false
	_attracted = false
	_magnet_speed = 0.0
	_burst_vel = Vector2.ZERO
	_attract_at = -1.0
	_bounds = bounds
	if _shape != null and _shape.shape is CircleShape2D:
		(_shape.shape as CircleShape2D).radius = data.radius
	visible = true
	# Deferred: pickups spawn from an enemy's death, which runs inside the player
	# bolt's area_entered signal where toggling monitorable is blocked. Deferring
	# also keeps enable ordered after any same-frame release (see pool_disable).
	set_deferred("monitorable", true)
	set_process(true)
	queue_redraw()


## Spawns with an outward launch (boss / chest loot fountain); the pickup
## flies out, slows, then homes in on the magnet target after `attract_after`.
func spawn_burst(world_position: Vector2, pickup_data: PickupData, bounds: Rect2,
		velocity: Vector2, attract_after: float) -> void:
	spawn(world_position, pickup_data, bounds)
	_burst_vel = velocity
	_attract_at = attract_after


## Forces homing toward the magnet target regardless of distance.
func attract() -> void:
	if magnet_target != null and is_instance_valid(magnet_target) and not _collected:
		_attracted = true
		_magnet_speed = maxf(_magnet_speed, _MAGNET_START_SPEED)


func _process(delta: float) -> void:
	if data == null:
		return
	_age += delta
	if _attract_at >= 0.0 and _age >= _attract_at:
		_attract_at = -1.0
		attract()
	if not _attracted and _burst_vel != Vector2.ZERO:
		global_position += _burst_vel * delta
		_burst_vel *= maxf(0.0, 1.0 - _BURST_DRAG * delta)
		if _burst_vel.length_squared() < 400.0:
			_burst_vel = Vector2.ZERO
		queue_redraw()
		return
	if not _attracted and magnet_target != null and is_instance_valid(magnet_target) \
			and magnet_target.has_method("get_magnet_radius"):
		var r: float = magnet_target.get_magnet_radius()
		if r > 0.0 and global_position.distance_squared_to(magnet_target.global_position) <= r * r:
			attract()
	if _attracted and magnet_target != null and is_instance_valid(magnet_target):
		_magnet_speed = minf(_MAGNET_MAX_SPEED, _magnet_speed + _MAGNET_ACCEL * delta)
		var goal: Vector2 = magnet_target.get_core_global_position() \
				if magnet_target.has_method("get_core_global_position") else magnet_target.global_position
		global_position = global_position.move_toward(goal, _magnet_speed * delta)
		queue_redraw()
		return
	global_position.y += data.fall_speed * delta
	queue_redraw()
	if _age >= data.lifetime or not _bounds.has_point(global_position):
		_release()


func _draw() -> void:
	if data == null:
		return
	var pulse := 0.85 + 0.15 * sin(Time.get_ticks_msec() * 0.01 + _age * 4.0)
	match data.kind:
		PickupData.Kind.HEAL:
			_draw_heal(pulse)
			return
		PickupData.Kind.MAGNET:
			_draw_magnet(pulse)
			return
		PickupData.Kind.CHEST:
			_draw_chest(pulse)
			return
	# Hex-adjacent layered disc (green recovery role) — readable at 64–96 px.
	draw_circle(Vector2.ZERO, data.radius * 1.85, Color(data.color, 0.16 * pulse))
	draw_circle(Vector2.ZERO, data.radius * 1.7, Color(data.color, 0.22))
	draw_circle(Vector2.ZERO, data.radius * 1.15, Color(data.color, 0.85))
	draw_circle(Vector2.ZERO, data.radius * 0.55, Color(1.0, 1.0, 1.0, 0.95))
	draw_arc(Vector2.ZERO, data.radius * 1.3 * pulse, 0.0, TAU, 6, Color(0.7, 1.0, 0.85, 0.75), 3.0, true)


func _draw_heal(pulse: float) -> void:
	var r := data.radius
	draw_circle(Vector2.ZERO, r * 1.7, Color(data.color, 0.18 * pulse))
	draw_circle(Vector2.ZERO, r, Color(0.05, 0.2, 0.1, 0.9))
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 24, data.color, 3.0, true)
	var w := r * 0.28
	draw_rect(Rect2(-w, -r * 0.62, w * 2.0, r * 1.24), Color(1, 1, 1, 0.95))
	draw_rect(Rect2(-r * 0.62, -w, r * 1.24, w * 2.0), Color(1, 1, 1, 0.95))


func _draw_magnet(pulse: float) -> void:
	var r := data.radius
	draw_circle(Vector2.ZERO, r * 1.7, Color(data.color, 0.18 * pulse))
	draw_circle(Vector2.ZERO, r, Color(0.04, 0.1, 0.2, 0.9))
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 24, data.color, 3.0, true)
	# Horseshoe magnet glyph.
	draw_arc(Vector2(0, -r * 0.05), r * 0.5, 0.0, PI, 16, Color(1, 1, 1, 0.95), r * 0.22, true)
	draw_line(Vector2(-r * 0.5, -r * 0.05), Vector2(-r * 0.5, -r * 0.55), Color(1, 0.35, 0.35), r * 0.22)
	draw_line(Vector2(r * 0.5, -r * 0.05), Vector2(r * 0.5, -r * 0.55), Color(1, 0.35, 0.35), r * 0.22)


func _draw_chest(pulse: float) -> void:
	var r := data.radius
	# Beacon + glow so a chest reads from across the field.
	draw_circle(Vector2.ZERO, r * 2.0, Color(data.color, 0.14 * pulse))
	draw_arc(Vector2.ZERO, r * (1.5 + 0.2 * pulse), 0.0, TAU, 32, Color(data.color, 0.5 * pulse), 3.0, true)
	var body := Rect2(-r * 0.85, -r * 0.45, r * 1.7, r * 1.05)
	draw_rect(body, Color(0.25, 0.14, 0.04, 0.95))
	draw_rect(body, data.color, false, 3.0)
	draw_rect(Rect2(-r * 0.85, -r * 0.75, r * 1.7, r * 0.34), data.color)
	draw_rect(Rect2(-r * 0.14, -r * 0.5, r * 0.28, r * 0.4), Color(1, 1, 1, 0.95))


func get_kind() -> int:
	return data.kind if data != null else PickupData.Kind.ENERGY


## Called by the player when this pickup is collected. Returns its value once.
func collect() -> int:
	if _collected or data == null:
		return 0
	_collected = true
	var value := data.value
	_release()
	return value


func pool_reset() -> void:
	_age = 0.0
	_collected = false
	_attracted = false
	_magnet_speed = 0.0


func pool_disable() -> void:
	set_process(false)
	set_deferred("monitorable", false)
	visible = false
	_attracted = false


func _release() -> void:
	if release_callback.is_valid():
		release_callback.call(self)
	else:
		pool_disable()
