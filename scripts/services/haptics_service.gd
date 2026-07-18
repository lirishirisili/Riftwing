class_name HapticsService
extends RefCounted
## Haptic feedback interface. Prototype implementation is a no-op.
## Device adapters are added later without changing gameplay code.

## Returns true when the device supports haptics. Prototype: never.
func is_available() -> bool:
	return false

## Triggers a light impact. No-op in prototype.
func light() -> void:
	pass

## Triggers a medium impact. No-op in prototype.
func medium() -> void:
	pass

## Triggers a heavy impact. No-op in prototype.
func heavy() -> void:
	pass
