class_name WeaponData
extends Resource
## Balance data for an auto-firing weapon.
##
## References a ProjectileData rather than embedding projectile values, so the
## same bolt can be shared across weapons and everything stays data-driven.

## Shots per second while firing is active.
@export_range(0.5, 40.0, 0.5) var fire_rate: float = 8.0

## Projectiles emitted per shot (a spread fan when > 1).
@export_range(1, 16) var projectiles_per_shot: int = 1

## Total fan spread in degrees when projectiles_per_shot > 1.
@export_range(0.0, 180.0, 1.0) var spread_degrees: float = 0.0

## Muzzle offset from the weapon origin in logical pixels (up is -Y).
@export var muzzle_offset: Vector2 = Vector2(0.0, -70.0)

## The projectile fired by this weapon.
@export var projectile: ProjectileData
