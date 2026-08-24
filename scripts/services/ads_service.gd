class_name AdsService
extends RefCounted
## Advertising interface. Gameplay/UI talk only to this contract.
##
## This base implementation is a safe no-op used on editor/desktop builds and
## whenever the native LevelPlay plugin is missing, so gameplay code never has
## to branch on platform. The real mediation adapter is `LevelPlayAdsService`,
## selected in `PlatformServices`.

# Lifecycle.
signal initialization_finished(success: bool)

# Banner.
signal banner_loaded
signal banner_failed(message: String)

# Interstitial.
signal interstitial_ready
signal interstitial_displayed
signal interstitial_closed
signal interstitial_failed(message: String)

# Rewarded.
signal rewarded_ready
signal rewarded_displayed
signal rewarded_earned
signal rewarded_closed
signal rewarded_failed(message: String)

var _config: AdsConfig


## Returns true when a real ad backend is ready on this platform.
func is_available() -> bool:
	return false


## Supplies configuration (ids + frequency). Safe to call before initialize().
func configure(config: AdsConfig) -> void:
	_config = config


## Initializes the SDK once. Safe to call repeatedly.
func initialize() -> void:
	initialization_finished.emit(false)


# --- Banner (main menu only) ------------------------------------------------

func show_banner() -> void:
	pass


func hide_banner() -> void:
	pass


func destroy_banner() -> void:
	pass


# --- Interstitial -----------------------------------------------------------

func load_interstitial() -> void:
	pass


func is_interstitial_ready() -> bool:
	return false


func show_interstitial() -> bool:
	return false


## Centralized run-break interstitial policy. Screens report a completed run and
## the service decides (frequency + cooldown + readiness) whether to show one.
## Returns true only when an interstitial was actually displayed.
func handle_run_completed(_run_id: String) -> bool:
	return false


# --- Rewarded ---------------------------------------------------------------

func load_rewarded() -> void:
	pass


func is_rewarded_ready() -> bool:
	return false


func show_rewarded() -> bool:
	return false


# --- App lifecycle ----------------------------------------------------------

func on_app_pause() -> void:
	pass


func on_app_resume() -> void:
	pass


# --- Development helpers -----------------------------------------------------

## Launches the LevelPlay Integration Test Suite (development builds only).
func launch_test_suite() -> void:
	pass
