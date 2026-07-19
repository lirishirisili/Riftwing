extends Node2D
## Cinematic scrolling space backdrop (world-space sprites).
##
## Uses Sprite2D pairs in the gameplay canvas (z_index -20) so the backdrop is
## always visible under ships and bolts. ParallaxBackground was abandoned here
## because as a CanvasLayer it failed to show under the run Camera2D setup.

const _SCROLL_FAR := 22.0
const _SCROLL_NEBULA := 38.0
const _SCROLL_DEBRIS := 70.0

@onready var _base: Sprite2D = $BaseFill
@onready var _far_a: Sprite2D = $FarA
@onready var _far_b: Sprite2D = $FarB
@onready var _nebula_a: Sprite2D = $NebulaA
@onready var _nebula_b: Sprite2D = $NebulaB
@onready var _debris_a: Sprite2D = $DebrisA
@onready var _debris_b: Sprite2D = $DebrisB
@onready var _galaxy: Sprite2D = $Galaxy
@onready var _planet: Sprite2D = $Planet
@onready var _dim: Sprite2D = $CenterDim

var _scroll_far := 0.0
var _scroll_nebula := 0.0
var _scroll_debris := 0.0
var _view := Vector2(1080, 1920)


func _ready() -> void:
	z_index = -20
	_ensure_solid_textures()
	_fit_viewport()
	get_viewport().size_changed.connect(_fit_viewport)
	call_deferred("_fit_viewport")


func _process(delta: float) -> void:
	_scroll_far = fmod(_scroll_far + delta * _SCROLL_FAR, _view.y)
	_scroll_nebula = fmod(_scroll_nebula + delta * _SCROLL_NEBULA, _view.y)
	_scroll_debris = fmod(_scroll_debris + delta * _SCROLL_DEBRIS, _view.y)
	_place_pair(_far_a, _far_b, _scroll_far)
	_place_pair(_nebula_a, _nebula_b, _scroll_nebula)
	_place_pair(_debris_a, _debris_b, _scroll_debris)
	_pulse_accents(delta)


func _pulse_accents(delta: float) -> void:
	var t := Time.get_ticks_msec() * 0.001
	if _galaxy != null:
		_galaxy.rotation += delta * 0.02
		_galaxy.modulate.a = 0.4 + sin(t * 0.55) * 0.1
	if _planet != null:
		_planet.modulate.a = 0.72 + sin(t * 0.35) * 0.08


func _place_pair(a: Sprite2D, b: Sprite2D, scroll: float) -> void:
	if a == null or b == null:
		return
	a.position = Vector2(0.0, scroll - _view.y)
	b.position = Vector2(0.0, scroll)


func _ensure_solid_textures() -> void:
	if _base != null and _base.texture == null:
		_base.texture = _make_solid(Color(0.02, 0.04, 0.1, 1.0))
	# Soft full-width readability veil (no hard 9:16 column seams on tablets).
	if _dim != null:
		_dim.texture = _make_soft_dim_texture()


func _make_solid(color: Color) -> ImageTexture:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)


## Horizontal gradient: gentle mid-lane darken that fades at the sides.
func _make_soft_dim_texture() -> ImageTexture:
	var w := 64
	var h := 8
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for x in w:
		var t := float(x) / float(w - 1)
		# Peak opacity in the center, near-zero at edges — no hard vertical cut.
		var edge := absf(t - 0.5) * 2.0
		var a := 0.28 * (1.0 - edge * edge)
		var c := Color(0.01, 0.015, 0.04, a)
		for y in h:
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


func _fit_viewport() -> void:
	var size := get_viewport().get_visible_rect().size
	_view = Vector2(maxf(1080.0, size.x), maxf(1920.0, size.y))

	if _base != null:
		_base.centered = false
		_base.position = Vector2.ZERO
		if _base.texture != null:
			var bt := _base.texture.get_size()
			_base.scale = Vector2(_view.x / maxf(1.0, bt.x), _view.y / maxf(1.0, bt.y))

	_scale_tile(_far_a)
	_scale_tile(_far_b)
	_scale_tile(_nebula_a)
	_scale_tile(_nebula_b)
	_scale_tile(_debris_a)
	_scale_tile(_debris_b)
	_place_pair(_far_a, _far_b, _scroll_far)
	_place_pair(_nebula_a, _nebula_b, _scroll_nebula)
	_place_pair(_debris_a, _debris_b, _scroll_debris)

	if _galaxy != null and _galaxy.texture != null:
		_galaxy.centered = true
		_galaxy.position = Vector2(_view.x * 0.5, _view.y * 0.74)
		var gw := _galaxy.texture.get_size().x
		if gw > 0.0:
			var gs := (_view.x * 1.1) / gw
			_galaxy.scale = Vector2(gs, gs)

	if _planet != null and _planet.texture != null:
		_planet.centered = true
		_planet.position = Vector2(_view.x * 0.86, _view.y * 0.2)
		var pw := _planet.texture.get_size().x
		if pw > 0.0:
			var ps := (_view.x * 0.58) / pw
			_planet.scale = Vector2(ps, ps)

	if _dim != null and _dim.texture != null:
		_dim.centered = true
		_dim.position = Vector2(_view.x * 0.5, _view.y * 0.5)
		var dw := maxf(1.0, _dim.texture.get_size().x)
		var dh := maxf(1.0, _dim.texture.get_size().y)
		# Full bleed — soft gradient handles lane readability without side bands.
		_dim.scale = Vector2(_view.x / dw, _view.y / dh)


func _scale_tile(sprite: Sprite2D) -> void:
	if sprite == null or sprite.texture == null:
		return
	var tex := sprite.texture.get_size()
	if tex.x <= 0.0 or tex.y <= 0.0:
		return
	sprite.centered = false
	sprite.scale = Vector2(_view.x / tex.x, _view.y / tex.y)
