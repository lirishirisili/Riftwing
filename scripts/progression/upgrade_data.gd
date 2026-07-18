class_name UpgradeData
extends Resource
## A single roguelite upgrade offered on the three-card choice screen.
##
## Everything the choice screen and UpgradeManager need is data (icon, title,
## description, rarity, prerequisites, max level, and typed effects). No upgrade
## behavior or balance value is hard-coded in gameplay scripts.

## Card frame + palette role. Order matches the rare/epic/legendary art in
## assets/ui/ and the rarity colors in docs/01_VISUAL_DIRECTION.md.
enum Rarity { RARE, EPIC, LEGENDARY }

## Stable identifier used by the loadout, prerequisites, and effect targets.
@export var id: String = ""

## Short card title (real UI text, never baked into the frame art).
@export var title: String = "Upgrade"

## One or two short lines describing the effect (kept terse for mobile).
@export_multiline var description: String = ""

## Icon shown on the card. SVGs author at large sizes, so cards scale it down.
@export var icon: Texture2D

## Rarity drives the card frame and the selection weighting.
@export var rarity: Rarity = Rarity.RARE

## Upgrade ids that must already be owned before this can be offered. Empty =
## always eligible (e.g. a brand-new weapon acquisition).
@export var prerequisites: PackedStringArray = PackedStringArray()

## Highest level this upgrade can reach. Once reached it stops being offered.
@export_range(1, 20) var max_level: int = 1

## Relative selection weight within its rarity tier (higher = more common).
@export_range(0.1, 20.0, 0.1) var weight: float = 1.0

## Effects applied each time this upgrade is chosen.
@export var effects: Array[UpgradeEffectData] = []

## Owned upgrade / weapon ids that activate the synergy hint on the card.
@export var synergy_ids: PackedStringArray = PackedStringArray()

## Short line shown when any synergy_id is already owned (e.g. "Synergy: Overcharged Spread").
@export var synergy_hint: String = ""


## Palette token for this rarity (border / accent color).
func rarity_color_token() -> String:
	match rarity:
		Rarity.EPIC: return "purple"
		Rarity.LEGENDARY: return "gold"
		_: return "cyan"


## Human-readable rarity label for the card and debug surfaces.
func rarity_label() -> String:
	match rarity:
		Rarity.EPIC: return "EPIC"
		Rarity.LEGENDARY: return "LEGENDARY"
		_: return "RARE"
