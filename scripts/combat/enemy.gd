class_name Enemy
extends Area2D
## Pooled, data-driven enemy.
##
## Movement (EnemyData.movement): FORMATION (enter -> hold -> exit, incl. the
## DIVER plunge), WEAVE, SWOOP, CHARGE, STRAFE. Fire (EnemyData.fire_pattern):
## AIMED_FAN, RING, SPIRAL, DOWN_SPREAD, SNIPE — every pattern is telegraphed
## first. Archetypes without final art draw a procedural neon hull
## (EnemyData.shape). Elites (make_elite) get more HP, a gold aura, and one
## affix: SHIELDED, SWIFT, VOLATILE, or REGEN.
##
## On death the enemy drops energy pickups and returns to its pool; it is never
## freed at runtime. Archetype differences come entirely from EnemyData.

signal died(enemy: Enemy)
## Emitted when a SPLITTER dies (or a carrier summons) so the WaveDirector can
## spawn children from the shared enemy pool (the Enemy has no pool reference).
signal split_requested(origin: Vector2, child_data: EnemyData, count: int)

enum Phase { IDLE, ENTER, WAIT, EXIT, DASH }
enum Affix { NONE, SHIELDED, SWIFT, VOLATILE, REGEN }

## Elite affix tuning (chances and HP multiplier live in SpawnProfileData).
const _SHIELD_FRACTION := 0.4
const _SWIFT_TIME_SCALE := 0.65
const _REGEN_PER_SECOND := 0.05
const _VOLATILE_RING := 14

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
var _max_hp: float = 1.0
var _phase_time: float = 0.0
var _age: float = 0.0

var _enter_from: Vector2
var _hold_pos: Vector2
var _exit_to: Vector2
var _entry_seconds: float = 1.2
var _wait_seconds: float = 4.0
var _exit_seconds: float = 2.0

# Shooter cycle state (telegraph -> fire -> rest).
var _shoot_timer: float = 0.0
var _telegraphing: bool = false
var _spiral_left: float = 0.0
var _spiral_timer: float = 0.0
var _spiral_angle: float = 0.0
## SNIPE locks its aim when the telegraph starts (fair: the line shows the shot).
var _snipe_dir: Vector2 = Vector2.DOWN
var _flash: float = 0.0
var _summon_timer: float = 0.0

## Difficulty scaling applied per run without mutating shared EnemyData.
var _contact_damage_mult: float = 1.0
## DIVER: set true once the dive begins so it only re-targets the player once.
var _diving: bool = false
## Visual hit kick (squash + nudge) 0..1; presentation only.
var _hit_kick: float = 0.0
var _base_sprite_scale: float = 0.12
var _dash_velocity: Vector2 = Vector2.ZERO
var _weave_x: float = 0.0

var _elite: bool = false
var _affix: int = Affix.NONE
var _shield: float = 0.0
var _time_scale: float = 1.0
## Procedural hull (built once per spawn; empty for sprite enemies).
var _hull := PackedVector2Array()

@onready var _sprite: Sprite2D = $Sprite
@onready var _shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	# The scene's CircleShape2D sub-resource is shared by every pooled instance;
	# give each enemy its own copy so per-archetype hit radii never leak.
	if _shape != null and _shape.shape != null:
		_shape.shape = _shape.shape.duplicate()


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
	_max_hp = data.max_health
	_phase = Phase.ENTER
	_phase_time = 0.0
	_age = 0.0
	_shoot_timer = data.shoot_rest
	_telegraphing = false
	_spiral_left = 0.0
	_spiral_timer = 0.0
	_spiral_angle = randf() * TAU
	_flash = 0.0
	_summon_timer = data.summon_interval * 0.5
	_contact_damage_mult = 1.0
	_diving = false
	_dash_velocity = Vector2.ZERO
	_weave_x = enter_from.x
	_elite = false
	_affix = Affix.NONE
	_shield = 0.0
	_time_scale = 1.0
	scale = Vector2.ONE
	global_position = enter_from

	_build_hull()
	if _sprite != null:
		_sprite.visible = data.shape == EnemyData.Shape.SPRITE and data.sprite != null
		_sprite.texture = data.sprite
		_sprite.scale = Vector2(data.sprite_scale, data.sprite_scale)
		_sprite.modulate = data.tint
		_sprite.position = Vector2.ZERO
		_sprite.rotation = 0.0
	_base_sprite_scale = data.sprite_scale
	_hit_kick = 0.0
	if _shape != null and _shape.shape is CircleShape2D:
		(_shape.shape as CircleShape2D).radius = data.hit_radius

	visible = true
	monitoring = true
	monitorable = true
	set_process(true)
	queue_redraw()


