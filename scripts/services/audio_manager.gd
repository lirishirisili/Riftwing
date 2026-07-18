extends Node
## Layered audio facade (autoload) — SFX pool + music + prefs.
##
## Gameplay/UI route named cues through play_sfx / play_music. Streams live under
## assets/audio. Focus loss ducks playback (AppRoot). Volumes persist in
## user://audio_prefs.cfg (not SaveManager).

const PRIORITY_LOW := 0
const PRIORITY_MEDIUM := 1
const PRIORITY_HIGH := 2

const GROUP_UI := "ui"
const GROUP_COMBAT := "combat"
const GROUP_WORLD := "world"
const GROUP_MUSIC := "music"

const BUS_MASTER := "Master"
const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"

const _PREFS_PATH := "user://audio_prefs.cfg"
const _SFX_POOL_SIZE := 12
const _VOICE_CAP_HIT := 3
const _MUSIC_FADE := 0.45
const _FIRE_LOOP_PATH := "res://assets/audio/sfx/fire_loop.ogg"
const _FIRE_LOOP_DB := -14.0
const _FIRE_LOOP_FADE := 0.1

const CUE_CATALOG := {
	"ui_click": {"group": GROUP_UI, "priority": PRIORITY_MEDIUM, "path": "res://assets/audio/sfx/ui_click.ogg"},
	"ui_confirm": {"group": GROUP_UI, "priority": PRIORITY_MEDIUM, "path": "res://assets/audio/sfx/ui_confirm.ogg"},
	"ui_back": {"group": GROUP_UI, "priority": PRIORITY_LOW, "path": "res://assets/audio/sfx/ui_back.ogg"},
	## Kept for catalog/API compatibility; playback is the soft fire loop, not one-shots.
	"fire": {"group": GROUP_COMBAT, "priority": PRIORITY_LOW, "path": "res://assets/audio/sfx/fire.ogg"},
	"hit": {"group": GROUP_COMBAT, "priority": PRIORITY_LOW, "path": "res://assets/audio/sfx/hit.ogg"},
	"player_hit": {"group": GROUP_COMBAT, "priority": PRIORITY_HIGH, "path": "res://assets/audio/sfx/player_hit.ogg"},
	"shield_impact": {"group": GROUP_COMBAT, "priority": PRIORITY_MEDIUM, "path": "res://assets/audio/sfx/shield_impact.ogg"},
	"pickup": {"group": GROUP_WORLD, "priority": PRIORITY_MEDIUM, "path": "res://assets/audio/sfx/pickup.ogg"},
	"explosion_small": {"group": GROUP_COMBAT, "priority": PRIORITY_MEDIUM, "path": "res://assets/audio/sfx/explosion_small.ogg"},
	"explosion_large": {"group": GROUP_COMBAT, "priority": PRIORITY_HIGH, "path": "res://assets/audio/sfx/explosion_large.ogg"},
	"ability": {"group": GROUP_COMBAT, "priority": PRIORITY_MEDIUM, "path": "res://assets/audio/sfx/ability.ogg"},
	"upgrade_open": {"group": GROUP_UI, "priority": PRIORITY_HIGH, "path": "res://assets/audio/sfx/upgrade_open.ogg"},
	"upgrade_select": {"group": GROUP_UI, "priority": PRIORITY_HIGH, "path": "res://assets/audio/sfx/upgrade_select.ogg"},
	"boss_warning": {"group": GROUP_WORLD, "priority": PRIORITY_HIGH, "path": "res://assets/audio/sfx/boss_warning.ogg"},
	"boss_laser": {"group": GROUP_COMBAT, "priority": PRIORITY_HIGH, "path": "res://assets/audio/sfx/boss_laser.ogg"},
	"boss_phase": {"group": GROUP_WORLD, "priority": PRIORITY_HIGH, "path": "res://assets/audio/sfx/boss_phase.ogg"},
	"boss_defeated": {"group": GROUP_WORLD, "priority": PRIORITY_HIGH, "path": "res://assets/audio/sfx/boss_defeated.ogg"},
	"victory_fanfare": {"group": GROUP_MUSIC, "priority": PRIORITY_HIGH, "path": "res://assets/audio/sfx/victory_fanfare.ogg"},
	"run_failed": {"group": GROUP_MUSIC, "priority": PRIORITY_HIGH, "path": "res://assets/audio/sfx/run_failed.ogg"},
}

