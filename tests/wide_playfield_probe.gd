extends SceneTree
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1600, 2560))
	await process_frame
	await process_frame
	var data: PlayerMovementData = load("res://resources/balance/player_movement_default.tres") as PlayerMovementData
	var base: Rect2 = data.gameplay_rect if data != null else Rect2(90, 240, 900, 1500)
	var vp := root.get_visible_rect().size
	var margin_l := base.position.x
	var margin_r := 1080.0 - (base.position.x + base.size.x)
	var play_w := maxf(base.size.x, vp.x - margin_l - margin_r)
	print("vp=", vp, " play_w=", play_w, " max_x=", margin_l + play_w)
	if play_w < 1400.0 and vp.x >= 1500.0:
		printerr("PLAYFIELD_TOO_NARROW")
		quit(1)
	# Load space bg
	var bg_scene := load("res://scenes/gameplay/space_background.tscn") as PackedScene
	var bg := bg_scene.instantiate()
	root.add_child(bg)
	await process_frame
	var dim: Sprite2D = bg.get_node("CenterDim")
	var dim_w := dim.texture.get_size().x * dim.scale.x if dim.texture else 0.0
	print("dim_w=", dim_w, " view_guess=", vp.x)
	if dim_w < vp.x * 0.95 and vp.x > 1080.0:
		# may still be fitting - check scale covers
		print("dim cover ratio=", dim_w / maxf(1.0, vp.x))
	print("WIDE_PLAYFIELD_OK")
	quit(0)
