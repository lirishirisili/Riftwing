class_name StoreService
extends RefCounted
## Platform store interface. Prototype implementation is a local no-op.
## Android and iOS adapters are added later without changing gameplay code.

## Returns true when a real store backend is connected. Prototype: never.
func is_available() -> bool:
	return false

## Requests product metadata for the given identifiers. No-op in prototype.
func query_products(product_ids: PackedStringArray) -> void:
	pass

## Begins a purchase flow for the given product. No-op in prototype.
func purchase(product_id: String) -> void:
	pass

## Restores previously owned entitlements. No-op in prototype.
func restore_purchases() -> void:
	pass
