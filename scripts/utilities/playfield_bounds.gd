class_name PlayfieldBounds
extends RefCounted
## Offscreen cull rect for projectiles and pickups.
##
## Matches the historical pool margin (~200× / ~400 y) around the logical
## screen. With canvas_items + aspect=expand the viewport grows on tablets, so
## callers must rebuild this from the live screen size — a fixed 1080-wide box
## culls player bolts spawned on the expanded right lane.

const MARGIN_L := 200.0
const MARGIN_T := 400.0
const MARGIN_R := 200.0
const MARGIN_B := 400.0


static func from_screen(screen: Vector2) -> Rect2:
	return Rect2(
		-MARGIN_L,
		-MARGIN_T,
		screen.x + MARGIN_L + MARGIN_R,
		screen.y + MARGIN_T + MARGIN_B
	)
