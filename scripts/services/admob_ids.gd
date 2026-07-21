class_name AdMobIds
extends RefCounted
## Production AdMob identifiers for RIFTWING.
## Debug builds use Google's official test unit IDs to protect the AdMob account.
## App IDs always stay production (wired in android/config.gd + ios .gdip).

const ANDROID_APP_ID := "ca-app-pub-1194823418071986~7112201236"
const IOS_APP_ID := "ca-app-pub-1194823418071986~3724188783"

const ANDROID_BANNER := "ca-app-pub-1194823418071986/1397528480"
const ANDROID_INTERSTITIAL := "ca-app-pub-1194823418071986/1261797118"
const ANDROID_REWARDED := "ca-app-pub-1194823418071986/8948715447"

const IOS_BANNER := "ca-app-pub-1194823418071986/8892186764"
const IOS_INTERSTITIAL := "ca-app-pub-1194823418071986/2519038469"
const IOS_REWARDED := "ca-app-pub-1194823418071986/3636558872"

## Google sample units — safe for debug/device QA.
const TEST_ANDROID_BANNER := "ca-app-pub-3940256099942544/6300978111"
const TEST_ANDROID_INTERSTITIAL := "ca-app-pub-3940256099942544/1033173712"
const TEST_ANDROID_REWARDED := "ca-app-pub-3940256099942544/5224354917"
const TEST_IOS_BANNER := "ca-app-pub-3940256099942544/2934735716"
const TEST_IOS_INTERSTITIAL := "ca-app-pub-3940256099942544/4411468910"
const TEST_IOS_REWARDED := "ca-app-pub-3940256099942544/1712485313"

const INTERSTITIAL_EVERY_N_RUNS := 3


static func is_mobile_platform() -> bool:
	var os_name := OS.get_name()
	return os_name == "Android" or os_name == "iOS"


static func use_test_units() -> bool:
	# Debug APKs / editor exports marked debug stay on test units.
	return OS.is_debug_build()


static func banner_unit_id() -> String:
	if OS.get_name() == "iOS":
		return TEST_IOS_BANNER if use_test_units() else IOS_BANNER
	return TEST_ANDROID_BANNER if use_test_units() else ANDROID_BANNER


static func interstitial_unit_id() -> String:
	if OS.get_name() == "iOS":
		return TEST_IOS_INTERSTITIAL if use_test_units() else IOS_INTERSTITIAL
	return TEST_ANDROID_INTERSTITIAL if use_test_units() else ANDROID_INTERSTITIAL


static func rewarded_unit_id() -> String:
	if OS.get_name() == "iOS":
		return TEST_IOS_REWARDED if use_test_units() else IOS_REWARDED
	return TEST_ANDROID_REWARDED if use_test_units() else ANDROID_REWARDED
