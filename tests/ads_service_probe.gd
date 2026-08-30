extends SceneTree
## Verifies the LevelPlay ads integration deterministically, without a device:
## - Config exposes the confirmed app keys + ad unit ids.
## - Interstitial cadence policy (no 1st-run ad, every 2 runs, 90s cooldown, id dedupe).
## - Service init ordering, ad creation only after init, auto-reload, and
##   exactly-once rewarded grant from the LevelPlay earned callback (never close).
## - Meta FAN + Unity Ads participate only as LevelPlay adapters.
## - ATT purpose string is declared for Meta advertiser tracking.
## godot --headless --path . --script res://tests/ads_service_probe.gd

const _MOCK := preload("res://tests/mocks/mock_levelplay_native.gd")
const _CONFIG_PATH := "res://resources/ads/levelplay_ads_config.tres"

var _rewarded_earned_count: int = 0
var _init_success_seen: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("ads_service_probe: start")
	var failed := 0
	failed += _check_files()
	failed += _check_config()
	failed += _check_frequency_gate()
	failed += _check_service_flow()
	failed += _check_noop_base()
	if failed == 0:
		print("ADS_SERVICE_PROBE_OK")
		quit(0)
	else:
		printerr("ADS_SERVICE_PROBE_FAILED count=%d" % failed)
		quit(1)


func _check_files() -> int:
	var fails := 0
	# LevelPlay integration files must exist.
	for path in [
		"res://scripts/services/ads_config.gd",
		"res://scripts/services/ad_frequency_gate.gd",
		"res://scripts/services/levelplay_ads_service.gd",
		"res://resources/ads/levelplay_ads_config.tres",
		"res://native/levelplay/android/plugin/src/main/java/com/lishistudio/riftwing/levelplay/RiftstrikeLevelPlayPlugin.kt",
		"res://native/levelplay/ios/riftstrike_levelplay.mm",
		"res://native/levelplay/android/plugin/src/main/res/xml/network_security_config.xml",
	]:
		if not FileAccess.file_exists(path):
			printerr("expected LevelPlay file missing: %s" % path)
			fails += 1
	# Legacy AdMob must stay inactive.
	for path in [
		"res://scripts/services/admob_ids.gd",
		"res://scripts/services/admob_ads_service.gd",
		"res://ios/plugins/poing-godot-admob-ads.gdip",
		"res://ios/plugins/poing-godot-admob-meta.gdip",
		"res://ios/plugins/poing-godot-admob-vungle.gdip",
	]:
		if FileAccess.file_exists(path):
			printerr("legacy AdMob file active: %s" % path)
			fails += 1
	var project := FileAccess.get_file_as_string("res://project.godot")
	if project.find("addons/admob/plugin.cfg") >= 0:
		printerr("AdMob editor plugin still enabled in project.godot")
		fails += 1
	var export_cfg := FileAccess.get_file_as_string("res://export_presets.cfg")
	if export_cfg.find("NSUserTrackingUsageDescription") < 0:
		printerr("export_presets missing NSUserTrackingUsageDescription (required for Meta ATT)")
		fails += 1
	var gdip := FileAccess.get_file_as_string("res://native/levelplay/ios/RiftstrikeLevelPlay.gdip.template")
	if gdip.find("NSUserTrackingUsageDescription") < 0:
		printerr("LevelPlay gdip missing NSUserTrackingUsageDescription")
		fails += 1
	var platform := FileAccess.get_file_as_string("res://scripts/services/platform_services.gd")
	if platform.find("AdMobAdsService") >= 0:
		printerr("PlatformServices still references AdMobAdsService")
		fails += 1
	if platform.find("LevelPlayAdsService") < 0:
		printerr("PlatformServices does not wire LevelPlayAdsService")
		fails += 1
	# Results must not call ad show APIs directly (policy is centralized).
	var results := FileAccess.get_file_as_string("res://scripts/ui/results_screen.gd")
	if results.find("show_rewarded") >= 0 or results.find("show_interstitial") >= 0:
		printerr("results still calls ad show APIs directly")
		fails += 1
	var gdap := FileAccess.get_file_as_string("res://native/levelplay/android/dist/RiftstrikeLevelPlay.gdap")
	if gdap.find("facebook-adapter:5.4.0") < 0:
		printerr("gdap missing LevelPlay facebook-adapter 5.4.0")
		fails += 1
	if gdap.find("audience-network-sdk:6.22.0") < 0:
		printerr("gdap missing Meta FAN SDK 6.22.0")
		fails += 1
	if gdap.find("unityads-adapter:5.5.0") < 0:
		printerr("gdap missing LevelPlay unityads-adapter")
		fails += 1
	var nsc := FileAccess.get_file_as_string("res://native/levelplay/android/plugin/src/main/res/xml/network_security_config.xml")
	if nsc.find("127.0.0.1") < 0:
		printerr("network_security_config missing 127.0.0.1 cleartext for Meta FAN")
		fails += 1
	var ios_mm := FileAccess.get_file_as_string("res://native/levelplay/ios/riftstrike_levelplay.mm")
	if ios_mm.find("ATTrackingManager") < 0 or ios_mm.find("setAdvertiserTrackingEnabled") < 0:
		printerr("iOS bridge missing ATT / Meta advertiser tracking before init")
		fails += 1
	if ios_mm.find("initWithRequest") < 0:
		printerr("iOS bridge missing LevelPlay init")
		fails += 1
	var android_kt := FileAccess.get_file_as_string("res://native/levelplay/android/plugin/src/main/java/com/lishistudio/riftwing/levelplay/RiftstrikeLevelPlayPlugin.kt")
	if android_kt.find("import com.unity3d.ads.UnityAds") >= 0 or android_kt.find("import com.facebook.ads") >= 0:
		printerr("Android bridge still loads Unity Ads or Meta FAN directly")
		fails += 1
	if android_kt.find("LevelPlay.init") < 0:
		printerr("Android bridge missing LevelPlay.init")
		fails += 1
	var ads_config_src := FileAccess.get_file_as_string("res://scripts/services/ads_config.gd")
	for meta_placement in [
		"1001621046236414",
		"1001621049569747",
		"1001621052903080",
		"1001621062903079",
		"1001621069569745",
		"1001621066236412",
	]:
		if ads_config_src.find(meta_placement) >= 0:
			printerr("ads_config contains Meta placement id %s (must stay dashboard-only)" % meta_placement)
			fails += 1
	print("files_ok")
	return fails


