class_name AdsService
extends RefCounted
## Advertising interface. Prototype implementation is a no-op.
## Monetization is deferred until retention is proven; no SDKs are wired here.

## Returns true when an ad backend is ready. Prototype: never.
func is_available() -> bool:
	return false

## Preloads a rewarded ad. No-op in prototype.
func load_rewarded() -> void:
	pass

## Shows a rewarded ad. Returns false because no ad can be shown in prototype.
func show_rewarded() -> bool:
	return false
