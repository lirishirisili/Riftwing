class_name Boss
extends Area2D
## The first boss (Void Titan): a data-driven encounter state machine.
##
## Top-level flow:
##   IDLE -> WARNING -> ENTER -> FIGHT <-> PHASE_TRANSITION -> DEFEATED
## During FIGHT an inner pattern loop (TELEGRAPH -> ACTIVE -> RECOVER) cycles the
## current phase's BossPatternData list. All timing advances by delta (no await),
## so the fight is deterministic, pausable, and testable from a probe.
##
## Every attack is preceded by a telegraph and leaves a viable safe route
## (docs/02_GAMEPLAY_SPEC.md). Behavior lives here; every number comes from
## BossData / BossPatternData (docs/04_ARCHITECTURE.md).

signal warning_started(name: String)
signal entered()
signal health_changed(current: float, maximum: float)
signal phase_changed(phase: int)
signal attack_started(kind: int, phase: int)
## Emitted when a summoned add is destroyed by the player (not on exit-recycle),
## so the run host can count enemies destroyed for the results screen.
signal add_destroyed()
## Fires the moment HP hits zero (before the ~1.2s death beat ends with
## `defeated`), so the host can clear hostile fire and protect the player.
signal dying()
signal defeated()

enum State { IDLE, WARNING, ENTER, FIGHT, PHASE_TRANSITION, DEFEATED }
enum Beat { TELEGRAPH, ACTIVE, RECOVER }

@export var data: BossData

## Injected by the host scene (mirrors how WaveDirector wires enemies).
var enemy_projectile_pool: ProjectilePool
var enemy_pool: NodePool
var pickup_pool: NodePool
var pickup_data: PickupData
var player: Node2D
var screen_size: Vector2 = Vector2(1080, 1920)
## World rect outside which summoned adds are reclaimed.
var despawn_bounds: Rect2 = Rect2(-200.0, -400.0, 1480.0, 2720.0)

var _state: int = State.IDLE
var _state_time: float = 0.0
var _health: float = 0.0
var _phase: int = 1

# Entrance interpolation.
var _enter_from: Vector2
var _hold_pos: Vector2

# Inner pattern-loop state.
var _patterns: Array[BossPatternData] = []
var _pattern_index: int = 0
var _beat: int = Beat.TELEGRAPH
var _beat_time: float = 0.0
var _current: BossPatternData = null

# Radial sub-state: fire rings spaced across the active window.
var _rings_fired: int = 0
var _ring_timer: float = 0.0
var _pattern_spin: float = 0.0

# Laser sub-state.
var _laser_angle: float = 0.0
var _laser_hot: bool = false

# Summon sub-state.
var _waves_summoned: int = 0
var _wave_timer: float = 0.0
## Adds spawned by SUMMON_WAVE, tracked so DEFEATED can clear the arena.
var _summoned: Array[Enemy] = []

var _flash: float = 0.0
var _defeated_emitted: bool = false
## Per-run HP scaling (difficulty). Applied at begin(); never mutates BossData.
var _hp_mult: float = 1.0
## Per-run outgoing damage scaling (laser + body contact). Enemy bolts are scaled
## by the enemy ProjectilePool instead.
var _damage_mult: float = 1.0
## Difficulty applied to summoned adds so they match the wave enemies.
var _add_hp_mult: float = 1.0
var _add_contact_mult: float = 1.0
## Cached safe-gap slots for the current radial pattern (rebuilt per pattern,
## so firing and telegraph drawing never allocate).
var _gap_slots: Dictionary = {}
## Phase the current PHASE_TRANSITION leads into.
var _pending_phase: int = 2
## Fight clock (drives sway + procedural visuals).
var _fight_time: float = 0.0
# New-pattern sub-state (spiral / volley / wall / orbs / rain).
var _shot_timer: float = 0.0
var _shots_done: int = 0
var _spiral_angle: float = 0.0
var _rain_x := PackedFloat32Array()
var _wall_gap_x: float = 0.0
## Leviathan tail: recent positions (fixed ring, no per-frame allocation).
const _TAIL_LEN := 12
var _tail := PackedVector2Array()
var _tail_timer: float = 0.0

@onready var _sprite: Sprite2D = $Sprite
@onready var _shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	if data == null:
		data = BossData.new()
	set_process(false)
	visible = false
	monitoring = false
	monitorable = false
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)


## Assigns a new BossData and returns the node to a clean idle (for mini → final).
func prepare(new_data: BossData) -> void:
	if new_data != null:
		data = new_data
	_defeated_emitted = false
	_current = null
	_laser_hot = false
	_flash = 0.0
	_phase = 1
	_clear_summoned()
	_enter_state(State.IDLE)
	visible = false
	set_process(false)
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)