const CUE_ALIASES := {
	"explosion": "explosion_small",
	"weapon_fire": "fire",
	"player_fire": "fire",
}

const MUSIC_TRACKS := {
	"menu": "res://assets/audio/music/music_menu.ogg",
	"run": "res://assets/audio/music/music_run.ogg",
	"boss": "res://assets/audio/music/music_boss.ogg",
}

var enabled: bool = true
var has_focus: bool = true
var master_linear: float = 1.0
var music_linear: float = 0.75
var sfx_linear: float = 1.0

var last_sfx: String = ""
var last_priority: int = PRIORITY_LOW
var last_group: String = GROUP_COMBAT
var last_music: String = ""
var sfx_count: int = 0
var _per_cue: Dictionary = {}
var _per_group: Dictionary = {}
var _focus_blocked: int = 0

var _streams: Dictionary = {}
var _music_streams: Dictionary = {}
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_priority: Array[int] = []
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_using_a: bool = true
var _fade_tween: Tween
var _fire_loop_player: AudioStreamPlayer
var _fire_loop_stream: AudioStream
var _fire_loop_wanted: bool = false
var _fire_loop_suppressed: bool = false
var _fire_fade_tween: Tween
var fire_loop_playing: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	_load_prefs()
	_build_pool()
	_preload_streams()
	_apply_bus_volumes()


func _ensure_buses() -> void:
	if AudioServer.get_bus_index(BUS_MUSIC) < 0:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, BUS_MUSIC)
		AudioServer.set_bus_send(AudioServer.bus_count - 1, BUS_MASTER)
	if AudioServer.get_bus_index(BUS_SFX) < 0:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, BUS_SFX)
		AudioServer.set_bus_send(AudioServer.bus_count - 1, BUS_MASTER)


func _build_pool() -> void:
	for i in _SFX_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = BUS_SFX
		p.finished.connect(_on_sfx_finished.bind(p))
		add_child(p)
		_sfx_players.append(p)
		_sfx_priority.append(PRIORITY_LOW)
	_music_a = AudioStreamPlayer.new()
	_music_a.bus = BUS_MUSIC
	add_child(_music_a)
	_music_b = AudioStreamPlayer.new()
	_music_b.bus = BUS_MUSIC
	add_child(_music_b)
	_fire_loop_player = AudioStreamPlayer.new()
	_fire_loop_player.bus = BUS_SFX
	_fire_loop_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_fire_loop_player)


func _preload_streams() -> void:
	for cue in CUE_CATALOG.keys():
		var entry: Dictionary = CUE_CATALOG[cue]
		var path := String(entry.get("path", ""))
		if path != "" and ResourceLoader.exists(path):
			_streams[cue] = load(path)
	for track in MUSIC_TRACKS.keys():
		var path := String(MUSIC_TRACKS[track])
		if ResourceLoader.exists(path):
			var stream: AudioStream = load(path)
			if stream is AudioStreamOggVorbis:
				(stream as AudioStreamOggVorbis).loop = true
			_music_streams[track] = stream
	if ResourceLoader.exists(_FIRE_LOOP_PATH):
		_fire_loop_stream = load(_FIRE_LOOP_PATH)
		if _fire_loop_stream is AudioStreamOggVorbis:
			(_fire_loop_stream as AudioStreamOggVorbis).loop = true


func set_has_focus(focused: bool) -> void:
	has_focus = focused
	if not focused:
		_stop_all_sfx()
		_sync_fire_loop()
		if _music_a != null:
			_music_a.stream_paused = true
		if _music_b != null:
			_music_b.stream_paused = true
	else:
		if _music_a != null:
			_music_a.stream_paused = false
		if _music_b != null:
			_music_b.stream_paused = false
		_sync_fire_loop()


func set_enabled(value: bool) -> void:
	enabled = value
	_apply_bus_volumes()
	if not enabled:
		_stop_all_sfx()
		stop_music()
	_sync_fire_loop()
	_save_prefs()


## Soft continuous plasma bed while autofire is active (shmup sustain).
func start_fire_loop() -> void:
	_fire_loop_wanted = true
	_sync_fire_loop()


func stop_fire_loop() -> void:
	_fire_loop_wanted = false
	_sync_fire_loop()


