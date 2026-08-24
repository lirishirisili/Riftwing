#import "riftstrike_levelplay.h"

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <IronSource/IronSource.h>

#include "core/config/engine.h"

// ---------------------------------------------------------------------------
// Objective-C delegate glue. Each delegate forwards LevelPlay callbacks to the
// C++ singleton, which re-emits Godot signals. Reward "earned" exactly-once is
// enforced in GDScript (`LevelPlayAdsService`), matching Android.
// ---------------------------------------------------------------------------

static UIViewController *rlp_root_view_controller() {
	UIViewController *vc = [UIApplication sharedApplication].keyWindow.rootViewController;
	while (vc.presentedViewController) {
		vc = vc.presentedViewController;
	}
	return vc;
}

@interface RLPInterstitialDelegate : NSObject <LPMInterstitialAdDelegate>
@end

@interface RLPRewardedDelegate : NSObject <LPMRewardedAdDelegate>
@end

@interface RLPBannerDelegate : NSObject <LPMBannerAdViewDelegate>
@end

// Holds the ObjC ad objects/delegates so ARC keeps them alive.
@interface RLPBridge : NSObject
@property (nonatomic, strong) LPMInterstitialAd *interstitialAd;
@property (nonatomic, strong) LPMRewardedAd *rewardedAd;
@property (nonatomic, strong) LPMBannerAdView *bannerAdView;
@property (nonatomic, strong) RLPInterstitialDelegate *interstitialDelegate;
@property (nonatomic, strong) RLPRewardedDelegate *rewardedDelegate;
@property (nonatomic, strong) RLPBannerDelegate *bannerDelegate;
@property (nonatomic, copy) NSString *interstitialAdUnitId;
@property (nonatomic, copy) NSString *rewardedAdUnitId;
@property (nonatomic, copy) NSString *bannerAdUnitId;
@property (nonatomic, assign) BOOL initialized;
+ (instancetype)shared;
@end

@implementation RLPBridge
+ (instancetype)shared {
	static RLPBridge *shared = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ shared = [[RLPBridge alloc] init]; });
	return shared;
}
@end

static String rlp_error_string(NSError *error) {
	if (error == nil) {
		return String("unknown error");
	}
	return String("code=") + itos((int)error.code) + " message=" + String::utf8([error.localizedDescription UTF8String]);
}

// --- Interstitial delegate --------------------------------------------------

@implementation RLPInterstitialDelegate
- (void)didLoadAdWithAdInfo:(LPMAdInfo *)adInfo {
	RiftstrikeLevelPlay::get_singleton()->set_interstitial_ready(true);
	RiftstrikeLevelPlay::get_singleton()->notify_signal("interstitial_loaded");
}
- (void)didFailToLoadAdWithAdUnitId:(NSString *)adUnitId error:(NSError *)error {
	RiftstrikeLevelPlay::get_singleton()->set_interstitial_ready(false);
	RiftstrikeLevelPlay::get_singleton()->notify_signal_str("interstitial_load_failed", rlp_error_string(error));
}
- (void)didDisplayAdWithAdInfo:(LPMAdInfo *)adInfo {
	RiftstrikeLevelPlay::get_singleton()->set_interstitial_ready(false);
	RiftstrikeLevelPlay::get_singleton()->notify_signal("interstitial_displayed");
}
- (void)didFailToDisplayAdWithAdInfo:(LPMAdInfo *)adInfo error:(NSError *)error {
	RiftstrikeLevelPlay::get_singleton()->set_interstitial_ready(false);
	RiftstrikeLevelPlay::get_singleton()->notify_signal_str("interstitial_display_failed", rlp_error_string(error));
}
- (void)didClickAdWithAdInfo:(LPMAdInfo *)adInfo {
	RiftstrikeLevelPlay::get_singleton()->notify_signal("interstitial_clicked");
}
- (void)didCloseAdWithAdInfo:(LPMAdInfo *)adInfo {
	RiftstrikeLevelPlay::get_singleton()->notify_signal("interstitial_closed");
}
- (void)didChangeAdInfo:(LPMAdInfo *)adInfo {}
@end

// --- Rewarded delegate ------------------------------------------------------

