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
## A non-energy pickup (heal / magnet / chest) was collected; the run host
## resolves it. `kind` is PickupData.Kind.
signal special_pickup(kind: int, value: int)

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
## Fraction of incoming damage absorbed by hangar defense (0..0.9). Applied via
## the shared CombatProfile so armor math lives in one place.
var _damage_reduction: float = 0.0
## True once we hold private duplicates so run upgrades never mutate shared .tres.
var _owns_combat_data: bool = false
var _owns_move_data: bool = false
## Rate limit for shield feedback while invulnerable (a sweeping laser calls
## take_damage every frame; one burst per window keeps shake/audio sane).
const _SHIELD_FEEDBACK_INTERVAL := 0.25
var _shield_feedback_cooldown: float = 0.0
## Sustained-overlap contact damage: area_entered fires once per overlap, so a
## ship parked on a tank or the boss body re-checks on this cadence.
const _CONTACT_RECHECK_INTERVAL := 0.1
var _contact_timer: float = 0.0
var _magnet_mult: float = 1.0
## Consecutive pickups (raises the chime pitch); resets after a short gap.
const _PICKUP_STREAK_WINDOW := 0.45
var _pickup_streak: int = 0
var _pickup_streak_timer: float = 0.0
## Passive repair (fraction of max HP per second) and its sub-HP accumulator.
var _regen_per_sec: float = 0.0
var _regen_accum: float = 0.0
## Kinetic barrier: absorbs one hit, then recharges (0 = not owned).
var _barrier_recharge: float = 0.0
var _barrier_timer: float = 0.0
var _barrier_ready: bool = false

@onready var _core: CollisionShape2D = $CollisionCore
@onready var _sprite: Sprite2D = $Sprite
@onready var _engine: Sprite2D = $EngineGlow
@onready var _engine_r: Sprite2D = $EngineGlowRight

var _spawn_scale: float = 1.0
var _spawn_time: float = 0.0


func _ready() -> void:
	if data == null:
		data = PlayerMovementData.new()
	if combat_data == null:
		combat_data = PlayerCombatData.new()
	_health = combat_data.max_health
	_adapt_play_rect()
	_recenter_if_needed()
	_target = _clamp_to_bounds(global_position)
	_spawn_time = 0.35
	_spawn_scale = 0.2
	set_process(true)
	set_process_unhandled_input(true)
	get_viewport().size_changed.connect(_on_viewport_changed)
	call_deferred("_on_viewport_changed")
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)
	health_changed.emit(_health, combat_data.max_health)
	energy_changed.emit(_energy)


func _process(delta: float) -> void:
	# Frame-rate independent exponential smoothing toward the target.
	var t := 1.0 - exp(-data.follow_smoothing * delta)
	global_position = global_position.lerp(_target, t)
	_update_presentation(delta)
	if _shield_feedback_cooldown > 0.0:
		_shield_feedback_cooldown -= delta
	if _pickup_streak_timer > 0.0:
		_pickup_streak_timer -= delta
		if _pickup_streak_timer <= 0.0:
			_pickup_streak = 0
	_tick_contact_damage(delta)
	_tick_sustain(delta)
	if _invuln_time > 0.0:
		_invuln_time = maxf(0.0, _invuln_time - delta)
		# Blink while invulnerable for readable feedback.
		modulate.a = 0.4 if int(_invuln_time * 20.0) % 2 == 0 else 1.0
	else:
		modulate.a = 1.0
	# Low-HP: keep alpha readable; tint via sprite only so collision stays clear.
	if _sprite != null and _alive and combat_data != null and combat_data.max_health > 0.0:
		var hp_frac := _health / combat_data.max_health
		if hp_frac <= 0.3:
			var warn := 0.55 + 0.45 * absf(sin(Time.get_ticks_msec() * 0.012))
			_sprite.modulate = Color(1.0, warn * 0.55, warn * 0.45, 1.0)
		else:
			_sprite.modulate = Color.WHITE


func _update_presentation(delta: float) -> void:
	# Subtle bank toward lateral motion; separate engine pulse (not baked in hull).
	var dx := _target.x - global_position.x
	if _sprite != null:
		_sprite.rotation = lerpf(_sprite.rotation, clampf(dx * 0.0022, -0.28, 0.28), 1.0 - exp(-10.0 * delta))
	if _spawn_time > 0.0:
		_spawn_time = maxf(0.0, _spawn_time - delta)
		_spawn_scale = lerpf(0.2, 1.0, 1.0 - (_spawn_time / 0.35))
		scale = Vector2(_spawn_scale, _spawn_scale)
	elif scale != Vector2.ONE:
		scale = Vector2.ONE
	var pulse := 0.82 + 0.18 * sin(Time.get_ticks_msec() * 0.014)
	var thrust := clampf(absf(dx) / 220.0, 0.0, 1.0)
	var low_hp := combat_data != null and combat_data.max_health > 0.0 \
		and (_health / combat_data.max_health) <= 0.3
	_update_engine_plume(_engine, -28.0, pulse, thrust, low_hp)
	_update_engine_plume(_engine_r, 28.0, pulse, thrust, low_hp)