## Pause menus / upgrade overlay suppress the loop without clearing weapon intent.
func set_fire_loop_suppressed(suppressed: bool) -> void:
	_fire_loop_suppressed = suppressed
	_sync_fire_loop()


func is_fire_loop_wanted() -> bool:
	return _fire_loop_wanted


func _sync_fire_loop() -> void:
	var should := (
		_fire_loop_wanted
		and not _fire_loop_suppressed
		and enabled
		and has_focus
		and _fire_loop_player != null
		and _fire_loop_stream != null
	)
	if should:
		_play_fire_loop()
	else:
		_fade_stop_fire_loop()


func _play_fire_loop() -> void:
	if _fire_loop_player == null or _fire_loop_stream == null:
		return
	if _fire_loop_player.playing and fire_loop_playing:
		return
	if _fire_fade_tween != null and _fire_fade_tween.is_valid():
		_fire_fade_tween.kill()
	_fire_loop_player.stream = _fire_loop_stream
	_fire_loop_player.volume_db = -40.0
	_fire_loop_player.play()
	fire_loop_playing = true
	_fire_fade_tween = create_tween()
	_fire_fade_tween.tween_property(_fire_loop_player, "volume_db", _FIRE_LOOP_DB, _FIRE_LOOP_FADE)


func _fade_stop_fire_loop() -> void:
	if _fire_loop_player == null:
		return
	if not _fire_loop_player.playing and not fire_loop_playing:
		return
	if _fire_fade_tween != null and _fire_fade_tween.is_valid():
		_fire_fade_tween.kill()
	fire_loop_playing = false
	var p := _fire_loop_player
	_fire_fade_tween = create_tween()
	_fire_fade_tween.tween_property(p, "volume_db", -40.0, _FIRE_LOOP_FADE)
	_fire_fade_tween.tween_callback(func() -> void:
		if p != null and not fire_loop_playing:
			p.stop()
	)


func set_master_volume(linear: float) -> void:
	master_linear = clampf(linear, 0.0, 1.0)
	_apply_bus_volumes()
	_save_prefs()


func set_music_volume(linear: float) -> void:
	music_linear = clampf(linear, 0.0, 1.0)
	_apply_bus_volumes()
	_save_prefs()


func set_sfx_volume(linear: float) -> void:
	sfx_linear = clampf(linear, 0.0, 1.0)
	_apply_bus_volumes()
	_save_prefs()


func _apply_bus_volumes() -> void:
	var master := 0.0 if not enabled else master_linear
	_set_bus_linear(BUS_MASTER, master)
	_set_bus_linear(BUS_MUSIC, music_linear)
	_set_bus_linear(BUS_SFX, sfx_linear)


