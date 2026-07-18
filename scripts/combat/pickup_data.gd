class_name PickupData
extends Resource
## Data for a collectible pickup (energy this milestone).

## Energy granted to the player on collection.
@export_range(1, 100) var value: int = 1

## Visual radius in logical pixels.
@export_range(4.0, 64.0, 1.0) var radius: float = 16.0

## Body color.
@export var color: Color = Color("#00FF9C")

## Downward drift speed in logical pixels/second.
@export_range(0.0, 800.0, 10.0) var fall_speed: float = 140.0

## Seconds before an uncollected pickup despawns.
@export_range(1.0, 30.0, 0.5) var lifetime: float = 9.0
