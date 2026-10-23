extends SceneTree
## Captures screenshots of key run moments for visual review (needs a real
## renderer, so run WITHOUT --headless):
## godot --path . --script res://tools/capture_run_moments.gd -- <out_dir> [stage_id]
##
## Saves: combat.png (waves + upgrades), nova.png (Rift Nova blast),
## boss.png (boss pattern), boss_kill.png (kill beat + loot fountain).

var _out_dir := "user://captures"
var _stage_id := "1-1"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_out_dir = args[0]
	if args.size() >= 2:
		_stage_id = args[1]
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(_out_dir)
	DisplayServer.window_set_size(Vector2i(540, 960))
	var router: Node = root.get_node("SceneRouter")
	var holder := Node.new()
	root.add_child(holder)
	router.call("configure", holder)
	router.call("go_to", "run", {"sector": 1, "stage_id": _stage_id})
	await _frames(10)
	var run: Node = holder.get_child(0)
	var feel: Node = root.get_node("GameFeel")
	feel.set("quality", 2)

	# Give the ship a build so the screen fills like a mid-run moment.
	var mgr = run.get_node("UpgradeManager")
	for id in ["plasma_twin_array", "plasma_spread_array", "homing_missiles", "arc_laser", "guardian_drone"]:
		mgr.apply(load("res://resources/upgrades/%s.tres" % id))
	# One evolved weapon so the capture shows an evolution.
	for i in 4:
		mgr.apply(load("res://resources/upgrades/guardian_drone.tres"))
	mgr.apply(load("res://resources/upgrades/kinetic_barrier.tres"))
	mgr.apply(load("res://resources/upgrades/evo_aegis_halo.tres"))
	var player = run.get_node("PlayerShip")
	await _seconds(7.0, run, player)
	await _snap("combat")

	run.call("_add_nova_charge", 1.0)
	run.call("_on_nova_activated")
	await _frames(6)
	await _snap("nova")

	run.call("debug_skip_to_mini_boss")
	await _seconds(6.5, run, player)
	await _snap("boss")

	run.get_node("Boss").call("debug_defeat")
	await _frames(12)
	await _snap("boss_kill")
	print("CAPTURE_RUN_MOMENTS_OK %s" % _out_dir)
	quit(0)


## Lets the run play while sweeping the ship side to side (keeps it alive and
## firing across the field) and auto-picking upgrade cards.
func _seconds(seconds: float, run: Node, player: Node) -> void:
	var t := 0.0
	while t < seconds:
		var x := 540.0 + sin(t * 1.3) * 300.0
		player.set("_target", Vector2(x, 1500.0))
		player.call("grant_invulnerability", 0.5)
		var screen = run.get_node("UpgradeScreen")
		if screen.call("is_open"):
			var cards: Array = screen.get("_cards")
			if not cards.is_empty():
				screen.call("_on_card_chosen", cards[0].call("get_upgrade"))
		await process_frame
		t += 1.0 / 60.0


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	var path := _out_dir.path_join("%s.png" % name)
	img.save_png(path)
	print("captured %s (%dx%d)" % [path, img.get_width(), img.get_height()])
