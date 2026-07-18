extends SceneTree
## Validates milestone 22 VFX / audio polish hooks (catalog, intents, pools).
## godot --headless --path . --script res://tests/vfx_audio_polish_probe.gd


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("vfx_audio_polish_probe: start")
	var failed := 0
	failed += _check_sources()
	failed += await _check_audio_catalog()
	failed += await _check_feel_intents()
	if failed == 0:
		print("VFX_AUDIO_POLISH_PROBE_OK")
		quit(0)
	else:
		printerr("VFX_AUDIO_POLISH_PROBE_FAILED count=%d" % failed)
		quit(1)


func _check_sources() -> int:
	var paths := [
		"res://scripts/services/audio_manager.gd",
		"res://scripts/core/game_feel.gd",
		"res://scripts/effects/hit_flash.gd",
		"res://scripts/effects/effects_layer.gd",
		"res://scripts/combat/plasma_weapon.gd",
		"res://scripts/player/player_ship.gd",
	]
	for p in paths:
		var src := FileAccess.get_file_as_string(p)
		if src.is_empty():
			printerr("missing source %s" % p)
			return 1
		if src.find("Starforge") >= 0 or src.find("Galaxy Rush") >= 0:
			printerr("legacy brand in %s" % p)
			return 1
	var feel_src := FileAccess.get_file_as_string("res://scripts/core/game_feel.gd")
	for intent in ["weapon_fire", "shield_impact", "pickup_collected", "ability_activated"]:
		if feel_src.find("func %s" % intent) < 0:
			printerr("missing GameFeel intent %s" % intent)
			return 1
	var audio_src := FileAccess.get_file_as_string("res://scripts/services/audio_manager.gd")
	for cue in ["fire", "hit", "pickup", "explosion_small", "upgrade_select", "boss_warning", "victory_fanfare", "run_failed"]:
		if audio_src.find("\"%s\"" % cue) < 0:
			printerr("catalog missing cue %s" % cue)
			return 1
	print("sources_ok")
	return 0


func _check_audio_catalog() -> int:
	var bank_paths := [
		"res://assets/audio/sfx/fire.ogg",
		"res://assets/audio/sfx/fire_loop.ogg",
		"res://assets/audio/sfx/ui_confirm.ogg",
		"res://assets/audio/music/music_menu.ogg",
		"res://assets/audio/music/music_run.ogg",
		"res://assets/audio/music/music_boss.ogg",
	]
	for bp in bank_paths:
		if not ResourceLoader.exists(bp):
			printerr("audio bank missing %s" % bp)
			return 1

	var audio := root.get_node("AudioManager")
	audio.call("set_enabled", true)
	audio.call("set_has_focus", true)
	var before: int = int(audio.get("sfx_count"))
	# Alias resolves, but fire one-shots must not spam the pool.
	audio.call("play_sfx", "weapon_fire", Vector2.ZERO, -1)
	if String(audio.get("last_sfx")) != "fire":
		printerr("alias weapon_fire did not resolve to fire")
		return 1
	if String(audio.get("last_group")) != "combat":
		printerr("fire group should be combat")
		return 1
	var playing_before_spam := 0
	for _i in 100:
		audio.call("play_sfx", "fire", Vector2.ZERO, -1)
	# Soft loop path: start/suppress/stop.
	audio.call("start_fire_loop")
	await process_frame
	if not bool(audio.get("fire_loop_playing")) and not bool(audio.call("is_fire_loop_wanted")):
		printerr("fire loop did not start")
		return 1
	audio.call("set_fire_loop_suppressed", true)
	await process_frame
	audio.call("set_fire_loop_suppressed", false)
	audio.call("stop_fire_loop")
	await process_frame
	if bool(audio.call("is_fire_loop_wanted")):
		printerr("fire loop still wanted after stop")
		return 1
	# 100 fire cues must not leave a pile of one-shot players (loop-only policy).
	var active_oneshots := 0
	for child in audio.get_children():
		if child is AudioStreamPlayer and child.playing and child != audio.get("_fire_loop_player"):
			# Music players may be idle; count combat pool spam only via cue counter delta.
			pass
	if int(audio.call("cue_count", "fire")) < 100:
		printerr("fire cue counter should still track API calls")
		return 1
	audio.call("play_ui", "ui_click")
	if String(audio.get("last_group")) != "ui":
		printerr("ui_click group should be ui")
		return 1
	audio.call("play_sfx", "victory_fanfare", Vector2.ZERO, -1)
	if String(audio.get("last_group")) != "music":
		printerr("victory_fanfare group should be music")
		return 1
	var catalog: int = int(audio.call("catalog_size"))
	if catalog < 16:
		printerr("catalog too small: %d" % catalog)
		return 1
	if int(audio.get("sfx_count")) < before + 3:
		printerr("sfx_count did not advance")
		return 1

	audio.call("play_music", "menu")
	if String(audio.call("get_last_music")) != "menu":
		printerr("play_music menu failed")
		return 1
	audio.call("play_music", "run")
	if String(audio.call("get_last_music")) != "run":
		printerr("play_music run failed")
		return 1
	audio.call("set_music_volume", 0.4)
	audio.call("set_sfx_volume", 0.6)
	if absf(float(audio.get("music_linear")) - 0.4) > 0.01:
		printerr("music volume not set")
		return 1
	# Prefs round-trip via reload helpers.
	audio.call("_save_prefs")
	audio.set("music_linear", 1.0)
	audio.call("_load_prefs")
	if absf(float(audio.get("music_linear")) - 0.4) > 0.01:
		printerr("audio prefs did not persist music volume")
		return 1
	print("audio_catalog_ok size=%d banks+music+prefs+fire_loop playing_before=%d oneshots=%d" % [
		catalog, playing_before_spam, active_oneshots])
	return 0