## Promotes this enemy to an elite with one affix. Called by the spawner right
## after spawn + apply_scaling.
func make_elite(affix: int, hp_mult: float) -> void:
	_elite = true
	_affix = affix
	_health *= maxf(1.0, hp_mult)
	_max_hp = _health
	scale = Vector2(1.22, 1.22)
	match affix:
		Affix.SHIELDED:
			_shield = _health * _SHIELD_FRACTION
		Affix.SWIFT:
			_time_scale = 1.0 / _SWIFT_TIME_SCALE
	queue_redraw()


func is_elite() -> bool:
	return _elite


func get_affix() -> int:
	return _affix


func _process(raw_delta: float) -> void:
	if data == null:
		return
	var delta := raw_delta * _time_scale
	_phase_time += delta
	_age += delta
	var redraw := _elite or _telegraphing or _spiral_left > 0.0
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 4.0)
		_apply_tint()
		redraw = true
	if _hit_kick > 0.0:
		_hit_kick = maxf(0.0, _hit_kick - delta * 7.0)
		_apply_kick()
	if _affix == Affix.REGEN and _health < _max_hp:
		_health = minf(_max_hp, _health + _max_hp * _REGEN_PER_SECOND * delta)

	match data.movement:
		EnemyData.Movement.WEAVE:
			_move_weave(delta)
		EnemyData.Movement.SWOOP:
			_move_swoop(delta)
		_:
			_move_formation(delta)
	if _phase == Phase.ENTER or _phase == Phase.WAIT and data.movement == EnemyData.Movement.CHARGE:
		redraw = true
	if redraw:
		queue_redraw()


# --- Movement -----------------------------------------------------------------

func _move_formation(delta: float) -> void:
	match _phase:
		Phase.ENTER:
			var t: float = clampf(_phase_time / _entry_seconds, 0.0, 1.0)
			global_position = _enter_from.lerp(_hold_pos, ease(t, 0.4))
			if t >= 1.0:
				_enter_phase(Phase.WAIT)
		Phase.WAIT:
			_hold_behavior(delta)
		Phase.EXIT:
			var te: float = clampf(_phase_time / _exit_seconds, 0.0, 1.0)
			global_position = _hold_pos.lerp(_exit_to, ease(te, 2.2))
			if te >= 1.0:
				_release() # survived the wave; recycle quietly (no death drop)
		Phase.DASH:
			global_position += _dash_velocity * delta
			if not despawn_bounds.has_point(global_position):
				_release()


func _hold_behavior(delta: float) -> void:
	if data.movement == EnemyData.Movement.STRAFE:
		# Slide across the field around the hold point while firing.
		var span := 320.0
		var x := _hold_pos.x + sin(_phase_time * data.move_speed / span) * span
		global_position = Vector2(clampf(x, 80.0, despawn_bounds.end.x - 280.0), _hold_pos.y)
	else:
		# Soft hover so formations do not feel glued to a grid.
		var bob := sin(_phase_time * 2.4) * 6.0
		global_position = _hold_pos + Vector2(0.0, bob)
		if _sprite != null:
			_sprite.rotation = sin(_phase_time * 1.7) * 0.08
	if data.can_shoot:
		_update_shooting(delta)
	if data.summon != null:
		_summon_timer -= delta
		if _summon_timer <= 0.0:
			_summon_timer = data.summon_interval
			split_requested.emit(global_position + Vector2(0, 40), data.summon, data.summon_count)
	if data.movement == EnemyData.Movement.CHARGE:
		if _phase_time >= data.charge_windup:
			_begin_dash()
		return
	# Divers commit to a plunge toward the player instead of waiting out.
	if data.behavior == EnemyData.Behavior.DIVER and _phase_time >= data.dive_delay:
		_begin_dive()
	elif _phase_time >= _wait_seconds:
		_enter_phase(Phase.EXIT)