## Starts the encounter from the warning banner. Call once the host is wired.
func begin() -> void:
	_defeated_emitted = false
	_current = null
	_laser_hot = false
	_health = _max_health()
	_phase = 1
	_hold_pos = Vector2(screen_size.x * data.hold_ratio.x, screen_size.y * data.hold_ratio.y)
	_enter_from = Vector2(_hold_pos.x, -data.hit_radius * 2.0)
	global_position = _enter_from

	if _sprite != null:
		_sprite.texture = data.sprite
		_sprite.scale = Vector2(data.sprite_scale, data.sprite_scale)
		# The Overmind is fully procedural; other visuals decorate the sprite.
		_sprite.visible = data.visual != BossData.Visual.OVERMIND and data.sprite != null
		# Hydra heads / necks read on top of the hull; other visuals sit behind it.
		_sprite.show_behind_parent = data.visual == BossData.Visual.HYDRA
	_fight_time = 0.0
	_tail.clear()
	_apply_tint()
	if _shape != null and _shape.shape is CircleShape2D:
		(_shape.shape as CircleShape2D).radius = data.hit_radius

	_enter_state(State.WARNING)
	set_process(true)
	health_changed.emit(_health, _max_health())
	warning_started.emit(data.display_name)
	AudioManager.play_sfx("boss_warning", Vector2.ZERO, AudioManager.PRIORITY_HIGH)
	GameFeel.haptic("heavy")


func get_health() -> float:
	return _health


func get_health_fraction() -> float:
	var maxhp := _max_health()
	return 0.0 if maxhp <= 0.0 else _health / maxhp


## Per-run HP scaling (difficulty). Applied at begin(); never mutates BossData.
func set_scaling(hp_mult: float, damage_mult: float = 1.0) -> void:
	_hp_mult = maxf(0.1, hp_mult)
	_damage_mult = maxf(0.0, damage_mult)


## Difficulty for summoned adds (same values the WaveDirector applies).
func set_add_scaling(hp_mult: float, contact_damage_mult: float) -> void:
	_add_hp_mult = maxf(0.1, hp_mult)
	_add_contact_mult = maxf(0.0, contact_damage_mult)


## Body-contact damage after difficulty scaling (read by the player on overlap).
func get_contact_damage() -> float:
	return data.contact_damage * _damage_mult if data != null else 0.0


## Live summoned adds (read-only; iterate a duplicate if a hit can kill).
func get_adds() -> Array[Enemy]:
	return _summoned


## Damages every live summoned add (Rift Nova).
func damage_adds(amount: float) -> void:
	for e in _summoned.duplicate():
		if is_instance_valid(e):
			e.take_damage(amount)


func get_max_health() -> float:
	return _max_health()


## Nearest live summoned add to a point, or null (secondary-weapon auto-aim).
func nearest_add(from: Vector2) -> Enemy:
	var best: Enemy = null
	var best_d := INF
	for e in _summoned:
		if not is_instance_valid(e):
			continue
		var d := from.distance_squared_to(e.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best


## Scaled maximum health for this run (BossData is never mutated).
func _max_health() -> float:
	return data.max_health * _hp_mult


func get_phase() -> int:
	return _phase


func get_state() -> int:
	return _state


func is_active() -> bool:
	return _state == State.FIGHT or _state == State.PHASE_TRANSITION


func _process(delta: float) -> void:
	_state_time += delta
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 3.0)
		_apply_tint()

	match _state:
		State.WARNING:
			# Boss stays hidden; the banner (owned by the HUD) counts down.
			if _state_time >= data.warning_seconds:
				visible = true
				_enter_state(State.ENTER)
		State.ENTER:
			var t: float = clampf(_state_time / maxf(0.01, data.entry_seconds), 0.0, 1.0)
			global_position = _enter_from.lerp(_hold_pos, ease(t, 0.4))
			if t >= 1.0:
				global_position = _hold_pos
				monitoring = true
				monitorable = true
				entered.emit()
				_begin_fight(1)
		State.FIGHT:
			_fight_time += delta
			global_position = _hold_pos + _sway_offset()
			_update_fight(delta)
		State.PHASE_TRANSITION:
			global_position = _hold_pos + _sway_offset()
			# Brief invulnerable, dramatic beat before the next phase starts.
			if _state_time >= data.phase_transition_seconds:
				_begin_fight(_pending_phase)
		State.DEFEATED:
			_update_defeated(delta)

	_update_tail(delta)
	queue_redraw()


func _sway_offset() -> Vector2:
	if data.sway_amplitude <= 0.0:
		return Vector2.ZERO
	return Vector2(sin(_fight_time * TAU * data.sway_speed) * data.sway_amplitude, 0.0)


func _update_tail(delta: float) -> void:
	if data.visual != BossData.Visual.LEVIATHAN or not visible:
		return
	if _tail.size() != _TAIL_LEN:
		_tail.resize(_TAIL_LEN)
		_tail.fill(global_position)
	_tail_timer -= delta
	if _tail_timer > 0.0:
		return
	_tail_timer = 0.05
	for i in range(_TAIL_LEN - 1, 0, -1):
		_tail[i] = _tail[i - 1]
	_tail[0] = global_position


