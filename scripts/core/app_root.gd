extends Node
## Top-level application node.
##
## Wires the SceneRouter to its screen holder and the debug overlay, then routes
## to the bootstrap screen (the main menu). Owns app lifecycle hooks for mobile
## hardening: background flush of the save and audio-focus ducking
## (prompts/11_mobile_hardening.md).

@onready var _current_screen: Node = $CurrentScreen
@onready var _debug_overlay: CanvasLayer = $UIOverlay/DebugOverlay

var _backgrounded: bool = false


func _ready() -> void:
	# AppRoot stays ALWAYS so background/focus/Back keep working while a run is
	# paused. CurrentScreen must NOT inherit that — otherwise INHERIT children
	# (the whole run) keep processing and combat continues under Pause / upgrades.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_current_screen.process_mode = Node.PROCESS_MODE_PAUSABLE
	# Mobile default: locked 60 FPS. Do not leave the frame rate uncapped.
	Engine.max_fps = 60
	# Android Back must not auto-quit after we open pause / navigate — AppRoot owns it.
	get_tree().quit_on_go_back = false
	SceneRouter.configure(_current_screen)
	SceneRouter.screen_changed.connect(_on_screen_changed)
	SceneRouter.go_to(SceneRouter.SCREEN_MAIN_MENU)


func _notification(what: int) -> void:
	# APPLICATION_PAUSED/RESUMED are the reliable mobile background signals.
	# Focus-out alone is too noisy on desktop (alt-tab) so it only ducks audio
	# on mobile/web exports, never flushes the save.
	# WM_GO_BACK_REQUEST is the Android system Back button — must be handled or
	# the OS quits the app immediately.
	match what:
		NOTIFICATION_WM_GO_BACK_REQUEST:
			_handle_system_back()
		NOTIFICATION_APPLICATION_PAUSED:
			_enter_background(true)
		NOTIFICATION_APPLICATION_RESUMED:
			_enter_foreground()
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			if _is_mobile_runtime():
				_enter_background(false)
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_WM_WINDOW_FOCUS_IN:
			if _is_mobile_runtime():
				_enter_foreground()


## Android / system Back. Screens may implement handle_system_back() -> bool.
## Mid-run must pause (never quit). Meta screens navigate back. Main menu quits.
func _handle_system_back() -> void:
	var screen := SceneRouter.get_current_screen()
	if screen != null and screen.has_method("handle_system_back"):
		if bool(screen.call("handle_system_back")):
			return
	var id := SceneRouter.get_current_screen_id()
	if id == SceneRouter.SCREEN_MAIN_MENU or id == "":
		get_tree().quit()
		return
	SceneRouter.go_to(SceneRouter.SCREEN_MAIN_MENU)


func _enter_background(flush_save: bool) -> void:
	if _backgrounded and not flush_save:
		AudioManager.set_has_focus(false)
		return
	_backgrounded = true
	AudioManager.set_has_focus(false)
	if PlatformServices.ads != null:
		PlatformServices.ads.on_app_pause()
	if flush_save:
		SaveManager.save_game()


func _enter_foreground() -> void:
	_backgrounded = false
	AudioManager.set_has_focus(true)
	if PlatformServices.ads != null:
		PlatformServices.ads.on_app_resume()


func _is_mobile_runtime() -> bool:
	return OS.has_feature("android") or OS.has_feature("ios") or OS.has_feature("mobile")


func _on_screen_changed(screen_id: String) -> void:
	_debug_overlay.set_screen_id(screen_id)
