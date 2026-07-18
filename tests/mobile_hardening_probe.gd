extends SceneTree
## Headless mobile-hardening validation.
## godot --headless --path . --script res://tests/mobile_hardening_probe.gd


func _init() -> void:
	call_deferred("_run")


func _save() -> Node:
	return root.get_node("SaveManager")


func _audio() -> Node:
	return root.get_node("AudioManager")


func _feel() -> Node:
	return root.get_node("GameFeel")


func _run() -> void:
	print("mobile_hardening_probe: start")
	var failed := 0
	failed += _check_pool_cap()
	failed += _check_audio_focus()
	failed += _check_quality_persist()
	failed += await _check_lifecycle_and_screens()
	if failed == 0:
		print("MOBILE_HARDENING_PROBE_OK")
		quit(0)
	else:
		printerr("MOBILE_HARDENING_PROBE_FAILED count=%d" % failed)
		quit(1)


func _check_pool_cap() -> int:
	var scene := PackedScene.new()
	# Build a tiny dummy scene via a Node script-free node for pool growth.
	var holder := Node.new()
	root.add_child(holder)
	# Use an existing lightweight packed scene.
	var packed: PackedScene = load("res://scenes/effects/damage_number.tscn")
	if packed == null:
		printerr("damage_number scene missing")
		return 1
	var pool := ObjectPool.new(packed, holder, 4)
	pool.prewarm(2)
	if pool.get_total_count() != 2:
		printerr("prewarm size wrong")
		return 1
	var a := pool.acquire()
	var b := pool.acquire()
	var c := pool.acquire() # growth 1 -> total 3
	var d := pool.acquire() # growth 2 -> total 4
	var e := pool.acquire() # blocked
	if a == null or b == null or c == null or d == null:
		printerr("expected acquires under cap to succeed")
		return 1
	if e != null:
		printerr("acquire above max_total should return null")
		return 1
	if pool.get_blocked_acquires() < 1:
		printerr("blocked counter not incremented")
		return 1
	if pool.get_total_count() > 4:
		printerr("pool grew past max_total")
		return 1
	print("pool_cap_ok total=%d blocked=%d" % [pool.get_total_count(), pool.get_blocked_acquires()])
	return 0


func _check_audio_focus() -> int:
	var audio := _audio()
	audio.set("enabled", true)
	audio.call("set_has_focus", false)
	var before: int = int(audio.get("sfx_count"))
	audio.call("play_sfx", "test_bg", Vector2.ZERO, 0)
	if int(audio.get("sfx_count")) != before:
		printerr("sfx played without focus")
		return 1
	audio.call("set_has_focus", true)
	audio.call("play_sfx", "test_fg", Vector2.ZERO, 0)
	if int(audio.get("sfx_count")) != before + 1:
		printerr("sfx did not play with focus")
		return 1
	print("audio_focus_ok")
	return 0


func _check_quality_persist() -> int:
	var feel := _feel()
	feel.call("set_quality", 0) # LOW
	if String(feel.call("quality_name")) != "LOW":
		printerr("quality not LOW")
		return 1
	# Reload prefs via a fresh read of the cfg the same way GameFeel does.
	if not FileAccess.file_exists("user://effects_quality.cfg"):
		printerr("quality cfg not written")
		return 1
	var text := FileAccess.get_file_as_string("user://effects_quality.cfg").strip_edges()
	if text != "0":
		printerr("quality cfg contents wrong: %s" % text)
		return 1
	feel.call("set_quality", 2) # restore HIGH for other tests
	print("quality_persist_ok")
	return 0


func _check_lifecycle_and_screens() -> int:
	var sm := _save()
	var audio := _audio()
	sm.call("debug_add_currency", 1, 0)
	var energy_before: int = int(sm.call("get_rift_energy"))
	# Simulate background flush.
	sm.call("save_game")
	audio.call("set_has_focus", false)
	sm.call("load_game")
	if int(sm.call("get_rift_energy")) != energy_before:
		printerr("save integrity failed across flush")
		return 1
	audio.call("set_has_focus", true)

	var holder := Node.new()
	root.add_child(holder)
	var router := root.get_node("SceneRouter")
	router.call("configure", holder)
	router.call("go_to", "main_menu")
	await process_frame
	await process_frame
	if String(router.call("get_current_screen_id")) != "main_menu":
		printerr("main menu failed to open")
		return 1
	# Results screen now applies SafeArea — open standalone.
	router.call("go_to", "results")
	await process_frame
	await process_frame
	if String(router.call("get_current_screen_id")) != "results":
		printerr("results failed to open")
		return 1
	print("lifecycle_screens_ok")
	return 0
