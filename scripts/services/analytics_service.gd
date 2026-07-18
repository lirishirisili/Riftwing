class_name AnalyticsService
extends RefCounted
## Analytics interface. Prototype implementation is a local no-op.
## Event names must never contain legacy branding.

## Returns true when an analytics backend is connected. Prototype: never.
func is_available() -> bool:
	return false

## Records a gameplay event with optional properties. No-op in prototype.
func log_event(event_name: String, properties: Dictionary = {}) -> void:
	pass
