class_name Pickup
extends Area2D
## Pooled energy pickup. Drifts down, is collected on player overlap, and
## returns to its pool on collection or lifetime expiry (never freed at runtime).

var data: PickupData
## Called with self to return this node to its pool.
var release_callback: Callable = Callable()

var _age: float = 0.0
var _collected: bool = false
var _bounds: Rect2 = Rect2(-200, -400, 1480, 2720)

@onready var _shape: CollisionShape2D = $CollisionShape2D


## Activates the pickup at a world position.
func spawn(world_position: Vector2, pickup_data: PickupData, bounds: Rect2) -> void:
	data = pickup_data
	global_position = world_position
	_age = 0.0
	_collected = false
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


func _process(delta: float) -> void:
	if data == null:
		return
	global_position.y += data.fall_speed * delta
	_age += delta
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


func pool_disable() -> void:
	set_process(false)
	set_deferred("monitorable", false)
	visible = false


func _release() -> void:
	if release_callback.is_valid():
		release_callback.call(self)
	else:
		pool_disable()