func _update_engine_plume(node: Sprite2D, x: float, pulse: float, thrust: float, low_hp: bool) -> void:
	if node == null:
		return
	if low_hp:
		node.modulate = Color(1.0, 0.35 + 0.35 * pulse, 0.12, 0.8 + 0.2 * pulse)
		node.scale = Vector2(0.12 + 0.04 * thrust, 0.26 + 0.12 * pulse + 0.08 * thrust)
	else:
		node.modulate = Color(0.15, 0.92, 1.0, 0.8 + 0.2 * pulse)
		node.scale = Vector2(0.11 + 0.03 * thrust, 0.24 + 0.1 * pulse + 0.08 * thrust)
	node.position = Vector2(x, 58.0 + 5.0 * thrust)


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


## Applies a run's derived hangar stats. Duplicates the movement/combat data so
## the shared .tres resources are never mutated (docs/04_ARCHITECTURE.md).
func apply_combat_profile(profile: CombatProfile) -> void:
	if profile == null:
		return
	if combat_data == null:
		combat_data = PlayerCombatData.new()
	# Scale the run's tuned baseline HP by the hangar HP multiplier (relative), so
	# a level-0 ship keeps the balanced baseline and upgrades add real survivability.
	var baseline_hp := combat_data.max_health
	combat_data = combat_data.duplicate() as PlayerCombatData
	_owns_combat_data = true
	combat_data.max_health = maxf(1.0, baseline_hp * profile.hp_mult)
	_health = combat_data.max_health
	_damage_reduction = clampf(profile.damage_reduction, -0.2, 0.9)
	if data != null and not is_equal_approx(profile.move_speed_mult, 1.0):
		data = data.duplicate() as PlayerMovementData
		_owns_move_data = true
		data.follow_smoothing = clampf(data.follow_smoothing * profile.move_speed_mult, 1.0, 40.0)
	health_changed.emit(_health, combat_data.max_health)


# --- Run upgrade hooks (called by UpgradeManager) ----------------------------

## Adds flat incoming-damage reduction (stacks on hangar armor, hard-capped).
func add_damage_reduction(amount: float) -> void:
	_damage_reduction = clampf(_damage_reduction + amount, -0.2, 0.9)


## Multiplies max HP and grants the added headroom as current HP too, so a mid-run
## survivability pick feels immediately meaningful.
func apply_max_hp_mult(mult: float) -> void:
	if mult <= 0.0:
		return
	if combat_data == null:
		combat_data = PlayerCombatData.new()
	if not _owns_combat_data:
		combat_data = combat_data.duplicate() as PlayerCombatData
		_owns_combat_data = true
	var old_max := combat_data.max_health
	combat_data.max_health = maxf(1.0, old_max * mult)
	var delta := combat_data.max_health - old_max
	if delta > 0.0:
		_health = minf(combat_data.max_health, _health + delta)
	health_changed.emit(_health, combat_data.max_health)


## Multiplies movement responsiveness (follow smoothing), clamped to safe bounds.
func apply_move_speed_mult(mult: float) -> void:
	if data == null or mult <= 0.0:
		return
	if not _owns_move_data:
		data = data.duplicate() as PlayerMovementData
		_owns_move_data = true
	data.follow_smoothing = clampf(data.follow_smoothing * mult, 1.0, 40.0)


func get_health() -> float:
	return _health


## Current incoming-damage reduction (0..0.9), for HUD/debug and probes.
func get_damage_reduction() -> float:
	return _damage_reduction


func get_energy() -> int:
	return _energy


func is_alive() -> bool:
	return _alive


## Applies damage unless currently invulnerable. Called by enemy projectiles.
func take_damage(amount: float) -> void:
	if not _alive:
		return
	if _invuln_time > 0.0:
		# Invuln window acts as a brief shield: feedback only, no HP change.
		if _shield_feedback_cooldown <= 0.0:
			_shield_feedback_cooldown = _SHIELD_FEEDBACK_INTERVAL
			GameFeel.shield_impact(global_position)
		return
	if _barrier_ready:
		# The barrier eats the whole hit, then recharges.
		_barrier_ready = false
		_barrier_timer = _barrier_recharge
		_invuln_time = maxf(_invuln_time, 0.4)
		GameFeel.shield_impact(global_position)
		queue_redraw()
		return
	var mitigated := amount * (1.0 - _damage_reduction)
	_health = maxf(0.0, _health - maxf(0.0, mitigated))
	_invuln_time = combat_data.invuln_seconds
	GameFeel.player_hit(global_position)
	health_changed.emit(_health, combat_data.max_health)
	if _health <= 0.0:
		_alive = false
		died.emit()


## Pickup magnet radius (run upgrades scale it through apply_magnet_mult).
func get_magnet_radius() -> float:
	return combat_data.pickup_magnet_radius * _magnet_mult if combat_data != null else 0.0


## Scales the pickup magnet radius (run upgrade hook).
func apply_magnet_mult(mult: float) -> void:
	if mult > 0.0:
		_magnet_mult *= mult


