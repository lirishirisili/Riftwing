class_name LevelPlayAdsService
extends AdsService
## Unity LevelPlay adapter (Android + iOS) using the current LevelPlay ad-unit
## APIs. Talks to the native Godot plugin singleton "RiftstrikeLevelPlay" and
## re-emits the typed `AdsService` signals so gameplay/UI stay platform-agnostic.
##
## Responsibilities:
## - Initialize LevelPlay exactly once with the platform app key.
## - Create/prepare banner, interstitial, rewarded objects only after init.
## - Track readiness, auto-reload full-screen ads after they close/fail.
## - Enforce interstitial cadence via `AdFrequencyGate` (session-only state).
## - Grant a rewarded "earned" exactly once per show.
## - Log every step under [LEVELPLAY]/[BANNER]/[INTERSTITIAL]/[REWARDED].

const _SINGLETON_NAME := "RiftstrikeLevelPlay"

var _native: Object = null
var _initialized: bool = false
var _init_in_progress: bool = false

var _interstitial_ready: bool = false
var _rewarded_ready: bool = false

# Guards a single "earned" emission per rewarded show, regardless of the
# platform ordering of reward vs. close callbacks.
var _rewarded_reward_pending: bool = false

var _gate := AdFrequencyGate.new()


func _init() -> void:
	if Engine.has_singleton(_SINGLETON_NAME):
		_native = Engine.get_singleton(_SINGLETON_NAME)


## Test-only: injects a mock native backend implementing the same signal/method
## contract as the platform plugin, so cadence/reload/reward logic is verifiable
## headlessly without a device.
func attach_native_for_test(native: Object) -> void:
	_native = native
	_initialized = false
	_init_in_progress = false


func is_available() -> bool:
	return _native != null


func configure(config: AdsConfig) -> void:
	super.configure(config)
	if config != null:
		_gate.configure(config.runs_per_interstitial, config.minimum_interstitial_seconds)


func initialize() -> void:
	if _native == null:
		_log("LEVELPLAY", "native plugin unavailable; ads disabled on this platform")
		initialization_finished.emit(false)
		return
	if _initialized or _init_in_progress:
		return
	if _config == null:
		_log("LEVELPLAY", "no AdsConfig supplied; aborting init")
		initialization_finished.emit(false)
		return

	var app_key := _config.app_key_for_platform()
	if app_key == "":
		# Editor / dev fallback so the flow is exercisable headlessly. A real
		# Android/iOS device always resolves a platform key above.
		app_key = _config.android_app_key
	if app_key == "":
		_log("LEVELPLAY", "no app key for this platform; aborting init")
		initialization_finished.emit(false)
		return

	_connect_native_signals()
	_init_in_progress = true
	_log("LEVELPLAY", "init app_key=%s" % app_key)
	_native.call(
		"initialize",
		app_key,
		_config.banner_id_for_platform(),
		_config.interstitial_id_for_platform(),
		_config.rewarded_id_for_platform(),
		_config.development_mode)


# --- Banner -----------------------------------------------------------------

func show_banner() -> void:
	if not _initialized:
		return
	_log("BANNER", "load + show")
	_native.call("show_banner")


func hide_banner() -> void:
	if _native == null:
		return
	_native.call("hide_banner")


func destroy_banner() -> void:
	if _native == null:
		return
	_native.call("destroy_banner")


# --- Interstitial -----------------------------------------------------------

func load_interstitial() -> void:
	if not _initialized:
		return
	_interstitial_ready = false
	_log("INTERSTITIAL", "load")
	_native.call("load_interstitial")


func is_interstitial_ready() -> bool:
	return _interstitial_ready and _native != null


func show_interstitial() -> bool:
	if not is_interstitial_ready():
		return false
	_log("INTERSTITIAL", "show")
	_native.call("show_interstitial")
	return true


func handle_run_completed(run_id: String) -> bool:
	if not _initialized:
		return false
	_gate.register_run_completed(run_id)
	var now := _now_seconds()
	if not _gate.can_show_interstitial(now):
		_log("INTERSTITIAL", "run break skipped (runs=%d, since_last=%.1fs)" % [
			_gate.completed_runs(), _gate.seconds_since_last_shown(now)])
		return false
	if not is_interstitial_ready():
		_log("INTERSTITIAL", "run break eligible but not ready; skipping")
		return false
	if show_interstitial():
		_gate.mark_shown(now)
		return true
	return false


# --- Rewarded ---------------------------------------------------------------

func load_rewarded() -> void:
	if not _initialized:
		return
	_rewarded_ready = false
	_log("REWARDED", "load")
	_native.call("load_rewarded")


func is_rewarded_ready() -> bool:
	return _rewarded_ready and _native != null


func show_rewarded() -> bool:
	if not is_rewarded_ready():
		return false
	_rewarded_reward_pending = true
	_log("REWARDED", "show")
	_native.call("show_rewarded")
	return true


# --- App lifecycle ----------------------------------------------------------

func on_app_pause() -> void:
	if _native != null and _native.has_method("on_pause"):
		_native.call("on_pause")


func on_app_resume() -> void:
	if _native != null and _native.has_method("on_resume"):
		_native.call("on_resume")