func _set_bus_linear(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	var db := -80.0 if linear <= 0.001 else linear_to_db(linear)
	AudioServer.set_bus_volume_db(idx, db)


func resolve_cue(cue: String) -> Dictionary:
	var name := cue
	if CUE_ALIASES.has(name):
		name = String(CUE_ALIASES[name])
	if CUE_CATALOG.has(name):
		var entry: Dictionary = CUE_CATALOG[name]
		return {
			"cue": name,
			"group": String(entry.get("group", GROUP_COMBAT)),
			"priority": int(entry.get("priority", PRIORITY_LOW)),
		}
	return {"cue": name, "group": GROUP_COMBAT, "priority": PRIORITY_LOW}


func play_sfx(cue: String, _world_pos: Vector2 = Vector2.ZERO, priority: int = -1) -> void:
	if not enabled:
		return
	if not has_focus:
		_focus_blocked += 1
		return
	var resolved := resolve_cue(cue)
	var final_cue := String(resolved["cue"])
	var group := String(resolved["group"])
	var final_priority := priority if priority >= 0 else int(resolved["priority"])
	last_sfx = final_cue
	last_priority = final_priority
	last_group = group
	sfx_count += 1
	_per_cue[final_cue] = int(_per_cue.get(final_cue, 0)) + 1
	_per_group[group] = int(_per_group.get(group, 0)) + 1

	# Autofire uses the dedicated soft loop — never one-shot spam.
	if final_cue == "fire":
		return
	if final_cue == "hit" and _count_playing_cue_approx("hit") >= _VOICE_CAP_HIT:
		return

	var stream: AudioStream = _streams.get(final_cue) as AudioStream
	if stream == null:
		return
	var player := _acquire_sfx_player(final_priority)
	if player == null:
		return
	player.stream = stream
	player.volume_db = _priority_db(final_priority)
	player.play()


func play_ui(cue: String) -> void:
	play_sfx(cue, Vector2.ZERO, -1)


func play_music(track_id: String) -> void:
	if track_id == last_music and _current_music_player() != null and _current_music_player().playing:
		return
	if not enabled or not has_focus:
		last_music = track_id
		return
	var stream: AudioStream = _music_streams.get(track_id) as AudioStream
	if stream == null:
		return
	last_music = track_id
	var incoming := _music_b if _music_using_a else _music_a
	var outgoing := _music_a if _music_using_a else _music_b
	_music_using_a = not _music_using_a
	incoming.stream = stream
	incoming.volume_db = -40.0
	incoming.play()
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.set_parallel(true)
	_fade_tween.tween_property(incoming, "volume_db", 0.0, _MUSIC_FADE)
	if outgoing.playing:
		_fade_tween.tween_property(outgoing, "volume_db", -40.0, _MUSIC_FADE)
		_fade_tween.chain().tween_callback(func() -> void:
			outgoing.stop()
			outgoing.volume_db = 0.0
		)
	else:
		outgoing.volume_db = 0.0


func stop_music() -> void:
	last_music = ""
	if _music_a != null:
		_music_a.stop()
	if _music_b != null:
		_music_b.stop()


func get_last_music() -> String:
	return last_music


func cue_count(cue: String) -> int:
	var resolved := resolve_cue(cue)
	return int(_per_cue.get(String(resolved["cue"]), 0))


func group_count(group: String) -> int:
	return int(_per_group.get(group, 0))


func distinct_cues() -> int:
	return _per_cue.size()


func catalog_size() -> int:
	return CUE_CATALOG.size()


func focus_blocked_count() -> int:
	return _focus_blocked


func _current_music_player() -> AudioStreamPlayer:
	return _music_a if _music_using_a else _music_b


func _acquire_sfx_player(priority: int) -> AudioStreamPlayer:
	for i in _sfx_players.size():
		if not _sfx_players[i].playing:
			_sfx_priority[i] = priority
			return _sfx_players[i]
	# Steal lowest priority
	var best := 0
	for i in _sfx_priority.size():
		if _sfx_priority[i] < _sfx_priority[best]:
			best = i
	if _sfx_priority[best] > priority:
		return null
	_sfx_players[best].stop()
	_sfx_priority[best] = priority
	return _sfx_players[best]


func _priority_db(priority: int) -> float:
	match priority:
		PRIORITY_HIGH:
			return 0.0
		PRIORITY_MEDIUM:
			return -2.0
		_:
			return -6.0


func _count_playing_cue_approx(cue: String) -> int:
	var stream: AudioStream = _streams.get(cue) as AudioStream
	if stream == null:
		return 0
	var n := 0
	for p in _sfx_players:
		if p.playing and p.stream == stream:
			n += 1
	return n


func _on_sfx_finished(player: AudioStreamPlayer) -> void:
	var idx := _sfx_players.find(player)
	if idx >= 0:
		_sfx_priority[idx] = PRIORITY_LOW


func _stop_all_sfx() -> void:
	for p in _sfx_players:
		p.stop()
	_fade_stop_fire_loop()


func _load_prefs() -> void:
	if not FileAccess.file_exists(_PREFS_PATH):
		return
	var f := FileAccess.open(_PREFS_PATH, FileAccess.READ)
	if f == null:
		return
	var raw := f.get_as_text().strip_edges()
	f.close()
	# Format: enabled|master|music|sfx
	var parts := raw.split("|")
	if parts.size() >= 1:
		enabled = parts[0] != "0"
	if parts.size() >= 2:
		master_linear = clampf(float(parts[1]), 0.0, 1.0)
	if parts.size() >= 3:
		music_linear = clampf(float(parts[2]), 0.0, 1.0)
	if parts.size() >= 4:
		sfx_linear = clampf(float(parts[3]), 0.0, 1.0)


func _save_prefs() -> void:
	var f := FileAccess.open(_PREFS_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string("%s|%.3f|%.3f|%.3f" % [
		"1" if enabled else "0",
		master_linear,
		music_linear,
		sfx_linear,
	])
	f.close()
