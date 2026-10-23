class_name DeviceHapticsService
extends HapticsService
## Haptics on phones through Godot's built-in `Input.vibrate_handheld`
## (Android vibrator / iOS haptic engine). No third-party SDK.
##
## Pulses are short and amplitude-graded so combat feels physical without
## buzzing; GameFeel already rate-limits how often each strength can fire.
## Android needs the VIBRATE permission (enabled on both Android presets).

const _LIGHT_MS := 12
const _MEDIUM_MS := 24
const _HEAVY_MS := 45


func is_available() -> bool:
	return OS.has_feature("android") or OS.has_feature("ios")


func light() -> void:
	Input.vibrate_handheld(_LIGHT_MS, 0.35)


func medium() -> void:
	Input.vibrate_handheld(_MEDIUM_MS, 0.6)


func heavy() -> void:
	Input.vibrate_handheld(_HEAVY_MS, 1.0)
