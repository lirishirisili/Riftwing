extends SceneTree
## Proves the combat-depth pass: weapon levels, every evolution recipe, real
## weapon behaviors (beam, chain, drones, blasts, homing, pierce), banish, luck,
## and the new passives.
## godot --headless --path . --script res://tests/combat_depth_probe.gd

const EVOLUTIONS := {
	"evo_hydra_swarm": ["homing_missiles", "warhead_yield"],
	"evo_prism_lance": ["arc_laser", "rift_lens"],
	"evo_aegis_halo": ["guardian_drone", "kinetic_barrier"],
	"evo_storm_weaver": ["chain_lightning", "targeting_matrix"],
	"evo_singularity": ["void_bomb", "overcharged_core"],
	"evo_nova_cannon": ["plasma_rapid_coils", "piercing_rounds"],
}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("combat_depth_probe: start")
	var failed := 0
	failed += await _check_levels_and_evolutions()
	failed += await _check_weapon_behaviors()
	if failed == 0:
		print("COMBAT_DEPTH_PROBE_OK")
		quit(0)
	else:
		printerr("COMBAT_DEPTH_PROBE_FAILED count=%d" % failed)
		quit(1)


func _mount_run() -> Node:
	var scene = load("res://scenes/gameplay/run_scene.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	# Keep the probe deterministic: no waves, no boss.
	scene.get_node("WaveDirector").stop_and_clear()
	return scene


func _check_levels_and_evolutions() -> int:
	var fails := 0
	for evo_id in EVOLUTIONS.keys():
		var scene: Node = await _mount_run()
		var mgr = scene.get_node("UpgradeManager")
		var sys = scene.get_node("SecondaryWeaponSystem")
		var parts: Array = EVOLUTIONS[evo_id]
		var base = mgr.find_upgrade(parts[0])
		var partner = mgr.find_upgrade(parts[1])
		var evo = mgr.find_upgrade(evo_id)
		if base == null or partner == null or evo == null:
			printerr("%s: recipe upgrades missing" % evo_id)
			fails += 1
			scene.queue_free()
			continue
		if mgr.is_eligible(evo):
			printerr("%s eligible before recipe" % evo_id)
			fails += 1
		for i in base.max_level:
			mgr.apply(base)
		mgr.apply(partner)
		if not mgr.is_eligible(evo):
			printerr("%s not eligible after recipe" % evo_id)
			fails += 1
		var roll: Array = mgr.roll_choices(3, 5)
		if roll.is_empty() or roll[0] != evo:
			printerr("%s not forced into first slot" % evo_id)
			fails += 1
		var weapon_id: String = parts[0]
		if weapon_id != "plasma_rapid_coils" and sys.weapon_level(weapon_id) != base.max_level:
			printerr("%s weapon level %d (want %d)" % [weapon_id, sys.weapon_level(weapon_id), base.max_level])
			fails += 1
		mgr.apply(evo)
		var evolved: bool = scene.get_node("PlayerShip/PlasmaWeapon").evolved if weapon_id == "plasma_rapid_coils" \
			else sys.is_evolved(weapon_id)
		if not evolved:
			printerr("%s did not evolve" % evo_id)
			fails += 1
		if mgr.is_eligible(evo):
			printerr("%s still offered after taking it" % evo_id)
			fails += 1
		scene.queue_free()
		await process_frame
	# Banish removes a card for the run.
	var s2: Node = await _mount_run()
	var m2 = s2.get_node("UpgradeManager")
	var lens = m2.find_upgrade("rift_lens")
	m2.banish("rift_lens")
	if m2.is_eligible(lens):
		printerr("banished card still eligible")
		fails += 1
	s2.queue_free()
	await process_frame
	if fails == 0:
		print("evolutions_ok %d recipes, levels, forced slot, banish" % EVOLUTIONS.size())
	return fails


func _spawn_enemy(scene: Node, pos: Vector2, hp_mult: float = 50.0) -> Node:
	var director = scene.get_node("WaveDirector")
	var data = load("res://resources/enemies/tank.tres")
	director.call("_spawn_one", data, pos, pos, pos + Vector2(0, 3000), 0.01, 60.0, 1.0)
	var list: Array = director.get_active_enemies()
	var e = list[list.size() - 1]
	e.apply_scaling(hp_mult, 1.0)
	return e


func _hp(enemy: Node) -> float:
	return float(enemy.get("_health"))


func _check_weapon_behaviors() -> int:
	var fails := 0
	var scene: Node = await _mount_run()
	var sys = scene.get_node("SecondaryWeaponSystem")
	var player = scene.get_node("PlayerShip")
	var weapon = scene.get_node("PlayerShip/PlasmaWeapon")
	weapon.firing_active = false
	var ship: Vector2 = player.get_core_global_position()

	# BEAM: a target straight above the ship takes tick damage.
	var above = _spawn_enemy(scene, Vector2(ship.x, ship.y - 600.0))
	sys.acquire("arc_laser")
	sys.get("_active")["arc_laser"]["timer"] = 0.0
	var hp0 := _hp(above)
	for i in 30:
		await process_frame
	if _hp(above) >= hp0:
		printerr("beam did not damage a target above the ship")
		fails += 1

	# CHAIN: hits the first target and jumps to a neighbour.
	var a = _spawn_enemy(scene, ship + Vector2(-120, -300))
	var b = _spawn_enemy(scene, ship + Vector2(80, -380))
	sys.acquire("chain_lightning")
	var ha := _hp(a)
	var hb := _hp(b)
	sys.call("_fire", sys.get("_active")["chain_lightning"], false)
	if _hp(a) >= ha or _hp(b) >= hb:
		printerr("chain lightning did not link two targets")
		fails += 1

	# BLAST: area damage reaches every target in radius.
	var c = _spawn_enemy(scene, Vector2(300, 500))
	var d = _spawn_enemy(scene, Vector2(360, 540))
	var hc := _hp(c)
	var hd := _hp(d)
	sys.detonate(Vector2(330, 520), 150.0, 40.0, 1, 0.3)
	if _hp(c) >= hc or _hp(d) >= hd:
		printerr("area blast missed targets in radius")
		fails += 1

	# VORTEX: multi-pulse blasts keep hitting.
	sys.detonate(Vector2(330, 520), 150.0, 10.0, 3, 0.05)
	var hv := _hp(c)
	for i in 20:
		await process_frame
	if _hp(c) >= hv:
		printerr("vortex pulses did not re-detonate")
		fails += 1

	# ORBIT: drones exist and grow with levels.
	sys.acquire("guardian_drone")
	var entry: Dictionary = sys.get("_active")["guardian_drone"]
	var n0: int = sys.call("_orbit_count", entry, entry["data"])
	sys.level_up("guardian_drone")
	sys.level_up("guardian_drone")
	var n1: int = sys.call("_orbit_count", entry, entry["data"])
	if n1 <= n0:
		printerr("drone count did not grow with levels (%d -> %d)" % [n0, n1])
		fails += 1

	# HOMING: missiles have a turn rate and a blast.
	var missile = load("res://resources/weapons/friendly_missile_projectile.tres")
	if missile.homing_turn_rate <= 0.0 or missile.explode_radius <= 0.0:
		printerr("missiles are not homing / exploding")
		fails += 1

	# PIERCE: plasma pierce reaches the fired projectile.
	weapon.add_pierce(1)
	if weapon.call("_current_projectile").pierce < 1:
		printerr("plasma pierce not applied")
		fails += 1

	# Passives.
	var mgr = scene.get_node("UpgradeManager")
	var r0: float = player.get_magnet_radius()
	mgr.apply(mgr.find_upgrade("magnet_coil"))
	if player.get_magnet_radius() <= r0:
		printerr("magnet coil did not widen the magnet")
		fails += 1
	var xp = scene.get_node("ExperienceTracker")
	mgr.apply(mgr.find_upgrade("xp_siphon"))
	if xp.xp_mult <= 1.0:
		printerr("xp siphon did not raise xp gain")
		fails += 1
	mgr.apply(mgr.find_upgrade("kinetic_barrier"))
	if not player.has_barrier_ready():
		printerr("kinetic barrier not ready after pick")
		fails += 1
	var hp_before: float = player.get_health()
	player.take_damage(30.0)
	if player.get_health() < hp_before:
		printerr("barrier did not absorb the hit")
		fails += 1
	var luck0: float = mgr.get_luck()
	mgr.apply(mgr.find_upgrade("lucky_star"))
	if mgr.get_luck() <= luck0:
		printerr("lucky star added no luck")
		fails += 1

	scene.queue_free()
	await process_frame
	if fails == 0:
		print("weapons_ok beam/chain/blast/vortex/orbit/homing/pierce + passives")
	return fails
