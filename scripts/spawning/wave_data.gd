class_name WaveData
extends Resource
## An ordered set of timed spawn events forming a single wave/run.

## Descriptive label for debug surfaces.
@export var display_name: String = "Wave"

## Total intended duration in seconds (debug wave = 45).
@export_range(1.0, 600.0, 1.0) var duration: float = 45.0

## Spawn events; the director expects these ordered by ascending `time`.
@export var events: Array[WaveEventData] = []
