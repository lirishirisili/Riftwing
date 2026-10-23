extends Node
## Central game-feel facade (autoload).
##
## Gameplay code calls intent methods here (hits, deaths, fire, shield, pickup,
## ability, boss kill, level-up, streaks, the Rift Nova) and this router fans
## them out to the pooled effects layer, the camera rig (shake + zoom punch),
## the full-screen ScreenFX layer (flash, aberration, shockwave, danger
## vignette), the HapticsService, and the AudioManager. It also owns the effect
## quality level and the single time-scale controller (hit-stop + slow-motion).
##
## This layer is purely feedback: it never changes damage, health, spawns, or any
## balance value. Every route is guarded so scenes that register no effects layer
## or camera (e.g. the projectile stress test) simply no-op.

## Effect richness budget. Lower levels shrink particle counts / trail length and
## disable non-essential flourishes, without touching gameplay logic.
enum Quality { LOW, MEDIUM, HIGH }

## Hit-stop is clamped to the spec's 30-60 ms window for strong attacks.
const HITSTOP_MIN_SECONDS := 0.03
const HITSTOP_MAX_SECONDS := 0.06
## Time scale held during a hit-stop (near-freeze, not full, so audio/anim breathe).
const HITSTOP_TIME_SCALE := 0.05
## Last fraction of a slow-motion window spent easing back to full speed.
const _SLOWMO_EASE_OUT := 0.35

## Minimum real-time spacing between haptic pulses of each strength, so a
## stream of bolt impacts never turns into a continuous buzz.
const _HAPTIC_SPACING_MS := {"light": 70, "medium": 110, "heavy": 160}

const _QUALITY_CFG := "user://effects_quality.cfg"
const _HAPTICS_CFG := "user://haptics_enabled.cfg"

## Default HIGH for desktop feel; settings can persist LOW for mid-range devices.
var quality: int = Quality.HIGH
## Player preference; when false, haptic hooks no-op even if the service exists.
var haptics_enabled: bool = true
## Set by DebugOverlay when F3 / three-finger debug is active (milestone 15).
var debug_markers_enabled: bool = false

# Registered feedback sinks (cleared on scene teardown).
var _effects: Node = null
var _camera: Node = null
var _screen_fx: Node = null

# Time-scale bookkeeping, measured in real (unscaled) time so a scaled delta can
# never leave the game frozen.
var _hitstop_until_ms: int = 0
var _hitstop_active: bool = false
var _slowmo_scale: float = 1.0
var _slowmo_start_ms: int = 0
var _slowmo_until_ms: int = 0
var _haptic_last_ms: Dictionary = {"light": 0, "medium": 0, "heavy": 0}

# Debug counters so the harness can prove each system fired.
var counters := {
	"hit_flash": 0,
	"explosion_small": 0,
	"explosion_large": 0,
	"damage_number": 0,
	"crit": 0,
	"shake": 0,
	"hitstop": 0,
	"slowmo": 0,
	"haptic": 0,
	"muzzle": 0,
	"shield": 0,
	"pickup": 0,
	"ability": 0,
	"upgrade": 0,
	"combo": 0,
	"streak": 0,
	"level_up": 0,
	"boss_kill": 0,
	"nova": 0,
	"screen_flash": 0,
	"shockwave": 0,
}


func _ready() -> void:
	# Autoload must keep processing while the tree is paused so a pause menu can
	# still animate; hit-stop uses real time, not the pause state.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_prefs()


func _process(_delta: float) -> void:
	_update_time_scale()


# --- Registration ------------------------------------------------------------

## The active scene's EffectsLayer registers here so effects route to its pools.
func register_effects_layer(layer: Node) -> void:
	_effects = layer


func register_camera(camera: Node) -> void:
	_camera = camera


## The run's full-screen post layer (flash / aberration / shockwave / vignette).
func register_screen_fx(fx: Node) -> void:
	_screen_fx = fx


## Scenes call this on teardown so stale references never linger between screens.
func clear_sinks() -> void:
	_effects = null
	_camera = null
	_screen_fx = null
	_hitstop_active = false
	_hitstop_until_ms = 0
	_slowmo_until_ms = 0
	_slowmo_scale = 1.0
	Engine.time_scale = 1.0


# --- Quality -----------------------------------------------------------------

