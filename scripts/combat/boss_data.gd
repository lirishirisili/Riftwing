class_name BossData
extends Resource
## Balance, visuals, and phased attack lists for a boss encounter.
##
## The Boss runtime node reads these values; no boss constant is hard-coded
## (docs/04_ARCHITECTURE.md). Phase 1 and phase 2 each carry their own ordered
## list of BossPatternData, so a single health threshold changes both the attack
## behavior and its visuals through data alone (docs/02_GAMEPLAY_SPEC.md: boss
## phases change visuals and projectile behavior).

## Display name shown on the health bar and warning banner.
@export var display_name: String = "Void Titan"

## Total hit points across the whole fight.
@export_range(100.0, 100000.0, 10.0) var max_health: float = 2400.0

## Body sprite (boss placeholder SVG) and its scale (SVGs author at 1024px).
@export var sprite: Texture2D
@export_range(0.05, 2.0, 0.01) var sprite_scale: float = 0.5

## Radius of the circular hurtbox in logical pixels.
@export_range(20.0, 400.0, 1.0) var hit_radius: float = 150.0

## Contact damage if the player rams the boss body.
@export_range(0.0, 200.0, 1.0) var contact_damage: float = 20.0

## Number of segments drawn on the health bar (segmented per prompt 06).
@export_range(1, 40) var health_segments: int = 20

# --- Entrance ---------------------------------------------------------------

## Seconds the WARNING banner shows before the boss flies in.
@export_range(0.5, 6.0, 0.1) var warning_seconds: float = 2.2

## Seconds to fly from above the top edge to the hold position.
@export_range(0.3, 5.0, 0.1) var entry_seconds: float = 1.6

## Hold position as a fraction of screen size; the boss stays in the upper area
## so the lower screen remains the player's dodge space.
@export var hold_ratio: Vector2 = Vector2(0.5, 0.24)

# --- Phases -----------------------------------------------------------------

## Fraction of max health at which the fight enters phase 2 (prompt 06: 40%).
@export_range(0.05, 0.95, 0.01) var phase2_threshold: float = 0.4

## Ordered attack patterns cycled during phase 1.
@export var phase1_patterns: Array[BossPatternData] = []

## Ordered attack patterns cycled during phase 2 (denser / faster).
@export var phase2_patterns: Array[BossPatternData] = []
