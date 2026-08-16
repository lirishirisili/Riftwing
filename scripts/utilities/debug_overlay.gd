extends CanvasLayer
## Developer overlay: FPS, memory, safe-area, quality, pools, audio focus.
##
## Hidden by default (milestone 15). Toggle with F3 (`debug_toggle`) or a
## three-finger tap on touch devices. Safe-area outline toggles with F4.
## Purely diagnostic; no gameplay logic.

var _screen_id: String = "-"
var _active_touches: Dictionary = {}

@onready var _panel: PanelContainer = $Panel
@onready var _label: Label = $Panel/Margin/Info
@onready var _safe_rect_draw: Control = $SafeRect


func _ready() -> void:
	layer = 128
	visible = false
	GameFeel.debug_markers_enabled = false
	if _safe_rect_draw != null:
		_safe_rect_draw.visible = false
	add_to_group("debug_ui")
	_safe_rect_draw.draw.connect(_on_safe_rect_draw)
	set_process(true)


func set_screen_id(screen_id: String) -> void:
	_screen_id = screen_id


func _process(_delta: float) -> void:
	if not visible:
		return
	var vp_size := get_viewport().get_visible_rect().size
	var safe := SafeArea.get_logical_rect(get_tree())
	var platform := PlatformServices.get_platform_name()
	var mem_static := Performance.get_monitor(Performance.MEMORY_STATIC)
	var mem_static_max := Performance.get_monitor(Performance.MEMORY_STATIC_MAX)
	var obj_count := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var node_count := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var pool_line := _pool_summary()
	_label.text = "\n".join([
		"RIFTSTRIKE · debug",
		"FPS: %d" % Engine.get_frames_per_second(),
		"Mem: %.1f / %.1f MB" % [mem_static / 1048576.0, mem_static_max / 1048576.0],
		"Objects: %d  Nodes: %d" % [obj_count, node_count],
		"Viewport: %d x %d (%.2f)" % [int(vp_size.x), int(vp_size.y), vp_size.x / maxf(1.0, vp_size.y)],
		"Safe: (%d, %d) %d x %d" % [
			int(safe.position.x), int(safe.position.y),
			int(safe.size.x), int(safe.size.y)
		],
		"Screen: %s" % _screen_id,
		"Platform: %s" % platform,
		"Effects: %s  Haptics: %s" % [
			GameFeel.quality_name(),
			"ON" if GameFeel.haptics_enabled else "OFF",
		],
		"Audio: %s  Focus: %s" % [
			"ON" if AudioManager.enabled else "OFF",
			"YES" if AudioManager.has_focus else "NO",
		],
		pool_line,
	])
	_safe_rect_draw.queue_redraw()


func _pool_summary() -> String:
	var nodes := get_tree().get_nodes_in_group("pool_stats")
	if nodes.is_empty():
		return "Pools: (none in scene)"
	var active := 0
	var total := 0
	var blocked := 0
	var peak := 0
	for node in nodes:
		if node.has_method("get_stats"):
			var s: Dictionary = node.call("get_stats")
			active += int(s.get("active", 0))
			total += int(s.get("total", 0))
			blocked += int(s.get("blocked", 0))
			peak = maxi(peak, int(s.get("peak", 0)))
	return "Pools: act %d / tot %d  peak %d  blocked %d" % [active, total, peak, blocked]


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_toggle"):
		_toggle_overlay()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("debug_toggle_safe_area"):
		_safe_rect_draw.visible = not _safe_rect_draw.visible
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch:
		_handle_touch(event as InputEventScreenTouch)


func _handle_touch(touch: InputEventScreenTouch) -> void:
	if touch.canceled or not touch.pressed:
		_active_touches.erase(touch.index)
		return
	_active_touches[touch.index] = true
	# Optional mobile toggle: three concurrent fingers (does not steal one-finger drag).
	if _active_touches.size() >= 3:
		_toggle_overlay()
		_active_touches.clear()
		get_viewport().set_input_as_handled()


func _toggle_overlay() -> void:
	visible = not visible
	GameFeel.debug_markers_enabled = visible


func _on_safe_rect_draw() -> void:
	if not _safe_rect_draw.visible:
		return
	var safe := SafeArea.get_logical_rect(get_tree())
	var outline := Palette.get_color("cyan", Color.CYAN)
	_safe_rect_draw.draw_rect(safe, outline, false, 3.0)
