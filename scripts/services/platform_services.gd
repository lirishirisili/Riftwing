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
	haptics = HapticsService.new()
	cloud_save = CloudSaveService.new()
	achievements = AchievementService.new()
	ads = _make_ads_service()
	ads.configure(_load_ads_config())
	ads.initialize()


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
