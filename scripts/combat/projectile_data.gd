class_name ProjectileData
extends Resource
## Balance and visual data for a single projectile.
##
## All tunable values live here (docs/04_ARCHITECTURE.md: data resources hold
## balance, runtime nodes hold behavior). The Projectile node reads these; no
## projectile values are hard-coded in gameplay scripts.

## Travel speed in logical pixels/second.
@export_range(50.0, 4000.0, 10.0) var speed: float = 1400.0

## Seconds before the projectile expires and returns to the pool.
@export_range(0.1, 10.0, 0.1) var lifetime: float = 2.0

## Damage applied on hit (consumed by the combat milestone; unused here).
@export_range(0.0, 1000.0, 1.0) var damage: float = 10.0

## Radius of the round cap / collision core in logical pixels.
@export_range(1.0, 64.0, 0.5) var radius: float = 7.0

## Length of the bolt body in logical pixels (drawn along travel direction).
@export_range(0.0, 256.0, 1.0) var length: float = 34.0

## Body color. Player bolts are cyan per docs/01_VISUAL_DIRECTION.md.
@export var color: Color = Color("#00D7FF")
