class_name AdsService
extends RefCounted
## Advertising interface. Gameplay/UI talk only to this contract.
## Prototype: no-op. Mobile builds swap in AdMobAdsService via PlatformServices.

signal initialization_finished(success: bool)
signal rewarded_earned
signal rewarded_closed
signal rewarded_failed(message: String)
signal interstitial_closed
signal interstitial_failed(message: String)


## Returns true when a real ad backend is ready on this platform.
func is_available() -> bool:
	return false


## Initializes the SDK once. Safe to call repeatedly.
func initialize() -> void:
	initialization_finished.emit(false)


## Banner (main menu).
func show_banner() -> void:
	pass


func hide_banner() -> void:
	pass


func destroy_banner() -> void:
	pass


## Interstitial (every N completed runs).
func load_interstitial() -> void:
	pass


func is_interstitial_ready() -> bool:
	return false


func show_interstitial() -> bool:
	return false


## Rewarded (opt-in ×2 rewards on Results).
func load_rewarded() -> void:
	pass


func is_rewarded_ready() -> bool:
	return false


func show_rewarded() -> bool:
	return false
