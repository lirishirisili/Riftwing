extends SceneTree
## Validates AdsService wiring without requiring a device SDK.
## godot --headless --path . --script res://tests/ads_service_probe.gd


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("ads_service_probe: start")
	var failed := 0
	failed += _check_files()
	failed += _check_runtime()
	if failed == 0:
		print("ADS_SERVICE_PROBE_OK")
		quit(0)
	else:
		printerr("ADS_SERVICE_PROBE_FAILED count=%d" % failed)
		quit(1)


func _check_files() -> int:
	var fails := 0
	for path in [
		"res://addons/admob/plugin.cfg",
		"res://addons/admob/android/config.gd",
		"res://addons/admob/android/bin/package.gd",
		"res://ios/plugins/poing-godot-admob-ads.gdip",
		"res://scripts/services/admob_ids.gd",
		"res://scripts/services/admob_ads_service.gd",
	]:
		if not FileAccess.file_exists(path):
			printerr("missing %s" % path)
			fails += 1
	var android_cfg := FileAccess.get_file_as_string("res://addons/admob/android/config.gd")
	if android_cfg.find("ca-app-pub-1194823418071986~7112201236") < 0:
		printerr("Android App ID missing from config.gd")
		fails += 1
	var ios_cfg := FileAccess.get_file_as_string("res://ios/plugins/poing-godot-admob-ads.gdip")
	if ios_cfg.find("ca-app-pub-1194823418071986~3724188783") < 0:
		printerr("iOS App ID missing from gdip")
		fails += 1
	if ios_cfg.find("NSUserTrackingUsageDescription") < 0:
		printerr("iOS NSUserTrackingUsageDescription missing from gdip")
		fails += 1
	if ios_cfg.find("AppTrackingTransparency.framework") < 0:
		printerr("iOS AppTrackingTransparency.framework missing from gdip")
		fails += 1
	var ads_svc := FileAccess.get_file_as_string("res://scripts/services/admob_ads_service.gd")
	if ads_svc.find("UserMessagingPlatform") < 0:
		printerr("AdMobAdsService missing UMP consent flow")
		fails += 1
	if ads_svc.find("_gather_consent_then_initialize_sdk") < 0:
		printerr("AdMobAdsService missing consent-before-init path")
		fails += 1
	var export_cfg := FileAccess.get_file_as_string("res://export_presets.cfg")
	if export_cfg.find("NSUserTrackingUsageDescription") < 0:
		printerr("export_presets missing NSUserTrackingUsageDescription")
		fails += 1
	var results := FileAccess.get_file_as_string("res://scripts/ui/results_screen.gd")
	if results.find("WATCH FOR x2") < 0 and results.find("DoubleRewards") < 0:
		printerr("results missing rewarded CTA wiring")
		fails += 1
	if results.find("note_run_completed") < 0:
		printerr("results missing interstitial pacing")
		fails += 1
	var menu := FileAccess.get_file_as_string("res://scripts/ui/main_menu.gd")
	if menu.find("show_banner") >= 0 or menu.find("_show_menu_banner") >= 0:
		printerr("main menu still hooks banner ads")
		fails += 1
	print("files_ok")
	return fails


func _check_runtime() -> int:
	var fails := 0
	var platform := root.get_node("PlatformServices")
	var ads: AdsService = platform.get("ads")
	if ads == null:
		printerr("PlatformServices.ads missing")
		return 1
	# Desktop/editor must stay no-op and never crash.
	if ads.is_available():
		printerr("desktop ads unexpectedly available")
		fails += 1
	if ads.show_rewarded():
		printerr("no-op rewarded should return false")
		fails += 1
	if ads.show_interstitial():
		printerr("no-op interstitial should return false")
		fails += 1
	ads.show_banner()
	ads.hide_banner()

	var sm := root.get_node("SaveManager")
	sm.call("reset")
	var c1: int = sm.call("note_run_completed")
	var c2: int = sm.call("note_run_completed")
	var c3: int = sm.call("note_run_completed")
	if c1 != 1 or c2 != 2 or c3 != 3:
		printerr("run counter wrong %d %d %d" % [c1, c2, c3])
		fails += 1
	if not bool(sm.call("should_show_interstitial_for_latest_run")):
		printerr("interstitial should trigger on run 3")
		fails += 1
	sm.call("note_run_completed")
	if bool(sm.call("should_show_interstitial_for_latest_run")):
		printerr("interstitial should not trigger on run 4")
		fails += 1

	if AdMobIds.INTERSTITIAL_EVERY_N_RUNS != 3:
		printerr("expected every 3 runs")
		fails += 1
	print("runtime_ok")
	return fails
