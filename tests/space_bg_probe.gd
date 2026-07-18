extends SceneTree
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var packed := load("res://scenes/gameplay/run_scene.tscn") as PackedScene
	if packed == null:
		printerr("run_scene missing")
		quit(1)
		return
	var run := packed.instantiate()
	root.add_child(run)
	await process_frame
	await process_frame
	var bg := run.get_node_or_null("SpaceBackground")
	if bg == null:
		printerr("SpaceBackground missing")
		quit(1)
		return
	var neb := bg.get_node_or_null("NebulaA") as Sprite2D
	if neb == null or neb.texture == null:
		printerr("NebulaA texture missing")
		quit(1)
		return
	var far := bg.get_node_or_null("FarA") as Sprite2D
	if far == null or far.texture == null:
		printerr("FarA texture missing")
		quit(1)
		return
	print("bg_ok nebula_size=%s far_size=%s view_children=%d" % [str(neb.texture.get_size()), str(far.texture.get_size()), bg.get_child_count()])
	print("SPACE_BG_PROBE_OK")
	quit(0)
