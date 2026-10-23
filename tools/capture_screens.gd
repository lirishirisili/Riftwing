extends SceneTree
## Windowed screenshots of meta screens for visual review (real renderer):
## godot --path . --script res://tools/capture_screens.gd -- <out_dir>

const SHOTS := [
	["main_menu", {}],
	["progress", {"tab": 0}],
	["progress", {"tab": 1}],
	["progress", {"tab": 2}],
	["modes", {}],
	["stage_map", {"stage_id": "2-1"}],
	["hangar", {}],
]

var _out_dir := "user://captures"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_out_dir = args[0]
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(_out_dir)
	DisplayServer.window_set_size(Vector2i(540, 960))
	var router: Node = root.get_node("SceneRouter")
	var holder := Node.new()
	root.add_child(holder)
	router.call("configure", holder)
	var n := 0
	for shot in SHOTS:
		router.call("go_to", shot[0], shot[1])
		var until := Time.get_ticks_msec() + 1200
		while Time.get_ticks_msec() < until:
			await process_frame
		await RenderingServer.frame_post_draw
		var img: Image = root.get_texture().get_image()
		var name := "%02d_%s" % [n, shot[0]]
		img.save_png(_out_dir.path_join(name + ".png"))
		print("captured %s" % name)
		n += 1
	quit(0)
