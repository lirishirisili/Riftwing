extends Node2D
## Deterministic debug scene for the player movement milestone.
##
## Draws the configurable gameplay rectangle, marks the live pointer/touch
## position, and highlights the ship's small collision core, so drag feel,
## bounds clamping, and the vertical finger offset can be verified visually.
## No shooting, enemies, or HUD.

@onready var _player: PlayerShip = $PlayerShip
@onready var _overlay: Control = $Overlay

var _pointer: Vector2 = Vector2.ZERO
var _pointer_active: bool = false


func _ready() -> void:
	_overlay.draw.connect(_on_overlay_draw)


func _process(_delta: float) -> void:
	_overlay.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_pointer_active = event.pressed
		_pointer = event.position
	elif event is InputEventScreenDrag:
		_pointer = event.position


func _on_overlay_draw() -> void:
	var canvas_inv := get_viewport().get_canvas_transform().affine_inverse()
	var cyan := Palette.get_color("cyan", Color.CYAN)
	var orange := Palette.get_color("orange", Color(1, 0.48, 0.1))
	var muted := Palette.get_color("muted", Color(0.46, 0.57, 0.71))

	# Gameplay bounds the ship origin is confined to.
	var rect: Rect2 = _player.data.gameplay_rect
	_overlay.draw_rect(rect, Color(muted, 0.9), false, 3.0)

	# Live pointer position (raw touch/finger location).
	if _pointer_active:
		var world_pointer := canvas_inv * _pointer
		_overlay.draw_circle(world_pointer, 48.0, Color(orange, 0.25))
		_overlay.draw_arc(world_pointer, 48.0, 0.0, TAU, 32, orange, 3.0)

	# Ship collision core (small, independent of the ship art).
	var core := _player.get_core_global_position()
	_overlay.draw_circle(core, 18.0, Color(cyan, 0.35))
	_overlay.draw_arc(core, 18.0, 0.0, TAU, 24, cyan, 2.0)