# --- Fight loop -------------------------------------------------------------

func _begin_fight(phase: int) -> void:
	_phase = phase
	match phase:
		3:
			_patterns = data.phase3_patterns
		2:
			_patterns = data.phase2_patterns
		_:
			_patterns = data.phase1_patterns
	_pattern_index = 0
	_enter_state(State.FIGHT)
	_begin_pattern()


func _begin_pattern() -> void:
	if _patterns.is_empty():
		_current = null
		return
	_current = _patterns[_pattern_index % _patterns.size()]
	_beat = Beat.TELEGRAPH
	_beat_time = 0.0
	_rings_fired = 0
	_ring_timer = 0.0
	_waves_summoned = 0
	_wave_timer = 0.0
	_laser_hot = false
	_pattern_spin = 0.0
	# Laser starts at one edge of its sweep arc (centered on straight-down).
	_laser_angle = -deg_to_rad(_current.laser_sweep_degrees * 0.5)
	_gap_slots = _gap_slot_set(_current.radial_bullets) if _current.kind == BossPatternData.Kind.RADIAL_BURST else {}
	_shot_timer = 0.0
	_shots_done = 0
	_prepare_new_pattern()


func _update_fight(delta: float) -> void:
	if _current == null:
		if not _patterns.is_empty():
			_begin_pattern()
		return

	_beat_time += delta
	match _beat:
		Beat.TELEGRAPH:
			if _beat_time >= _current.telegraph_seconds:
				_beat = Beat.ACTIVE
				_beat_time = 0.0
				attack_started.emit(_current.kind, _phase)
				_on_active_begin()
		Beat.ACTIVE:
			_update_active(delta)
			if _beat_time >= _current.active_seconds:
				_beat = Beat.RECOVER
				_beat_time = 0.0
				_laser_hot = false
		Beat.RECOVER:
			if _beat_time >= _current.recover_seconds:
				_pattern_index += 1
				_begin_pattern()


func _on_active_begin() -> void:
	match _current.kind:
		BossPatternData.Kind.RADIAL_BURST:
			# Fire the first ring immediately, then space the rest.
			_fire_radial_ring()
			_rings_fired = 1
			_ring_timer = 0.0
		BossPatternData.Kind.SWEEP_LASER:
			_laser_hot = true
			AudioManager.play_sfx("boss_laser", Vector2.ZERO, AudioManager.PRIORITY_HIGH)
		BossPatternData.Kind.SUMMON_WAVE:
			_summon_one_wave()
			_waves_summoned = 1
			_wave_timer = 0.0


func _update_active(delta: float) -> void:
	match _current.kind:
		BossPatternData.Kind.RADIAL_BURST:
			_update_radial(delta)
		BossPatternData.Kind.SWEEP_LASER:
			_update_laser(delta)
		BossPatternData.Kind.SUMMON_WAVE:
			_update_summon(delta)
		BossPatternData.Kind.SPIRAL_STREAM:
			_update_spiral(delta)
		BossPatternData.Kind.AIMED_VOLLEY:
			_update_spaced(delta, _current.volley_count)
		BossPatternData.Kind.WALL_GAPS:
			_update_spaced(delta, _current.wall_count)
		BossPatternData.Kind.HOMING_ORBS:
			_update_spaced(delta, 1)
		BossPatternData.Kind.BULLET_RAIN:
			_update_spaced(delta, _current.rain_bullets_per_column)


# --- Attack 1: radial burst with safe gaps ----------------------------------

func _update_radial(delta: float) -> void:
	if _rings_fired >= _current.radial_rings:
		return
	_ring_timer += delta
	# Evenly distribute the remaining rings across the active window.
	var interval: float = _current.active_seconds / float(maxi(1, _current.radial_rings))
	if _ring_timer >= interval:
		_ring_timer -= interval
		_pattern_spin += deg_to_rad(_current.radial_spin_degrees)
		_fire_radial_ring()
		_rings_fired += 1


func _fire_radial_ring() -> void:
	if enemy_projectile_pool == null or _current.radial_projectile == null:
		return
	var n: int = _current.radial_bullets
	# Slots occupied by the safe gaps, so those bullets are skipped and a real
	# corridor opens up (docs/02_GAMEPLAY_SPEC.md: viable safe route).
	var step := TAU / float(n)
	for i in n:
		if _gap_slots.has(i):
			continue
		var angle := _pattern_spin + step * float(i)
		var dir := Vector2.RIGHT.rotated(angle)
		enemy_projectile_pool.spawn(global_position, dir, _current.radial_projectile)


## The set of ring slots that are left empty to form the safe gaps.
func _gap_slot_set(n: int) -> Dictionary:
	var slots: Dictionary = {}
	if _current.radial_gaps <= 0:
		return slots
	var spacing := float(n) / float(_current.radial_gaps)
	for g in _current.radial_gaps:
		var base := int(round(spacing * float(g)))
		for w in _current.radial_gap_slots:
			slots[(base + w) % n] = true
	return slots


