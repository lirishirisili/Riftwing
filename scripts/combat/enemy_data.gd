class_name EnemyData
extends Resource
## Balance, visuals, and behavior flags for a single enemy archetype.
##
## Scout vs Shooter is expressed purely as data (docs/04_ARCHITECTURE.md): the
## Enemy runtime node reads these values; no archetype-specific script exists.

## Movement/behavior archetype. STANDARD hovers then exits; DIVER drops toward
## the player after a brief hover; TANK is a slow, durable STANDARD variant;
## SPLITTER spawns smaller enemies on death (docs/02_GAMEPLAY_SPEC.md).
enum Behavior { STANDARD, DIVER, TANK, SPLITTER }

## Human-readable name for debug surfaces.
@export var display_name: String = "Enemy"

## Archetype behavior driving the runtime movement / death logic.
@export var behavior: Behavior = Behavior.STANDARD

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

# --- Diver behavior ---------------------------------------------------------

## DIVER: seconds hovered before diving toward the player's column.
@export_range(0.0, 4.0, 0.1) var dive_delay: float = 0.5

## DIVER: how much faster than the authored exit the dive plunges.
@export_range(1.0, 6.0, 0.1) var dive_speed_mult: float = 3.0

# --- Splitter behavior ------------------------------------------------------

## SPLITTER: enemy spawned on death (usually a small, fast archetype).
@export var split_into: EnemyData

## SPLITTER: how many children spawn on death (0 disables splitting).
@export_range(0, 6) var split_count: int = 0

# --- Movement / fire / hull (combat depth pass) -------------------------------

## FORMATION: enter -> hold (bob) -> exit (the original behavior, incl. DIVER).
## WEAVE: descends through the field on a sine path.
## SWOOP: arcs in from one side to the other through its hold point.
## CHARGE: holds, telegraphs, then dashes at where the player was.
## STRAFE: holds, then slides side to side while firing, then exits.
enum Movement { FORMATION, WEAVE, SWOOP, CHARGE, STRAFE }

## AIMED_FAN: telegraphed fan at the player. RING: full ring. SPIRAL: rotating
## stream. DOWN_SPREAD: fan straight down. SNIPE: long line telegraph, one fast bolt.
enum FirePattern { AIMED_FAN, RING, SPIRAL, DOWN_SPREAD, SNIPE }

## SPRITE uses `sprite`; the rest are procedural neon hulls (violet hull +
## warm core, docs/01_VISUAL_DIRECTION.md) for archetypes without final art.
enum Shape { SPRITE, DART, DIAMOND, HEX, CROSS, ORB, CARRIER }

@export var movement: Movement = Movement.FORMATION
@export var fire_pattern: FirePattern = FirePattern.AIMED_FAN
@export var shape: Shape = Shape.SPRITE

## Travel speed for WEAVE (descent) and STRAFE (slide), px/s.
@export_range(40.0, 1200.0, 10.0) var move_speed: float = 240.0
## WEAVE sine amplitude (px) and frequency (cycles/s).
@export_range(0.0, 500.0, 5.0) var weave_amplitude: float = 140.0
@export_range(0.1, 4.0, 0.05) var weave_frequency: float = 0.7
## CHARGE wind-up (telegraph) seconds and dash speed px/s.
@export_range(0.1, 3.0, 0.05) var charge_windup: float = 0.7
@export_range(300.0, 3000.0, 50.0) var charge_speed: float = 1500.0

## RING bullet count.
@export_range(4, 48) var ring_count: int = 12
## SPIRAL: bullets per second per arm, degrees turned per shot, arms, and how
## long one stream lasts after its telegraph.
@export_range(1.0, 30.0, 0.5) var spiral_rate: float = 7.0
@export_range(-90.0, 90.0, 1.0) var spiral_turn_degrees: float = 19.0
@export_range(1, 6) var spiral_arms: int = 2
@export_range(0.3, 8.0, 0.1) var spiral_duration: float = 2.2

## CARRIER-style summoning while holding (null disables).
@export var summon: EnemyData
@export_range(1, 8) var summon_count: int = 3
@export_range(0.5, 20.0, 0.5) var summon_interval: float = 4.0

## Spawn-director budget cost (bigger threats cost more).
@export_range(0.1, 20.0, 0.1) var threat_cost: float = 1.0
## Large explosion + hit-stop on death (replaces the old HP threshold).
@export var big_explosion: bool = false
