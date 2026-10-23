extends SceneTree
## Regression probe for the stability pass (shared hitboxes, kill double-count,
## run-wide upgrade bonuses, background pause, settlement, daily isolation,
## ship differentiation, fire catch-up cap).
## godot --headless --path . --script res://tests/stability_probe.gd


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("stability_probe: start")
	var failed := 0
	failed += _check_ship_reference()
	failed += _check_daily_pool()
	failed += _check_settlement()
	failed += await _check_live_run()
	if failed == 0:
		print("STABILITY_PROBE_OK")
		quit(0)
	else:
		printerr("STABILITY_PROBE_FAILED count=%d" % failed)
		quit(1)


func _check_ship_reference() -> int:
	var catalog := load("res://resources/ships/ship_catalog_default.tres") as ShipCatalogData
	var starter := catalog.find_by_id(catalog.default_ship_id())
	var lance := catalog.find_by_id("solar_lance")
	if starter == null or lance == null:
		printerr("ship catalog missing starter / solar_lance")
		return 1
	var zero := {"weapons": 0, "shield": 0, "engine": 0, "drones": 0, "ultimate": 0}
	var base := CombatProfile.from_hangar(starter, zero, starter)
	var top := CombatProfile.from_hangar(lance, zero, starter)
	if not is_equal_approx(base.weapon_damage_mult, 1.0):
		printerr("starter not neutral vs itself: %f" % base.weapon_damage_mult)
		return 1
	if top.weapon_damage_mult <= 1.0 or top.hp_mult <= 1.0:
		printerr("solar lance not stronger than starter: dmg=%f hp=%f" % [top.weapon_damage_mult, top.hp_mult])
		return 1
	print("ships_ok lance dmg=%.2f hp=%.2f" % [top.weapon_damage_mult, top.hp_mult])
	return 0


func _check_daily_pool() -> int:
	var d := DailyChallenge.build(["1-2"], 0)
	if String(d["stage_id"]) != "1-2" or String(d["difficulty"]) != "normal":
		printerr("daily ignored launchable pool / hard gate: %s" % str(d))
		return 1
	print("daily_ok")
	return 0


func _check_settlement() -> int:
	var fails := 0
	var stats = load("res://scripts/progression/run_stats.gd").new()
	var settlement = load("res://scripts/progression/run_settlement.gd")
	stats.run_id = "stability_probe_%d" % Time.get_ticks_msec()
	stats.victory = true
	stats.stage_id = "1-8"
	stats.is_daily = true
	stats.enemies_destroyed = 10
	var save: Node = root.get_node("SaveManager")
	var was_cleared: bool = save.is_stage_cleared("1-8")
	settlement.settle(stats)
	if not stats.settled or stats.rewards == null:
		printerr("settlement did not run")
		fails += 1
	var granted_first: bool = stats.granted
	settlement.settle(stats)
	if stats.granted != granted_first:
		printerr("settlement not idempotent")
		fails += 1
	if not was_cleared and save.is_stage_cleared("1-8"):
		printerr("daily run recorded a campaign clear")
		fails += 1
	if not save.is_clock_trusted():
		printerr("clock reported untrusted on a normal machine")
		fails += 1
	if fails == 0:
		print("settlement_ok")
	return fails


func _check_live_run() -> int:
	var fails := 0
	var scene = load("res://scenes/gameplay/run_scene.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	# 1) Pooled enemies own their hit shapes.
	var pool = scene.get_node("EnemyPool")
	var scout = load("res://resources/enemies/scout.tres")
	var tank = load("res://resources/enemies/tank.tres")
	var a = pool.acquire()
	var b = pool.acquire()
	a.spawn(scout, Vector2(200, -100), Vector2(200, 300), Vector2(200, 2200), 1.0, 2.0, 1.0)
	b.spawn(tank, Vector2(600, -100), Vector2(600, 300), Vector2(600, 2200), 1.0, 2.0, 1.0)
	var ra: float = ((a.get_node("CollisionShape2D") as CollisionShape2D).shape as CircleShape2D).radius
	var rb: float = ((b.get_node("CollisionShape2D") as CollisionShape2D).shape as CircleShape2D).radius
	if is_equal_approx(ra, rb):
		printerr("enemy hit shapes still shared: %f == %f" % [ra, rb])
		fails += 1

	# 2) Re-acquired enemies drop the previous owner's listeners.
	a.died.connect(func(_e) -> void: pass)
	pool.release(a)
	var c = pool.acquire()
	if c.died.get_connections().size() != 0:
		printerr("pooled enemy kept %d died listeners" % c.died.get_connections().size())
		fails += 1
	pool.release(b)
	pool.release(c)

	# 3) "all" secondary bonuses reach weapons acquired afterwards.
	var sys = scene.get_node("SecondaryWeaponSystem")
	sys.acquire("arc_laser")
	var before: float = sys.bolt_damage("arc_laser")
	sys.add_damage_mult("all", 2.0)
	sys.acquire("chain_lightning")
	var chain_base = load("res://resources/weapons/secondary/chain_lightning.tres")
	if sys.bolt_damage("arc_laser") <= before:
		printerr("all-damage did not boost owned weapon")
		fails += 1
	if chain_base != null and sys.bolt_damage("chain_lightning") < chain_base.damage * 1.99:
		printerr("all-damage missed a weapon acquired later: %f" % sys.bolt_damage("chain_lightning"))
		fails += 1

	# 4) Backgrounding opens the pause overlay.
	var hud = scene.get_node("UI/GameplayHUD")
	scene.call("on_app_backgrounded")
	if not hud.is_hud_paused():
		printerr("backgrounding did not pause the run")
		fails += 1
	hud.force_resume()

	# 5) A long hitch cannot dump unbounded plasma volleys.
	var weapon = scene.get_node("PlayerShip/PlasmaWeapon")
	var bolts = scene.get_node("PlayerProjectilePool")
	bolts.release_all()
	weapon.call("_process", 5.0)
	var per_volley: int = weapon.data.projectiles_per_shot + weapon.bonus_projectiles
	if bolts.get_active_count() > per_volley * 4:
		printerr("plasma burst after hitch: %d bolts" % bolts.get_active_count())
		fails += 1

	scene.queue_free()
	await process_frame
	if fails == 0:
		print("live_ok shapes/listeners/all-bonus/pause/hitch")
	return fails