# --- Attack 2: telegraphed sweeping laser -----------------------------------

func _update_laser(delta: float) -> void:
	var span := deg_to_rad(_current.laser_sweep_degrees)
	var active := maxf(0.01, _current.active_seconds)
	# Progress 0..1 across the active window; optionally sweep back.
	var p := clampf(_beat_time / active, 0.0, 1.0)
	if _current.laser_return_sweep:
		p = 1.0 - absf(1.0 - 2.0 * p)  # 0 -> 1 -> 0 triangle
	_laser_angle = -span * 0.5 + span * p

	if _laser_hot and player != null:
		_apply_laser_damage()


func _apply_laser_damage() -> void:
	# Damage is a point-to-ray distance test (beam is a ray from the boss along
	# _laser_angle, pointing generally downward). Thin beam => a safe side exists.
	var origin := global_position
	var dir := Vector2.DOWN.rotated(_laser_angle)
	var to_player: Vector2 = player.global_position - origin
	var proj := to_player.dot(dir)
	if proj <= 0.0:
		return  # player is behind the beam origin; not on the ray
	var closest := origin + dir * proj
	var dist := player.global_position.distance_to(closest)
	if dist <= _current.laser_half_width + 18.0:  # +core radius
		if player.has_method("take_damage"):
			player.call("take_damage", _current.laser_damage * _damage_mult)


# --- Attack 3: summon waves --------------------------------------------------

func _update_summon(delta: float) -> void:
	if _waves_summoned >= _current.summon_waves:
		return
	_wave_timer += delta
	var interval: float = _current.active_seconds / float(maxi(1, _current.summon_waves))
	if _wave_timer >= interval:
		_wave_timer -= interval
		_summon_one_wave()
		_waves_summoned += 1


func _summon_one_wave() -> void:
	if enemy_pool == null or _current.summon_enemy == null:
		return
	var count: int = _current.summon_per_wave
	var mid := float(count - 1) * 0.5
	var center_x := screen_size.x * 0.5
	var hold_y := screen_size.y * 0.36
	for i in count:
		var node := enemy_pool.acquire()
		var enemy := node as Enemy
		if enemy == null:
			continue
		var x := center_x + (float(i) - mid) * _current.summon_spacing
		var hold := Vector2(x, hold_y)
		var enter_from := Vector2(x, -120.0)
		var exit_to := Vector2(x, screen_size.y + 200.0)
		enemy.release_callback = Callable(self, "_on_summon_released")
		enemy.enemy_projectile_pool = enemy_projectile_pool
		enemy.pickup_pool = pickup_pool
		enemy.pickup_data = pickup_data
		enemy.player = player
		enemy.despawn_bounds = despawn_bounds
		# `died` fires only on a real kill (not exit-recycle); re-broadcast it so
		# the run host can tally enemies destroyed.
		if not enemy.died.is_connected(_on_summoned_died):
			enemy.died.connect(_on_summoned_died)
		enemy.spawn(_current.summon_enemy, enter_from, hold, exit_to, 1.0, 3.0, 1.8)
		enemy.apply_scaling(_add_hp_mult, _add_contact_mult)
		_summoned.append(enemy)


func _on_summoned_died(_enemy: Enemy) -> void:
	add_destroyed.emit()


func _on_summon_released(node: Node) -> void:
	var e := node as Enemy
	if e != null:
		_summoned.erase(e)
	if enemy_pool != null:
		enemy_pool.release(node)


# --- Damage / phases / defeat -----------------------------------------------

## Probe / QA: force the defeat sequence even during WARNING/ENTER.
## Emits `defeated` immediately (skips the ~1.2s death beat) so headless
## probes are not dependent on real-time delta accumulation.
func debug_defeat() -> void:
	if _state == State.DEFEATED or _defeated_emitted:
		return
	_health = 0.0
	health_changed.emit(_health, _max_health())
	_enter_defeated()
	_defeated_emitted = true
	defeated.emit()
	visible = false
	set_process(false)


## Applies damage from a player projectile. Ignored until the boss is fightable
## and while phase-transitioning (a brief invulnerable dramatic beat).
func take_damage(amount: float) -> void:
	if not is_active() or _state == State.PHASE_TRANSITION:
		return
	if _health <= 0.0:
		return
	_health = maxf(0.0, _health - amount)
	_flash = 1.0
	_apply_tint()
	health_changed.emit(_health, _max_health())
	# Impact feedback (flash, number, SFX) comes from the projectile that hit us;
	# emitting it here too doubled every bolt.

	if _health <= 0.0:
		_enter_defeated()
	elif _phase == 1 and get_health_fraction() <= data.phase2_threshold:
		_enter_phase_transition(2)
	elif (_phase == 2 and data.phase3_threshold > 0.0 and not data.phase3_patterns.is_empty()
			and get_health_fraction() <= data.phase3_threshold):
		_enter_phase_transition(3)