## Adds passive repair (fraction of max HP per second).
func add_regen(fraction_per_second: float) -> void:
	_regen_per_sec = maxf(0.0, _regen_per_sec + fraction_per_second)


## Kinetic barrier: first pick sets the recharge time; later picks shorten it.
func add_barrier(recharge_seconds: float) -> void:
	if _barrier_recharge <= 0.0:
		_barrier_recharge = maxf(2.0, recharge_seconds)
		_barrier_ready = true
	else:
		_barrier_recharge = maxf(2.0, _barrier_recharge * 0.8)
	queue_redraw()


func has_barrier_ready() -> bool:
	return _barrier_ready


## Restores a fraction of max HP (health pickups, chests).
func heal_fraction(fraction: float) -> void:
	if not _alive or combat_data == null or fraction <= 0.0:
		return
	_health = minf(combat_data.max_health, _health + combat_data.max_health * fraction)
	health_changed.emit(_health, combat_data.max_health)
	GameFeel.heal(global_position)


func _tick_sustain(delta: float) -> void:
	if not _alive or combat_data == null:
		return
	if _regen_per_sec > 0.0 and _health < combat_data.max_health:
		_regen_accum += combat_data.max_health * _regen_per_sec * delta
		# Emit in whole-HP steps so the HUD is not rebuilt every frame.
		if _regen_accum >= 1.0:
			var gain := floorf(_regen_accum)
			_regen_accum -= gain
			_health = minf(combat_data.max_health, _health + gain)
			health_changed.emit(_health, combat_data.max_health)
	if _barrier_ready:
		queue_redraw()
	if _barrier_recharge > 0.0 and not _barrier_ready:
		_barrier_timer -= delta
		if _barrier_timer <= 0.0:
			_barrier_ready = true
			queue_redraw()


func _draw() -> void:
	if _barrier_ready and _alive:
		var pulse := 0.6 + 0.25 * sin(Time.get_ticks_msec() * 0.006)
		var c := Palette.get_color("cyan", Color(0.2, 0.95, 1.0))
		draw_arc(Vector2.ZERO, 92.0, 0.0, TAU, 48, Color(c, 0.45 * pulse), 4.0, true)
		draw_arc(Vector2.ZERO, 98.0, 0.0, TAU, 48, Color(c, 0.18 * pulse), 8.0, true)


## Grants a protected window (e.g. after a boss dies, or on revive) without
## shortening one already running.
func grant_invulnerability(seconds: float) -> void:
	_invuln_time = maxf(_invuln_time, seconds)


## Re-applies body contact while the core keeps overlapping a hostile body.
func _tick_contact_damage(delta: float) -> void:
	if not _alive or _invuln_time > 0.0:
		_contact_timer = 0.0
		return
	_contact_timer -= delta
	if _contact_timer > 0.0:
		return
	_contact_timer = _CONTACT_RECHECK_INTERVAL
	if not monitoring:
		return
	for area in get_overlapping_areas():
		if area is Enemy:
			take_damage((area as Enemy).get_contact_damage())
			return
		if area is Boss and (area as Boss).is_active():
			take_damage((area as Boss).get_contact_damage())
			return


## Enemies and pickups overlap the player core.
func _on_area_entered(area: Area2D) -> void:
	if area is Pickup:
		var pickup := area as Pickup
		var kind := pickup.get_kind()
		var gained := pickup.collect()
		if gained > 0 and kind != PickupData.Kind.ENERGY:
			special_pickup.emit(kind, gained)
		elif gained > 0:
			_energy += gained
			energy_changed.emit(_energy)
			_pickup_streak += 1
			_pickup_streak_timer = _PICKUP_STREAK_WINDOW
			GameFeel.pickup_collected(global_position, _pickup_streak)
	elif area is Enemy:
		take_damage((area as Enemy).get_contact_damage())


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


func _on_viewport_changed() -> void:
	_adapt_play_rect()
	_recenter_if_needed()
	_target = _clamp_to_bounds(_target)


## Keep authored insets (≈90px sides / HUD top) relative to the design box, then
## grow the playable area with the expanded viewport so tablet sides are not dead.
func _adapt_play_rect() -> void:
	if data == null:
		return
	var base := data.gameplay_rect
	var vp := get_viewport().get_visible_rect().size
	var margin_l := base.position.x
	var margin_t := base.position.y
	var margin_r := maxf(0.0, 1080.0 - (base.position.x + base.size.x))
	var margin_b := maxf(0.0, 1920.0 - (base.position.y + base.size.y))
	_play_rect = Rect2(
		margin_l,
		margin_t,
		maxf(base.size.x, vp.x - margin_l - margin_r),
		maxf(base.size.y, vp.y - margin_t - margin_b)
	)


## Scene default spawn is 540×1500 (9:16 center). On wider viewports, slide to mid.
func _recenter_if_needed() -> void:
	var vp := get_viewport().get_visible_rect().size
	if vp.x <= 1080.0:
		return
	# Only nudge X when still sitting on the authored 9:16 spawn column.
	if absf(global_position.x - 540.0) < 8.0:
		global_position.x = vp.x * 0.5
		_target.x = global_position.x
