class_name HangarUpgradeTrackData
extends Resource
## One permanent hangar upgrade category (weapons / shield / engine / drones / ultimate).
##
## Every cost and every per-level stat delta lives here. Hangar UI and SaveManager
## only read these numbers — nothing is hard-coded in gameplay scripts
## (docs/04_ARCHITECTURE.md: configuration uses custom Resources).

enum Category { WEAPONS, SHIELD, ENGINE, DRONES, ULTIMATE }

## Stable key stored in the save (`weapons`, `shield`, ...).
@export var id: String = ""

@export var category: Category = Category.WEAPONS

## Row title shown in the hangar (real UI text).
@export var title: String = "Upgrade"

@export var icon: Texture2D

## Palette token for the row accent (purple / cyan / green / orange / ...).
@export var accent_token: String = "cyan"

@export_range(1, 40) var max_level: int = 20

## Cost to buy level 1 from 0. Higher levels use cost_base + cost_per_level * level.
@export var cost_base: int = 200

## Extra Rift Energy charged per already-owned level.
@export var cost_per_level: int = 80

## Flat stat deltas granted by each purchased level.
@export var attack_per_level: int = 0
@export var defense_per_level: int = 0
@export var hp_per_level: int = 0
@export var critical_per_level: float = 0.0


## Rift Energy cost to advance from `current_level` to current_level + 1.
## Returns -1 when the track is already at max level.
func cost_for_next_level(current_level: int) -> int:
	if current_level < 0 or current_level >= max_level:
		return -1
	return maxi(0, cost_base + cost_per_level * current_level)


## Human-readable next-level benefit for the upgrade row preview.
func next_benefit_label() -> String:
	var parts: PackedStringArray = PackedStringArray()
	if attack_per_level != 0:
		parts.append("%+d ATK" % attack_per_level)
	if defense_per_level != 0:
		parts.append("%+d DEF" % defense_per_level)
	if hp_per_level != 0:
		parts.append("%+d HP" % hp_per_level)
	if not is_zero_approx(critical_per_level):
		parts.append("%+.1f%% CRIT" % critical_per_level)
	if parts.is_empty():
		return "+0"
	return ", ".join(parts)


## Save / UI key for this category.
static func category_key(cat: Category) -> String:
	match cat:
		Category.WEAPONS: return "weapons"
		Category.SHIELD: return "shield"
		Category.ENGINE: return "engine"
		Category.DRONES: return "drones"
		Category.ULTIMATE: return "ultimate"
		_: return "weapons"