func _enter_phase_transition(next_phase: int) -> void:
	_pending_phase = next_phase
	_enter_state(State.PHASE_TRANSITION)
	_current = null
	_laser_hot = false
	_flash = 1.0
	_apply_tint()
	phase_changed.emit(next_phase)
	GameFeel.enemy_death(global_position, true)
	GameFeel.boss_phase(global_position)
	GameFeel.request_hitstop(0.08)
	AudioManager.play_sfx("boss_phase", Vector2.ZERO, AudioManager.PRIORITY_HIGH)
	GameFeel.haptic("heavy")


func _enter_defeated() -> void:
	_enter_state(State.DEFEATED)
	_current = null
	_laser_hot = false
	dying.emit()
	# Deferred: defeat is triggered from take_damage, which runs inside the
	# player bolt's area_entered signal where toggling monitoring is blocked.
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	# Clear any summoned adds so the arena is clean for the victory beat.
	_clear_summoned()
	GameFeel.enemy_death(global_position, true)
	GameFeel.boss_killed(global_position)
	AudioManager.play_sfx("boss_defeated", Vector2.ZERO, AudioManager.PRIORITY_HIGH)
	GameFeel.haptic("heavy")


func _update_defeated(_delta: float) -> void:
	# A short death sequence of secondary blasts, then the victory event fires
	# once and the boss hides itself.
	if _state_time >= 1.2 and not _defeated_emitted:
		_defeated_emitted = true
		defeated.emit()
		visible = false
		set_process(false)
	elif _state_time < 1.2:
		# Staggered explosions across the body for spectacle.
		if int(_state_time * 8.0) != int((_state_time - _delta_hint()) * 8.0):
			var offset := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * data.hit_radius * 0.7
			GameFeel.enemy_death(global_position + offset, false)


func _delta_hint() -> float:
	# Small helper so the explosion cadence check reads clearly; ~one frame.
	return 1.0 / 60.0


func _clear_summoned() -> void:
	# Copy first: releasing mutates the array via the release callback.
	var adds := _summoned.duplicate()
	for e in adds:
		if is_instance_valid(e):
			e.pool_disable()
			if enemy_pool != null:
				enemy_pool.release(e)
	_summoned.clear()


func _on_area_entered(area: Area2D) -> void:
	# Ramming the boss body hurts the player (boss has no body-contact bullet).
	if area == player and player.has_method("take_damage"):
		player.call("take_damage", get_contact_damage())


func _apply_tint() -> void:
	if _sprite == null:
		return
	# Later phases run a hotter base tint; hit flash blends toward white.
	var base := data.tint if data != null else Color.WHITE
	if _phase >= 2:
		base = base * Color(1.1, 0.85, 1.1, 1.0)
	if _phase >= 3:
		base = base * Color(1.15, 0.8, 0.8, 1.0)
	_sprite.modulate = base.lerp(Color(2.0, 2.0, 2.0, 1.0), _flash)


func _enter_state(next: int) -> void:
	_state = next
	_state_time = 0.0


# --- Telegraphs (readability) -----------------------------------------------

func _draw() -> void:
	if data == null:
		return
	if visible and _state != State.IDLE and _state != State.WARNING:
		_draw_visual()
	if _state == State.PHASE_TRANSITION:
		# Expanding shock ring to sell the phase flip.
		var pr := clampf(_state_time / maxf(0.01, data.phase_transition_seconds), 0.0, 1.0)
		draw_arc(Vector2.ZERO, data.hit_radius * (1.0 + pr * 1.5), 0.0, TAU, 48,
			Color(1.0, 0.22, 0.95, 1.0 - pr), 6.0, true)
		return
	if _state != State.FIGHT or _current == null:
		return

	# Draw the telegraph during the TELEGRAPH beat; intensity ramps up as the
	# attack approaches so timing is legible on a small screen.
	if _beat == Beat.TELEGRAPH:
		var t := clampf(_beat_time / maxf(0.01, _current.telegraph_seconds), 0.0, 1.0)
		match _current.kind:
			BossPatternData.Kind.RADIAL_BURST:
				_draw_radial_telegraph(t)
			BossPatternData.Kind.SWEEP_LASER:
				_draw_laser_telegraph(t)
			BossPatternData.Kind.SUMMON_WAVE:
				_draw_summon_telegraph(t)
			_:
				_draw_new_telegraph(t)
	elif _beat == Beat.ACTIVE and _current.kind == BossPatternData.Kind.SWEEP_LASER:
		_draw_laser_active()
	elif _beat == Beat.ACTIVE and _current.kind == BossPatternData.Kind.BULLET_RAIN:
		# Keep the lanes faintly marked while they rain.
		_draw_rain_lanes(0.35)


