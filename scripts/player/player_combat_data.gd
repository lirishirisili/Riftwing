class_name PlayerCombatData
extends Resource
## Player survivability values (kept separate from movement data).

## Maximum and starting hit points.
@export_range(1.0, 1000.0, 1.0) var max_health: float = 100.0

## Invulnerability window after taking a hit, in seconds (spec: ~0.8-1.2).
@export_range(0.0, 3.0, 0.05) var invuln_seconds: float = 1.0
