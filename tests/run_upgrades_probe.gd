extends SceneTree
## Proves the run upgrade system is real end-to-end: the catalog has 20 authored
## upgrades, and inside a live run each effect kind routes to a concrete runtime
## change (plasma mods, secondary weapons, abilities, survivability), while the
## shared projectile pool stays hard-capped under sustained secondary fire.
## godot --headless --path . --script res://tests/run_upgrades_probe.gd

const UPGRADE_IDS := [
	"plasma_overcharge", "plasma_spread_array", "homing_missiles", "arc_laser",
	"guardian_drone", "chain_lightning", "void_bomb", "plasma_rapid_coils",
	"plasma_heavy_slugs", "plasma_twin_array", "targeting_matrix", "missile_swarm",
	"arc_amplifier", "drone_overclock", "warhead_yield", "reinforced_hull",
	"ablative_plating", "afterburner", "adrenaline_core", "overcharged_core",
]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("run_upgrades_probe: start")
	var failed := 0
	failed += _check_catalog()
	failed += await _check_live_run()
	if failed == 0:
		print("RUN_UPGRADES_PROBE_OK upgrades=%d" % UPGRADE_IDS.size())
		quit(0)
	else:
		printerr("RUN_UPGRADES_PROBE_FAILED count=%d" % failed)
		quit(1)


func _load_upgrade(id: String):
	return load("res://resources/upgrades/%s.tres" % id)


func _check_catalog() -> int:
	var fails := 0
	if UPGRADE_IDS.size() != 20:
		printerr("expected 20 upgrades, listed %d" % UPGRADE_IDS.size())
		fails += 1
	for id in UPGRADE_IDS:
		var up = _load_upgrade(id)
		if up == null:
			printerr("upgrade missing: %s" % id)
			fails += 1
			continue
		if up.id != id:
			printerr("upgrade id mismatch: file %s -> id %s" % [id, up.id])
			fails += 1
		if String(up.title).strip_edges() == "":
			printerr("upgrade %s has empty title" % id)
			fails += 1
		if up.effects.is_empty():
			printerr("upgrade %s has no effects (would be a no-op card)" % id)
			fails += 1
	if fails == 0:
		print("catalog_ok 20 upgrades, all have effects")
	return fails


func _check_live_run() -> int:
	var fails := 0
	var scene = load("res://scenes/gameplay/run_scene.tscn").instantiate()
	root.add_child(scene)
	# Let _ready run: hangar profile applied, secondary configured + bound.
	await process_frame
	await process_frame

	var mgr = scene.get_node("UpgradeManager")
	var sys = scene.get_node("SecondaryWeaponSystem")
	var weapon = scene.get_node("PlayerShip/PlasmaWeapon")
	var player = scene.get_node("PlayerShip")
	var pool = scene.get_node("PlayerProjectilePool")

	if mgr.catalog.size() != 20:
		printerr("UpgradeManager catalog size %d (want 20)" % mgr.catalog.size())
		fails += 1

	# Abilities are always live (bound to the two HUD buttons).
	if not sys.has_weapon("ability_missiles") or not sys.has_weapon("ability_arc"):
		printerr("abilities not registered in live run")
		fails += 1
	if not sys.fire_ability(true) or not sys.fire_ability(false):
		printerr("abilities did not fire")
		fails += 1

	# Plasma line routes to concrete weapon modifiers.
	fails += _apply_expect_gt(mgr, "plasma_heavy_slugs",
		func() -> float: return weapon.damage_mult, "plasma damage")
	fails += _apply_expect_gt(mgr, "plasma_rapid_coils",
		func() -> float: return weapon.fire_rate_mult, "plasma fire rate")
	fails += _apply_expect_gt(mgr, "plasma_twin_array",
		func() -> float: return float(weapon.bonus_projectiles), "plasma bolts")
	fails += _apply_expect_gt(mgr, "targeting_matrix",
		func() -> float: return weapon.crit_chance, "plasma crit")

	# Weapon acquisition + secondary boost.
	if sys.has_weapon("homing_missiles"):
		printerr("homing_missiles unexpectedly pre-owned")
		fails += 1
	mgr.apply(_load_upgrade("homing_missiles"))
	if not sys.has_weapon("homing_missiles"):
		printerr("acquiring homing_missiles via manager failed")
		fails += 1
	var shots_before := int(sys.shots_per_volley("homing_missiles"))
	mgr.apply(_load_upgrade("missile_swarm"))
	if int(sys.shots_per_volley("homing_missiles")) <= shots_before:
		printerr("missile_swarm did not add missiles")
		fails += 1

	# Global secondary damage lifts ability bolts.
	fails += _apply_expect_gt(mgr, "warhead_yield",
		func() -> float: return sys.bolt_damage("ability_missiles"), "secondary all dmg")

	# Survivability + agility.
	fails += _apply_expect_gt(mgr, "reinforced_hull",
		func() -> float: return player.combat_data.max_health, "max HP")
	fails += _apply_expect_gt(mgr, "ablative_plating",
		func() -> float: return player.get_damage_reduction(), "armor")
	fails += _apply_expect_gt(mgr, "afterburner",
		func() -> float: return player.data.follow_smoothing, "move speed")

	# Sustained secondary + plasma fire must never grow the pool past its cap.
	sys.acquire("chain_lightning")
	sys.acquire("void_bomb")
	for i in 30:
		sys.fire_ability(true)
		sys.fire_ability(false)
		await process_frame
	var stats = pool.get_stats()
	if int(stats["total"]) > int(stats["max"]):
		printerr("pool exceeded cap: total=%d max=%d" % [int(stats["total"]), int(stats["max"])])
		fails += 1

	scene.queue_free()
	if fails == 0:
		print("live_run_ok routing+abilities+pool cap=%d total=%d" % [
			int(stats["max"]), int(stats["total"])])
	return fails


func _apply_expect_gt(mgr, id: String, sampler: Callable, label: String) -> int:
	var before := float(sampler.call())
	var up = _load_upgrade(id)
	if up == null:
		printerr("%s: upgrade missing" % id)
		return 1
	mgr.apply(up)
	var after := float(sampler.call())
	if after <= before:
		printerr("%s (%s) did not increase: %f -> %f" % [id, label, before, after])
		return 1
	return 0
