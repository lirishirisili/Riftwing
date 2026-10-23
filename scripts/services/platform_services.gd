extends Node
## Autoload aggregator for platform-specific services.
##
## Gameplay code talks to these typed interfaces only and never references an
## Android or iOS SDK directly. Prototype implementations are no-op / local.
## Concrete adapters are swapped in here later without touching gameplay code.

const _ADS_CONFIG_PATH := "res://resources/ads/levelplay_ads_config.tres"

var store: StoreService
var ads: AdsService
var analytics: AnalyticsService
var haptics: HapticsService
var cloud_save: CloudSaveService
var achievements: AchievementService


func _ready() -> void:
	# Default no-op implementations. Real adapters replace these by assignment
	# during platform bring-up, keeping gameplay code unchanged.
	store = StoreService.new()
	analytics = AnalyticsService.new()
	# Real device haptics on phones; the no-op base everywhere else.
	var device_haptics := DeviceHapticsService.new()
	haptics = device_haptics if device_haptics.is_available() else HapticsService.new()
	cloud_save = CloudSaveService.new()
	achievements = AchievementService.new()
	ads = _make_ads_service()
	ads.configure(_load_ads_config())
	# Ads start only once the player made a privacy choice (consent must be set
	# before the SDK initializes). SaveManager loads after this autoload, so the
	# check is deferred.
	call_deferred("_start_ads_if_consented")


var _ads_started: bool = false


func _start_ads_if_consented() -> void:
	var privacy: Dictionary = SaveManager.section("privacy")
	if bool(privacy.get("asked", false)):
		_start_ads(bool(privacy.get("consent", false)))


## True once the first-launch privacy question has been answered.
func has_privacy_choice() -> bool:
	return bool(SaveManager.section("privacy").get("asked", false))


func get_ads_consent() -> bool:
	return bool(SaveManager.section("privacy").get("consent", false))


## Stores the player's choice and applies it. Starts ads on the first call; a
## later change (Settings) updates consent for the running SDK.
func apply_privacy(consent: bool) -> void:
	var privacy: Dictionary = SaveManager.section("privacy")
	privacy["asked"] = true
	privacy["consent"] = consent
	SaveManager.save_game()
	if _ads_started:
		_apply_consent(consent)
	else:
		_start_ads(consent)


func _start_ads(consent: bool) -> void:
	if _ads_started:
		return
	_ads_started = true
	_apply_consent(consent)
	ads.initialize()


func _apply_consent(consent: bool) -> void:
	ads.set_consent(consent)
	# CCPA: no consent means "do not sell". The game is not child-directed.
	ads.set_metadata("do_not_sell", "false" if consent else "true")
	ads.set_metadata("is_child_directed", "false")


## Selects the Unity LevelPlay adapter when its native plugin is present
## (Android/iOS device builds), otherwise a safe no-op (editor/desktop/missing
## plugin). Exactly one ads service is created per process.
func _make_ads_service() -> AdsService:
	var levelplay := LevelPlayAdsService.new()
	if levelplay.is_available():
		return levelplay
	return AdsService.new()


func _load_ads_config() -> AdsConfig:
	var config: AdsConfig = load(_ADS_CONFIG_PATH) as AdsConfig
	if config == null:
		config = AdsConfig.new()
	config.development_mode = OS.is_debug_build()
	return config


## Human-readable platform label for debug/telemetry surfaces.
func get_platform_name() -> String:
	return OS.get_name()