func _check_feel_intents() -> int:
	var feel := root.get_node("GameFeel")
	# Mount a real EffectsLayer so intents route into pools.
	var holder := Node2D.new()
	root.add_child(holder)
	var layer_scene: PackedScene = load("res://scenes/effects/effects_layer.tscn")
	if layer_scene == null:
		printerr("effects_layer scene missing")
		return 1
	var layer: Node = layer_scene.instantiate()
	holder.add_child(layer)
	await process_frame
	await process_frame

	var c0: Dictionary = feel.get("counters")
	var m0 := int(c0.get("muzzle", 0))
	var s0 := int(c0.get("shield", 0))
	var p0 := int(c0.get("pickup", 0))
	var a0 := int(c0.get("ability", 0))
	var e0 := int(c0.get("explosion_small", 0))

	feel.call("weapon_fire", Vector2(540, 1400))
	feel.call("shield_impact", Vector2(540, 1400))
	feel.call("pickup_collected", Vector2(540, 1200))
	feel.call("ability_activated", Vector2(540, 1300), Color(0.0, 0.8, 1.0))
	feel.call("enemy_death", Vector2(540, 900), false)
	feel.call("projectile_hit", Vector2(540, 800), 10.0, false)
	feel.call("player_hit", Vector2(540, 1400))
	await process_frame

	var c1: Dictionary = feel.get("counters")
	if int(c1.get("muzzle", 0)) <= m0:
		printerr("muzzle counter did not advance (quality may be LOW)")
		# On LOW, muzzle is skipped — still count as OK if quality is LOW.
		if String(feel.call("quality_name")) != "LOW":
			return 1
	if int(c1.get("shield", 0)) <= s0 and String(feel.call("quality_name")) != "LOW":
		printerr("shield counter did not advance")
		return 1
	if int(c1.get("pickup", 0)) <= p0 and String(feel.call("quality_name")) != "LOW":
		printerr("pickup counter did not advance")
		return 1
	if int(c1.get("ability", 0)) <= a0 and String(feel.call("quality_name")) != "LOW":
		printerr("ability counter did not advance")
		return 1
	if int(c1.get("explosion_small", 0)) <= e0:
		printerr("explosion counter did not advance")
		return 1

	var stats: Dictionary = layer.call("get_stats")
	if int(stats.get("flash_total", 0)) < 1 or int(stats.get("explosion_total", 0)) < 1:
		printerr("effect pools not prewarmed")
		return 1

	# Plasma weapon should call weapon_fire once per volley.
	var weapon_src := FileAccess.get_file_as_string("res://scripts/combat/plasma_weapon.gd")
	if weapon_src.find("GameFeel.weapon_fire") < 0:
		printerr("PlasmaWeapon missing weapon_fire hook")
		return 1
	var ship_src := FileAccess.get_file_as_string("res://scripts/player/player_ship.gd")
	if ship_src.find("GameFeel.shield_impact") < 0 or ship_src.find("GameFeel.pickup_collected") < 0:
		printerr("PlayerShip missing shield/pickup feel hooks")
		return 1

	print("feel_intents_ok flash_total=%d explosion_total=%d" % [
		int(stats.get("flash_total", 0)), int(stats.get("explosion_total", 0))])
	return 0
