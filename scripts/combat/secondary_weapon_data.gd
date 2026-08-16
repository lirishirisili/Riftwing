class_name SecondaryWeaponData
extends Resource
## Balance data for one acquired secondary weapon or ability.
##
## Secondary weapons are driven by SecondaryWeaponSystem, which auto-fires the
## continuous ones on their interval and triggers the ability ones on demand.
## All numbers live here so the runtime node never hard-codes balance
## (docs/04_ARCHITECTURE.md: data resources hold balance, nodes hold behavior).

## Stable id, matched against ACQUIRE_WEAPON effect targets and upgrade targets.
@export var id: String = ""

## Short human-readable name for HUD / debug.
@export var display_name: String = "Weapon"

## Seconds between automatic shots. Ability weapons ignore this (fired on demand).
@export_range(0.05, 10.0, 0.05) var interval: float = 1.0

## Bolts emitted per shot (a fan when > 1).
@export_range(1, 24) var projectiles_per_shot: int = 1

## Total fan spread in degrees when projectiles_per_shot > 1.
@export_range(0.0, 360.0, 1.0) var spread_degrees: float = 0.0

## When true, each bolt is aimed at the nearest target at spawn time (no in-flight
## steering — pool friendly). Otherwise bolts fire straight up.
@export var homing: bool = false

## When true this entry is an on-demand ability (HUD button) rather than an
## auto-firing weapon; SecondaryWeaponSystem does not tick it every frame.
@export var is_ability: bool = false

## Per-bolt damage. Overrides the referenced projectile's own damage so the same
## visual projectile can be shared across weapons at different power levels.
@export_range(0.0, 1000.0, 1.0) var damage: float = 10.0

## Muzzle offset from the player core in logical pixels (up is -Y).
@export var muzzle_offset: Vector2 = Vector2(0.0, -70.0)

## The projectile fired by this weapon (visual + speed/lifetime/radius).
@export var projectile: ProjectileData
