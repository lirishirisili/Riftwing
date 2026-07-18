class_name WaveEventData
extends Resource
## One timed spawn instruction within a WaveData.
##
## Describes when to spawn, which enemy, how many, the formation, and the
## per-enemy entry/wait/exit timing. All values are data; the WaveDirector only
## interprets them.

## Seconds from wave start when this event fires.
@export_range(0.0, 300.0, 0.1) var time: float = 0.0

## Enemy archetype to spawn.
@export var enemy: EnemyData

## Number of enemies in this event.
@export_range(1, 40) var count: int = 5

## Formation kind: "row" (horizontal line) or "vee" (shallow V).
@export_enum("row", "vee") var formation: String = "row"

## Horizontal center of the formation as a fraction of screen width (0..1).
@export_range(0.0, 1.0, 0.01) var center_x_ratio: float = 0.5

## Spacing between formation slots in logical pixels.
@export_range(40.0, 400.0, 5.0) var spacing: float = 150.0

## Y position (logical pixels) the formation holds at during WAIT.
@export_range(0.0, 1920.0, 10.0) var hold_y: float = 420.0

## Seconds to fly in from off-screen to the hold position.
@export_range(0.1, 8.0, 0.1) var entry_seconds: float = 1.2

## Seconds to hold at the formation before exiting.
@export_range(0.0, 30.0, 0.5) var wait_seconds: float = 4.0

## Seconds to fly out (downward, past the player) after waiting.
@export_range(0.1, 8.0, 0.1) var exit_seconds: float = 2.0
