class_name EventData
extends Resource
## A recurring, locally-timed challenge (e.g. VOID INVASION). No backend.
##
## The active window repeats every `period_days`, staying active for the first
## `active_days` of each period, aligned to a fixed `anchor_unix` epoch so the
## countdown is always real and deterministic on any device. Progress accrues from
## gameplay during the active window and the reward is granted once per occurrence.

## Metric that fills the progress bar.
enum Metric { ENEMIES_DESTROYED }

@export var id: String = "void_invasion"
@export var display_name: String = "VOID INVASION"
@export_multiline var description: String = "Repel the Void incursion. Destroy enemies during the invasion window to earn the cache."

## Cadence: the event repeats every `period_days` and is active for the first
## `active_days` of each period.
@export_range(1, 60) var period_days: int = 7
@export_range(1, 60) var active_days: int = 5

## Alignment epoch (UTC seconds). Windows are measured from here so every device
## agrees on the schedule. Default: 2024-01-01 00:00:00 UTC.
@export var anchor_unix: int = 1704067200

@export var metric: Metric = Metric.ENEMIES_DESTROYED

## Progress needed within one active window to earn the reward.
@export_range(1, 100000) var goal: int = 300

@export var reward_energy: int = 500
@export_range(0, 999) var reward_core: int = 3


func _period_seconds() -> int:
	return maxi(1, period_days) * 86400


func _active_seconds() -> int:
	return clampi(active_days, 1, period_days) * 86400


## Zero-based index of the period containing `now` (also identifies the occurrence).
func window_index(now: int) -> int:
	return int(floor(float(now - anchor_unix) / float(_period_seconds())))


func window_start(now: int) -> int:
	return anchor_unix + window_index(now) * _period_seconds()


func is_active(now: int) -> bool:
	return (now - window_start(now)) < _active_seconds()


## Seconds until the active window ends (when active) or until the next window
## opens (when currently in the inactive tail of a period).
func remaining_seconds(now: int) -> int:
	var start := window_start(now)
	if (now - start) < _active_seconds():
		return maxi(0, (start + _active_seconds()) - now)
	return maxi(0, (start + _period_seconds()) - now)


## Per-occurrence save key so progress/claims never leak across windows.
func occurrence_id(now: int) -> String:
	return "%s#%d" % [id, window_index(now)]


## Compact "Xd Yh" / "Yh Zm" / "Zm" countdown for banners.
static func format_countdown(seconds: int) -> String:
	seconds = maxi(0, seconds)
	var days := seconds / 86400
	var hours := (seconds % 86400) / 3600
	var minutes := (seconds % 3600) / 60
	if days > 0:
		return "%dD %dH" % [days, hours]
	if hours > 0:
		return "%dH %dM" % [hours, minutes]
	return "%dM" % minutes
