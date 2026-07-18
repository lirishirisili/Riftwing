class_name PlayerShip
extends Area2D
## Drag-follow player ship (movement only; no shooting).
##
## One finger (or the mouse via touch emulation) dragged anywhere sets a target;
## the ship eases toward that target minus a vertical offset so it stays visible
## above the finger, clamped to a configurable gameplay rectangle. A small,
## separate collision core (independent of the ship art) represents the real
## hittable area. Input is released safely on touch cancellation, pause, and
## application focus loss so movement never sticks.

@export var data: PlayerMovementData
@export var combat_data: PlayerCombatData

signal health_changed(current: float, maximum: float)
signal energy_changed(total: int)
signal died()

## True while a drag is actively steering the ship.
var _dragging: bool = false
## The finger index that owns the current drag (-1 = mouse-emulated / none).
var _active_touch: int = -1
## Target position for the ship origin in world/logical coordinates.
var _target: Vector2
## Runtime playfield (base resource rect expanded for taller/wider viewports).
var _play_rect: Rect2 = Rect2(90, 240, 900, 1500)

var _health: float = 0.0
var _energy: int = 0
var _invuln_time: float = 0.0
var _alive: bool = true

@onready var _core: CollisionShape2D = $CollisionCore


func _ready() -> void:
	if data == null:
		data = PlayerMovementData.new()
	if combat_data == null:
		combat_data = PlayerCombatData.new()
	_health = combat_data.max_health
	_adapt_play_rect()
	_target = _clamp_to_bounds(global_position)
	set_process(true)
	set_process_unhandled_input(true)
	get_viewport().size_changed.connect(_adapt_play_rect)
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)
	health_changed.emit(_health, combat_data.max_health)
	energy_changed.emit(_energy)


func _process(delta: float) -> void:
	# Frame-rate independent exponential smoothing toward the target.
	var t := 1.0 - exp(-data.follow_smoothing * delta)
	global_position = global_position.lerp(_target, t)
	if _invuln_time > 0.0:
		_invuln_time = maxf(0.0, _invuln_time - delta)
		# Blink while invulnerable for readable feedback.
		modulate.a = 0.4 if int(_invuln_time * 20.0) % 2 == 0 else 1.0
	else:
		modulate.a = 1.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		# OS-cancelled touches (incoming call, gesture interrupt) must release.
		if touch.canceled:
			if touch.index == _active_touch or _active_touch == -1:
				_cancel_drag()
			return
		if touch.pressed:
			# Multi-touch: ignore additional fingers so ownership never steals mid-drag.
			if _dragging and touch.index != _active_touch:
				return
			_begin_drag(touch.index, touch.position)
		elif touch.index == _active_touch:
			_cancel_drag()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if _dragging and drag.index == _active_touch:
			_update_target(drag.position)


func _notification(what: int) -> void:
	# Backgrounding, focus loss, or tree pause must not leave input stuck.
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT, \
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_PAUSED:
			_cancel_drag()


## Returns the ship's small collision core in world coordinates (for later
## damage systems and for the debug scene to visualize).
func get_core_global_position() -> Vector2:
	return _core.global_position


func get_health() -> float:
	return _health


func get_energy() -> int:
	return _energy


func is_alive() -> bool:
	return _alive


## Applies damage unless currently invulnerable. Called by enemy projectiles.
func take_damage(amount: float) -> void:
	if not _alive or _invuln_time > 0.0:
		return
	_health = maxf(0.0, _health - amount)
	_invuln_time = combat_data.invuln_seconds
	GameFeel.player_hit(global_position)
	health_changed.emit(_health, combat_data.max_health)
	if _health <= 0.0:
		_alive = false
		died.emit()


## Enemies and pickups overlap the player core.
func _on_area_entered(area: Area2D) -> void:
	if area is Pickup:
		var gained := (area as Pickup).collect()
		if gained > 0:
			_energy += gained
			energy_changed.emit(_energy)
	elif area is Enemy:
		take_damage((area as Enemy).data.contact_damage if (area as Enemy).data != null else 0.0)


func _begin_drag(index: int, screen_pos: Vector2) -> void:
	_dragging = true
	_active_touch = index
	_update_target(screen_pos)


func _cancel_drag() -> void:
	_dragging = false
	_active_touch = -1


func _update_target(screen_pos: Vector2) -> void:
	# Convert screen pixels to world/logical space via the canvas transform (so
	# a future camera stays correct), lift the ship above the finger, then
	# confine the origin to the gameplay rectangle.
	var world := get_viewport().get_canvas_transform().affine_inverse() * screen_pos
	world.y -= data.vertical_offset
	_target = _clamp_to_bounds(world)


func _clamp_to_bounds(pos: Vector2) -> Vector2:
	var r := _play_rect
	return Vector2(
		clampf(pos.x, r.position.x, r.position.x + r.size.x),
		clampf(pos.y, r.position.y, r.position.y + r.size.y)
	)


## Expands the authored 1080×1920 playfield when stretch/expand grows the
## viewport (19.5:9 / 20:9), without mutating the shared Resource.
func _adapt_play_rect() -> void:
	if data == null:
		return
	var base := data.gameplay_rect
	var vp := get_viewport().get_visible_rect().size
	var extra_w := maxf(0.0, vp.x - 1080.0)
	var extra_h := maxf(0.0, vp.y - 1920.0)
	_play_rect = Rect2(
		base.position.x - extra_w * 0.5,
		base.position.y,
		base.size.x + extra_w,
		base.size.y + extra_h
	)
	_target = _clamp_to_bounds(_target)