func launch_test_suite() -> void:
	if _native == null or _config == null or not _config.development_mode:
		return
	if _native.has_method("launch_test_suite"):
		_log("LEVELPLAY", "launch test suite")
		_native.call("launch_test_suite")


# --- Native signal wiring ---------------------------------------------------

func _connect_native_signals() -> void:
	var map := {
		"init_success": _on_init_success,
		"init_failed": _on_init_failed,
		"banner_loaded": _on_banner_loaded,
		"banner_load_failed": _on_banner_failed,
		"banner_clicked": _on_banner_clicked,
		"interstitial_loaded": _on_interstitial_loaded,
		"interstitial_load_failed": _on_interstitial_failed,
		"interstitial_displayed": _on_interstitial_displayed,
		"interstitial_display_failed": _on_interstitial_display_failed,
		"interstitial_closed": _on_interstitial_closed,
		"interstitial_clicked": _on_interstitial_clicked,
		"rewarded_loaded": _on_rewarded_loaded,
		"rewarded_load_failed": _on_rewarded_failed,
		"rewarded_displayed": _on_rewarded_displayed,
		"rewarded_display_failed": _on_rewarded_display_failed,
		"rewarded_closed": _on_rewarded_closed,
		"rewarded_clicked": _on_rewarded_clicked,
		"rewarded_earned": _on_rewarded_earned,
	}
	for sig_name in map.keys():
		if _native.has_signal(sig_name) and not _native.is_connected(sig_name, map[sig_name]):
			_native.connect(sig_name, map[sig_name])


func _on_init_success() -> void:
	_init_in_progress = false
	_initialized = true
	_log("LEVELPLAY", "init success")
	initialization_finished.emit(true)
	# Create/prepare ad objects only after init success.
	load_interstitial()
	load_rewarded()


func _on_init_failed(error: String) -> void:
	_init_in_progress = false
	_initialized = false
	_log("LEVELPLAY", "init failed: %s" % error)
	initialization_finished.emit(false)


func _on_banner_loaded() -> void:
	_log("BANNER", "loaded / impression")
	banner_loaded.emit()


func _on_banner_failed(error: String) -> void:
	_log("BANNER", "failed: %s" % error)
	banner_failed.emit(error)


func _on_banner_clicked() -> void:
	_log("BANNER", "clicked")


func _on_interstitial_loaded() -> void:
	_interstitial_ready = true
	_log("INTERSTITIAL", "ready")
	interstitial_ready.emit()


func _on_interstitial_failed(error: String) -> void:
	_interstitial_ready = false
	_log("INTERSTITIAL", "load failed: %s" % error)
	interstitial_failed.emit(error)


func _on_interstitial_displayed() -> void:
	_interstitial_ready = false
	_log("INTERSTITIAL", "displayed")
	interstitial_displayed.emit()


func _on_interstitial_display_failed(error: String) -> void:
	_interstitial_ready = false
	_log("INTERSTITIAL", "display failed: %s" % error)
	interstitial_failed.emit(error)
	_reload_interstitial()


func _on_interstitial_closed() -> void:
	_log("INTERSTITIAL", "closed")
	interstitial_closed.emit()
	_reload_interstitial()


func _on_interstitial_clicked() -> void:
	_log("INTERSTITIAL", "clicked")


func _on_rewarded_loaded() -> void:
	_rewarded_ready = true
	_log("REWARDED", "ready")
	rewarded_ready.emit()


func _on_rewarded_failed(error: String) -> void:
	_rewarded_ready = false
	_log("REWARDED", "load failed: %s" % error)
	rewarded_failed.emit(error)


func _on_rewarded_displayed() -> void:
	_rewarded_ready = false
	_log("REWARDED", "displayed")
	rewarded_displayed.emit()


func _on_rewarded_display_failed(error: String) -> void:
	_rewarded_ready = false
	_rewarded_reward_pending = false
	_log("REWARDED", "display failed: %s" % error)
	rewarded_failed.emit(error)
	_reload_rewarded()


func _on_rewarded_earned(reward_name: String, amount: int) -> void:
	# Grant exactly once per show, even if the callback repeats or arrives after
	# close. Only the official LevelPlay onAdRewarded / didRewardAd path emits
	# this signal — closed/dismissed never grants.
	if not _rewarded_reward_pending:
		return
	_rewarded_reward_pending = false
	_log("REWARDED", "reward-earned name=%s amount=%d" % [reward_name, amount])
	rewarded_earned.emit()


func _on_rewarded_closed() -> void:
	# Close/dismiss must never grant. Reload the next rewarded ad.
	_log("REWARDED", "closed")
	rewarded_closed.emit()
	_reload_rewarded()


func _on_rewarded_clicked() -> void:
	_log("REWARDED", "clicked")


func _reload_interstitial() -> void:
	_log("INTERSTITIAL", "reload")
	load_interstitial()


func _reload_rewarded() -> void:
	_log("REWARDED", "reload")
	load_rewarded()


func _now_seconds() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


func _log(tag: String, message: String) -> void:
	print("[%s] %s" % [tag, message])