func set_quality(level: int) -> void:
	quality = clampi(level, Quality.LOW, Quality.HIGH)
	_save_prefs()
	_notify_glow()


func cycle_quality() -> void:
	quality = (quality + 1) % 3
	_save_prefs()
	_notify_glow()


func _notify_glow() -> void:
	get_tree().call_group("glow_controller", "apply_from_game_feel")


func set_haptics_enabled(enabled: bool) -> void:
	haptics_enabled = enabled
	_save_prefs()


func quality_name() -> String:
	match quality:
		Quality.LOW: return "LOW"
		Quality.MEDIUM: return "MEDIUM"
		_: return "HIGH"


func _load_prefs() -> void:
	if FileAccess.file_exists(_QUALITY_CFG):
		var qf := FileAccess.open(_QUALITY_CFG, FileAccess.READ)
		if qf != null:
			quality = clampi(int(qf.get_line().strip_edges()), Quality.LOW, Quality.HIGH)
	if FileAccess.file_exists(_HAPTICS_CFG):
		var hf := FileAccess.open(_HAPTICS_CFG, FileAccess.READ)
		if hf != null:
			haptics_enabled = hf.get_line().strip_edges() != "0"


func _save_prefs() -> void:
	AtomicFile.write_text(_QUALITY_CFG, str(quality))
	AtomicFile.write_text(_HAPTICS_CFG, "1" if haptics_enabled else "0")


## Particle count budget for an explosion by current quality.
func explosion_particles(is_major: bool) -> int:
	var base := 26 if is_major else 12
	match quality:
		Quality.LOW: return 0
		Quality.MEDIUM: return base / 2
		_: return base


## Debris shard count for an explosion by current quality.
func explosion_debris(is_major: bool) -> int:
	match quality:
		Quality.LOW: return 0
		Quality.MEDIUM: return 4 if is_major else 2
		_: return 8 if is_major else 4


## Spark count for a projectile impact by current quality.
func hit_spark_particles() -> int:
	match quality:
		Quality.LOW: return 0
		Quality.MEDIUM: return 4
		_: return 8


## Projectile trail length (segments); 0 disables the trail entirely.
func trail_length() -> int:
	match quality:
		Quality.LOW: return 0
		Quality.MEDIUM: return 5
		_: return 9


## Whether floating damage numbers are shown at all.
func damage_numbers_enabled() -> bool:
	return quality != Quality.LOW


## Screen-shake scale (LOW disables shake, MEDIUM softens it).
func shake_scale() -> float:
	match quality:
		Quality.LOW: return 0.0
		Quality.MEDIUM: return 0.6
		_: return 1.0


# --- Intent API (called by gameplay) ----------------------------------------

## A projectile struck a target. `to_player` distinguishes an enemy bolt hitting
## the player from a player bolt hitting an enemy (colors the feedback). Crits
## get a gold flash, a bigger number, and a bright ping.
func projectile_hit(world_pos: Vector2, damage: float, to_player: bool, is_crit: bool = false) -> void:
	var color := Palette.get_color("danger") if to_player else Palette.get_color("orange")
	if is_crit and not to_player:
		color = Palette.get_color("gold", Color(1.0, 0.84, 0.25))
	if _effects != null:
		_effects.spawn_hit_flash(world_pos, color)
		counters["hit_flash"] += 1
		if damage_numbers_enabled() and not to_player:
			_effects.spawn_damage_number(world_pos, int(round(damage)), is_crit)
			counters["damage_number"] += 1
	if is_crit and not to_player:
		counters["crit"] += 1
		_add_trauma(0.16)
		AudioManager.play_sfx("crit", world_pos, AudioManager.PRIORITY_LOW)
	else:
		_add_trauma(0.12)
		AudioManager.play_sfx("hit", world_pos, AudioManager.PRIORITY_LOW)
	_haptic("light")


## Secondary-weapon damage (chain arcs, beams, blasts, drones): a damage number
## and a small flash only. No shake / haptic / per-hit SFX so area weapons that
## touch many targets stay calm.
func area_hit(world_pos: Vector2, damage: float) -> void:
	if _effects == null:
		return
	if quality == Quality.HIGH:
		_effects.spawn_hit_flash(world_pos, Palette.get_color("orange"))
		counters["hit_flash"] += 1
	if damage_numbers_enabled():
		_effects.spawn_damage_number(world_pos, int(round(damage)), false)
		counters["damage_number"] += 1


