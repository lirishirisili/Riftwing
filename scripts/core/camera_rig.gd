class_name CameraRig
extends Camera2D
## Restrained trauma-based screen shake (docs/01_VISUAL_DIRECTION.md: explosions
## use restrained camera shake).
##
## Callers add "trauma" (0..1); actual offset uses trauma squared so light hits
## barely move and only big events shake hard. Trauma decays every frame so the
## camera always settles. Shake is applied as an offset around the rig's rest
## position, so it never fights gameplay positioning.

## Max positional shake in logical pixels at full trauma.
@export var max_offset: Vector2 = Vector2(26.0, 26.0)
## Max rotational shake in radians at full trauma (kept tiny for readability).
@export var max_roll: float = 0.05
## How fast trauma bleeds off per second.
@export var decay: float = 1.6
## Noise sampling frequency (higher = jitterier).
@export var frequency: float = 32.0

var _trauma: float = 0.0
var _noise := FastNoiseLite.new()
var _time: float = 0.0
## Zoom punch (big moments): real-time envelope, 0 = rest zoom.
var _punch_amount: float = 0.0
var _punch_total: float = 0.0
var _punch_left: float = 0.0


func _ready() -> void:
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.frequency = 0.9
	# Keep shaking smoothly even during hit-stop (time_scale dips) so the two
	# effects layer instead of cancelling; use real time for the noise walk.
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameFeel.register_camera(self)
	_center_on_viewport()
	get_viewport().size_changed.connect(_center_on_viewport)
	call_deferred("_center_on_viewport")


## Rest position tracks the logical viewport center so tall 19.5:9 / 20:9
## frames do not leave an empty band above the authored playfield. Shake still
## applies via `offset`, never by fighting this rest position.
func _center_on_viewport() -> void:
	var vp := get_viewport().get_visible_rect().size
	position = Vector2(vp.x * 0.5, vp.y * 0.5)


## Briefly zooms in by `amount` (0.08 = 8%) and eases back over `seconds`.
func zoom_punch(amount: float, seconds: float) -> void:
	_punch_amount = clampf(amount, 0.0, 0.2)
	_punch_total = maxf(0.05, seconds)
	_punch_left = _punch_total


## Adds trauma (clamped to 1). Small values fade almost immediately.
func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


func _process(delta: float) -> void:
	var real_delta := delta / maxf(Engine.time_scale, 0.001)
	_update_zoom(real_delta)
	# Advance on unscaled time so shake reads naturally through hit-stop.
	_time += real_delta * frequency
	if _trauma <= 0.0:
		offset = Vector2.ZERO
		rotation = 0.0
		return
	var shake := _trauma * _trauma
	offset = Vector2(
		max_offset.x * shake * _noise.get_noise_2d(_time, 0.0),
		max_offset.y * shake * _noise.get_noise_2d(0.0, _time)
	)
	rotation = max_roll * shake * _noise.get_noise_2d(_time, 100.0)
	_trauma = maxf(0.0, _trauma - decay * (delta / maxf(Engine.time_scale, 0.001)))


func _update_zoom(real_delta: float) -> void:
	if _punch_left <= 0.0:
		if zoom != Vector2.ONE:
			zoom = Vector2.ONE
		return
	_punch_left = maxf(0.0, _punch_left - real_delta)
	var p := 1.0 - _punch_left / _punch_total
	# Fast in (first 15%), slow ease out.
	var env := clampf(p / 0.15, 0.0, 1.0) if p < 0.15 else 1.0 - ease((p - 0.15) / 0.85, 0.6)
	zoom = Vector2.ONE * (1.0 + _punch_amount * env)


func get_trauma() -> float:
	return _trauma


func _exit_tree() -> void:
	GameFeel.register_camera(null)
