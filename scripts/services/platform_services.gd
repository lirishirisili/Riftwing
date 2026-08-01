extends Node
## Autoload aggregator for platform-specific services.
##
## Gameplay code talks to these typed interfaces only and never references an
## Android or iOS SDK directly. Prototype implementations are no-op / local.
## Concrete adapters are swapped in here later without touching gameplay code.

var store: StoreService
var ads: AdsService
var analytics: AnalyticsService
var haptics: HapticsService
var cloud_save: CloudSaveService
var achievements: AchievementService


func _ready() -> void:
	# Default no-op implementations. Real adapters replace these by assignment
	# during platform bring-up, keeping gameplay code unchanged.
	# Ads stay no-op on all platforms (AdMob removed for App Store privacy).
	store = StoreService.new()
	ads = AdsService.new()
	analytics = AnalyticsService.new()
	haptics = HapticsService.new()
	cloud_save = CloudSaveService.new()
	achievements = AchievementService.new()
	ads.initialize()


## Human-readable platform label for debug/telemetry surfaces.
func get_platform_name() -> String:
	return OS.get_name()
