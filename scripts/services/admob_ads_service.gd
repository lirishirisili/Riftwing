class_name AdMobAdsService
extends AdsService
## Poing Studios AdMob adapter. Used only on Android/iOS behind PlatformServices.
## Never referenced directly from combat systems.
##
## Startup order: UMP consent (GDPR + iOS IDFA/ATT via AdMob messages) → MobileAds.initialize.

var _initialized: bool = false
var _initializing: bool = false
var _sdk_init_started: bool = false
var _banner: AdView
var _interstitial: InterstitialAd
var _rewarded: RewardedAd
var _loading_interstitial: bool = false
var _loading_rewarded: bool = false
var _interstitial_content := FullScreenContentCallback.new()
var _rewarded_content := FullScreenContentCallback.new()
var _reward_listener := OnUserEarnedRewardListener.new()
var _earned_this_show: bool = false


func _init() -> void:
	_interstitial_content.on_ad_dismissed_full_screen_content = _on_interstitial_dismissed
	_interstitial_content.on_ad_failed_to_show_full_screen_content = _on_interstitial_show_failed
	_rewarded_content.on_ad_dismissed_full_screen_content = _on_rewarded_dismissed
	_rewarded_content.on_ad_failed_to_show_full_screen_content = _on_rewarded_show_failed
	_reward_listener.on_user_earned_reward = _on_user_earned_reward


func is_available() -> bool:
	return AdMobIds.is_mobile_platform() and Engine.has_singleton("PoingGodotAdMob")


func initialize() -> void:
	if _initialized:
		initialization_finished.emit(true)
		return
	if not is_available():
		initialization_finished.emit(false)
		return
	if _initializing:
		return
	_initializing = true
	_gather_consent_then_initialize_sdk()


## UMP first so GDPR / IDFA explainer + ATT can run before ad requests.
func _gather_consent_then_initialize_sdk() -> void:
	var request := ConsentRequestParameters.new()
	request.tag_for_under_age_of_consent = false
	UserMessagingPlatform.consent_information.update(
		request,
		_on_consent_info_updated_success,
		_on_consent_info_updated_failure,
	)


func _on_consent_info_updated_success() -> void:
	if UserMessagingPlatform.consent_information.get_is_consent_form_available():
		UserMessagingPlatform.load_consent_form(
			_on_consent_form_load_success,
			_on_consent_form_load_failure,
		)
	else:
		_initialize_mobile_ads()


func _on_consent_info_updated_failure(error: FormError) -> void:
	var detail := error.message if error != null else "unknown"
	push_warning("AdMob UMP consent update failed: %s" % detail)
	# Still initialize — non-personalized ads remain allowed.
	_initialize_mobile_ads()


func _on_consent_form_load_success(form: ConsentForm) -> void:
	var status := UserMessagingPlatform.consent_information.get_consent_status()
	if status == ConsentInformation.ConsentStatus.REQUIRED:
		form.show(_on_consent_form_dismissed)
	else:
		_initialize_mobile_ads()


func _on_consent_form_load_failure(error: FormError) -> void:
	var detail := error.message if error != null else "unknown"
	push_warning("AdMob UMP form load failed: %s" % detail)
	_initialize_mobile_ads()


func _on_consent_form_dismissed(error: FormError) -> void:
	if error != null and not error.message.is_empty():
		push_warning("AdMob UMP form dismiss: %s" % error.message)
	_initialize_mobile_ads()


func _initialize_mobile_ads() -> void:
	if _initialized:
		_initializing = false
		initialization_finished.emit(true)
		return
	if _sdk_init_started:
		return
	_sdk_init_started = true
	var listener := OnInitializationCompleteListener.new()
	listener.on_initialization_complete = func(_status: InitializationStatus) -> void:
		_initializing = false
		_initialized = true
		initialization_finished.emit(true)
		load_interstitial()
		load_rewarded()
	MobileAds.initialize(listener)