## Area blast ring (missile / bomb / vortex detonation).
func blast(world_pos: Vector2, radius: float, color: Color) -> void:
	if _effects != null:
		_effects.spawn_burst(world_pos, color, radius, 0.35)
	_add_trauma(0.1 + minf(radius, 300.0) / 1500.0)
	AudioManager.play_sfx("explosion_small", world_pos, AudioManager.PRIORITY_LOW)


## Chain-lightning arc through `points` (ship -> first target -> jumps).
func lightning(points: PackedVector2Array, color: Color) -> void:
	if _effects != null and points.size() >= 2:
		_effects.spawn_lightning(points, color)
	AudioManager.play_sfx_pitched("crit", 0.6, AudioManager.PRIORITY_LOW)


## An enemy died. `is_major` (tough enemies) gets a large explosion + hit-stop.
func enemy_death(world_pos: Vector2, is_major: bool) -> void:
	if _effects != null:
		_effects.spawn_explosion(world_pos, is_major)
		if is_major:
			counters["explosion_large"] += 1
		else:
			counters["explosion_small"] += 1
	if is_major:
		_add_trauma(0.55)
		request_hitstop(HITSTOP_MAX_SECONDS)
		_haptic("heavy")
		AudioManager.play_sfx("explosion_large", world_pos, AudioManager.PRIORITY_HIGH)
	else:
		_add_trauma(0.28)
		_haptic("medium")
		AudioManager.play_sfx("explosion_small", world_pos, AudioManager.PRIORITY_MEDIUM)


## An elite / chest carrier died: bigger blast, ripple, gold flash.
func elite_death(world_pos: Vector2) -> void:
	enemy_death(world_pos, true)
	if _effects != null:
		_effects.spawn_burst(world_pos, Palette.get_color("gold", Color(1.0, 0.84, 0.25)), 220.0, 0.6)
	_shockwave(world_pos, 0.55, 0.02)
	_flash(Palette.get_color("gold", Color(1.0, 0.84, 0.25)), 0.12, 0.18)


## The player took damage.
func player_hit(world_pos: Vector2) -> void:
	if _effects != null:
		_effects.spawn_hit_flash(world_pos, Palette.get_color("danger"))
		counters["hit_flash"] += 1
	_add_trauma(0.55)
	request_hitstop(HITSTOP_MIN_SECONDS)
	_haptic("heavy")
	_flash(Palette.get_color("danger", Color(1.0, 0.2, 0.25)), 0.22, 0.22)
	_aberrate(0.008, 0.3)
	AudioManager.play_sfx("player_hit", world_pos)


## The player ship was destroyed: slow-motion, big blast, red wash.
func player_death(world_pos: Vector2) -> void:
	if _effects != null:
		_effects.spawn_explosion(world_pos, true)
		_effects.spawn_burst(world_pos, Palette.get_color("cyan", Color(0.2, 0.95, 1.0)), 300.0, 0.9)
		counters["explosion_large"] += 1
	_add_trauma(0.9)
	request_slowmo(0.25, 0.9)
	_flash(Palette.get_color("danger", Color(1.0, 0.2, 0.25)), 0.35, 0.6)
	_aberrate(0.014, 0.8)
	_shockwave(world_pos, 0.8, 0.03)
	_haptic("heavy")
	AudioManager.play_sfx("explosion_large", world_pos, AudioManager.PRIORITY_HIGH)
	AudioManager.play_sfx("slowmo", world_pos, AudioManager.PRIORITY_HIGH)


## Player weapon volley. Muzzle flash only — continuous fire uses AudioManager
## fire loop (shmup sustain), not a one-shot per volley.
func weapon_fire(world_pos: Vector2) -> void:
	if _effects != null:
		_effects.spawn_muzzle_flash(world_pos, Palette.get_color("cyan", Color(0.2, 0.95, 1.0)))
		counters["muzzle"] += 1


## Invulnerability / shield absorbed a hit (no HP loss).
func shield_impact(world_pos: Vector2) -> void:
	if _effects != null:
		_effects.spawn_shield_burst(world_pos, Palette.get_color("cyan", Color(0.2, 0.95, 1.0)))
		counters["shield"] += 1
	_add_trauma(0.14)
	_haptic("light")
	AudioManager.play_sfx("shield_impact", world_pos)