@implementation RLPRewardedDelegate
- (void)didLoadAdWithAdInfo:(LPMAdInfo *)adInfo {
	RiftstrikeLevelPlay::get_singleton()->set_rewarded_ready(true);
	RiftstrikeLevelPlay::get_singleton()->notify_signal("rewarded_loaded");
}
- (void)didFailToLoadAdWithAdUnitId:(NSString *)adUnitId error:(NSError *)error {
	RiftstrikeLevelPlay::get_singleton()->set_rewarded_ready(false);
	RiftstrikeLevelPlay::get_singleton()->notify_signal_str("rewarded_load_failed", rlp_error_string(error));
}
- (void)didDisplayAdWithAdInfo:(LPMAdInfo *)adInfo {
	RiftstrikeLevelPlay::get_singleton()->set_rewarded_ready(false);
	RiftstrikeLevelPlay::get_singleton()->notify_signal("rewarded_displayed");
}
- (void)didFailToDisplayAdWithAdInfo:(LPMAdInfo *)adInfo error:(NSError *)error {
	RiftstrikeLevelPlay::get_singleton()->set_rewarded_ready(false);
	RiftstrikeLevelPlay::get_singleton()->notify_signal_str("rewarded_display_failed", rlp_error_string(error));
}
- (void)didClickAdWithAdInfo:(LPMAdInfo *)adInfo {
	RiftstrikeLevelPlay::get_singleton()->notify_signal("rewarded_clicked");
}
- (void)didCloseAdWithAdInfo:(LPMAdInfo *)adInfo {
	RiftstrikeLevelPlay::get_singleton()->notify_signal("rewarded_closed");
}
- (void)didChangeAdInfo:(LPMAdInfo *)adInfo {}
- (void)didRewardAdWithAdInfo:(LPMAdInfo *)adInfo reward:(LPMReward *)reward {
	String name = reward.name ? String::utf8([reward.name UTF8String]) : String();
	RiftstrikeLevelPlay::get_singleton()->notify_reward(name, (int)reward.amount);
}
@end

// --- Banner delegate --------------------------------------------------------

@implementation RLPBannerDelegate
- (void)didLoadAdWithAdInfo:(LPMAdInfo *)adInfo {
	dispatch_async(dispatch_get_main_queue(), ^{
		LPMBannerAdView *banner = [RLPBridge shared].bannerAdView;
		if (banner) {
			UIViewController *vc = rlp_root_view_controller();
			if (banner.superview == nil && vc) {
				CGSize screen = vc.view.bounds.size;
				CGSize bannerSize = banner.frame.size;
				banner.frame = CGRectMake((screen.width - bannerSize.width) / 2.0,
						screen.height - bannerSize.height,
						bannerSize.width, bannerSize.height);
				[vc.view addSubview:banner];
			}
			banner.hidden = NO;
		}
	});
	RiftstrikeLevelPlay::get_singleton()->notify_signal("banner_loaded");
}
- (void)didFailToLoadAdWithAdUnitId:(NSString *)adUnitId error:(NSError *)error {
	RiftstrikeLevelPlay::get_singleton()->notify_signal_str("banner_load_failed", rlp_error_string(error));
}
- (void)didDisplayAdWithAdInfo:(LPMAdInfo *)adInfo {}
- (void)didClickAdWithAdInfo:(LPMAdInfo *)adInfo {
	RiftstrikeLevelPlay::get_singleton()->notify_signal("banner_clicked");
}
- (void)didChangeAdInfo:(LPMAdInfo *)adInfo {}
@end

// ---------------------------------------------------------------------------
// C++ singleton
// ---------------------------------------------------------------------------

RiftstrikeLevelPlay *RiftstrikeLevelPlay::instance = nullptr;

RiftstrikeLevelPlay *RiftstrikeLevelPlay::get_singleton() {
	return instance;
}

