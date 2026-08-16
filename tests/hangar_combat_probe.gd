extends SceneTree
## Proves each hangar track maps to a measurable in-run combat stat via
## CombatProfile, and that building profiles never mutates the shared ShipData.
## godot --headless --path . --script res://tests/hangar_combat_probe.gd


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("hangar_combat_probe: start")
	var failed := 0
	failed += _check_profile_mapping()
	failed += _check_resolution_math()
	if failed == 0:
		print("HANGAR_COMBAT_PROBE_OK")
		quit(0)
	else:
		printerr("HANGAR_COMBAT_PROBE_FAILED count=%d" % failed)
		quit(1)


func _zero_levels() -> Dictionary:
	return {"weapons": 0, "shield": 0, "engine": 0, "drones": 0, "ultimate": 0}


func _check_profile_mapping() -> int:
	var fails := 0
	var catalog: ShipCatalogData = load("res://resources/ships/ship_catalog_default.tres")
	if catalog == null:
		printerr("catalog missing")
		return 1
	var ship: ShipData = catalog.find_by_id(catalog.default_ship_id())
	if ship == null:
		ship = catalog.ships[0] if catalog.ships.size() > 0 else null
	if ship == null:
		printerr("no ship in catalog")
		return 1

	# Snapshot shared resource fields to prove they are never mutated.
	var base_attack := ship.base_attack
	var base_hp := ship.base_hp
	var base_def := ship.base_defense
	var base_crit := ship.base_critical

	var base := CombatProfile.from_hangar(ship, _zero_levels())
	# Level-0 ship must read neutral modifiers so 1-1 keeps its tuned baseline.
	if not is_equal_approx(base.weapon_damage_mult, 1.0):
		printerr("base weapon mult not 1.0: %f" % base.weapon_damage_mult)
		fails += 1
	if not is_equal_approx(base.hp_mult, 1.0):
		printerr("base hp mult not 1.0: %f" % base.hp_mult)
		fails += 1
	if base.damage_reduction > 0.0:
		printerr("base ship should have 0 armor, got %f" % base.damage_reduction)
		fails += 1

	var checks := {
		"weapons": "weapon_damage_mult",
		"shield": "damage_reduction",
		"engine": "move_speed_mult",
		"drones": "crit_chance",
		"ultimate": "hp_mult",
	}
	for track_id in checks:
		var track := ship.track_by_id(track_id)
		if track == null:
			continue
		var levels := _zero_levels()
		levels[track_id] = 1
		var up := CombatProfile.from_hangar(ship, levels)
		var field: String = checks[track_id]
		if float(up.get(field)) <= float(base.get(field)):
			printerr("track %s did not raise %s (%f -> %f)" % [
				track_id, field, float(base.get(field)), float(up.get(field))])
			fails += 1

	# HP track (ultimate) must raise the HP multiplier above baseline.
	var hp_levels := _zero_levels()
	hp_levels["ultimate"] = 2
	if CombatProfile.from_hangar(ship, hp_levels).hp_mult <= base.hp_mult:
		printerr("ultimate did not raise hp_mult")
		fails += 1

	# Shared resource untouched.
	if ship.base_attack != base_attack or ship.base_hp != base_hp \
			or ship.base_defense != base_def or not is_equal_approx(ship.base_critical, base_crit):
		printerr("ShipData resource was mutated by profile building")
		fails += 1

	if fails == 0:
		print("profile_mapping_ok baseHPmult=1.0 baseATKmult=1.0 baseArmor=0")
	return fails


func _check_resolution_math() -> int:
	var fails := 0
	var p := CombatProfile.new()
	p.damage_reduction = 0.5
	if not is_equal_approx(p.mitigate(100.0), 50.0):
		printerr("mitigate wrong: %f" % p.mitigate(100.0))
		fails += 1

	# Forced crit: chance 1.0 always crits and multiplies damage.
	p.weapon_damage_mult = 2.0
	p.crit_chance = 1.0
	p.crit_multiplier = 2.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var hit := p.resolve_hit(10.0, rng)
	if not bool(hit["crit"]):
		printerr("forced crit did not crit")
		fails += 1
	if not is_equal_approx(float(hit["damage"]), 40.0):
		printerr("crit damage wrong: %f (want 40)" % float(hit["damage"]))
		fails += 1

	# Zero crit chance never crits.
	p.crit_chance = 0.0
	if bool(p.resolve_hit(10.0, rng)["crit"]):
		printerr("zero crit chance still crit")
		fails += 1

	if fails == 0:
		print("resolution_math_ok mitigate+crit")
	return fails
