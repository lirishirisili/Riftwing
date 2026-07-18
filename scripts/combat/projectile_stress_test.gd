extends Node2D
## Debug stress test for the projectile pool.
##
## Fires from a row of emitters at a high rate so more than 300 projectiles are
## alive at once, while reporting FPS and live pool statistics (active / free /
## total / peak / prewarm). If `total` stays equal to `prewarm`, the pool never
## grew and no runtime instantiate/free occurred.

# Tuned so peak concurrent bolts sit above the 300 target but below the pool
# prewarm (640), proving reuse without growth. Bolts live ~1.5s on screen, so
# ~280 emitted/second holds ~430 alive at once.
const _EMITTER_COUNT := 14
const _FANS_PER_EMITTER := 1
const _EMITTER_FIRE_RATE := 20.0
const _TARGET_MIN_ACTIVE := 300

@onready var _pool: ProjectilePool = $ProjectilePool
@onready var _label: Label = $Overlay/Panel/Margin/Info

var _projectile_data: ProjectileData
var _cooldown: float = 0.0
var _observed_peak: int = 0
var _grew: bool = false


func _ready() -> void:
	_projectile_data = load("res://resources/weapons/plasma_projectile.tres")


func _process(delta: float) -> void:
	_cooldown -= delta
	var interval := 1.0 / _EMITTER_FIRE_RATE
	while _cooldown <= 0.0:
		_fire_wave()
		_cooldown += interval
	_update_readout()


func _fire_wave() -> void:
	var spacing := 1080.0 / float(_EMITTER_COUNT + 1)
	for e in _EMITTER_COUNT:
		var x := spacing * float(e + 1)
		var origin := Vector2(x, 1750.0)
		# A small fan per emitter (centered on straight-up) so many bolts are
		# alive at once and spread across the screen.
		for f in _FANS_PER_EMITTER:
			var offset := float(f) - float(_FANS_PER_EMITTER - 1) * 0.5
			var angle := deg_to_rad(12.0 * offset)
			_pool.spawn(origin, Vector2.UP.rotated(angle), _projectile_data)


func _update_readout() -> void:
	var stats := _pool.get_stats()
	_observed_peak = maxi(_observed_peak, int(stats["peak"]))
	if int(stats["total"]) > int(stats["prewarm"]):
		_grew = true
	var growth := "NO (pool reused)" if not _grew else "YES (exceeded prewarm)"
	_label.text = "\n".join([
		"RIFTWING · projectile stress test",
		"FPS: %d" % Engine.get_frames_per_second(),
		"Active: %d" % int(stats["active"]),
		"Free: %d" % int(stats["free"]),
		"Total: %d" % int(stats["total"]),
		"Peak active: %d" % int(stats["peak"]),
		"Prewarm: %d" % int(stats["prewarm"]),
		"Target >= %d active: %s" % [_TARGET_MIN_ACTIVE, "MET" if _observed_peak >= _TARGET_MIN_ACTIVE else "..."],
		"Pool growth: %s" % growth,
	])