void RiftstrikeLevelPlay::_bind_methods() {
	ClassDB::bind_method(D_METHOD("initialize", "app_key", "banner_id", "interstitial_id", "rewarded_id", "development"), &RiftstrikeLevelPlay::initialize);
	ClassDB::bind_method(D_METHOD("show_banner"), &RiftstrikeLevelPlay::show_banner);
	ClassDB::bind_method(D_METHOD("hide_banner"), &RiftstrikeLevelPlay::hide_banner);
	ClassDB::bind_method(D_METHOD("destroy_banner"), &RiftstrikeLevelPlay::destroy_banner);
	ClassDB::bind_method(D_METHOD("load_interstitial"), &RiftstrikeLevelPlay::load_interstitial);
	ClassDB::bind_method(D_METHOD("is_interstitial_ready"), &RiftstrikeLevelPlay::is_interstitial_ready);
	ClassDB::bind_method(D_METHOD("show_interstitial"), &RiftstrikeLevelPlay::show_interstitial);
	ClassDB::bind_method(D_METHOD("load_rewarded"), &RiftstrikeLevelPlay::load_rewarded);
	ClassDB::bind_method(D_METHOD("is_rewarded_ready"), &RiftstrikeLevelPlay::is_rewarded_ready);
	ClassDB::bind_method(D_METHOD("show_rewarded"), &RiftstrikeLevelPlay::show_rewarded);
	ClassDB::bind_method(D_METHOD("on_pause"), &RiftstrikeLevelPlay::on_pause);
	ClassDB::bind_method(D_METHOD("on_resume"), &RiftstrikeLevelPlay::on_resume);
	ClassDB::bind_method(D_METHOD("launch_test_suite"), &RiftstrikeLevelPlay::launch_test_suite);

	ADD_SIGNAL(MethodInfo("init_success"));
	ADD_SIGNAL(MethodInfo("init_failed", PropertyInfo(Variant::STRING, "error")));
	ADD_SIGNAL(MethodInfo("banner_loaded"));
	ADD_SIGNAL(MethodInfo("banner_load_failed", PropertyInfo(Variant::STRING, "error")));
	ADD_SIGNAL(MethodInfo("banner_clicked"));
	ADD_SIGNAL(MethodInfo("interstitial_loaded"));
	ADD_SIGNAL(MethodInfo("interstitial_load_failed", PropertyInfo(Variant::STRING, "error")));
	ADD_SIGNAL(MethodInfo("interstitial_displayed"));
	ADD_SIGNAL(MethodInfo("interstitial_display_failed", PropertyInfo(Variant::STRING, "error")));
	ADD_SIGNAL(MethodInfo("interstitial_closed"));
	ADD_SIGNAL(MethodInfo("interstitial_clicked"));
	ADD_SIGNAL(MethodInfo("rewarded_loaded"));
	ADD_SIGNAL(MethodInfo("rewarded_load_failed", PropertyInfo(Variant::STRING, "error")));
	ADD_SIGNAL(MethodInfo("rewarded_displayed"));
	ADD_SIGNAL(MethodInfo("rewarded_display_failed", PropertyInfo(Variant::STRING, "error")));
	ADD_SIGNAL(MethodInfo("rewarded_closed"));
	ADD_SIGNAL(MethodInfo("rewarded_clicked"));
	ADD_SIGNAL(MethodInfo("rewarded_earned", PropertyInfo(Variant::STRING, "reward_name"), PropertyInfo(Variant::INT, "amount")));
}

void RiftstrikeLevelPlay::initialize(const String &app_key, const String &banner_id, const String &interstitial_id, const String &rewarded_id, bool development) {
	RLPBridge *bridge = [RLPBridge shared];
	if (bridge.initialized) {
		return;
	}
	bridge.bannerAdUnitId = [NSString stringWithUTF8String:banner_id.utf8().get_data()];
	bridge.interstitialAdUnitId = [NSString stringWithUTF8String:interstitial_id.utf8().get_data()];
	bridge.rewardedAdUnitId = [NSString stringWithUTF8String:rewarded_id.utf8().get_data()];

	NSString *key = [NSString stringWithUTF8String:app_key.utf8().get_data()];

	dispatch_async(dispatch_get_main_queue(), ^{
		LPMInitRequestBuilder *builder = [[LPMInitRequestBuilder alloc] initWithAppKey:key];
		LPMInitRequest *request = [builder build];
		[LevelPlay initWithRequest:request completion:^(LPMConfiguration *config, NSError *error) {
			if (error != nil) {
				bridge.initialized = NO;
				RiftstrikeLevelPlay::get_singleton()->notify_signal_str("init_failed", rlp_error_string(error));
				return;
			}
			bridge.initialized = YES;

			bridge.interstitialDelegate = [[RLPInterstitialDelegate alloc] init];
			bridge.interstitialAd = [[LPMInterstitialAd alloc] initWithAdUnitId:bridge.interstitialAdUnitId];
			bridge.interstitialAd.delegate = bridge.interstitialDelegate;

			bridge.rewardedDelegate = [[RLPRewardedDelegate alloc] init];
			bridge.rewardedAd = [[LPMRewardedAd alloc] initWithAdUnitId:bridge.rewardedAdUnitId];
			bridge.rewardedAd.delegate = bridge.rewardedDelegate;

			RiftstrikeLevelPlay::get_singleton()->notify_signal("init_success");
		}];
	});
}

void RiftstrikeLevelPlay::show_banner() {
	RLPBridge *bridge = [RLPBridge shared];
	if (!bridge.initialized) {
		return;
	}
	dispatch_async(dispatch_get_main_queue(), ^{
		if (bridge.bannerAdView == nil) {
			bridge.bannerDelegate = [[RLPBannerDelegate alloc] init];
			LPMAdSize *size = [LPMAdSize createAdaptiveAdSize];
			if (size == nil) {
				size = [LPMAdSize bannerSize];
			}
			bridge.bannerAdView = [[LPMBannerAdView alloc] initWithAdUnitId:bridge.bannerAdUnitId];
			[bridge.bannerAdView setAdSize:size];
			bridge.bannerAdView.delegate = bridge.bannerDelegate;
			bridge.bannerAdView.placementName = nil;
		}
		bridge.bannerAdView.hidden = NO;
		UIViewController *vc = rlp_root_view_controller();
		[bridge.bannerAdView loadAdWithViewController:vc];
	});
}