func _check_config() -> int:
	var fails := 0
	var config: AdsConfig = load(_CONFIG_PATH) as AdsConfig
	if config == null:
		printerr("ads config failed to load")
		return 1
	var expected := {
		"android_app_key": "27c3b0395",
		"android_banner_id": "jqgg68ya19n3ytgi",
		"android_interstitial_id": "rbll62fz9v6c3g8z",
		"android_rewarded_id": "0kp8369fne1aw2cr",
		"ios_app_key": "27c3aca0d",
		"ios_banner_id": "05n2yrznzri2l1pp",
		"ios_interstitial_id": "tarcjz9o8di0xoe7",
		"ios_rewarded_id": "xqcirr4y800m8wpy",
	}
	for key in expected.keys():
		if String(config.get(key)) != expected[key]:
			printerr("config %s = %s, expected %s" % [key, config.get(key), expected[key]])
			fails += 1
	if config.runs_per_interstitial != 2:
		printerr("runs_per_interstitial should be 2")
		fails += 1
	if not is_equal_approx(config.minimum_interstitial_seconds, 90.0):
		printerr("minimum_interstitial_seconds should be 90")
		fails += 1
	print("config_ok")
	return fails


func _check_frequency_gate() -> int:
	var fails := 0
	var gate := AdFrequencyGate.new()
	gate.configure(2, 90.0)
	# Run 1: never (first run).
	gate.register_run_completed("r1")
	if gate.can_show_interstitial(100.0):
		printerr("gate allowed interstitial after first run")
		fails += 1
	# Run 2: eligible.
	gate.register_run_completed("r2")
	if not gate.can_show_interstitial(100.0):
		printerr("gate blocked eligible interstitial at run 2")
		fails += 1
	gate.mark_shown(100.0)
	# Run 3: cadence blocks (odd).
	gate.register_run_completed("r3")
	if gate.can_show_interstitial(200.0):
		printerr("gate allowed interstitial at run 3 (cadence)")
		fails += 1
	# Run 4: cadence ok but cooldown (<90s) blocks.
	gate.register_run_completed("r4")
	if gate.can_show_interstitial(150.0):
		printerr("gate ignored 90s cooldown")
		fails += 1
	# Run 4 after cooldown: eligible.
	if not gate.can_show_interstitial(200.0):
		printerr("gate blocked run 4 after cooldown elapsed")
		fails += 1
	# Duplicate run id must not advance the counter.
	var gate2 := AdFrequencyGate.new()
	gate2.configure(2, 90.0)
	gate2.register_run_completed("dup")
	if gate2.register_run_completed("dup"):
		printerr("gate double-counted a duplicate run id")
		fails += 1
	if gate2.completed_runs() != 1:
		printerr("gate completed_runs should be 1 after duplicate")
		fails += 1
	print("frequency_gate_ok")
	return fails


