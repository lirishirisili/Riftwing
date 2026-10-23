extends SceneTree
## Proves the M6 onboarding / ads / privacy pass:
## - RewardedAd grants ONLY on the SDK reward callback (close never grants),
##   including a reward that arrives after close.
## - Revive: offered once per run, pauses combat, revives with HP, a second
##   death ends the run.
## - Results x2 is granted once per run id.
## - Interstitial guard rails (new-player grace runs, after a revive offer).
## - Privacy choice gates ads start and is stored; first-run tutorial hint.
## Works on a save copy and restores it.
## godot --headless --path . --script res://tests/monetization_probe.gd

var _save: Node
var _backup: Dictionary


class CountingAds extends AdsService:
	var run_breaks: int = 0
	var consent_calls: int = 0
	var last_consent: bool = true

	func handle_run_completed(_run_id: String) -> bool:
		run_breaks += 1
		return false

	func set_consent(consent: bool) -> void:
		consent_calls += 1
		last_consent = consent


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("monetization_probe: start")
	_save = root.get_node("SaveManager")
	_backup = (_save.get("_data") as Dictionary).duplicate(true)
	var failed := 0
	failed += await _check_reward_contract()
	failed += await _check_revive()
	failed += await _check_double_and_interstitial()
	failed += _check_privacy()
	failed += await _check_tutorial()
	_rewarded().simulate = false
	_save.set("_data", _backup)
	_save.call("save_game")
	if failed == 0:
		print("MONETIZATION_PROBE_OK")
		quit(0)
	else:
		printerr("MONETIZATION_PROBE_FAILED count=%d" % failed)
		quit(1)


func _rewarded():
	return load("res://scripts/services/rewarded_ad.gd")


func _check_reward_contract() -> int:
	var fails := 0
	var platform: Node = root.get_node("PlatformServices")
	var original: Object = platform.get("ads")
	var svc = load("res://scripts/services/levelplay_ads_service.gd").new()
	var mock = load("res://tests/mocks/mock_levelplay_native.gd").new()
	svc.attach_native_for_test(mock)
	svc.configure(load("res://resources/ads/levelplay_ads_config.tres"))
	svc.initialize()
	mock.drive_init_success()
	mock.drive_rewarded_loaded()
	platform.set("ads", svc)
	var R = _rewarded()
	R.simulate = false
	var granted := [0]
	var done := [null]
	# 1) Close without a reward never grants.
	if not R.show("probe", func() -> void: granted[0] += 1, func(ok: bool) -> void: done[0] = ok):
		printerr("rewarded show refused with a loaded ad")
		fails += 1
	mock.drive_rewarded_closed()
	var until := Time.get_ticks_msec() + 2200
	while Time.get_ticks_msec() < until and done[0] == null:
		await process_frame
	if granted[0] != 0 or done[0] != false:
		printerr("close without reward granted=%d done=%s" % [granted[0], str(done[0])])
		fails += 1
	# 2) Reward after close still grants (late callback window).
	mock.drive_rewarded_loaded()
	done[0] = null
	R.show("probe", func() -> void: granted[0] += 1, func(ok: bool) -> void: done[0] = ok)
	mock.drive_rewarded_closed()
	await process_frame
	mock.drive_rewarded_earned("Reward", 1)
	until = Time.get_ticks_msec() + 2200
	while Time.get_ticks_msec() < until and done[0] == null:
		await process_frame
	if granted[0] != 1 or done[0] != true:
		printerr("late reward not granted exactly once granted=%d done=%s" % [granted[0], str(done[0])])
		fails += 1
	platform.set("ads", original)
	if fails == 0:
		print("reward_contract_ok close-never-grants + late reward")
	return fails


