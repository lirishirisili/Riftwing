class_name RewardedOffer
extends RefCounted
## One-at-a-time rewarded-ad requests for gameplay / UI placements.
##
## `show(placement, on_reward, on_done)` plays a rewarded ad through
## PlatformServices.ads. `on_reward` runs ONLY from the SDK's reward-earned
## callback (never on close / dismiss), even when the platform delivers it after
## the close event. `on_done(rewarded: bool)` runs once when the request ends.
## Placements hide themselves when `is_ready()` is false (no fill, no plugin).
##
## `simulate` (debug builds only, off by default) grants instantly without an ad
## so placements can be exercised in the editor and in probes.

## Grace period for a reward callback that arrives after the close event.
const _LATE_REWARD_SECONDS := 1.5

static var simulate: bool = false

static var _active: bool = false
static var _request_id: int = 0
static var _earned: bool = false
static var _on_reward: Callable = Callable()
static var _on_done: Callable = Callable()
static var _placement: String = ""
## The ads service instance the signals are wired to (re-wired if it changes).
static var _connected_to: Object = null


static func is_ready() -> bool:
	if _active:
		return false
	if simulate and OS.is_debug_build():
		return true
	var ads: AdsService = PlatformServices.ads
	return ads != null and ads.is_rewarded_ready()


static func is_busy() -> bool:
	return _active


## Returns false (and does nothing) when no ad can be shown right now.
static func show(placement: String, on_reward: Callable, on_done: Callable = Callable()) -> bool:
	if not is_ready():
		return false
	_log("show", placement)
	if simulate and OS.is_debug_build():
		on_reward.call()
		if on_done.is_valid():
			on_done.call(true)
		return true
	var ads: AdsService = PlatformServices.ads
	_connect(ads)
	_active = true
	_request_id += 1
	_earned = false
	_on_reward = on_reward
	_on_done = on_done
	_placement = placement
	if not ads.show_rewarded():
		_finish(false)
		return false
	return true


static func _connect(ads: AdsService) -> void:
	if _connected_to == ads:
		return
	_connected_to = ads
	ads.rewarded_earned.connect(_on_earned_signal)
	ads.rewarded_closed.connect(_on_closed_signal)
	ads.rewarded_failed.connect(_on_failed_signal)


static func _on_earned_signal() -> void:
	if not _active or _earned:
		return
	_earned = true
	_log("earned", _placement)
	if _on_reward.is_valid():
		_on_reward.call()


static func _on_closed_signal() -> void:
	if not _active:
		return
	if _earned:
		_finish(true)
		return
	# Some networks report the reward right after close; wait briefly.
	var id := _request_id
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		_finish(false)
		return
	tree.create_timer(_LATE_REWARD_SECONDS, true, false, true).timeout.connect(func() -> void:
		if _active and _request_id == id:
			_finish(_earned))


static func _on_failed_signal(_message: String) -> void:
	if _active:
		_finish(false)


static func _finish(rewarded: bool) -> void:
	_active = false
	var done := _on_done
	_on_reward = Callable()
	_on_done = Callable()
	_log("done rewarded=%s" % str(rewarded), _placement)
	if done.is_valid():
		done.call(rewarded)


static func _log(what: String, placement: String) -> void:
	var analytics: AnalyticsService = PlatformServices.analytics
	if analytics != null:
		analytics.log_event("rewarded_" + what.split(" ")[0], {"placement": placement})
