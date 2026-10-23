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

## Enemies a bolt passes through before it is spent (0 = stops on first hit).
@export_range(0, 20) var pierce: int = 0

## Homing steer rate in radians/second toward the nearest target (0 = straight).
@export_range(0.0, 30.0, 0.1) var homing_turn_rate: float = 0.0

## Area blast radius on impact (0 = single target).
@export_range(0.0, 600.0, 5.0) var explode_radius: float = 0.0

## Area blast damage as a fraction of `damage`.
@export_range(0.0, 3.0, 0.05) var explode_damage_ratio: float = 0.75

## Also detonate when the lifetime runs out (lobbed bombs).
@export var explode_on_expire: bool = false

## Number of blast pulses (1 = single blast; >1 = a lingering vortex that
## re-detonates every `pulse_interval` seconds).
@export_range(1, 12) var explode_pulses: int = 1
@export_range(0.05, 2.0, 0.05) var pulse_interval: float = 0.35

## Runtime-only flag (never authored): set on the cached crit duplicate a
## weapon builds, so impact feedback can show a crit number.
var is_crit: bool = false
