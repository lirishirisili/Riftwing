extends Node
## Owns the single active screen and swaps between screens.
##
## Screens are added under the CurrentScreen holder passed by AppRoot. This is
## the only place that instantiates and frees top-level screens, so there is
## never more than one live screen and no orphaned nodes accumulate.

signal screen_changed(screen_id: String)

## Known screen identifiers. Only the visual sandbox exists at bootstrap;
## later milestones register menu, map, hangar, run, and results here.
const SCREEN_VISUAL_SANDBOX := "visual_sandbox"
const SCREEN_MOVEMENT_DEBUG := "movement_debug"
const SCREEN_PROJECTILE_STRESS_TEST := "projectile_stress_test"
const SCREEN_ENEMY_WAVE_DEBUG := "enemy_wave_debug"
const SCREEN_BOSS_DEBUG := "boss_debug"
const SCREEN_VISUAL_FOUNDATION := "visual_foundation"
const SCREEN_RUN := "run"
const SCREEN_RESULTS := "results"
const SCREEN_MAIN_MENU := "main_menu"
const SCREEN_SETTINGS := "settings"
const SCREEN_HANGAR := "hangar"
const SCREEN_STAGE_MAP := "stage_map"
## Shared "coming soon" stand-in for meta destinations owned by later milestones
## (Daily Challenge). Built by the payload it receives.
const SCREEN_PLACEHOLDER := "placeholder"

const _SCREEN_SCENES := {
	SCREEN_VISUAL_SANDBOX: "res://scenes/gameplay/visual_sandbox.tscn",
	SCREEN_MOVEMENT_DEBUG: "res://scenes/player/movement_debug.tscn",
	SCREEN_PROJECTILE_STRESS_TEST: "res://scenes/weapons/projectile_stress_test.tscn",
	SCREEN_ENEMY_WAVE_DEBUG: "res://scenes/gameplay/enemy_wave_debug.tscn",
	SCREEN_BOSS_DEBUG: "res://scenes/gameplay/boss_debug.tscn",
	SCREEN_VISUAL_FOUNDATION: "res://scenes/gameplay/visual_foundation.tscn",
	SCREEN_RUN: "res://scenes/gameplay/run_scene.tscn",
	SCREEN_RESULTS: "res://scenes/ui/results_screen.tscn",
	SCREEN_MAIN_MENU: "res://scenes/ui/main_menu.tscn",
	SCREEN_SETTINGS: "res://scenes/ui/settings_screen.tscn",
	SCREEN_HANGAR: "res://scenes/ui/hangar_screen.tscn",
	SCREEN_STAGE_MAP: "res://scenes/ui/stage_map_screen.tscn",
	SCREEN_PLACEHOLDER: "res://scenes/ui/placeholder_screen.tscn",
}

var _holder: Node = null
var _current: Node = null
var _current_id: String = ""


## Binds the container node that active screens are parented under.
func configure(holder: Node) -> void:
	_holder = holder


## Returns the identifier of the currently active screen.
func get_current_screen_id() -> String:
	return _current_id


## Replaces the active screen with the screen for the given identifier.
##
## An optional `payload` dictionary is handed to the new screen: if the
## instanced root has a `receive_payload(Dictionary)` method it is called before
## the screen is added to the tree, so screens like results can be built from run
## data without a global singleton. Pausing is always cleared on a transition so
## a screen swapped in from a paused run starts running.
func go_to(screen_id: String, payload: Dictionary = {}) -> void:
	if _holder == null:
		push_error("SceneRouter: holder not configured before go_to(%s)" % screen_id)
		return
	if not _SCREEN_SCENES.has(screen_id):
		push_error("SceneRouter: unknown screen id '%s'" % screen_id)
		return

	var packed: PackedScene = load(_SCREEN_SCENES[screen_id])
	if packed == null:
		push_error("SceneRouter: failed to load scene for '%s'" % screen_id)
		return

	if is_instance_valid(_current):
		_current.queue_free()
		_current = null

	# A prior screen may have paused the tree (e.g. an upgrade choice); never
	# leave a fresh screen frozen.
	get_tree().paused = false

	_current = packed.instantiate()
	_current_id = screen_id
	if not payload.is_empty() and _current.has_method("receive_payload"):
		_current.call("receive_payload", payload)
	_holder.add_child(_current)
	screen_changed.emit(screen_id)
