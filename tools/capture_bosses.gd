extends SceneTree
## Windowed capture of each campaign boss mid-fight (needs a real renderer):
## godot --path . --script res://tools/capture_bosses.gd -- <out_dir>

const BOSSES := ["cinder_warden", "ember_hydra", "abyss_sentinel", "rift_leviathan", "abyss_overmind", "void_titan_ascended"]

var _out_dir := "user://captures"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_out_dir = args[0]
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(_out_dir)
	DisplayServer.window_set_size(Vector2i(540, 960))
	for id in BOSSES:
		var scene = load("res://scenes/gameplay/run_scene.tscn").instantiate()
		root.add_child(scene)
		for i in 4:
			await process_frame
		scene.get_node("WaveDirector").stop_and_clear()
		var boss = scene.get_node("Boss")
		var player = scene.get_node("PlayerShip")
		boss.prepare(load("res://resources/bosses/%s.tres" % id))
		boss.begin()
		# Real time (frames are uncapped outside AppRoot).
		var until := Time.get_ticks_msec() + 7500
		while Time.get_ticks_msec() < until:
			player.call("grant_invulnerability", 1.0)
			await process_frame
		await RenderingServer.frame_post_draw
		var img: Image = root.get_texture().get_image()
		img.save_png(_out_dir.path_join("%s.png" % id))
		print("captured %s" % id)
		scene.queue_free()
		await process_frame
	quit(0)
