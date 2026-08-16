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
	if _shape != null and _shape.shape is CircleShape2D:
		(_shape.shape as CircleShape2D).radius = data.hit_radius

	_enter_state(State.WARNING)
	set_process(true)
	health_changed.emit(_health, _max_health())
	warning_started.emit(data.display_name)
	AudioManager.play_sfx("boss_warning", Vector2.ZERO, AudioManager.PRIORITY_HIGH)
	var haptics: HapticsService = PlatformServices.haptics
	if haptics != null:
		haptics.heavy()


func get_health() -> float:
	return _health


func get_health_fraction() -> float:
	var maxhp := _max_health()
	return 0.0 if maxhp <= 0.0 else _health / maxhp


## Per-run HP scaling (difficulty). Applied at begin(); never mutates BossData.
func set_scaling(hp_mult: float) -> void:
	_hp_mult = maxf(0.1, hp_mult)


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
			global_position = _hold_pos
			_update_fight(delta)
		State.PHASE_TRANSITION:
			global_position = _hold_pos
			# Brief invulnerable, dramatic beat before phase-2 patterns start.
			if _state_time >= 1.1:
				_begin_fight(2)
		State.DEFEATED:
			_update_defeated(delta)

	queue_redraw()


# --- Fight loop -------------------------------------------------------------

func _begin_fight(phase: int) -> void:
	_phase = phase
	_patterns = data.phase2_patterns if phase == 2 else data.phase1_patterns
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
	var gap_slots := _gap_slot_set(n)
	var step := TAU / float(n)
	for i in n:
		if gap_slots.has(i):
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
			player.call("take_damage", _current.laser_damage)


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
		# `died` fires only on a real kill (not exit-recycle); re-broadcast it so
		# the run host can tally enemies destroyed.
		if not enemy.died.is_connected(_on_summoned_died):
			enemy.died.connect(_on_summoned_died)
		enemy.spawn(_current.summon_enemy, enter_from, hold, exit_to, 1.0, 3.0, 1.8)
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
	GameFeel.projectile_hit(global_position, amount, false)

	if _health <= 0.0:
		_enter_defeated()
	elif _phase == 1 and get_health_fraction() <= data.phase2_threshold:
		_enter_phase_transition()


func _enter_phase_transition() -> void:
	_enter_state(State.PHASE_TRANSITION)
	_current = null
	_laser_hot = false
	_flash = 1.0
	_apply_tint()
	phase_changed.emit(2)
	GameFeel.enemy_death(global_position, true)
	GameFeel.request_hitstop(0.08)
	AudioManager.play_sfx("boss_phase", Vector2.ZERO, AudioManager.PRIORITY_HIGH)
	var haptics: HapticsService = PlatformServices.haptics
	if haptics != null:
		haptics.heavy()


func _enter_defeated() -> void:
	_enter_state(State.DEFEATED)
	_current = null
	_laser_hot = false
	# Deferred: defeat is triggered from take_damage, which runs inside the
	# player bolt's area_entered signal where toggling monitoring is blocked.
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	# Clear any summoned adds so the arena is clean for the victory beat.
	_clear_summoned()
	GameFeel.enemy_death(global_position, true)
	GameFeel.request_hitstop(0.12)
	AudioManager.play_sfx("boss_defeated", Vector2.ZERO, AudioManager.PRIORITY_HIGH)
	var haptics: HapticsService = PlatformServices.haptics
	if haptics != null:
		haptics.heavy()


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
		player.call("take_damage", data.contact_damage)


func _apply_tint() -> void:
	if _sprite == null:
		return
	# Phase 2 runs a hotter base tint; hit flash blends toward white.
	var base := Color(1.1, 0.85, 1.1, 1.0) if _phase >= 2 else Color.WHITE
	_sprite.modulate = base.lerp(Color(2.0, 2.0, 2.0, 1.0), _flash)


func _enter_state(next: int) -> void:
	_state = next
	_state_time = 0.0


# --- Telegraphs (readability) -----------------------------------------------

func _draw() -> void:
	if data == null:
		return
	if _state == State.PHASE_TRANSITION:
		# Expanding shock ring to sell the phase flip.
		var pr := clampf(_state_time / 1.1, 0.0, 1.0)
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
	elif _beat == Beat.ACTIVE and _current.kind == BossPatternData.Kind.SWEEP_LASER:
		_draw_laser_active()


func _draw_radial_telegraph(t: float) -> void:
	var danger := Palette.get_color("danger")
	danger.a = 0.35 + 0.5 * t
	# Predicted ring + soft outer halo (still below bullets via boss z).
	draw_arc(Vector2.ZERO, data.hit_radius * 2.35, 0.0, TAU, 64, Color(danger.r, danger.g, danger.b, 0.2 + 0.25 * t), 8.0, true)
	draw_arc(Vector2.ZERO, data.hit_radius * 2.2, 0.0, TAU, 64, danger, 3.5 + 3.0 * t, true)
	# Highlight the safe gaps in cyan so the corridor is obvious.
	var n: int = _current.radial_bullets
	var gap_slots := _gap_slot_set(n)
	var step := TAU / float(n)
	var safe := Palette.get_color("cyan")
	safe.a = 0.55 + 0.4 * t
	var r := data.hit_radius * 2.2
	for i in n:
		if not gap_slots.has(i):
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
