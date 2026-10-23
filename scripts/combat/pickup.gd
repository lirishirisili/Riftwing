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


## Forces homing toward the magnet target regardless of distance.
func attract() -> void:
	if magnet_target != null and is_instance_valid(magnet_target) and not _collected:
		_attracted = true
		_magnet_speed = maxf(_magnet_speed, _MAGNET_START_SPEED)


func _process(delta: float) -> void:
	if data == null:
		return
	_age += delta
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
	# Hex-adjacent layered disc (green recovery role) — readable at 64–96 px.
	var pulse := 0.85 + 0.15 * sin(Time.get_ticks_msec() * 0.01 + _age * 4.0)
	draw_circle(Vector2.ZERO, data.radius * 1.85, Color(data.color, 0.16 * pulse))
	draw_circle(Vector2.ZERO, data.radius * 1.7, Color(data.color, 0.22))
	draw_circle(Vector2.ZERO, data.radius * 1.15, Color(data.color, 0.85))
	draw_circle(Vector2.ZERO, data.radius * 0.55, Color(1.0, 1.0, 1.0, 0.95))
	draw_arc(Vector2.ZERO, data.radius * 1.3 * pulse, 0.0, TAU, 6, Color(0.7, 1.0, 0.85, 0.75), 3.0, true)


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
