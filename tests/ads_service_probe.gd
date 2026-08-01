extends SceneTree
## Confirms ads stay disabled (no AdMob wiring, no Results ad CTA).
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
		"res://scripts/services/admob_ids.gd",
		"res://scripts/services/admob_ads_service.gd",
		"res://ios/plugins/poing-godot-admob-ads.gdip",
		"res://ios/plugins/poing-godot-admob-meta.gdip",
		"res://ios/plugins/poing-godot-admob-vungle.gdip",
	]:
		if FileAccess.file_exists(path):
			printerr("ad SDK file still active: %s" % path)
			fails += 1
	var project := FileAccess.get_file_as_string("res://project.godot")
	if project.find("addons/admob/plugin.cfg") >= 0:
		printerr("AdMob editor plugin still enabled in project.godot")
		fails += 1
	var export_cfg := FileAccess.get_file_as_string("res://export_presets.cfg")
	if export_cfg.find("NSUserTrackingUsageDescription") >= 0:
		printerr("export_presets still declares NSUserTrackingUsageDescription")
		fails += 1
	var platform := FileAccess.get_file_as_string("res://scripts/services/platform_services.gd")
	if platform.find("AdMobAdsService") >= 0:
		printerr("PlatformServices still references AdMobAdsService")
		fails += 1
	var results := FileAccess.get_file_as_string("res://scripts/ui/results_screen.gd")
	if results.find("show_rewarded") >= 0 or results.find("show_interstitial") >= 0:
		printerr("results still calls ad show APIs")
		fails += 1
	if results.find("DoubleRewards") >= 0 or results.find("WATCH FOR x2") >= 0:
		printerr("results still wires rewarded CTA")
		fails += 1
	var scene := FileAccess.get_file_as_string("res://scenes/ui/results_screen.tscn")
	if scene.find("DoubleRewards") >= 0 or scene.find("RewardAdRow") >= 0:
		printerr("results scene still has rewarded ad row")
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
	if ads.is_available():
		printerr("ads unexpectedly available")
		fails += 1
	if ads.show_rewarded():
		printerr("no-op rewarded should return false")
		fails += 1
	if ads.show_interstitial():
		printerr("no-op interstitial should return false")
		fails += 1
	ads.show_banner()
	ads.hide_banner()
	print("runtime_ok")
	return fails
