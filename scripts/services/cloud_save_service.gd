class_name CloudSaveService
extends RefCounted
## Cloud save interface. Deferred feature; prototype implementation is a no-op.
## Local save remains the source of truth during the prototype.

## Returns true when cloud save is connected. Prototype: never.
func is_available() -> bool:
	return false

## Uploads a save payload. No-op in prototype.
func upload(_payload: Dictionary) -> void:
	pass

## Downloads a save payload. Returns an empty dictionary in prototype.
func download() -> Dictionary:
	return {}
