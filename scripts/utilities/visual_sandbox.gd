extends Node2D
## Bootstrap visual sandbox.
##
## Displays the three parallax background layers scrolling at different speeds
## plus the placeholder player ship silhouette, so the render pipeline, portrait
## framing, and placeholder assets can be validated. Contains no gameplay: no
## input-driven movement, weapons, enemies, or UI beyond this preview.

## Base downward scroll speed in logical pixels/second. Per-layer depth comes
## from each ParallaxLayer's motion_scale; seamless looping from motion_mirroring.
const _SCROLL_SPEED := 60.0

@onready var _parallax: ParallaxBackground = $Parallax


func _process(delta: float) -> void:
	_parallax.scroll_offset.y += delta * _SCROLL_SPEED
