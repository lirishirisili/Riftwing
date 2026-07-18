extends Node
## Central game-feel facade (autoload).
##
## Gameplay code calls a handful of intent methods here (projectile hit, enemy
## death, player hit) and this router fans them out to the pooled effects layer,
## the camera rig (screen shake), the HapticsService, and the AudioManager. It
## also owns the effect quality level and short hit-stop.
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

const _QUALITY_CFG := "user://effects_quality.cfg"
const _HAPTICS_CFG := "user://haptics_enabled.cfg"

## Default HIGH for desktop feel; settings can persist LOW for mid-range devices.
var quality: int = Quality.HIGH
## Player preference; when false, haptic hooks no-op even if the service exists.
var haptics_enabled: bool = true

# Registered feedback sinks (weak by pattern: cleared on scene teardown).
var _effects: Node = null
var _camera: Node = null

# Hit-stop bookkeeping, measured in real (unscaled) time so a scaled delta can
# never leave the game frozen.
var _hitstop_until_ms: int = 0
var _hitstop_active: bool = false

# Debug counters so the harness can prove each system fired.
var counters := {
	"hit_flash": 0,
	"explosion_small": 0,
	"explosion_large": 0,
	"damage_number": 0,
	"shake": 0,
	"hitstop": 0,
	"haptic": 0,
}


func _ready() -> void:
	# Autoload must keep processing while the tree is paused so a pause menu can
	# still animate; hit-stop uses real time, not the pause state.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_prefs()


func _process(_delta: float) -> void:
	if _hitstop_active and Time.get_ticks_msec() >= _hitstop_until_ms:
		_hitstop_active = false
		Engine.time_scale = 1.0


# --- Registration ------------------------------------------------------------

## The active scene's EffectsLayer registers here so effects route to its pools.
func register_effects_layer(layer: Node) -> void:
	_effects = layer


func register_camera(camera: Node) -> void:
	_camera = camera


## Scenes call this on teardown so stale references never linger between screens.
func clear_sinks() -> void:
	_effects = null
	_camera = null
	if _hitstop_active:
		_hitstop_active = false
		Engine.time_scale = 1.0


# --- Quality -----------------------------------------------------------------

func set_quality(level: int) -> void:
	quality = clampi(level, Quality.LOW, Quality.HIGH)
	_save_prefs()


func cycle_quality() -> void:
	quality = (quality + 1) % 3
	_save_prefs()


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
	var qf := FileAccess.open(_QUALITY_CFG, FileAccess.WRITE)
	if qf != null:
		qf.store_line(str(quality))
	var hf := FileAccess.open(_HAPTICS_CFG, FileAccess.WRITE)
	if hf != null:
		hf.store_line("1" if haptics_enabled else "0")


## Particle count budget for an explosion by current quality.
func explosion_particles(is_major: bool) -> int:
	var base := 26 if is_major else 12
	match quality:
		Quality.LOW: return 0
		Quality.MEDIUM: return base / 2
		_: return base


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
## the player from a player bolt hitting an enemy (colors the feedback).
func projectile_hit(world_pos: Vector2, damage: float, to_player: bool) -> void:
	var color := Palette.get_color("danger") if to_player else Palette.get_color("orange")
	if _effects != null:
		_effects.spawn_hit_flash(world_pos, color)
		counters["hit_flash"] += 1
		if damage_numbers_enabled() and not to_player:
			_effects.spawn_damage_number(world_pos, int(round(damage)))
			counters["damage_number"] += 1
	_add_trauma(0.12)
	_haptic("light")
	AudioManager.play_sfx("hit", world_pos, AudioManager.PRIORITY_LOW)


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


## The player took damage.
func player_hit(world_pos: Vector2) -> void:
	if _effects != null:
		_effects.spawn_hit_flash(world_pos, Palette.get_color("danger"))
	_add_trauma(0.5)
	request_hitstop(HITSTOP_MIN_SECONDS)
	_haptic("heavy")
	AudioManager.play_sfx("player_hit", world_pos, AudioManager.PRIORITY_HIGH)


# --- Screen shake ------------------------------------------------------------

func _add_trauma(amount: float) -> void:
	var scaled := amount * shake_scale()
	if scaled <= 0.0 or _camera == null:
		return
	_camera.add_trauma(scaled)
	counters["shake"] += 1


# --- Hit-stop ----------------------------------------------------------------

## Briefly slows time. Duration is clamped to the readable 30-60 ms window and
## measured in real time; requests never stack the freeze deeper, only extend it.
func request_hitstop(seconds: float) -> void:
	var dur := clampf(seconds, HITSTOP_MIN_SECONDS, HITSTOP_MAX_SECONDS)
	var until := Time.get_ticks_msec() + int(dur * 1000.0)
	_hitstop_until_ms = maxi(_hitstop_until_ms, until)
	if not _hitstop_active:
		_hitstop_active = true
		Engine.time_scale = HITSTOP_TIME_SCALE
		counters["hitstop"] += 1


# --- Haptics -----------------------------------------------------------------

func _haptic(kind: String) -> void:
	if not haptics_enabled:
		return
	var h: HapticsService = PlatformServices.haptics
	if h == null:
		return
	match kind:
		"light": h.light()
		"medium": h.medium()
		"heavy": h.heavy()
	counters["haptic"] += 1