func _move_weave(delta: float) -> void:
	# Straight descent with a sine sway; shoots while crossing the field.
	global_position.y += data.move_speed * delta
	global_position.x = _weave_x + sin(_age * TAU * data.weave_frequency) * data.weave_amplitude
	if _phase == Phase.ENTER:
		_phase = Phase.WAIT
	if data.can_shoot and global_position.y > 0.0:
		_update_shooting(delta)
	if global_position.y > despawn_bounds.end.y - 300.0:
		_release()


func _move_swoop(delta: float) -> void:
	# Quadratic arc: side -> hold point (control) -> opposite side.
	var total := _entry_seconds + _exit_seconds
	var t := clampf(_age / maxf(0.1, total), 0.0, 1.0)
	var a := _enter_from.lerp(_hold_pos, t)
	var b := _hold_pos.lerp(_exit_to, t)
	global_position = a.lerp(b, t)
	if _phase == Phase.ENTER and t > 0.15:
		_phase = Phase.WAIT
	if data.can_shoot and t > 0.2 and t < 0.8:
		_update_shooting(delta)
	if t >= 1.0:
		_release()


## Charger: dash straight at where the player is now.
func _begin_dash() -> void:
	var target := player.global_position if player != null else global_position + Vector2.DOWN
	_dash_velocity = (target - global_position).normalized() * data.charge_speed
	_enter_phase(Phase.DASH)


## Diver commit: aim the plunge at the player's column and speed up the exit.
func _begin_dive() -> void:
	_diving = true
	var target_x := _exit_to.x
	if player != null:
		target_x = player.global_position.x
	_exit_to = Vector2(target_x, _exit_to.y)
	_exit_seconds = maxf(0.2, _exit_seconds / maxf(1.0, data.dive_speed_mult))
	_enter_phase(Phase.EXIT)


# --- Shooting -------------------------------------------------------------------

func _update_shooting(delta: float) -> void:
	if _spiral_left > 0.0:
		_tick_spiral(delta)
		return
	_shoot_timer -= delta
	if _telegraphing:
		if _shoot_timer <= 0.0:
			_telegraphing = false
			_shoot_timer = data.shoot_rest
			_fire_pattern()
	elif _shoot_timer <= 0.0:
		_telegraphing = true
		_shoot_timer = data.shoot_telegraph
		if data.fire_pattern == EnemyData.FirePattern.SNIPE and player != null:
			_snipe_dir = (player.global_position - global_position).normalized()


func _fire_pattern() -> void:
	if enemy_projectile_pool == null or data.projectile == null:
		return
	match data.fire_pattern:
		EnemyData.FirePattern.RING:
			var off := randf() * TAU
			for i in data.ring_count:
				_shoot(Vector2.RIGHT.rotated(off + TAU * float(i) / float(data.ring_count)))
		EnemyData.FirePattern.SPIRAL:
			_spiral_left = data.spiral_duration
			_spiral_timer = 0.0
		EnemyData.FirePattern.DOWN_SPREAD:
			_fire_fan(Vector2.DOWN)
		EnemyData.FirePattern.SNIPE:
			_shoot(_snipe_dir)
		_:
			var aim := Vector2.DOWN
			if player != null:
				aim = (player.global_position - global_position).normalized()
			_fire_fan(aim)


func _fire_fan(base_dir: Vector2) -> void:
	var count := data.burst_count
	if count <= 1:
		_shoot(base_dir)
		return
	var step := data.burst_spread_degrees / float(count - 1)
	var start := -data.burst_spread_degrees * 0.5
	for i in count:
		_shoot(base_dir.rotated(deg_to_rad(start + step * float(i))))