func _draw_radial_telegraph(t: float) -> void:
	var danger := Palette.get_color("danger")
	danger.a = 0.35 + 0.5 * t
	# Predicted ring + soft outer halo (still below bullets via boss z).
	draw_arc(Vector2.ZERO, data.hit_radius * 2.35, 0.0, TAU, 64, Color(danger.r, danger.g, danger.b, 0.2 + 0.25 * t), 8.0, true)
	draw_arc(Vector2.ZERO, data.hit_radius * 2.2, 0.0, TAU, 64, danger, 3.5 + 3.0 * t, true)
	# Highlight the safe gaps in cyan so the corridor is obvious.
	var n: int = _current.radial_bullets
	var step := TAU / float(n)
	var safe := Palette.get_color("cyan")
	safe.a = 0.55 + 0.4 * t
	var r := data.hit_radius * 2.2
	for i in n:
		if not _gap_slots.has(i):
			continue
		var a := _pattern_spin + step * float(i)
		var p := Vector2.RIGHT.rotated(a) * r
		draw_circle(p, 12.0 + 7.0 * t, safe)
		draw_arc(p, 16.0 + 8.0 * t, 0.0, TAU, 16, Color(1, 1, 1, 0.45 + 0.35 * t), 2.0, true)


func _draw_laser_telegraph(t: float) -> void:
	var span := deg_to_rad(_current.laser_sweep_degrees)
	var start := -span * 0.5
	var reach := screen_size.y * 1.2
	var danger := Palette.get_color("danger")
	# Faint swept sector = the whole danger zone; the un-swept side is safe.
	var sector := danger
	sector.a = 0.14 + 0.16 * t
	draw_arc(Vector2.ZERO, reach * 0.5, start + PI * 0.5, start + span + PI * 0.5, 36, sector, 2.5, true)
	var steps := 10
	for i in steps + 1:
		var a := start + span * float(i) / float(steps)
		var d := Vector2.DOWN.rotated(a)
		draw_line(Vector2.ZERO, d * reach, Color(sector.r, sector.g, sector.b, sector.a * 0.55), 2.0)
	# Bright aim line where the beam will begin + tip marker.
	var beam := danger
	beam.a = 0.55 + 0.45 * t
	var start_dir := Vector2.DOWN.rotated(start)
	draw_line(Vector2.ZERO, start_dir * reach, beam, 3.5 + 3.5 * t, true)
	draw_circle(start_dir * (reach * 0.55), 8.0 + 6.0 * t, Color(1.0, 0.9, 0.4, 0.5 + 0.4 * t))


func _draw_laser_active() -> void:
	var dir := Vector2.DOWN.rotated(_laser_angle)
	var reach := screen_size.y * 1.2
	var w := _current.laser_half_width
	var core := Palette.get_color("danger")
	# Outer glow then bright core so the beam reads but a safe side stays clear.
	draw_line(Vector2.ZERO, dir * reach, Color(core.r, core.g, core.b, 0.3), w * 2.2, true)
	draw_line(Vector2.ZERO, dir * reach, Color(1.0, 0.85, 0.9, 0.95), w, true)


func _draw_summon_telegraph(t: float) -> void:
	var danger := Palette.get_color("purple")
	danger.a = 0.4 + 0.45 * t
	var count: int = _current.summon_per_wave
	var mid := float(count - 1) * 0.5
	var center_x := screen_size.x * 0.5
	var hold_y := screen_size.y * 0.36
	# Warning rings at each column where an add will drop in.
	for i in count:
		var x := center_x + (float(i) - mid) * _current.summon_spacing
		var local := to_local(Vector2(x, hold_y))
		draw_arc(local, 34.0 + 12.0 * t, 0.0, TAU, 28, danger, 3.5, true)
		draw_circle(local, 6.0 + 4.0 * t, Color(1.0, 0.85, 1.0, 0.45 + 0.4 * t))


func pool_reset() -> void:
	pass


func pool_disable() -> void:
	set_process(false)
	visible = false
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)


# --- Attacks 4-8: spiral / volley / walls / orbs / rain -------------------------

## Per-pattern setup at the start of its TELEGRAPH (positions the telegraph shows).
func _prepare_new_pattern() -> void:
	if _current == null:
		return
	match _current.kind:
		BossPatternData.Kind.WALL_GAPS:
			_wall_gap_x = _random_gap_x()
		BossPatternData.Kind.BULLET_RAIN:
			_rain_x.resize(_current.rain_columns)
			var lane := screen_size.x / float(_current.rain_columns + 1)
			for i in _current.rain_columns:
				_rain_x[i] = lane * float(i + 1) + randf_range(-lane * 0.3, lane * 0.3)


func _random_gap_x() -> float:
	var half := _current.wall_gap_width * 0.5
	return randf_range(half + 60.0, screen_size.x - half - 60.0)


func _falling_projectile() -> ProjectileData:
	return _current.falling_projectile if _current.falling_projectile != null else _current.radial_projectile


