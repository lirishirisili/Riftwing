class_name SecondaryWeaponData
extends Resource
## Balance data for one acquired secondary weapon or ability.
##
## Secondary weapons are driven by SecondaryWeaponSystem, which auto-fires the
## continuous ones on their interval and triggers the ability ones on demand.
## All numbers live here so the runtime node never hard-codes balance
## (docs/04_ARCHITECTURE.md: data resources hold balance, nodes hold behavior).

## How the weapon delivers damage.
## BOLT  - pooled projectiles (straight, aimed, homing, piercing, or exploding).
## CHAIN - instant lightning that jumps between nearby targets.
## BEAM  - a vertical piercing beam from the ship that ticks damage.
## ORBIT - drones circling the ship: contact damage + aimed shots.
enum Kind { BOLT, CHAIN, BEAM, ORBIT }

## Stable id, matched against ACQUIRE_WEAPON effect targets and upgrade targets.
@export var id: String = ""

## Short human-readable name for HUD / debug.
@export var display_name: String = "Weapon"

@export var kind: Kind = Kind.BOLT

## Weapon color (beam, arcs, drones, ring bursts).
@export var color: Color = Color("#00D7FF")

## Seconds between automatic shots. Ability weapons ignore this (fired on demand).
@export_range(0.05, 10.0, 0.05) var interval: float = 1.0

## Bolts emitted per shot (a fan when > 1).
@export_range(1, 24) var projectiles_per_shot: int = 1

## Total fan spread in degrees when projectiles_per_shot > 1.
@export_range(0.0, 360.0, 1.0) var spread_degrees: float = 0.0

## When true, each bolt is aimed at the nearest target at spawn time.
## (In-flight steering comes from the projectile's homing_turn_rate.)
@export var homing: bool = false

## When true this entry is an on-demand ability (HUD button) rather than an
## auto-firing weapon; SecondaryWeaponSystem does not tick it every frame.
@export var is_ability: bool = false

## Per-bolt / per-tick / per-arc damage. Overrides the referenced projectile's
## own damage so one visual projectile can be shared at different power levels.
@export_range(0.0, 1000.0, 1.0) var damage: float = 10.0

## Muzzle offset from the player core in logical pixels (up is -Y).
@export var muzzle_offset: Vector2 = Vector2(0.0, -70.0)

## The projectile fired by this weapon (BOLT, and ORBIT drone shots).
@export var projectile: ProjectileData

# --- CHAIN ------------------------------------------------------------------

## Max distance from the ship to the first target.
@export_range(50.0, 2000.0, 10.0) var chain_range: float = 700.0
## Extra targets after the first.
@export_range(0, 30) var chain_jumps: int = 3
## Max distance between two links of the chain.
@export_range(50.0, 1000.0, 10.0) var chain_jump_range: float = 260.0

# --- BEAM -------------------------------------------------------------------

## Half width of the beam in logical px.
@export_range(4.0, 200.0, 1.0) var beam_half_width: float = 22.0
## Seconds the beam stays on per cycle (>= interval means always on).
@export_range(0.1, 30.0, 0.1) var beam_duration: float = 1.2
## Seconds between damage ticks while the beam is on.
@export_range(0.03, 1.0, 0.01) var beam_tick: float = 0.1

# --- ORBIT ------------------------------------------------------------------

@export_range(1, 8) var orbit_count: int = 2
@export_range(40.0, 400.0, 5.0) var orbit_radius: float = 120.0
## Radians per second.
@export_range(0.2, 12.0, 0.1) var orbit_speed: float = 2.6
## Body radius of a drone (contact damage + bolt blocking).
@export_range(6.0, 80.0, 1.0) var orbit_body_radius: float = 22.0
## Contact damage per second as a fraction of `damage`.
@export_range(0.0, 10.0, 0.1) var orbit_contact_dps_ratio: float = 1.5
## Drones erase enemy bolts they touch.
@export var orbit_blocks_bullets: bool = false

# --- Levels / evolution ------------------------------------------------------

## Damage multiplier per weapon level above 1.
@export_range(1.0, 3.0, 0.01) var level_damage_mult: float = 1.2
## Fire-rate multiplier per weapon level above 1.
@export_range(1.0, 2.0, 0.01) var level_rate_mult: float = 1.06
## +1 projectile / arc jump / drone every N levels (0 = never).
@export_range(0, 5) var level_count_every: int = 2

## The weapon this one becomes when its evolution card is taken.
@export var evolves_into: SecondaryWeaponData
