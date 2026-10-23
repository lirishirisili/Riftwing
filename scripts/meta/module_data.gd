class_name ModuleData
extends Resource
## Equippable hangar module (3 slots). Rarity scales the bonus; three identical
## modules of one rarity merge into the next rarity.
##
## Stats: damage, hp, crit, magnet, xp, fire_rate, armor, core_find.

enum Rarity { COMMON, RARE, EPIC, LEGENDARY }

@export var id: String = ""
@export var title: String = "Module"
@export var stat: String = "damage"
## Bonus by rarity (COMMON..LEGENDARY). Multipliers are fractions (+0.06 = +6%).
@export var values: PackedFloat32Array = PackedFloat32Array([0.04, 0.08, 0.14, 0.22])
@export var icon: Texture2D


func value_at(rarity: int) -> float:
	return values[clampi(rarity, 0, values.size() - 1)] if not values.is_empty() else 0.0


static func rarity_name(rarity: int) -> String:
	match rarity:
		Rarity.RARE: return "RARE"
		Rarity.EPIC: return "EPIC"
		Rarity.LEGENDARY: return "LEGENDARY"
		_: return "COMMON"


static func rarity_color(rarity: int) -> Color:
	match rarity:
		Rarity.RARE: return Color(0.2, 0.85, 1.0)
		Rarity.EPIC: return Color(0.7, 0.4, 1.0)
		Rarity.LEGENDARY: return Color(1.0, 0.8, 0.25)
		_: return Color(0.75, 0.8, 0.9)
