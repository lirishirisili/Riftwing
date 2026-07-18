extends SceneTree
## Validates export configuration without claiming an iOS binary was built.
## godot --headless --path . --script res://tests/export_validation_probe.gd


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("export_validation_probe: start")
	print("os=%s" % OS.get_name())
	var failed := 0
	failed += _check_identity_and_presets()
	failed += _check_project_portrait_and_version()
	failed += _check_icons()
	failed += _check_android_environment()
	failed += _check_ios_environment_honesty()
	if failed == 0:
		print("EXPORT_VALIDATION_PROBE_OK")
		quit(0)
	else:
		printerr("EXPORT_VALIDATION_PROBE_FAILED count=%d" % failed)
		quit(1)


func _check_identity_and_presets() -> int:
	var identity_text := FileAccess.get_file_as_string("res://manifests/product_identity.json")
	if identity_text.is_empty():
		printerr("product_identity.json missing")
		return 1
	var identity: Variant = JSON.parse_string(identity_text)
	if typeof(identity) != TYPE_DICTIONARY:
		printerr("product_identity.json invalid JSON")
		return 1
	var idict: Dictionary = identity
	var android_id := String(idict.get("android_application_id_provisional", ""))
	var ios_id := String(idict.get("ios_bundle_id_provisional", ""))
	var version_name := String(idict.get("version_name", ""))
	var version_code := int(idict.get("version_code", -1))
	var min_sdk := int(idict.get("android_min_sdk", -1))
	var target_sdk := int(idict.get("android_target_sdk", -1))
	if android_id != "com.lishistudio.riftwing" or ios_id != "com.lishistudio.riftwing":
		printerr("unexpected provisional ids")
		return 1
	if version_name != "0.1.0" or version_code != 1:
		printerr("unexpected version fields")
		return 1
	if min_sdk != 24 or target_sdk != 36:
		printerr("unexpected sdk fields")
		return 1

	var presets := FileAccess.get_file_as_string("res://export_presets.cfg")
	if presets.is_empty():
		printerr("export_presets.cfg missing")
		return 1
	for needle in [
		'name="Android Debug"',
		'name="Android Release"',
		'name="iOS"',
		'package/unique_name="com.lishistudio.riftwing"',
		'application/bundle_identifier="com.lishistudio.riftwing"',
		'version/name="0.1.0"',
		"version/code=1",
		"permissions/vibrate=true",
		"permissions/internet=false",
		'gradle_build/export_format=1',
		'gradle_build/use_gradle_build=true',
		"application/export_project_only=true",
		'application/min_ios_version="15.0"',
		"keystore/release_password=\"\"",
		'application/app_store_team_id=""',
	]:
		if presets.find(needle) < 0:
			printerr("preset missing required field: %s" % needle)
			return 1
	# Release (Gradle) owns explicit SDK overrides; Debug uses template defaults.
	if presets.find('name="Android Release"') < 0:
		printerr("Android Release preset missing")
		return 1
	var release_idx := presets.find('name="Android Release"')
	var release_block := presets.substr(release_idx, mini(2500, presets.length() - release_idx))
	if release_block.find('gradle_build/min_sdk="24"') < 0 or release_block.find('gradle_build/target_sdk="36"') < 0:
		printerr("Android Release missing min/target SDK overrides")
		return 1
	# No legacy brand / no embedded secret-looking release passwords.
	for bad in ["Starforge", "Galaxy Rush", "STARFORGE", "GALAXY RUSH"]:
		if presets.find(bad) >= 0:
			printerr("legacy brand in export_presets.cfg")
			return 1
	if presets.find("BEGIN RSA PRIVATE") >= 0:
		printerr("private key material must not be in export_presets.cfg")
		return 1
	print("identity_presets_ok android=%s ios=%s v=%s/%d" % [
		android_id, ios_id, version_name, version_code])
	return 0


func _check_project_portrait_and_version() -> int:
	var project := FileAccess.get_file_as_string("res://project.godot")
	if project.find("window/handheld/orientation=1") < 0:
		printerr("portrait orientation not set in project.godot")
		return 1
	if project.find('config/version="0.1.0"') < 0:
		printerr("config/version missing")
		return 1
	if project.find("renderer/rendering_method=\"mobile\"") < 0:
		printerr("mobile renderer not set")
		return 1
	print("project_ok portrait+version+mobile_renderer")
	return 0


func _check_icons() -> int:
	var paths := [
		"res://assets/branding/icon_main_192.png",
		"res://assets/branding/icon_adaptive_fg_432.png",
		"res://assets/branding/icon_adaptive_bg_432.png",
		"res://assets/branding/icon_ios_1024.png",
	]
	for path in paths:
		if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
			printerr("icon missing: %s" % path)
			return 1
	print("icons_ok")
	return 0


func _check_android_environment() -> int:
	var sdk := ""
	if OS.has_environment("ANDROID_HOME"):
		sdk = OS.get_environment("ANDROID_HOME")
	elif OS.has_environment("ANDROID_SDK_ROOT"):
		sdk = OS.get_environment("ANDROID_SDK_ROOT")
	else:
		var guess := OS.get_environment("LOCALAPPDATA").path_join("Android/Sdk")
		if DirAccess.dir_exists_absolute(guess):
			sdk = guess
	var templates := OS.get_environment("APPDATA").path_join("Godot/export_templates/4.7.stable")
	var has_sdk := not sdk.is_empty() and DirAccess.dir_exists_absolute(sdk)
	var has_templates := DirAccess.dir_exists_absolute(templates)
	var android_bin := templates.path_join("android_debug.apk")
	var has_android_template := FileAccess.file_exists(android_bin)
	print("android_env sdk=%s templates=%s android_debug_apk=%s" % [
		("yes:" + sdk) if has_sdk else "no",
		"yes" if has_templates else "no",
		"yes" if has_android_template else "no",
	])
	# Environment gaps are reported but do not fail the config probe — the
	# milestone accepts "succeeds when SDK/templates available".
	if not has_sdk:
		print("android_env_note: SDK not detected in this process; configure Editor Settings")
	if not has_android_template:
		print("android_env_note: install Godot 4.7 export templates before APK export")
	return 0


func _check_ios_environment_honesty() -> int:
	var is_mac := OS.get_name() == "macOS"
	if is_mac:
		print("ios_env: macOS host — Xcode build still requires manual signing")
	else:
		print("ios_env: NOT macOS — iOS binary not built or tested here")
	# Ensure docs exist for Mac follow-up.
	if not FileAccess.file_exists("res://docs/EXPORT_VALIDATION.md"):
		printerr("EXPORT_VALIDATION.md missing")
		return 1
	if not FileAccess.file_exists("res://docs/EXPORT_SIGNING.md"):
		printerr("EXPORT_SIGNING.md missing")
		return 1
	var validation := FileAccess.get_file_as_string("res://docs/EXPORT_VALIDATION.md")
	if validation.find("does not claim an iOS binary") < 0 and validation.find("does not claim an iOS") < 0:
		# Soft check — key honesty sentence.
		if validation.find("macOS") < 0:
			printerr("EXPORT_VALIDATION.md missing macOS guidance")
			return 1
	print("ios_docs_ok")
	return 0