## Energy pickup collected. `streak` (consecutive pickups) raises the chime's
## pitch so a vacuum of gems sings upward.
func pickup_collected(world_pos: Vector2, streak: int = 0) -> void:
	if _effects != null and quality != Quality.LOW:
		_effects.spawn_hit_flash(world_pos, Palette.get_color("green", Color(0.25, 0.95, 0.55)))
		counters["pickup"] += 1
	_haptic("light")
	var pitch := 1.0 + minf(float(maxi(0, streak)), 16.0) * 0.045
	AudioManager.play_sfx_pitched("pickup", pitch, AudioManager.PRIORITY_MEDIUM)


## Ability button feedback (presentation only — no combat resolution).
func ability_activated(world_pos: Vector2, tint: Color) -> void:
	if _effects != null:
		_effects.spawn_shield_burst(world_pos, tint)
		counters["ability"] += 1
	_add_trauma(0.2)
	_haptic("medium")
	AudioManager.play_sfx("ability", world_pos)


## Post-upgrade power-fantasy beat: short halo + muzzle so the pick "lands".
func upgrade_applied(world_pos: Vector2, tint: Color = Color(0.2, 0.95, 1.0)) -> void:
	if _effects != null:
		_effects.spawn_shield_burst(world_pos, tint)
		_effects.spawn_muzzle_flash(world_pos + Vector2(0, -36), tint)
		_effects.spawn_burst(world_pos, tint, 170.0, 0.45)
		counters["upgrade"] += 1
	_add_trauma(0.22)
	_haptic("medium")
	AudioManager.play_sfx("upgrade_select", world_pos, AudioManager.PRIORITY_MEDIUM)


## Level reached: radial burst around the ship + rising chime, right before the
## card screen opens.
func level_up(world_pos: Vector2) -> void:
	if _effects != null:
		var tint := Palette.get_color("purple", Color(0.7, 0.35, 1.0))
		_effects.spawn_burst(world_pos, tint, 260.0, 0.5)
		_effects.spawn_shield_burst(world_pos, tint)
	counters["level_up"] += 1
	_flash(Palette.get_color("purple", Color(0.7, 0.35, 1.0)), 0.1, 0.25)
	_haptic("medium")
	AudioManager.play_sfx("level_up", world_pos, AudioManager.PRIORITY_HIGH)


## Combo milestone juice (presentation only — does not change kill scoring).
func combo_peak(world_pos: Vector2, combo: int) -> void:
	if combo < 5:
		return
	if _effects != null and quality != Quality.LOW:
		var tint := Palette.get_color("orange", Color(1, 0.55, 0.15))
		if combo >= 15:
			tint = Palette.get_color("gold", Color(1, 0.84, 0.25))
		elif combo >= 10:
			tint = Palette.get_color("purple", Color(0.7, 0.35, 1.0))
		_effects.spawn_hit_flash(world_pos, tint)
		counters["combo"] += 1
	if combo >= 10:
		_add_trauma(0.18)
		_haptic("medium")
	else:
		_haptic("light")
	AudioManager.play_sfx("pickup", world_pos, AudioManager.PRIORITY_LOW)


## Kill-streak callout tier reached (the HUD shows the text).
func streak(world_pos: Vector2, tier: int) -> void:
	counters["streak"] += 1
	if _effects != null:
		_effects.spawn_burst(world_pos, Palette.get_color("gold", Color(1.0, 0.84, 0.25)), 140.0 + 40.0 * tier, 0.4)
	_add_trauma(0.2 + 0.05 * tier)
	_haptic("medium")
	AudioManager.play_sfx_pitched("streak", 1.0 + 0.08 * float(tier), AudioManager.PRIORITY_MEDIUM)


## Boss phase flip: ripple + channel split on top of the boss's own beat.
func boss_phase(world_pos: Vector2) -> void:
	_shockwave(world_pos, 0.7, 0.03)
	_aberrate(0.01, 0.5)
	_flash(Palette.get_color("magenta", Color(1.0, 0.22, 0.55)), 0.14, 0.25)


