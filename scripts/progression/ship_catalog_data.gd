class_name ShipCatalogData
extends Resource
## Ordered hangar roster. The sidebar renders every entry; unlock state comes
## from SaveManager, not from mutating these Resources.

@export var ships: Array[ShipData] = []


func find_by_id(ship_id: String) -> ShipData:
	for ship in ships:
		if ship != null and ship.id == ship_id:
			return ship
	return null


## Default selected ship for a fresh save (first starts_unlocked entry).
func default_ship_id() -> String:
	for ship in ships:
		if ship != null and ship.starts_unlocked and ship.id != "":
			return ship.id
	if not ships.is_empty() and ships[0] != null:
		return ships[0].id
	return ""


func starting_unlocked_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for ship in ships:
		if ship != null and ship.starts_unlocked and ship.id != "":
			ids.append(ship.id)
	return ids
