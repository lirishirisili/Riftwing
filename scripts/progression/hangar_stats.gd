class_name HangarStats
extends RefCounted
## Pure hangar stat math. No I/O, no SaveManager writes.
##
## Given a ShipData and a level map (`weapons` → int, ...), computes current
## totals, power, and the preview totals after buying one more level of a track.

var attack: int = 0
var defense: int = 0
var hp: int = 0
var critical: float = 0.0


static func compute(ship: ShipData, levels: Dictionary) -> HangarStats:
	var stats := HangarStats.new()
	if ship == null:
		return stats
	stats.attack = ship.base_attack
	stats.defense = ship.base_defense
	stats.hp = ship.base_hp
	stats.critical = ship.base_critical
	for track in ship.tracks():
		var level := int(levels.get(track.id, 0))
		level = clampi(level, 0, track.max_level)
		stats.attack += track.attack_per_level * level
		stats.defense += track.defense_per_level * level
		stats.hp += track.hp_per_level * level
		stats.critical += track.critical_per_level * float(level)
	return stats


## Stats as they would read after purchasing one more level of `track_id`.
static func preview_after(ship: ShipData, levels: Dictionary, track_id: String) -> HangarStats:
	var next := levels.duplicate()
	var current := int(next.get(track_id, 0))
	next[track_id] = current + 1
	return compute(ship, next)


## Simple power readout used by the hangar header (weighted sum of the four stats).
func power() -> int:
	return attack * 2 + defense * 2 + int(float(hp) * 0.25) + int(critical * 40.0)


func critical_display() -> String:
	return "%.1f%%" % critical