## Boss destroyed: the headline beat — slow-motion, zoom punch, shockwave,
## white flash, aberration, heavy haptic.
func boss_killed(world_pos: Vector2) -> void:
	counters["boss_kill"] += 1
	if _effects != null:
		_effects.spawn_burst(world_pos, Color(1, 1, 1), 420.0, 0.9)
		_effects.spawn_burst(world_pos, Palette.get_color("magenta", Color(1.0, 0.22, 0.55)), 320.0, 1.1)
	request_slowmo(0.2, 1.15)
	_add_trauma(1.0)
	_zoom_punch(0.08, 0.9)
	_shockwave(world_pos, 1.0, 0.045)
	_flash(Color(1, 1, 1), 0.3, 0.45)
	_aberrate(0.016, 1.0)
	_haptic("heavy")
	AudioManager.play_sfx("slowmo", world_pos, AudioManager.PRIORITY_HIGH)


## Rift Nova detonation (screen-clear ultimate).
func nova(world_pos: Vector2) -> void:
	counters["nova"] += 1
	if _effects != null:
		_effects.spawn_burst(world_pos, Palette.get_color("cyan", Color(0.2, 0.95, 1.0)), 900.0, 0.8)
		_effects.spawn_burst(world_pos, Color(1, 1, 1), 520.0, 0.5)
	request_slowmo(0.35, 0.45)
	_add_trauma(0.85)
	_zoom_punch(0.05, 0.5)
	_shockwave(world_pos, 0.8, 0.05)
	_flash(Palette.get_color("cyan", Color(0.2, 0.95, 1.0)), 0.32, 0.35)
	_aberrate(0.012, 0.6)
	_haptic("heavy")
	AudioManager.play_sfx("nova_blast", world_pos, AudioManager.PRIORITY_HIGH)


## The Rift Nova finished charging.
func nova_ready(world_pos: Vector2) -> void:
	if _effects != null:
		_effects.spawn_shield_burst(world_pos, Palette.get_color("cyan", Color(0.2, 0.95, 1.0)))
	_haptic("medium")
	AudioManager.play_sfx("nova_ready", world_pos, AudioManager.PRIORITY_MEDIUM)


## Generic celebratory beats used by pickups / chests / evolutions / revive.
func heal(world_pos: Vector2) -> void:
	if _effects != null:
		_effects.spawn_burst(world_pos, Palette.get_color("green", Color(0.25, 0.95, 0.55)), 150.0, 0.45)
	_haptic("light")
	AudioManager.play_sfx("heal", world_pos, AudioManager.PRIORITY_MEDIUM)


func chest_open(world_pos: Vector2) -> void:
	if _effects != null:
		_effects.spawn_burst(world_pos, Palette.get_color("gold", Color(1.0, 0.84, 0.25)), 240.0, 0.6)
	_flash(Palette.get_color("gold", Color(1.0, 0.84, 0.25)), 0.16, 0.3)
	_haptic("medium")
	AudioManager.play_sfx("chest_open", world_pos, AudioManager.PRIORITY_HIGH)


func evolve(world_pos: Vector2) -> void:
	if _effects != null:
		_effects.spawn_burst(world_pos, Palette.get_color("gold", Color(1.0, 0.84, 0.25)), 380.0, 0.8)
		_effects.spawn_burst(world_pos, Color(1, 1, 1), 200.0, 0.5)
	_shockwave(world_pos, 0.7, 0.03)
	_flash(Color(1, 1, 1), 0.25, 0.35)
	_haptic("heavy")
	AudioManager.play_sfx("evolve", world_pos, AudioManager.PRIORITY_HIGH)


func revive(world_pos: Vector2) -> void:
	if _effects != null:
		_effects.spawn_burst(world_pos, Palette.get_color("cyan", Color(0.2, 0.95, 1.0)), 600.0, 0.8)
	_shockwave(world_pos, 0.8, 0.04)
	_flash(Palette.get_color("cyan", Color(0.2, 0.95, 1.0)), 0.3, 0.4)
	_haptic("heavy")
	AudioManager.play_sfx("revive", world_pos, AudioManager.PRIORITY_HIGH)


func elite_spawn(world_pos: Vector2) -> void:
	if _effects != null:
		_effects.spawn_burst(world_pos, Palette.get_color("gold", Color(1.0, 0.84, 0.25)), 160.0, 0.5)
	AudioManager.play_sfx("elite_spawn", world_pos, AudioManager.PRIORITY_MEDIUM)


