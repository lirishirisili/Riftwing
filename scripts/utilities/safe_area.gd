class_name SafeArea
extends RefCounted
## Computes the usable safe rectangle in logical (stretch) coordinates.
##
## Devices report a safe area in native window pixels. Because the project uses
## canvas_items stretch with aspect=expand (1080×1920 base, viewport grows on
## wider/taller screens), we convert those pixels into logical coordinates so
## UI margins line up with the game's coordinate space. On desktop/headless
## there is no cutout, so the safe area equals the full logical viewport.
##
## Windows often reports the monitor *work area* (excluding the taskbar) as the
## display safe area even for a normal game window. Those huge insets are not
## mobile cutouts — we reject implausibly large bands so meta UI is not crushed.

## Max fraction of an axis that a single inset may consume (notch / home bar).
const _MAX_INSET_FRACTION := 0.12


## Returns the safe rectangle for the given tree in logical coordinates.
static func get_logical_rect(tree: SceneTree) -> Rect2:
	var logical_size := _get_logical_size(tree)
	var full := Rect2(Vector2.ZERO, logical_size)

	var window_size := Vector2(DisplayServer.window_get_size())
	if window_size.x <= 0.0 or window_size.y <= 0.0:
		return full

	var native_safe := DisplayServer.get_display_safe_area()
	var native_rect := Rect2(native_safe)
	# No reported insets (typical desktop/headless): whole viewport is safe.
	if native_rect.size == Vector2.ZERO or native_rect == Rect2(Vector2.ZERO, window_size):
		return full

	var inset_l := native_rect.position.x
	var inset_t := native_rect.position.y
	var inset_r := window_size.x - (native_rect.position.x + native_rect.size.x)
	var inset_b := window_size.y - (native_rect.position.y + native_rect.size.y)
	# Reject taskbar / work-area misreports (far larger than phone cutouts).
	if (
		inset_l > window_size.x * _MAX_INSET_FRACTION
		or inset_r > window_size.x * _MAX_INSET_FRACTION
		or inset_t > window_size.y * _MAX_INSET_FRACTION
		or inset_b > window_size.y * _MAX_INSET_FRACTION
	):
		return full

	# Map native pixels -> logical units.
	var scale := logical_size / window_size
	var safe := Rect2(native_rect.position * scale, native_rect.size * scale)
	return safe.intersection(full)


## Returns the logical viewport size (grows from 1080×1920 under expand stretch).
static func _get_logical_size(tree: SceneTree) -> Vector2:
	var root := tree.root
	var vp_size := Vector2(root.get_visible_rect().size)
	if vp_size.x > 0.0 and vp_size.y > 0.0:
		return vp_size
	return Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width", 1080)),
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 1920))
	)
