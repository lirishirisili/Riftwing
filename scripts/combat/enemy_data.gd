class_name EnemyData
extends Resource
## Balance, visuals, and behavior flags for a single enemy archetype.
##
## Scout vs Shooter is expressed purely as data (docs/04_ARCHITECTURE.md): the
## Enemy runtime node reads these values; no archetype-specific script exists.

## Human-readable name for debug surfaces.
@export var display_name: String = "Enemy"

## Hit points before destruction.
@export_range(1.0, 5000.0, 1.0) var max_health: float = 20.0

## Damage dealt to the player on body contact.
@export_range(0.0, 1000.0, 1.0) var contact_damage: float = 12.0

## Energy pickups dropped on death.
@export_range(0, 20) var energy_drop: int = 1

## Elite / chest beat: tougher silhouette + guaranteed fat energy drop.
@export var is_elite: bool = false

## Body sprite and its scale (SVGs author at 1024px, so scale is small).
@export var sprite: Texture2D
@export_range(0.01, 2.0, 0.01) var sprite_scale: float = 0.12

## Radius of the circular hurtbox in logical pixels.
@export_range(4.0, 256.0, 1.0) var hit_radius: float = 42.0

## Tint applied to the sprite.
@export var tint: Color = Color("#FF7A1A")

# --- Shooter behavior (ignored when can_shoot is false) ---------------------

## When true this archetype telegraphs and fires bursts while waiting.
@export var can_shoot: bool = false

## Seconds the telegraph is shown before each burst.
@export_range(0.05, 3.0, 0.05) var shoot_telegraph: float = 0.7

## Bullets emitted per burst (fired as a readable fan).
@export_range(1, 12) var burst_count: int = 3

## Total fan spread of a burst in degrees.
@export_range(0.0, 120.0, 1.0) var burst_spread_degrees: float = 26.0

## Rest between the end of one burst cycle and the next telegraph.
@export_range(0.1, 6.0, 0.1) var shoot_rest: float = 1.1

## Projectile fired by this enemy (enemy bullets are a distinct resource).
@export var projectile: ProjectileData
