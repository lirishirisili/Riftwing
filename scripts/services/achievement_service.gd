class_name AchievementService
extends RefCounted
## Achievement interface. Prototype implementation is a no-op.
## Platform adapters are added later without changing gameplay code.

## Returns true when an achievement backend is connected. Prototype: never.
func is_available() -> bool:
	return false

## Unlocks an achievement by identifier. No-op in prototype.
func unlock(achievement_id: String) -> void:
	pass

## Reports incremental progress for an achievement. No-op in prototype.
func report_progress(achievement_id: String, progress: float) -> void:
	pass
