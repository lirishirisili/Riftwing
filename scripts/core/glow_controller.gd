extends Node
## Quality-gated WorldEnvironment glow for premium neon feel.
##
## HIGH/MEDIUM enable restrained bloom; LOW disables it so mid-range devices
## stay readable and stable. Does not blur Control text.

var _env_node: WorldEnvironment
var _environment: Environment
var _last_quality: int = -1


func _ready() -> void:
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_CLEAR_COLOR
	_environment.glow_enabled = false
	_environment.glow_intensity = 0.55
	_environment.glow_strength = 0.85
	_environment.glow_bloom = 0.12
	_environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	_environment.glow_hdr_threshold = 0.85
	_environment.glow_hdr_scale = 1.6
	_environment.set_glow_level(1, 0.0)
	_environment.set_glow_level(2, 0.55)
	_environment.set_glow_level(3, 0.85)
	_environment.set_glow_level(4, 0.45)
	_environment.set_glow_level(5, 0.15)
	_env_node = WorldEnvironment.new()
	_env_node.environment = _environment
	add_child(_env_node)
	add_to_group("glow_controller")
	apply_from_game_feel()


func apply_from_game_feel() -> void:
	apply_quality(GameFeel.quality)


func apply_quality(level: int) -> void:
	if _environment == null or level == _last_quality:
		return
	_last_quality = level
	match level:
		GameFeel.Quality.LOW:
			_environment.glow_enabled = false
		GameFeel.Quality.MEDIUM:
			_environment.glow_enabled = true
			_environment.glow_intensity = 0.32
			_environment.glow_bloom = 0.05
		_:
			_environment.glow_enabled = true
			_environment.glow_intensity = 0.52
			_environment.glow_bloom = 0.1
