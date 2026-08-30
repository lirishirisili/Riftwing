#ifndef RIFTSTRIKE_LEVELPLAY_H
#define RIFTSTRIKE_LEVELPLAY_H

// RIFTSTRIKE LevelPlay bridge for the Godot iOS platform.
//
// Registered as the engine singleton "RiftstrikeLevelPlay". Wraps the current
// LevelPlay iOS ad-unit APIs (IronSourceSDK 9.5.0.0): LevelPlay init +
// LPMInterstitialAd / LPMRewardedAd / LPMBannerAdView. No legacy IronSource
// init/load/show APIs are used. Unity Ads and Meta FAN participate only as
// LevelPlay mediated networks. ATT + FBAdSettings.setAdvertiserTrackingEnabled
// run before LevelPlay init. Signals mirror the Android plugin exactly so
// the shared GDScript `LevelPlayAdsService` is platform-agnostic.

#include "core/object/class_db.h"
#include "core/object/object.h"
#include "core/string/ustring.h"

class RiftstrikeLevelPlay : public Object {
	GDCLASS(RiftstrikeLevelPlay, Object);

	static RiftstrikeLevelPlay *instance;

protected:
	static void _bind_methods();

public:
	// GDScript-facing API (matches the Android @UsedByGodot surface).
	void initialize(const String &app_key, const String &banner_id, const String &interstitial_id, const String &rewarded_id, bool development);

	void show_banner();
	void hide_banner();
	void destroy_banner();

	void load_interstitial();
	bool is_interstitial_ready();
	void show_interstitial();

	void load_rewarded();
	bool is_rewarded_ready();
	void show_rewarded();

	void on_pause();
	void on_resume();
	void launch_test_suite();

	// Called from the Objective-C delegates to fan results back to GDScript.
	void notify_signal(const String &name);
	void notify_signal_str(const String &name, const String &arg);
	void notify_reward(const String &reward_name, int amount);

	void set_interstitial_ready(bool ready);
	void set_rewarded_ready(bool ready);

	static RiftstrikeLevelPlay *get_singleton();

	RiftstrikeLevelPlay();
	~RiftstrikeLevelPlay();
};

#endif // RIFTSTRIKE_LEVELPLAY_H
