class_name UpgradeEffectData
extends Resource
## One atomic effect applied when an upgrade is chosen.
##
## Effects are pure data (docs/04_ARCHITECTURE.md: data resources hold balance,
## runtime nodes hold behavior). UpgradeManager reads `kind` + `target` + `value`
## and routes them to the right runtime system; no numbers live in code.

## What the effect does. Kept as an enum so the manager can switch without
## string typos, while authoring stays readable in the inspector.
enum Kind {
	ACQUIRE_WEAPON,   ## Adds a weapon id to the run loadout (level 1).
	FIRE_RATE_MULT,   ## Multiplies a weapon's fire rate by `value`.
	PROJECTILES_ADD,  ## Adds `value` (rounded) projectiles per shot.
	SPREAD_ADD,       ## Adds `value` degrees to the fan spread.
	DAMAGE_MULT,      ## Multiplies a weapon's projectile damage by `value`.
}

## The effect type.
@export var kind: Kind = Kind.FIRE_RATE_MULT

## Weapon id the effect targets (e.g. "plasma"). Empty for global effects.
@export var target: String = "plasma"

## Magnitude. Meaning depends on `kind` (a multiplier, a count, or degrees).
@export var value: float = 1.0
