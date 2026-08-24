class_name AdsConfig
extends Resource
## Central LevelPlay configuration (per-platform app keys + ad unit ids + frequency).
##
## Balance/config lives in a Resource, never hard-coded in the service, so the
## interstitial cadence and ad ids can be tuned without touching logic. Ids are
## the confirmed LevelPlay dashboard values for com.lishistudio.riftwing.

## Android LevelPlay app key.
@export var android_app_key: String = "27c3b0395"
## Android ad unit ids.
@export var android_banner_id: String = "jqgg68ya19n3ytgi"
@export var android_interstitial_id: String = "rbll62fz9v6c3g8z"
@export var android_rewarded_id: String = "0kp8369fne1aw2cr"

## iOS LevelPlay app key.
@export var ios_app_key: String = "27c3aca0d"
## iOS ad unit ids.
@export var ios_banner_id: String = "05n2yrznzri2l1pp"
@export var ios_interstitial_id: String = "tarcjz9o8di0xoe7"
@export var ios_rewarded_id: String = "xqcirr4y800m8wpy"

## Interstitial frequency (session-scoped; never persisted to save data).
## - Skip the interstitial after the player's very first completed run.
## - At most one interstitial every N completed runs.
## - At least this many seconds between two interstitial displays.
@export var runs_per_interstitial: int = 2
@export var minimum_interstitial_seconds: float = 90.0

## When true, enable extra LevelPlay logging + allow the test suite entry point.
## Set from the build type at runtime, not persisted.
@export var development_mode: bool = false


## Returns the app key for the running platform, or "" when unsupported.
func app_key_for_platform() -> String:
	if OS.has_feature("android"):
		return android_app_key
	if OS.has_feature("ios"):
		return ios_app_key
	return ""


func banner_id_for_platform() -> String:
	if OS.has_feature("android"):
		return android_banner_id
	if OS.has_feature("ios"):
		return ios_banner_id
	return ""


func interstitial_id_for_platform() -> String:
	if OS.has_feature("android"):
		return android_interstitial_id
	if OS.has_feature("ios"):
		return ios_interstitial_id
	return ""


func rewarded_id_for_platform() -> String:
	if OS.has_feature("android"):
		return android_rewarded_id
	if OS.has_feature("ios"):
		return ios_rewarded_id
	return ""