## Fires `total` evenly spaced shots of the current pattern across the active window.
func _update_spaced(delta: float, total: int) -> void:
	if _shots_done >= total:
		return
	_shot_timer -= delta
	if _shot_timer > 0.0:
		return
	_shot_timer += _current.active_seconds / float(maxi(1, total))
	match _current.kind:
		BossPatternData.Kind.AIMED_VOLLEY:
			_fire_volley()
		BossPatternData.Kind.WALL_GAPS:
			_fire_wall()
		BossPatternData.Kind.HOMING_ORBS:
			_fire_orbs()
		BossPatternData.Kind.BULLET_RAIN:
			_fire_rain_row()
	_shots_done += 1


func _update_spiral(delta: float) -> void:
	if enemy_projectile_pool == null or _current.radial_projectile == null:
		return
	_shot_timer -= delta
	var interval := 1.0 / maxf(0.5, _current.spiral_rate)
	while _shot_timer <= 0.0:
		_shot_timer += interval
		_spiral_angle += deg_to_rad(_current.spiral_turn_degrees)
		for arm in _current.spiral_arms:
			var dir := Vector2.DOWN.rotated(_spiral_angle + TAU * float(arm) / float(_current.spiral_arms))
			enemy_projectile_pool.spawn(global_position, dir, _current.radial_projectile)


func _fire_volley() -> void:
	if enemy_projectile_pool == null or _current.radial_projectile == null or player == null:
		return
	var aim := (player.global_position - global_position).normalized()
	var n := _current.volley_bullets
	var spread := _current.volley_spread_degrees
	for i in n:
		var a := 0.0 if n <= 1 else -spread * 0.5 + spread * float(i) / float(n - 1)
		enemy_projectile_pool.spawn(global_position, aim.rotated(deg_to_rad(a)), _current.radial_projectile)


## A horizontal wall of bullets falling from the top with one gap; each new
## wall's gap shifts so the safe lane keeps moving (shown by the telegraph and
## by the empty lane itself).
func _fire_wall() -> void:
	var proj := _falling_projectile()
	if enemy_projectile_pool == null or proj == null:
		return
	if _shots_done > 0:
		_wall_gap_x = clampf(_wall_gap_x + randf_range(-260.0, 260.0),
			_current.wall_gap_width * 0.5 + 60.0, screen_size.x - _current.wall_gap_width * 0.5 - 60.0)
	var half := _current.wall_gap_width * 0.5
	var x := _current.wall_spacing * 0.5
	while x < screen_size.x:
		if absf(x - _wall_gap_x) > half:
			enemy_projectile_pool.spawn(Vector2(x, -40.0), Vector2.DOWN, proj)
		x += _current.wall_spacing


func _fire_orbs() -> void:
	var proj := _falling_projectile()
	if enemy_projectile_pool == null or proj == null:
		return
	var n := _current.orb_count
	for i in n:
		var dir := Vector2.DOWN.rotated(deg_to_rad(-70.0 + 140.0 * float(i) / float(maxi(1, n - 1))))
		enemy_projectile_pool.spawn(global_position + dir * data.hit_radius * 0.6, dir, proj)


func _fire_rain_row() -> void:
	var proj := _falling_projectile()
	if enemy_projectile_pool == null or proj == null:
		return
	for x in _rain_x:
		enemy_projectile_pool.spawn(Vector2(x, -40.0), Vector2.DOWN, proj)


# --- New telegraphs ----------------------------------------------------------------

func _draw_new_telegraph(t: float) -> void:
	var danger := Palette.get_color("danger")
	match _current.kind:
		BossPatternData.Kind.SPIRAL_STREAM:
			var arms := _current.spiral_arms
			for arm in arms:
				var dir := Vector2.DOWN.rotated(_spiral_angle + TAU * float(arm) / float(arms) + t * 0.6)
				draw_line(dir * data.hit_radius, dir * data.hit_radius * (1.6 + 1.2 * t), Color(danger, 0.4 + 0.5 * t), 5.0, true)
			draw_arc(Vector2.ZERO, data.hit_radius * 1.9, 0.0, TAU, 48, Color(danger, 0.25 + 0.4 * t), 3.0, true)
		BossPatternData.Kind.AIMED_VOLLEY:
			if player != null:
				var aim := to_local(player.global_position).normalized()
				var half := deg_to_rad(_current.volley_spread_degrees * 0.5)
				for a in [-half, 0.0, half]:
					var d := aim.rotated(a)
					draw_line(d * data.hit_radius, d * data.hit_radius * 3.2, Color(danger, 0.35 + 0.55 * t), 4.0, true)
		BossPatternData.Kind.WALL_GAPS:
			# Danger band across the top with the safe gap in cyan.
			var y := to_local(Vector2(0.0, 60.0)).y
			var left := to_local(Vector2(0.0, 0.0)).x
			var right := to_local(Vector2(screen_size.x, 0.0)).x
			var gap := to_local(Vector2(_wall_gap_x, 0.0)).x
			var half_gap := _current.wall_gap_width * 0.5
			var band := Color(danger, 0.3 + 0.5 * t)
			draw_line(Vector2(left, y), Vector2(gap - half_gap, y), band, 14.0)
			draw_line(Vector2(gap + half_gap, y), Vector2(right, y), band, 14.0)
			var safe := Palette.get_color("cyan")
			draw_line(Vector2(gap - half_gap, y), Vector2(gap + half_gap, y), Color(safe, 0.6 + 0.3 * t), 6.0)
		BossPatternData.Kind.HOMING_ORBS:
			var n := _current.orb_count
			for i in n:
				var dir := Vector2.DOWN.rotated(deg_to_rad(-70.0 + 140.0 * float(i) / float(maxi(1, n - 1))))
				draw_circle(dir * data.hit_radius * 0.9, 10.0 + 10.0 * t, Color(1.0, 0.5, 0.9, 0.4 + 0.5 * t))
		BossPatternData.Kind.BULLET_RAIN:
			_draw_rain_lanes(0.3 + 0.6 * t)