func _check_service_flow() -> int:
	var fails := 0
	var config: AdsConfig = load(_CONFIG_PATH) as AdsConfig
	var svc := LevelPlayAdsService.new()
	var mock = _MOCK.new()
	svc.configure(config)
	svc.attach_native_for_test(mock)

	_init_success_seen = false
	_rewarded_earned_count = 0
	svc.initialization_finished.connect(func(success: bool): _init_success_seen = success)
	svc.rewarded_earned.connect(func(): _rewarded_earned_count += 1)

	if not svc.is_available():
		printerr("service should be available with a native backend")
		fails += 1

	# Init once; ad objects are created (loaded) only after init success.
	svc.initialize()
	if mock.initialize_calls != 1:
		printerr("initialize not called exactly once")
		fails += 1
	if mock.interstitial_load_calls != 0 or mock.rewarded_load_calls != 0:
		printerr("ads loaded before init success")
		fails += 1

	mock.drive_init_success()
	if not _init_success_seen:
		printerr("initialization_finished(true) not emitted")
		fails += 1
	if mock.interstitial_load_calls != 1 or mock.rewarded_load_calls != 1:
		printerr("ads not loaded after init success")
		fails += 1

	# Duplicate initialize must be ignored.
	svc.initialize()
	if mock.initialize_calls != 1:
		printerr("duplicate initialize was not prevented")
		fails += 1

	# Ready state follows the loaded callbacks.
	if svc.is_interstitial_ready() or svc.is_rewarded_ready():
		printerr("ads reported ready before loaded callback")
		fails += 1
	mock.drive_interstitial_loaded()
	mock.drive_rewarded_loaded()
	if not svc.is_interstitial_ready() or not svc.is_rewarded_ready():
		printerr("ads not ready after loaded callback")
		fails += 1

	# Cadence via handle_run_completed (interstitial is ready).
	if svc.handle_run_completed("run1"):
		printerr("interstitial shown after first run")
		fails += 1
	if not svc.handle_run_completed("run2"):
		printerr("interstitial not shown at run 2")
		fails += 1
	if mock.interstitial_show_calls != 1:
		printerr("interstitial show not called exactly once at run 2")
		fails += 1
	if svc.handle_run_completed("run3"):
		printerr("interstitial shown at run 3 (cadence)")
		fails += 1
	if svc.handle_run_completed("run4"):
		printerr("interstitial shown at run 4 (cooldown)")
		fails += 1

	# Auto-reload after close.
	var loads_before: int = mock.interstitial_load_calls
	mock.drive_interstitial_closed()
	if mock.interstitial_load_calls != loads_before + 1:
		printerr("interstitial not reloaded after close")
		fails += 1

	# Rewarded: exactly-once earned, even if the callback repeats.
	if not svc.show_rewarded():
		printerr("show_rewarded should succeed when ready")
		fails += 1
	if mock.rewarded_show_calls != 1:
		printerr("rewarded show not called once")
		fails += 1
	mock.drive_rewarded_earned("coins", 1)
	mock.drive_rewarded_earned("coins", 1)
	if _rewarded_earned_count != 1:
		printerr("rewarded_earned emitted %d times, expected exactly 1" % _rewarded_earned_count)
		fails += 1
	var rew_loads_before: int = mock.rewarded_load_calls
	mock.drive_rewarded_closed()
	if mock.rewarded_load_calls != rew_loads_before + 1:
		printerr("rewarded not reloaded after close")
		fails += 1
	if _rewarded_earned_count != 1:
		printerr("rewarded close granted a reward")
		fails += 1

	# Close without an earned callback must not grant.
	mock.drive_rewarded_loaded()
	if not svc.show_rewarded():
		printerr("second show_rewarded should succeed after reload")
		fails += 1
	mock.drive_rewarded_closed()
	if _rewarded_earned_count != 1:
		printerr("close-without-earned granted a reward")
		fails += 1

	print("service_flow_ok")
	return fails


func _check_noop_base() -> int:
	var fails := 0
	var ads := AdsService.new()
	if ads.is_available():
		printerr("base AdsService should not be available")
		fails += 1
	if ads.show_rewarded():
		printerr("no-op rewarded should return false")
		fails += 1
	if ads.show_interstitial():
		printerr("no-op interstitial should return false")
		fails += 1
	if ads.handle_run_completed("x"):
		printerr("no-op handle_run_completed should return false")
		fails += 1
	ads.show_banner()
	ads.hide_banner()
	print("noop_base_ok")
	return fails
