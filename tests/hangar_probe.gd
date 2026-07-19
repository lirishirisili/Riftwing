extends SceneTree
## Headless hangar validation.
## godot --headless --path . --script res://tests/hangar_probe.gd
##
## Autoload globals are not registered for --script SceneTree entry points, so
## this probe resolves SaveManager / SceneRouter via /root.


func _init() -> void:
	call_deferred("_run")


func _save() -> Node:
	return root.get_node("SaveManager")


func _router() -> Node:
	return root.get_node("SceneRouter")


func _run() -> void:
	print("hangar_probe: start")
	var failed := 0
	failed += _check_resources()
	failed += _check_purchase_and_save()
	failed += await _check_hangar_screen()
	if failed == 0:
		print("HANGAR_PROBE_OK")
		quit(0)
	else:
		printerr("HANGAR_PROBE_FAILED count=%d" % failed)
		quit(1)


func _check_resources() -> int:
	var catalog: ShipCatalogData = load("res://resources/ships/ship_catalog_default.tres")
	if catalog == null or catalog.ships.size() != 4:
		printerr("catalog missing or wrong size")
		return 1
	var vanguard := catalog.find_by_id("vanguard_mk2")
	if vanguard == null or not vanguard.starts_unlocked:
		printerr("vanguard missing/unlocked flag wrong")
		return 1
	if vanguard.tracks().size() != 5:
		printerr("expected 5 tracks, got %d" % vanguard.tracks().size())
		return 1
	var locked := 0
	for ship in catalog.ships:
		if ship != null and not ship.starts_unlocked:
			locked += 1
	if locked != 3:
		printerr("expected 3 locked ships, got %d" % locked)
		return 1
	var stats := HangarStats.compute(vanguard, {})
	if stats.attack != vanguard.base_attack:
		printerr("base attack mismatch")
		return 1
	print("resources_ok ships=%d locked=%d atk=%d" % [catalog.ships.size(), locked, stats.attack])
	return 0


func _check_purchase_and_save() -> int:
	var sm := _save()
	sm.call("reset")
	var catalog: ShipCatalogData = load("res://resources/ships/ship_catalog_default.tres")
	var ship := catalog.find_by_id("vanguard_mk2")
	var weapons := ship.weapons_track
	var cost0 := weapons.cost_for_next_level(0)

	if bool(sm.call("try_purchase_upgrade", ship.id, weapons)):
		printerr("purchase succeeded with 0 energy")
		return 1
	if int(sm.call("get_upgrade_level", ship.id, "weapons")) != 0:
		printerr("level changed after failed purchase")
		return 1

	sm.call("debug_add_currency", cost0 - 1, 0)
	if bool(sm.call("try_purchase_upgrade", ship.id, weapons)):
		printerr("purchase succeeded without enough energy")
		return 1
	if int(sm.call("get_rift_energy")) != cost0 - 1:
		printerr("energy changed on failed purchase")
		return 1

	for _i in 8:
		if bool(sm.call("try_purchase_upgrade", ship.id, weapons)):
			printerr("spam purchase succeeded without enough energy")
			return 1

	sm.call("debug_add_currency", 1, 0)
	if not bool(sm.call("try_purchase_upgrade", ship.id, weapons)):
		printerr("affordable purchase failed")
		return 1
	if int(sm.call("get_upgrade_level", ship.id, "weapons")) != 1:
		printerr("level not incremented")
		return 1
	if int(sm.call("get_rift_energy")) != 0:
		printerr("energy not deducted to 0, got %d" % int(sm.call("get_rift_energy")))
		return 1

	var levels: Dictionary = sm.call("get_upgrade_levels", ship.id)
	var after := HangarStats.compute(ship, levels)
	if after.attack != ship.base_attack + weapons.attack_per_level:
		printerr("stat curve not applied")
		return 1

	if bool(sm.call("select_ship", "razor_wing")):
		printerr("locked ship was selected")
		return 1
	sm.call("debug_add_currency", 5000, 0)
	var razor := catalog.find_by_id("razor_wing")
	if bool(sm.call("try_purchase_upgrade", "razor_wing", razor.weapons_track)):
		printerr("locked ship accepted upgrade")
		return 1

	var energy_before := int(sm.call("get_rift_energy"))
	sm.call("load_game")
	if int(sm.call("get_upgrade_level", ship.id, "weapons")) != 1:
		printerr("upgrade level not persisted")
		return 1
	if int(sm.call("get_rift_energy")) != energy_before:
		printerr("energy not persisted")
		return 1
	if String(sm.call("get_selected_ship_id")) != "vanguard_mk2":
		printerr("selected ship not persisted")
		return 1

	print("purchase_ok cost0=%d energy=%d atk=%d" % [cost0, int(sm.call("get_rift_energy")), after.attack])
	return 0


func _check_hangar_screen() -> int:
	var sm := _save()
	var router := _router()
	sm.call("reset")
	sm.call("debug_add_currency", 1000, 2)
	var holder := Node.new()
	root.add_child(holder)
	router.call("configure", holder)
	router.call("go_to", "hangar")
	await process_frame
	await process_frame
	if String(router.call("get_current_screen_id")) != "hangar":
		printerr("hangar screen not active")
		return 1
	var screen: Node = null
	for child in holder.get_children():
		if child.get_script() != null and String(child.get_script().resource_path).ends_with("hangar_screen.gd"):
			screen = child
			break
	if screen == null:
		printerr("HangarScreen instance missing")
		return 1
	var name_label := screen.get_node_or_null("%ShipName") as Label
	if name_label == null:
		name_label = screen.find_child("ShipName", true, false) as Label
	if name_label == null or name_label.text.find("VANGUARD") < 0:
		printerr("ship name missing/wrong: %s" % (name_label.text if name_label else "null"))
		return 1
	var brand := screen.find_child("BrandLabel", true, false) as Label
	if brand == null:
		brand = screen.find_child("Brand", true, false) as Label
	if brand == null or brand.text != "RIFTWING":
		printerr("branding missing")
		return 1
	if screen.find_child("Shell", true, false) == null:
		printerr("MetaScreenShell missing on hangar")
		return 1
	if screen.find_child("EquipButton", true, false) == null or not (screen.find_child("EquipButton", true, false) is GlowCtaButton):
		printerr("hangar EQUIP not GlowCtaButton")
		return 1
	var track := (load("res://resources/ships/vanguard_mk2.tres") as ShipData).weapons_track
	var before_level := int(sm.call("get_upgrade_level", "vanguard_mk2", "weapons"))
	var before_energy := int(sm.call("get_rift_energy"))
	if not bool(sm.call("try_purchase_upgrade", "vanguard_mk2", track)):
		printerr("ui-path purchase failed with banked energy")
		return 1
	if int(sm.call("get_upgrade_level", "vanguard_mk2", "weapons")) != before_level + 1:
		printerr("ui-path level not updated")
		return 1
	if int(sm.call("get_rift_energy")) >= before_energy:
		printerr("ui-path energy not deducted")
		return 1
	print("screen_ok brand=%s ship=%s energy=%d" % [
		brand.text, name_label.text, int(sm.call("get_rift_energy"))])
	return 0