void RiftstrikeLevelPlay::hide_banner() {
	RLPBridge *bridge = [RLPBridge shared];
	dispatch_async(dispatch_get_main_queue(), ^{
		bridge.bannerAdView.hidden = YES;
	});
}

void RiftstrikeLevelPlay::destroy_banner() {
	RLPBridge *bridge = [RLPBridge shared];
	dispatch_async(dispatch_get_main_queue(), ^{
		if (bridge.bannerAdView) {
			[bridge.bannerAdView removeFromSuperview];
			[bridge.bannerAdView destroyBanner];
			bridge.bannerAdView = nil;
		}
	});
}

void RiftstrikeLevelPlay::load_interstitial() {
	RLPBridge *bridge = [RLPBridge shared];
	if (!bridge.initialized) {
		return;
	}
	set_interstitial_ready(false);
	dispatch_async(dispatch_get_main_queue(), ^{
		[bridge.interstitialAd loadAd];
	});
}

bool RiftstrikeLevelPlay::is_interstitial_ready() {
	RLPBridge *bridge = [RLPBridge shared];
	return bridge.interstitialAd != nil && [bridge.interstitialAd isAdReady];
}

void RiftstrikeLevelPlay::show_interstitial() {
	RLPBridge *bridge = [RLPBridge shared];
	dispatch_async(dispatch_get_main_queue(), ^{
		UIViewController *vc = rlp_root_view_controller();
		[bridge.interstitialAd showAdWithViewController:vc placementName:nil];
	});
}

void RiftstrikeLevelPlay::load_rewarded() {
	RLPBridge *bridge = [RLPBridge shared];
	if (!bridge.initialized) {
		return;
	}
	set_rewarded_ready(false);
	dispatch_async(dispatch_get_main_queue(), ^{
		[bridge.rewardedAd loadAd];
	});
}

bool RiftstrikeLevelPlay::is_rewarded_ready() {
	RLPBridge *bridge = [RLPBridge shared];
	return bridge.rewardedAd != nil && [bridge.rewardedAd isAdReady];
}

void RiftstrikeLevelPlay::show_rewarded() {
	RLPBridge *bridge = [RLPBridge shared];
	dispatch_async(dispatch_get_main_queue(), ^{
		UIViewController *vc = rlp_root_view_controller();
		[bridge.rewardedAd showAdWithViewController:vc placementName:nil];
	});
}

void RiftstrikeLevelPlay::on_pause() {
	// New LevelPlay APIs manage lifecycle automatically; kept for parity.
}

void RiftstrikeLevelPlay::on_resume() {
	// See on_pause().
}

void RiftstrikeLevelPlay::launch_test_suite() {
	dispatch_async(dispatch_get_main_queue(), ^{
		[LevelPlay launchTestSuite:rlp_root_view_controller()];
	});
}

void RiftstrikeLevelPlay::notify_signal(const String &name) {
	call_deferred("emit_signal", name);
}

void RiftstrikeLevelPlay::notify_signal_str(const String &name, const String &arg) {
	call_deferred("emit_signal", name, arg);
}

void RiftstrikeLevelPlay::notify_reward(const String &reward_name, int amount) {
	call_deferred("emit_signal", "rewarded_earned", reward_name, amount);
}

void RiftstrikeLevelPlay::set_interstitial_ready(bool ready) {
	// Readiness is authoritative in GDScript; retained for symmetry with Android.
}

void RiftstrikeLevelPlay::set_rewarded_ready(bool ready) {
}

RiftstrikeLevelPlay::RiftstrikeLevelPlay() {
	ERR_FAIL_COND(instance != nullptr);
	instance = this;
}

RiftstrikeLevelPlay::~RiftstrikeLevelPlay() {
	if (instance == this) {
		instance = nullptr;
	}
}

// ---------------------------------------------------------------------------
// Plugin registration hooks referenced by RiftstrikeLevelPlay.gdip.
// ---------------------------------------------------------------------------

void register_riftstrike_levelplay_types() {
	ClassDB::register_class<RiftstrikeLevelPlay>();
	RiftstrikeLevelPlay *singleton = memnew(RiftstrikeLevelPlay);
	Engine::get_singleton()->add_singleton(Engine::Singleton("RiftstrikeLevelPlay", singleton));
}

void unregister_riftstrike_levelplay_types() {
	if (RiftstrikeLevelPlay::get_singleton() != nullptr) {
		memdelete(RiftstrikeLevelPlay::get_singleton());
	}
}
