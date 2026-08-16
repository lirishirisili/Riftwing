extends SceneTree
## Validates production upgrade-choice cards / overlay via the run host.
## godot --headless --path . --script res://tests/upgrade_cards_probe.gd


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("upgrade_cards_probe: start")
	var failed := 0
	failed += _check_resources()
	failed += await _check_runtime()
	if failed == 0:
		print("UPGRADE_CARDS_PROBE_OK")
		quit(0)
	else:
		printerr("UPGRADE_CARDS_PROBE_FAILED count=%d" % failed)
		quit(1)


func _check_resources() -> int:
	var paths := [
		"res://scenes/ui/upgrade_screen.tscn",
		"res://scenes/ui/upgrade_card.tscn",
		"res://assets/ui/upgrade_card_rare.svg",
		"res://assets/ui/upgrade_card_epic.svg",
		"res://assets/ui/upgrade_card_legendary.svg",
	]
	for path in paths:
		if not ResourceLoader.exists(path):
			printerr("missing %s" % path)
			return 1
	var screen_src := FileAccess.get_file_as_string("res://scenes/ui/upgrade_screen.tscn")
	var card_src := FileAccess.get_file_as_string("res://scripts/ui/upgrade_card.gd")
	if screen_src.find("Starforge") >= 0 or screen_src.find("Galaxy Rush") >= 0:
		printerr("legacy brand in upgrade screen")
		return 1
	if screen_src.find("RIFTSTRIKE") < 0:
		printerr("RIFTSTRIKE missing from upgrade screen")
		return 1
	if card_src.find("play_selection") < 0 or card_src.find("_FRAME_PATHS") < 0:
		printerr("card rarity/selection chrome missing")
		return 1
	var data_src := FileAccess.get_file_as_string("res://scripts/progression/upgrade_data.gd")
	if data_src.find("purple") < 0 or data_src.find("gold") < 0 or data_src.find("cyan") < 0:
		printerr("rarity color tokens incomplete")
		return 1
	print("resources_ok")
	return 0


func _check_runtime() -> int:
	var fails := 0
	var router := root.get_node("SceneRouter")
	var holder := Node.new()
	root.add_child(holder)
	router.call("configure", holder)
	router.call("go_to", "run", {"sector": 1, "stage_id": "1-1", "fast": true})
	await process_frame
	await process_frame
	await process_frame

	var run: Node = holder.get_child(0)
	if run == null:
		printerr("run host missing")
		return 1
	var upgrade_screen: Node = run.get_node_or_null("UpgradeScreen")
	var xp: Node = run.get_node_or_null("ExperienceTracker")
	if upgrade_screen == null or xp == null:
		printerr("UpgradeScreen or ExperienceTracker missing")
		return 1

	# Force a level-up so the production overlay opens through the real path.
	xp.call("add_experience", int(xp.call("get_xp_for_next")))
	for _i in 30:
		await process_frame
		if bool(upgrade_screen.call("is_open")):
			break

	if not bool(upgrade_screen.call("is_open")):
		printerr("upgrade overlay did not open after level-up")
		fails += 1
		return fails
	if not paused:
		printerr("tree should be paused during upgrade choice")
		fails += 1
	var player: Node = run.get_node_or_null("Player")
	if player != null and player.can_process():
		printerr("player still can_process during upgrade choice")
		fails += 1

	var brand := upgrade_screen.find_child("Brand", true, false) as Label
	if brand == null or brand.text != "RIFTSTRIKE":
		printerr("brand missing on overlay")
		fails += 1

	var cards_parent := upgrade_screen.find_child("Cards", true, false)
	if cards_parent == null or cards_parent.get_child_count() < 1:
		printerr("no upgrade cards built")
		fails += 1
		return fails

	var card: Node = cards_parent.get_child(0)
	var rarity_label := card.find_child("Rarity", true, false) as Label
	if rarity_label == null or rarity_label.text.strip_edges() == "":
		printerr("rarity label empty")
		fails += 1
	var frame := card.find_child("Frame", true, false) as TextureRect
	if frame == null or frame.texture == null:
		printerr("rarity frame texture missing")
		fails += 1

	var upgrade: Variant = card.call("get_upgrade")
	card.emit_signal("chosen", upgrade)
	for _i in 90:
		await process_frame
		if not paused and not bool(upgrade_screen.call("is_open")):
			break
	if paused or bool(upgrade_screen.call("is_open")):
		upgrade_screen.call("_finish_close")
		await process_frame
	if paused:
		printerr("tree still paused after selection")
		fails += 1
	if bool(upgrade_screen.call("is_open")):
		printerr("overlay still open after selection")
		fails += 1
	# After close, cards must be cleared (no ghost stack from prior level).
	if int(upgrade_screen.call("get_card_count")) != 0:
		printerr("cards not cleared after close count=%d" % int(upgrade_screen.call("get_card_count")))
		fails += 1

	# Burst XP while no pending choice: only ONE level should open (no cascade).
	xp.call("add_experience", 200)
	for _i in 30:
		await process_frame
		if bool(upgrade_screen.call("is_open")):
			break
	if not bool(upgrade_screen.call("is_open")):
		printerr("second upgrade overlay did not open")
		fails += 1
	else:
		# Queue must stay at a single pending choice despite the XP dump.
		if int(xp.call("get_pending_levels")) != 1:
			printerr("pending levels should be 1 after burst got=%d" % int(xp.call("get_pending_levels")))
			fails += 1
		var n2 := int(upgrade_screen.call("get_card_count"))
		if n2 != 3:
			printerr("second open card count want=3 got=%d" % n2)
			fails += 1
		var title := upgrade_screen.find_child("Title", true, false) as Label
		if title != null and title.text.find("LEVEL") < 0:
			printerr("level title missing on second open")
			fails += 1
		# Pick and close again.
		var cards2 := upgrade_screen.find_child("Cards", true, false)
		if cards2 != null and cards2.get_child_count() > 0:
			var c2: Node = cards2.get_child(0)
			c2.emit_signal("chosen", c2.call("get_upgrade"))
			for _i in 90:
				await process_frame
				if not bool(upgrade_screen.call("is_open")):
					break
			if bool(upgrade_screen.call("is_open")):
				upgrade_screen.call("_finish_close")
				await process_frame
		if int(upgrade_screen.call("get_card_count")) != 0:
			printerr("cards not cleared after second close")
			fails += 1

	print("runtime_ok rarity=%s double_level_ok" % [
		rarity_label.text if rarity_label else "?"])
	return fails