func _draw_rain_lanes(alpha: float) -> void:
	var danger := Palette.get_color("danger")
	var top := to_local(Vector2(0.0, 0.0)).y
	var bottom := to_local(Vector2(0.0, screen_size.y)).y
	for x in _rain_x:
		var lx := to_local(Vector2(x, 0.0)).x
		var y := top
		while y < bottom:
			draw_line(Vector2(lx, y), Vector2(lx, y + 40.0), Color(danger, alpha), 6.0)
			y += 80.0


# --- Procedural boss visuals ---------------------------------------------------------

func _draw_visual() -> void:
	match data.visual:
		BossData.Visual.HYDRA:
			_draw_hydra()
		BossData.Visual.LEVIATHAN:
			_draw_leviathan()
		BossData.Visual.OVERMIND:
			_draw_overmind()


func _draw_hydra() -> void:
	var r := data.hit_radius
	var c := data.tint
	for i in 3:
		var side := float(i) - 1.0
		var sway := sin(_fight_time * 1.6 + float(i) * 1.3) * 0.18
		var dir := Vector2.DOWN.rotated(side * 0.75 + sway)
		var head := dir * r * 1.25
		draw_line(Vector2.ZERO, head, Color(c, 0.35), 34.0, true)
		draw_line(Vector2.ZERO, head, Color(0.12, 0.05, 0.03, 0.95), 22.0, true)
		var hs := 40.0
		var pts := PackedVector2Array([head + dir * hs, head + dir.orthogonal() * hs * 0.7,
			head - dir * hs * 0.5, head - dir.orthogonal() * hs * 0.7, head + dir * hs])
		draw_colored_polygon(pts, Color(0.18, 0.06, 0.02, 0.98))
		draw_polyline(pts, c, 4.0, true)
		var eye := 0.6 + 0.4 * sin(_fight_time * 6.0 + float(i))
		draw_circle(head + dir * hs * 0.2, 9.0, Color(1.0, 0.85, 0.3, eye))


func _draw_leviathan() -> void:
	if _tail.size() != _TAIL_LEN:
		return
	var c := data.tint
	var r := data.hit_radius
	for i in range(_TAIL_LEN - 1, 0, -1):
		var p := to_local(_tail[i]) + Vector2(0.0, -float(i) * 18.0)
		var s := r * (0.62 - 0.035 * float(i))
		draw_circle(p, s, Color(0.03, 0.1, 0.12, 0.95))
		draw_arc(p, s, 0.0, TAU, 24, Color(c, 0.85), 4.0, true)
		draw_circle(p, s * 0.25, Color(c, 0.5))


func _draw_overmind() -> void:
	var r := data.hit_radius
	var c := data.tint
	# Rotating armor plates.
	for i in 6:
		var a := _fight_time * 0.5 + TAU * float(i) / 6.0
		var p := Vector2.RIGHT.rotated(a) * r * 1.05
		var d := Vector2.RIGHT.rotated(a)
		var plate := PackedVector2Array([p + d * 26.0, p + d.orthogonal() * 34.0, p - d * 18.0, p - d.orthogonal() * 34.0])
		draw_colored_polygon(plate, Color(0.06, 0.04, 0.12, 0.97))
		plate.append(plate[0])
		draw_polyline(plate, c, 3.5, true)
	# The eye: sclera, iris tracking the player, slit pupil.
	draw_circle(Vector2.ZERO, r * 0.82, Color(0.08, 0.02, 0.1, 0.98))
	draw_arc(Vector2.ZERO, r * 0.82, 0.0, TAU, 64, Color(c, 0.9), 6.0, true)
	var look := Vector2.ZERO
	if player != null:
		look = to_local(player.global_position).normalized() * r * 0.22
	var iris := Color(1.0, 0.25, 0.45, 1.0).lerp(Color.WHITE, _flash * 0.6)
	draw_circle(look, r * 0.42, Color(iris, 0.35))
	draw_circle(look, r * 0.32, iris)
	draw_line(look + Vector2(0, -r * 0.26), look + Vector2(0, r * 0.26), Color(0.02, 0.0, 0.03), 12.0, true)