func _tick_spiral(delta: float) -> void:
	_spiral_left -= delta
	_spiral_timer -= delta
	var interval := 1.0 / maxf(0.5, data.spiral_rate)
	while _spiral_timer <= 0.0:
		_spiral_timer += interval
		_spiral_angle += deg_to_rad(data.spiral_turn_degrees)
		for arm in data.spiral_arms:
			_shoot(Vector2.DOWN.rotated(_spiral_angle + TAU * float(arm) / float(data.spiral_arms)))
	if _spiral_left <= 0.0:
		_spiral_left = 0.0
		_shoot_timer = data.shoot_rest


func _shoot(dir: Vector2) -> void:
	if enemy_projectile_pool != null and data.projectile != null:
		enemy_projectile_pool.spawn(global_position, dir, data.projectile)


# --- Drawing --------------------------------------------------------------------

func _build_hull() -> void:
	_hull.clear()
	var r := data.hit_radius
	match data.shape:
		EnemyData.Shape.DART:
			_hull.append_array([Vector2(0, r), Vector2(r * 0.75, -r * 0.7), Vector2(0, -r * 0.3), Vector2(-r * 0.75, -r * 0.7)])
		EnemyData.Shape.DIAMOND:
			_hull.append_array([Vector2(0, r * 1.1), Vector2(r * 0.7, 0), Vector2(0, -r * 1.0), Vector2(-r * 0.7, 0)])
		EnemyData.Shape.HEX:
			for i in 6:
				_hull.append(Vector2.RIGHT.rotated(TAU * float(i) / 6.0 + PI / 6.0) * r)
		EnemyData.Shape.CROSS:
			var w := r * 0.36
			_hull.append_array([Vector2(-w, -r), Vector2(w, -r), Vector2(w, -w), Vector2(r, -w), Vector2(r, w),
				Vector2(w, w), Vector2(w, r), Vector2(-w, r), Vector2(-w, w), Vector2(-r, w), Vector2(-r, -w), Vector2(-w, -w)])
		EnemyData.Shape.ORB:
			for i in 10:
				var rr := r * (1.0 if i % 2 == 0 else 0.72)
				_hull.append(Vector2.RIGHT.rotated(TAU * float(i) / 10.0) * rr)
		EnemyData.Shape.CARRIER:
			_hull.append_array([Vector2(-r * 0.5, -r), Vector2(r * 0.5, -r), Vector2(r, -r * 0.3), Vector2(r * 0.8, r * 0.7),
				Vector2(r * 0.3, r), Vector2(-r * 0.3, r), Vector2(-r * 0.8, r * 0.7), Vector2(-r, -r * 0.3)])
		_:
			pass
	if not _hull.is_empty():
		_hull.append(_hull[0])


