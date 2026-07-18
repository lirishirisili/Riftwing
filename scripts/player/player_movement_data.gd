class_name PlayerMovementData
extends Resource
## Balance data for player drag-follow movement.
##
## Behavior lives in PlayerShip; tunable values live here so movement feel can
## be adjusted without touching code (docs/04_ARCHITECTURE.md: data resources
## hold balance, runtime nodes hold behavior).

## Higher values make the ship reach the pointer faster. Used as the rate of a
## frame-rate independent exponential smoothing, so feel is stable across FPS.
@export_range(1.0, 40.0, 0.5) var follow_smoothing: float = 18.0

## Logical pixels the ship is kept above the pointer, so a finger never covers
## the ship during drag movement.
@export_range(0.0, 400.0, 1.0) var vertical_offset: float = 150.0

## The rectangle (logical coordinates) the ship's origin is confined to. Inset
## from the 1080x1920 playfield to keep the whole ship silhouette on-screen and
## clear of the top HUD region.
@export var gameplay_rect: Rect2 = Rect2(90.0, 240.0, 900.0, 1500.0)
