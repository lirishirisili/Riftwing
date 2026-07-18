class_name ShipData
extends Resource
## Authored definition for one hangar ship.
##
## Base combat stats and the five permanent upgrade tracks are data. Runtime
## unlock / equip / level state lives in SaveManager, never on this Resource
## (so shared .tres files are never mutated).

@export var id: String = ""

@export var display_name: String = "Ship"

## Short rarity / tier line (e.g. "TIER 2  ·  RARE").
@export var tier_label: String = "TIER 1"

@export var portrait: Texture2D
@export var hero_texture: Texture2D

## Tint applied to placeholder art so locked ships stay visually distinct.
@export var accent_modulate: Color = Color.WHITE

@export var base_attack: int = 100
@export var base_defense: int = 80
@export var base_hp: int = 1000
@export var base_critical: float = 5.0

## When true, SaveManager unlocks this ship for new/migrated saves. Locked ships
## are shown in the hangar with a padlock — there is no real-money unlock path.
@export var starts_unlocked: bool = false

## Shown under LOCKED ships (progression teaser; not a store SKU).
@export var unlock_hint: String = "Coming soon"

@export var weapons_track: HangarUpgradeTrackData
@export var shield_track: HangarUpgradeTrackData
@export var engine_track: HangarUpgradeTrackData
@export var drones_track: HangarUpgradeTrackData
@export var ultimate_track: HangarUpgradeTrackData


## Ordered tracks matching the hangar upgrade rows.
func tracks() -> Array[HangarUpgradeTrackData]:
	var list: Array[HangarUpgradeTrackData] = []
	if weapons_track != null:
		list.append(weapons_track)
	if shield_track != null:
		list.append(shield_track)
	if engine_track != null:
		list.append(engine_track)
	if drones_track != null:
		list.append(drones_track)
	if ultimate_track != null:
		list.append(ultimate_track)
	return list


## Looks up a track by its save key (`weapons`, `shield`, ...).
func track_by_id(track_id: String) -> HangarUpgradeTrackData:
	for track in tracks():
		if track.id == track_id:
			return track
	return null
