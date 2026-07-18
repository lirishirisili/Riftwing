class_name BossPatternData
extends Resource
## One boss attack pattern, expressed purely as data.
##
## Following the EnemyData idiom (docs/04_ARCHITECTURE.md: data resources hold
## balance, runtime nodes hold behavior), a single Boss runtime node interprets
## `kind` and reads only the fields relevant to that kind. No attack constants
## live in code; a designer authors every count, angle, and duration in a .tres.
##
## Every pattern has a telegraph window so the attack is readable before it can
## harm the player (docs/02_GAMEPLAY_SPEC.md: every attack has a telegraph and a
## viable safe route).

## Which attack this pattern drives.
enum Kind {
	RADIAL_BURST,  ## Rings of purple bullets with angular safe gaps.
	SWEEP_LASER,   ## A rotating beam that sweeps across an arc.
	SUMMON_WAVE,   ## Spawns small void-spawn enemy waves.
}

## The attack type.
@export var kind: Kind = Kind.RADIAL_BURST

## Label for debug surfaces.
@export var display_name: String = "Pattern"

## Seconds the telegraph is shown before the attack becomes dangerous. The
## player uses this window to reach a safe route.
@export_range(0.1, 4.0, 0.05) var telegraph_seconds: float = 1.0

## Seconds the attack is actively dangerous (bullets fired / beam sweeping /
## adds dropping in).
@export_range(0.1, 12.0, 0.05) var active_seconds: float = 1.2

## Seconds of recovery after the attack before the next pattern begins (breathing
## room so the fight stays readable).
@export_range(0.0, 6.0, 0.05) var recover_seconds: float = 0.8

# --- RADIAL_BURST fields ----------------------------------------------------

## Bullets in a full ring before gaps are carved out.
@export_range(6, 72) var radial_bullets: int = 28

## Number of angular safe gaps carved into the ring.
@export_range(0, 8) var radial_gaps: int = 2

## Width of each safe gap, measured in skipped bullet slots.
@export_range(1, 12) var radial_gap_slots: int = 3

## How many rings are fired in sequence during the active window.
@export_range(1, 12) var radial_rings: int = 3

## Degrees the whole pattern rotates between rings, so the safe corridor shifts
## but stays dodgeable rather than static or unfair.
@export_range(-90.0, 90.0, 1.0) var radial_spin_degrees: float = 8.0

## Purple enemy bullet fired by the radial pattern.
@export var radial_projectile: ProjectileData

# --- SWEEP_LASER fields -----------------------------------------------------

## Total arc the beam sweeps through, in degrees, centered on straight-down.
@export_range(20.0, 220.0, 1.0) var laser_sweep_degrees: float = 130.0

## Half-width of the damaging beam in logical pixels (thin so a safe side exists).
@export_range(6.0, 80.0, 1.0) var laser_half_width: float = 26.0

## Damage applied to the player per hit while standing in the beam.
@export_range(1.0, 200.0, 1.0) var laser_damage: float = 18.0

## When true the beam sweeps back to its start after reaching the end (still
## within active_seconds).
@export var laser_return_sweep: bool = false

# --- SUMMON_WAVE fields -----------------------------------------------------

## Enemy archetype summoned as adds.
@export var summon_enemy: EnemyData

## Number of separate waves summoned during the active window.
@export_range(1, 6) var summon_waves: int = 2

## Enemies per summoned wave.
@export_range(1, 12) var summon_per_wave: int = 4

## Formation spacing for summoned adds, in logical pixels.
@export_range(60.0, 400.0, 5.0) var summon_spacing: float = 150.0