func _draw() -> void:
	if data == null:
		return
	var r := data.hit_radius
	if not _hull.is_empty():
		var tint := data.tint.lerp(Color.WHITE, _flash)
		var k := 1.0 + 0.1 * _hit_kick
		draw_set_transform(Vector2(0.0, -5.0 * _hit_kick), 0.0, Vector2(k, 2.0 - k))
		draw_colored_polygon(_hull, Color(0.07, 0.04, 0.14, 0.95))
		draw_polyline(_hull, Color(tint, 0.35), 9.0, true)
		draw_polyline(_hull, tint, 3.5, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Orange energy core (visual language: violet hull + warm core).
	var core_r := r * 0.28
	var core_c := Color(1.0, 0.55, 0.15, 0.9)
	if _affix == Affix.VOLATILE:
		core_c = Color(1.0, 0.2, 0.2, 0.75 + 0.25 * sin(_age * 12.0))
	draw_circle(Vector2(0.0, 6.0), core_r * 1.6, Color(core_c, 0.35))
	draw_circle(Vector2(0.0, 6.0), core_r, core_c)
	if _elite:
		_draw_elite(r)
	# Entrance: soft expanding ring so arrivals read without covering bolts.
	if _phase == Phase.ENTER and data.movement == EnemyData.Movement.FORMATION:
		var et := clampf(_phase_time / _entry_seconds, 0.0, 1.0)
		var er := r * (1.2 + 1.4 * et)
		draw_arc(Vector2.ZERO, er, 0.0, TAU, 32, Color(0.55, 0.25, 1.0, 0.55 * (1.0 - et)), 3.0, true)
	if _phase == Phase.WAIT and data.movement == EnemyData.Movement.CHARGE and player != null:
		_draw_charge_telegraph(r)
	# Telegraph: warning ring + aim line toward the player (readable on phones).
	if _telegraphing:
		_draw_fire_telegraph(r)


func _draw_elite(r: float) -> void:
	var gold := Color(1.0, 0.8, 0.22)
	var pulse := 0.6 + 0.4 * sin(_age * 5.0)
	draw_arc(Vector2.ZERO, r * 1.35, 0.0, TAU, 40, Color(gold, 0.35 + 0.3 * pulse), 4.0, true)
	draw_arc(Vector2.ZERO, r * 1.5, 0.0, TAU, 40, Color(gold, 0.15 * pulse), 8.0, true)
	match _affix:
		Affix.SHIELDED:
			if _shield > 0.0:
				draw_circle(Vector2.ZERO, r * 1.2, Color(0.3, 0.85, 1.0, 0.16))
				draw_arc(Vector2.ZERO, r * 1.2, 0.0, TAU, 40, Color(0.3, 0.9, 1.0, 0.8), 3.0, true)
		Affix.SWIFT:
			for i in 3:
				var x := (float(i) - 1.0) * r * 0.4
				draw_line(Vector2(x, -r * 1.3), Vector2(x, -r * 1.9), Color(gold, 0.6), 3.0, true)
		Affix.REGEN:
			draw_line(Vector2(-r * 0.2, -r * 1.05), Vector2(r * 0.2, -r * 1.05), Color(0.35, 1.0, 0.5), 4.0)
			draw_line(Vector2(0, -r * 1.25), Vector2(0, -r * 0.85), Color(0.35, 1.0, 0.5), 4.0)


func _draw_charge_telegraph(r: float) -> void:
	var t := clampf(_phase_time / maxf(0.01, data.charge_windup), 0.0, 1.0)
	var aim := to_local(player.global_position).normalized()
	var danger := Color(1.0, 0.23, 0.3, 0.25 + 0.6 * t)
	draw_line(aim * r * 1.1, aim * 1400.0, Color(danger, danger.a * 0.4), 10.0 * t + 2.0, true)
	draw_line(aim * r * 1.1, aim * 1400.0, danger, 2.5, true)


func _draw_fire_telegraph(r: float) -> void:
	var pulse := 0.7 + 0.3 * absf(sin(_age * 20.0))
	draw_arc(Vector2.ZERO, r * 1.85, 0.0, TAU, 40, Color(1.0, 0.23, 0.3, pulse), 4.5, true)
	draw_arc(Vector2.ZERO, r * 1.35, 0.0, TAU, 28, Color(1.0, 0.85, 0.35, 0.55 * pulse), 2.0, true)
	match data.fire_pattern:
		EnemyData.FirePattern.SNIPE:
			# Long lock-on line along the exact shot path.
			draw_line(_snipe_dir * r * 1.2, _snipe_dir * 2400.0, Color(1.0, 0.2, 0.25, 0.55 * pulse), 3.0, true)
		EnemyData.FirePattern.RING, EnemyData.FirePattern.SPIRAL:
			draw_arc(Vector2.ZERO, r * 2.4, 0.0, TAU, 48, Color(1.0, 0.3, 0.3, 0.35 * pulse), 2.0, true)
		EnemyData.FirePattern.DOWN_SPREAD:
			draw_line(Vector2(0, r * 1.2), Vector2(0, r * 4.6), Color(1.0, 0.23, 0.23, 0.8), 3.5, true)
		_:
			if player != null:
				var aim := to_local(player.global_position).normalized()
				draw_line(aim * r * 1.2, aim * r * 4.6, Color(1.0, 0.23, 0.23, 0.8), 3.5, true)
				draw_circle(aim * r * 4.6, 5.0, Color(1.0, 0.9, 0.4, 0.85))


# --- Damage / scaling -------------------------------------------------------------

## Applies per-run difficulty scaling. Called by the WaveDirector right after
## spawn; multiplies current HP and stores the contact-damage multiplier so the
## shared EnemyData is never mutated.
func apply_scaling(hp_mult: float, contact_damage_mult: float) -> void:
	if hp_mult > 0.0:
		_health = maxf(1.0, _health * hp_mult)
		_max_hp = _health
	_contact_damage_mult = maxf(0.0, contact_damage_mult)


## Contact damage after difficulty scaling (read by the player on body overlap).
func get_contact_damage() -> float:
	if data == null:
		return 0.0
	return data.contact_damage * _contact_damage_mult * (1.5 if _elite else 1.0)


## Applies damage from a player projectile. Handles death + drops once.
func take_damage(amount: float) -> void:
	if _phase == Phase.IDLE or _health <= 0.0:
		return
	var dmg := amount
	if _shield > 0.0:
		var absorbed := minf(_shield, dmg)
		_shield -= absorbed
		dmg -= absorbed
	_health -= dmg
	_flash = 1.0
	_hit_kick = 1.0
	_apply_tint()
	if _health <= 0.0:
		_die()


func pool_reset() -> void:
	_phase = Phase.IDLE
	_health = 0.0
	# The enemy pool is shared by the WaveDirector and the Boss (adds). Drop the
	# previous owner's listeners so one kill is never reported to both owners.
	_disconnect_all(died)
	_disconnect_all(split_requested)


func _disconnect_all(sig: Signal) -> void:
	for c in sig.get_connections():
		sig.disconnect(c["callable"])


func pool_disable() -> void:
	set_process(false)
	# Deferred: death/release can occur inside a projectile's area_entered signal,
	# where Godot blocks toggling monitoring/monitorable directly.
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	visible = false
	_phase = Phase.IDLE
	_telegraphing = false
	_spiral_left = 0.0


func _enter_phase(next: int) -> void:
	_phase = next
	_phase_time = 0.0
	queue_redraw()


func _die() -> void:
	# Feel: tougher enemies get a large explosion + hit-stop.
	var is_major := data.big_explosion or data.is_elite or data.can_shoot
	if _elite or data.is_elite:
		GameFeel.elite_death(global_position)
	else:
		GameFeel.enemy_death(global_position, is_major)
	if _affix == Affix.VOLATILE:
		var off := randf() * TAU
		for i in _VOLATILE_RING:
			_shoot(Vector2.RIGHT.rotated(off + TAU * float(i) / float(_VOLATILE_RING)))
	_drop_energy()
	if data.behavior == EnemyData.Behavior.SPLITTER and data.split_into != null and data.split_count > 0:
		split_requested.emit(global_position, data.split_into, data.split_count)
	died.emit(self)
	_release()


func _drop_energy() -> void:
	if pickup_pool == null or pickup_data == null or data.energy_drop <= 0:
		return
	var drops := data.energy_drop * (3 if _elite else 1)
	for i in drops:
		var node := pickup_pool.acquire()
		var pickup := node as Pickup
		if pickup == null:
			continue
		var jitter := Vector2(randf_range(-24.0, 24.0), randf_range(-16.0, 16.0))
		pickup.release_callback = Callable(pickup_pool, "release")
		pickup.magnet_target = player
		pickup.spawn(global_position + jitter, pickup_data, despawn_bounds)


func _apply_tint() -> void:
	if _sprite == null or data == null:
		return
	_sprite.modulate = data.tint.lerp(Color.WHITE, _flash)


## Squash + upward nudge on hit so every bolt visibly connects.
func _apply_kick() -> void:
	if _sprite == null:
		return
	var k := _hit_kick * _hit_kick
	_sprite.scale = Vector2(_base_sprite_scale * (1.0 + 0.12 * k), _base_sprite_scale * (1.0 - 0.08 * k))
	_sprite.position = Vector2(0.0, -6.0 * k)


func _release() -> void:
	# Deferred: _die() runs inside the player bolt's area_entered signal, where
	# directly toggling monitoring/monitorable is blocked by Godot.
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	if release_callback.is_valid():
		release_callback.call(self)
	else:
		pool_disable()