func show_banner() -> void:
	if not _ensure_ready():
		return
	if _banner != null:
		_banner.show()
		return
	var size := AdSize.get_current_orientation_anchored_adaptive_banner_ad_size(AdSize.FULL_WIDTH)
	_banner = AdView.new(AdMobIds.banner_unit_id(), size, AdPosition.Values.TOP)
	var listener := AdListener.new()
	listener.on_ad_failed_to_load = func(error: LoadAdError) -> void:
		push_warning("AdMob banner failed: %s" % error.message)
	_banner.ad_listener = listener
	_banner.load_ad(AdRequest.new())


func hide_banner() -> void:
	if _banner != null:
		_banner.hide()


func destroy_banner() -> void:
	if _banner != null:
		_banner.destroy()
		_banner = null


func load_interstitial() -> void:
	if not _ensure_ready() or _loading_interstitial or _interstitial != null:
		return
	_loading_interstitial = true
	var callback := InterstitialAdLoadCallback.new()
	callback.on_ad_failed_to_load = func(error: LoadAdError) -> void:
		_loading_interstitial = false
		push_warning("AdMob interstitial failed: %s" % error.message)
	callback.on_ad_loaded = func(ad: InterstitialAd) -> void:
		_loading_interstitial = false
		_destroy_interstitial()
		ad.full_screen_content_callback = _interstitial_content
		_interstitial = ad
	InterstitialAdLoader.new().load(AdMobIds.interstitial_unit_id(), AdRequest.new(), callback)


func is_interstitial_ready() -> bool:
	return _interstitial != null


func show_interstitial() -> bool:
	if _interstitial == null:
		load_interstitial()
		return false
	_mute_audio(true)
	_interstitial.show()
	return true


func load_rewarded() -> void:
	if not _ensure_ready() or _loading_rewarded or _rewarded != null:
		return
	_loading_rewarded = true
	var callback := RewardedAdLoadCallback.new()
	callback.on_ad_failed_to_load = func(error: LoadAdError) -> void:
		_loading_rewarded = false
		push_warning("AdMob rewarded failed: %s" % error.message)
	callback.on_ad_loaded = func(ad: RewardedAd) -> void:
		_loading_rewarded = false
		_destroy_rewarded()
		ad.full_screen_content_callback = _rewarded_content
		_rewarded = ad
	RewardedAdLoader.new().load(AdMobIds.rewarded_unit_id(), AdRequest.new(), callback)


func is_rewarded_ready() -> bool:
	return _rewarded != null


func show_rewarded() -> bool:
	if _rewarded == null:
		load_rewarded()
		rewarded_failed.emit("Rewarded ad not ready")
		return false
	_earned_this_show = false
	_mute_audio(true)
	_rewarded.show(_reward_listener)
	return true


func _ensure_ready() -> bool:
	if not is_available():
		return false
	if not _initialized and not _initializing:
		initialize()
	return _initialized or _initializing


func _on_interstitial_dismissed() -> void:
	_mute_audio(false)
	_destroy_interstitial()
	interstitial_closed.emit()
	load_interstitial()


func _on_interstitial_show_failed(error: AdError) -> void:
	_mute_audio(false)
	_destroy_interstitial()
	interstitial_failed.emit(error.message if error != null else "show failed")
	load_interstitial()


func _on_rewarded_dismissed() -> void:
	_mute_audio(false)
	_destroy_rewarded()
	rewarded_closed.emit()
	if not _earned_this_show:
		rewarded_failed.emit("Ad closed before reward")
	load_rewarded()


func _on_rewarded_show_failed(error: AdError) -> void:
	_mute_audio(false)
	_destroy_rewarded()
	rewarded_failed.emit(error.message if error != null else "show failed")
	load_rewarded()


func _on_user_earned_reward(_item: RewardedItem) -> void:
	_earned_this_show = true
	rewarded_earned.emit()


func _destroy_interstitial() -> void:
	if _interstitial != null:
		_interstitial.destroy()
		_interstitial = null


func _destroy_rewarded() -> void:
	if _rewarded != null:
		_rewarded.destroy()
		_rewarded = null


func _mute_audio(muted: bool) -> void:
	if Engine.has_singleton("PoingGodotAdMob"):
		MobileAds.set_app_muted(muted)
	AudioManager.set_has_focus(not muted)
