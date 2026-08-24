class_name AdFrequencyGate
extends RefCounted
## Pure, session-scoped interstitial cadence policy.
##
## Deliberately holds NO persistent state: completed-run counting and the last
## shown timestamp live only for the current process, so player save data is
## never touched by ad frequency. Unique run ids are de-duplicated so a Results
## screen that is rebuilt (e.g. navigation back) never double-counts a run.
##
## Policy (configurable):
## - No interstitial after the player's first completed run.
## - Eligible at most once every `runs_per_interstitial` completed runs.
## - At least `minimum_interstitial_seconds` between two displays.

var _runs_per_interstitial: int = 2
var _minimum_seconds: float = 90.0

var _completed_runs: int = 0
var _seen_run_ids: Dictionary = {}
var _last_shown_seconds: float = -1.0
var _has_shown: bool = false


func configure(runs_per_interstitial: int, minimum_seconds: float) -> void:
	_runs_per_interstitial = maxi(1, runs_per_interstitial)
	_minimum_seconds = maxf(0.0, minimum_seconds)


## Records a completed run. De-duplicates by run id; blank ids always count.
## Returns true when this call registered a new completed run.
func register_run_completed(run_id: String) -> bool:
	if run_id != "":
		if _seen_run_ids.has(run_id):
			return false
		_seen_run_ids[run_id] = true
	_completed_runs += 1
	return true


## True when the cadence + cooldown allow showing an interstitial now.
## `now_seconds` is a monotonic clock (e.g. Time.get_ticks_msec() / 1000.0).
func can_show_interstitial(now_seconds: float) -> bool:
	# Never after the first completed run.
	if _completed_runs < 2:
		return false
	# At most one every N completed runs.
	if _completed_runs % _runs_per_interstitial != 0:
		return false
	# Minimum spacing between displays.
	if _has_shown and (now_seconds - _last_shown_seconds) < _minimum_seconds:
		return false
	return true


## Marks that an interstitial was actually displayed at `now_seconds`.
func mark_shown(now_seconds: float) -> void:
	_has_shown = true
	_last_shown_seconds = now_seconds


func completed_runs() -> int:
	return _completed_runs


func seconds_since_last_shown(now_seconds: float) -> float:
	if not _has_shown:
		return INF
	return now_seconds - _last_shown_seconds