func _mount_run() -> Node:
	var scene = load("res://scenes/gameplay/run_scene.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	return scene


func _check_revive() -> int:
	var fails := 0
	_rewarded().simulate = true
	var scene: Node = await _mount_run()
	var player = scene.get_node("PlayerShip")
	var hud = scene.get_node("UI/GameplayHUD")
	player.force_kill()
	await process_frame
	if not hud.is_revive_offer_open() or not paused:
		printerr("revive not offered on first death (open=%s paused=%s)" % [hud.is_revive_offer_open(), paused])
		fails += 1
	hud.hide_revive_offer()
	hud.revive_accepted.emit()
	await process_frame
	if not player.is_alive() or paused:
		printerr("revive did not restore the ship / unpause")
		fails += 1
	player.force_kill()
	await process_frame
	if hud.is_revive_offer_open() or not bool(scene.get("_run_over")):
		printerr("second death did not end the run")
		fails += 1
	if not scene.call("get_run_stats").revive_offered:
		printerr("revive_offered not recorded")
		fails += 1
	scene.queue_free()
	paused = false
	await process_frame
	if fails == 0:
		print("revive_ok once per run")
	return fails


func _check_double_and_interstitial() -> int:
	var fails := 0
	var platform: Node = root.get_node("PlatformServices")
	var original: Object = platform.get("ads")
	var counting := CountingAds.new()
	platform.set("ads", counting)
	_rewarded().simulate = true
	var stats = load("res://scripts/progression/run_stats.gd").new()
	stats.run_id = "monetization_probe_%d" % Time.get_ticks_msec()
	stats.victory = true
	stats.enemies_destroyed = 30
	var router: Node = root.get_node("SceneRouter")
	var holder := Node.new()
	root.add_child(holder)
	router.call("configure", holder)
	router.call("go_to", "results", {"stats": stats})
	await process_frame
	await process_frame
	var results: Node = holder.get_child(0)
	var energy0: int = _save.call("get_rift_energy")
	var btn = results.find_child("DoubleRewards", true, false)
	if btn == null:
		printerr("x2 rewards button missing")
		fails += 1
	else:
		results.call("_on_double_reward")
		results.call("_on_double_reward")
		var gained: int = int(_save.call("get_rift_energy")) - energy0
		if gained != stats.rewards.rift_energy:
			printerr("x2 granted %d (want exactly %d once)" % [gained, stats.rewards.rift_energy])
			fails += 1
	# Grace runs: a brand-new pilot sees no interstitial.
	_save.call("section", "lifetime")["runs"] = 1
	results.set("_watched_rewarded", false)
	results.call("_maybe_run_break_interstitial")
	if counting.run_breaks != 0:
		printerr("interstitial considered during grace runs")
		fails += 1
	_save.call("section", "lifetime")["runs"] = 20
	results.call("_maybe_run_break_interstitial")
	if counting.run_breaks != 1:
		printerr("interstitial not considered for a veteran (%d)" % counting.run_breaks)
		fails += 1
	stats.revive_offered = true
	results.call("_maybe_run_break_interstitial")
	if counting.run_breaks != 1:
		printerr("interstitial considered after a revive offer")
		fails += 1
	router.call("go_to", "main_menu")
	await process_frame
	platform.set("ads", original)
	if fails == 0:
		print("double_ok once per run + interstitial guard rails")
	return fails


func _check_privacy() -> int:
	var platform: Node = root.get_node("PlatformServices")
	var original: Object = platform.get("ads")
	var counting := CountingAds.new()
	platform.set("ads", counting)
	platform.set("_ads_started", true)
	platform.call("apply_privacy", false)
	var ok: bool = counting.consent_calls == 1 and not counting.last_consent \
		and bool(_save.call("section", "privacy")["asked"]) and not bool(platform.call("get_ads_consent"))
	platform.set("ads", original)
	if not ok:
		printerr("privacy choice not applied / stored")
		return 1
	print("privacy_ok")
	return 0


func _check_tutorial() -> int:
	var t: Dictionary = _save.call("section", "tutorial")
	t["drag"] = false
	_rewarded().simulate = false
	var scene: Node = await _mount_run()
	var hint = scene.get_node("UI/GameplayHUD").find_child("TutorialHint", true, false)
	var fails := 0
	if hint == null or not hint.visible:
		printerr("drag hint not shown on a fresh pilot")
		fails += 1
	scene.get_node("PlayerShip").drag_started.emit()
	if hint != null and hint.visible:
		printerr("drag hint did not hide on first drag")
		fails += 1
	if not bool(t.get("drag", false)):
		printerr("drag tutorial not marked seen")
		fails += 1
	scene.queue_free()
	await process_frame
	if fails == 0:
		print("tutorial_ok")
	return fails
