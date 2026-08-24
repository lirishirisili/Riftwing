extends RefCounted
## Test double for the native "RiftstrikeLevelPlay" plugin singleton.
##
## Implements the exact signal + method contract that `LevelPlayAdsService`
## talks to, and records calls so probes can drive the whole flow (init ->
## load -> ready -> show -> earn/close -> reload) deterministically, with no
## device or SDK.

signal init_success
signal init_failed(error: String)
signal banner_loaded
signal banner_load_failed(error: String)
signal banner_clicked
signal interstitial_loaded
signal interstitial_load_failed(error: String)
signal interstitial_displayed
signal interstitial_display_failed(error: String)
signal interstitial_closed
signal interstitial_clicked
signal rewarded_loaded
signal rewarded_load_failed(error: String)
signal rewarded_displayed
signal rewarded_display_failed(error: String)
signal rewarded_closed
signal rewarded_clicked
signal rewarded_earned(reward_name: String, amount: int)

var initialize_calls: int = 0
var interstitial_load_calls: int = 0
var rewarded_load_calls: int = 0
var interstitial_show_calls: int = 0
var rewarded_show_calls: int = 0
var banner_show_calls: int = 0
var banner_hide_calls: int = 0

var last_app_key: String = ""
var last_banner_id: String = ""
var last_interstitial_id: String = ""
var last_rewarded_id: String = ""


func initialize(app_key: String, banner_id: String, interstitial_id: String, rewarded_id: String, _development: bool) -> void:
	initialize_calls += 1
	last_app_key = app_key
	last_banner_id = banner_id
	last_interstitial_id = interstitial_id
	last_rewarded_id = rewarded_id


func load_interstitial() -> void:
	interstitial_load_calls += 1


func is_interstitial_ready() -> bool:
	return false


func show_interstitial() -> void:
	interstitial_show_calls += 1


func load_rewarded() -> void:
	rewarded_load_calls += 1


func is_rewarded_ready() -> bool:
	return false


func show_rewarded() -> void:
	rewarded_show_calls += 1


func show_banner() -> void:
	banner_show_calls += 1


func hide_banner() -> void:
	banner_hide_calls += 1


func destroy_banner() -> void:
	pass


func on_pause() -> void:
	pass


func on_resume() -> void:
	pass


func launch_test_suite() -> void:
	pass


# --- Test drivers (simulate native callbacks) -------------------------------

func drive_init_success() -> void:
	init_success.emit()


func drive_interstitial_loaded() -> void:
	interstitial_loaded.emit()


func drive_interstitial_closed() -> void:
	interstitial_closed.emit()


func drive_rewarded_loaded() -> void:
	rewarded_loaded.emit()


func drive_rewarded_earned(name: String, amount: int) -> void:
	rewarded_earned.emit(name, amount)


func drive_rewarded_closed() -> void:
	rewarded_closed.emit()
