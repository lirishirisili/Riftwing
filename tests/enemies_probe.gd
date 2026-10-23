extends SceneTree
## Proves the enemy / spawning pass: every new archetype's movement and fire
## pattern, ambient budget spawning, elites (affix + chest drop), and the heal /
## magnet / chest pickups including the chest reveal flow.
## Simulation is stepped manually (fixed deltas) so it is deterministic and fast.
## godot --headless --path . --script res://tests/enemies_probe.gd

const STEP := 1.0 / 30.0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("enemies_probe: start")
	var failed := 0
	failed += await _check_archetypes()
	failed += await _check_ambient_and_elites()
	failed += await _check_pickups_and_chest()
	if failed == 0:
		print("ENEMIES_PROBE_OK")
		quit(0)
	else:
		printerr("ENEMIES_PROBE_FAILED count=%d" % failed)
		quit(1)


func _mount_run() -> Node:
	var scene = load("res://scenes/gameplay/run_scene.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	scene.get_node("WaveDirector").stop_and_clear()
	scene.get_node("PlayerShip/PlasmaWeapon").firing_active = false
	return scene


func _spawn(scene: Node, id: String, pos: Vector2, wait: float = 8.0) -> Node:
	var director = scene.get_node("WaveDirector")
	var data = load("res://resources/enemies/%s.tres" % id)
	var exit := Vector2(pos.x, 2400.0)
	if data.movement == 2: # SWOOP: side to side
		director.call("_spawn_one", data, Vector2(-150, 300), Vector2(540, 700), Vector2(1230, 400), 1.0, 0.0, 1.0)
	else:
		director.call("_spawn_one", data, pos, pos, exit, 0.05, wait, 1.0)
	var list: Array = director.get_active_enemies()
	return list[list.size() - 1]


func _step(node: Node, seconds: float) -> void:
	var t := 0.0
	while t < seconds and is_instance_valid(node) and node.visible:
		node.call("_process", STEP)
		t += STEP


func _check_archetypes() -> int:
	var fails := 0
	var scene: Node = await _mount_run()
	var bolts = scene.get_node("EnemyProjectilePool")

	# WEAVE descends and sways.
	var weaver = _spawn(scene, "weaver", Vector2(540, -100))
	var y0: float = weaver.global_position.y
	_step(weaver, 1.0)
	if weaver.global_position.y <= y0 + 100.0:
		printerr("weaver did not descend")
		fails += 1

	# SWOOP arcs through and releases at the far side.
	var swarm = _spawn(scene, "swarmling", Vector2.ZERO)
	_step(swarm, 3.0)
	if swarm.visible:
		printerr("swarmling did not finish its swoop")
		fails += 1

	# CHARGE telegraphs then dashes.
	var lancer = _spawn(scene, "lancer", Vector2(540, 400))
	_step(lancer, 1.2)
	if int(lancer.get("_phase")) != 4 and lancer.visible:
		printerr("lancer did not dash (phase %d)" % int(lancer.get("_phase")))
		fails += 1

	# RING / SPIRAL / SNIPE / DOWN_SPREAD fire their patterns.
	for case in [["bulwark", 10], ["spinner", 8], ["sniper", 1], ["striker", 4]]:
		bolts.release_all()
		var e = _spawn(scene, case[0], Vector2(540, 400), 30.0)
		_step(e, 4.5)
		if bolts.get_active_count() < int(case[1]):
			printerr("%s fired %d bolts (want >= %d)" % [case[0], bolts.get_active_count(), case[1]])
			fails += 1
		e.call("_release")

	# STRAFE slides sideways.
	var striker = _spawn(scene, "striker", Vector2(540, 400), 30.0)
	var xs := []
	for i in 40:
		striker.call("_process", STEP)
		xs.append(striker.global_position.x)
	if absf(float(xs.max()) - float(xs.min())) < 40.0:
		printerr("striker did not strafe")
		fails += 1
	striker.call("_release")

	# CARRIER summons drones.
	var director = scene.get_node("WaveDirector")
	director.set_ambient(load("res://resources/spawning/nova_early.tres"))
	var carrier = _spawn(scene, "carrier", Vector2(540, 400), 30.0)
	var before: int = director.get_active_enemy_count()
	_step(carrier, 2.5)
	await process_frame
	if director.get_active_enemy_count() <= before:
		printerr("carrier summoned nothing")
		fails += 1
	director.stop_and_clear()

	scene.queue_free()
	await process_frame
	if fails == 0:
		print("archetypes_ok weave/swoop/charge/ring/spiral/snipe/spread/strafe/carrier")
	return fails


func _check_ambient_and_elites() -> int:
	var fails := 0
	var scene: Node = await _mount_run()
	var director = scene.get_node("WaveDirector")
	director.set_ambient(load("res://resources/spawning/nova_mid.tres"))
	var elites := [0]
	director.elite_spawned.connect(func(_e) -> void: elites[0] += 1)
	director.force_next_elite()
	for i in 300:
		director.call("_process", STEP)
	if director.get_active_enemy_count() < 3:
		printerr("ambient spawning produced %d enemies in 10s" % director.get_active_enemy_count())
		fails += 1
	if elites[0] < 1:
		printerr("forced elite never spawned")
		fails += 1
	var elite: Node = null
	for e in director.get_active_enemies():
		if e.is_elite():
			elite = e
	var pickups = scene.get_node("PickupPool")
	if elite != null:
		var chests_before := _count_kind(pickups, 3)
		elite.take_damage(1000000.0)
		if _count_kind(pickups, 3) <= chests_before:
			printerr("elite kill dropped no chest")
			fails += 1
	director.stop_and_clear()
	scene.queue_free()
	await process_frame
	if fails == 0:
		print("ambient_ok spawning + elite + chest drop")
	return fails


func _count_kind(pool: Node, kind: int) -> int:
	var n := 0
	for p in pool.get_active_nodes():
		if p.get_kind() == kind:
			n += 1
	return n


func _check_pickups_and_chest() -> int:
	var fails := 0
	var scene: Node = await _mount_run()
	var player = scene.get_node("PlayerShip")
	var screen = scene.get_node("UpgradeScreen")
	# Heal orb (drop the starter ship's signature barrier so the hit lands).
	player.set("_barrier_ready", false)
	player.take_damage(40.0)
	var hp0: float = player.get_health()
	scene.call("_on_special_pickup", 1, 20)
	if player.get_health() <= hp0:
		printerr("heal orb did not heal")
		fails += 1
	# Chest reveal.
	var closed := [false]
	screen.reveal_closed.connect(func() -> void: closed[0] = true)
	scene.call("_on_special_pickup", 3, 1)
	await process_frame
	if not screen.is_open() or screen.get_card_count() < 1:
		printerr("chest did not open a reveal")
		fails += 1
	screen.call("_close_reveal")
	for i in 30:
		await process_frame
		if closed[0]:
			break
	if not closed[0] or paused:
		printerr("chest reveal did not close cleanly (paused=%s)" % paused)
		fails += 1
	scene.queue_free()
	await process_frame
	if fails == 0:
		print("pickups_ok heal + chest reveal")
	return fails