## Public haptic pulse ("light" / "medium" / "heavy") for UI and gameplay
## code. Honors the player setting and the per-strength rate limit.
func haptic(kind: String) -> void:
	_haptic(kind)


## Persistent low-HP vignette (0 = off).
func set_danger(level: float) -> void:
	if _screen_fx != null:
		_screen_fx.set_danger(level)


# --- Screen-space helpers ------------------------------------------------------

func _flash(color: Color, alpha: float, seconds: float) -> void:
	if _screen_fx == null:
		return
	# LOW keeps flashes (cheap overlay) but softer.
	var a := alpha * (0.6 if quality == Quality.LOW else 1.0)
	_screen_fx.flash(color, a, seconds)
	counters["screen_flash"] += 1


func _aberrate(amount: float, seconds: float) -> void:
	if _screen_fx != null:
		_screen_fx.aberrate(amount, seconds)


func _shockwave(world_pos: Vector2, seconds: float, strength: float) -> void:
	if _screen_fx != null:
		_screen_fx.shockwave(world_pos, seconds, strength)
		counters["shockwave"] += 1


func _zoom_punch(amount: float, seconds: float) -> void:
	if _camera != null and _camera.has_method("zoom_punch") and quality != Quality.LOW:
		_camera.zoom_punch(amount, seconds)


# --- Screen shake ------------------------------------------------------------

func _add_trauma(amount: float) -> void:
	var scaled := amount * shake_scale()
	if scaled <= 0.0 or _camera == null:
		return
	_camera.add_trauma(scaled)
	counters["shake"] += 1


# --- Time scale (hit-stop + slow-motion) --------------------------------------

## Briefly slows time. Duration is clamped to the readable 30-60 ms window and
## measured in real time; requests never stack the freeze deeper, only extend it.
func request_hitstop(seconds: float) -> void:
	var dur := clampf(seconds, HITSTOP_MIN_SECONDS, HITSTOP_MAX_SECONDS)
	var until := Time.get_ticks_msec() + int(dur * 1000.0)
	_hitstop_until_ms = maxi(_hitstop_until_ms, until)
	if not _hitstop_active:
		_hitstop_active = true
		counters["hitstop"] += 1
	_update_time_scale()


## Slow-motion for a real-time window; eases back to full speed at the end.
## A deeper request wins; a longer one extends the window.
func request_slowmo(scale: float, real_seconds: float) -> void:
	var now := Time.get_ticks_msec()
	var s := clampf(scale, 0.05, 1.0)
	if now >= _slowmo_until_ms:
		_slowmo_scale = s
		_slowmo_start_ms = now
	else:
		_slowmo_scale = minf(_slowmo_scale, s)
	_slowmo_until_ms = maxi(_slowmo_until_ms, now + int(maxf(0.0, real_seconds) * 1000.0))
	counters["slowmo"] += 1
	_update_time_scale()


func is_slowmo_active() -> bool:
	return Time.get_ticks_msec() < _slowmo_until_ms


func _update_time_scale() -> void:
	var now := Time.get_ticks_msec()
	var target := 1.0
	if _hitstop_active:
		if now >= _hitstop_until_ms:
			_hitstop_active = false
		else:
			target = HITSTOP_TIME_SCALE
	if now < _slowmo_until_ms:
		var total := maxf(1.0, float(_slowmo_until_ms - _slowmo_start_ms))
		var left := float(_slowmo_until_ms - now) / total
		var s := _slowmo_scale
		if left < _SLOWMO_EASE_OUT:
			s = lerpf(1.0, _slowmo_scale, left / _SLOWMO_EASE_OUT)
		target = minf(target, s)
	if not is_equal_approx(Engine.time_scale, target):
		Engine.time_scale = target


# --- Haptics -----------------------------------------------------------------

func _haptic(kind: String) -> void:
	if not haptics_enabled:
		return
	var h: HapticsService = PlatformServices.haptics
	if h == null:
		return
	var now := Time.get_ticks_msec()
	if now - int(_haptic_last_ms.get(kind, 0)) < int(_HAPTIC_SPACING_MS.get(kind, 80)):
		return
	_haptic_last_ms[kind] = now
	match kind:
		"light": h.light()
		"medium": h.medium()
		"heavy": h.heavy()
	counters["haptic"] += 1
