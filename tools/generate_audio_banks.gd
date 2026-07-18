extends SceneTree
## Headless SFX/music WAV synthesizer → assets/audio (then ffmpeg to ogg).
## godot --headless --path . --script res://tools/generate_audio_banks.gd

const SR := 44100
const SFX_DIR := "res://assets/audio/sfx"
const MUSIC_DIR := "res://assets/audio/music"
const TMP_DIR := "user://audio_gen_tmp"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SFX_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MUSIC_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TMP_DIR))

	var sfx := {
		"ui_click": _pad(_tone(880.0, 0.05, 0.28, "square")),
		"ui_confirm": _pad(_mix([_tone(523.0, 0.08, 0.25), _tone(784.0, 0.1, 0.22)])),
		"ui_back": _pad(_tone(392.0, 0.07, 0.22, "square")),
		"fire": _pad(_mix([_sweep(1400.0, 700.0, 0.06, 0.22), _noise(0.05, 0.08)])),
		"hit": _pad(_mix([_tone(220.0, 0.05, 0.2, "square"), _noise(0.04, 0.12)])),
		"player_hit": _pad(_mix([_sweep(300.0, 80.0, 0.18, 0.4), _noise(0.15, 0.25)])),
		"shield_impact": _pad(_mix([_tone(660.0, 0.08, 0.2), _tone(990.0, 0.1, 0.15)])),
		"pickup": _pad(_mix([_tone(740.0, 0.07, 0.22), _tone(988.0, 0.1, 0.2), _tone(1175.0, 0.12, 0.18)])),
		"explosion_small": _pad(_mix([_noise(0.18, 0.35), _sweep(180.0, 40.0, 0.2, 0.3)])),
		"explosion_large": _pad(_mix([_noise(0.35, 0.45), _sweep(140.0, 30.0, 0.4, 0.4), _tone(55.0, 0.35, 0.25)])),
		"ability": _pad(_mix([_sweep(400.0, 900.0, 0.15, 0.28), _tone(1200.0, 0.1, 0.18)])),
		"upgrade_open": _pad(_mix([_tone(440.0, 0.12, 0.22), _tone(554.0, 0.14, 0.2), _tone(659.0, 0.16, 0.18)])),
		"upgrade_select": _pad(_mix([_tone(659.0, 0.1, 0.25), _tone(880.0, 0.14, 0.22), _tone(1175.0, 0.16, 0.2)])),
		"boss_warning": _pad(_mix([_sweep(200.0, 120.0, 0.35, 0.4, "square"), _tone(100.0, 0.35, 0.2)])),
		"boss_laser": _pad(_mix([_tone(180.0, 0.25, 0.25, "saw"), _noise(0.25, 0.15)])),
		"boss_phase": _pad(_mix([_sweep(90.0, 220.0, 0.4, 0.35), _tone(55.0, 0.4, 0.22)])),
		"boss_defeated": _pad(_mix([_tone(523.0, 0.15, 0.25), _tone(659.0, 0.18, 0.22), _tone(784.0, 0.22, 0.2)])),
		"victory_fanfare": _pad(_mix([
			_tone(523.0, 0.18, 0.28),
			_concat(_silence(0.12), _tone(659.0, 0.18, 0.26)),
			_concat(_silence(0.24), _tone(784.0, 0.22, 0.28)),
			_concat(_silence(0.36), _tone(1047.0, 0.35, 0.3)),
		])),
		"run_failed": _pad(_mix([_sweep(400.0, 120.0, 0.45, 0.35), _tone(98.0, 0.45, 0.25)])),
	}

	var abs_tmp := ProjectSettings.globalize_path(TMP_DIR)
	var abs_sfx := ProjectSettings.globalize_path(SFX_DIR)
	var abs_music := ProjectSettings.globalize_path(MUSIC_DIR)

	for name in sfx.keys():
		var wav_path := abs_tmp.path_join("%s.wav" % name)
		_write_wav(wav_path, sfx[name])
		var ogg_path := abs_sfx.path_join("%s.ogg" % name)
		if not _ffmpeg(wav_path, ogg_path):
			printerr("ffmpeg sfx failed %s" % name)
			quit(1)
			return
		print("sfx %s" % name)

	for kind in ["menu", "run", "boss"]:
		var samples := _music(kind, 28.0)
		var wav_path := abs_tmp.path_join("%s.wav" % kind)
		_write_wav(wav_path, samples)
		var ogg_path := abs_music.path_join("music_%s.ogg" % kind)
		if not _ffmpeg(wav_path, ogg_path):
			printerr("ffmpeg music failed %s" % kind)
			quit(1)
			return
		print("music %s" % kind)

	# Soft plasma bed for continuous autofire (shmup sustain loop).
	var fire_loop := _fire_loop(3.0)
	var fl_wav := abs_tmp.path_join("fire_loop.wav")
	_write_wav(fl_wav, fire_loop)
	var fl_ogg := abs_sfx.path_join("fire_loop.ogg")
	if not _ffmpeg(fl_wav, fl_ogg):
		printerr("ffmpeg fire_loop failed")
		quit(1)
		return
	print("sfx fire_loop")

	print("GENERATE_AUDIO_BANKS_OK")
	quit(0)


func _ffmpeg(wav: String, ogg: String) -> bool:
	DirAccess.make_dir_recursive_absolute(ogg.get_base_dir())
	var args := PackedStringArray(["-y", "-i", wav, "-c:a", "libvorbis", "-q:a", "5", ogg])
	var out: Array = []
	var err: Array = []
	var code := OS.execute("ffmpeg", args, out, true, false)
	if code != 0:
		printerr("ffmpeg code=%d %s" % [code, str(err)])
		return false
	return FileAccess.file_exists(ogg)


func _write_wav(path: String, samples: PackedFloat32Array) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("cannot write %s" % path)
		return
	var data_size := samples.size() * 2
	f.store_buffer("RIFF".to_utf8_buffer())
	f.store_32(36 + data_size)
	f.store_buffer("WAVE".to_utf8_buffer())
	f.store_buffer("fmt ".to_utf8_buffer())
	f.store_32(16)
	f.store_16(1)
	f.store_16(1)
	f.store_32(SR)
	f.store_32(SR * 2)
	f.store_16(2)
	f.store_16(16)
	f.store_buffer("data".to_utf8_buffer())
	f.store_32(data_size)
	for i in samples.size():
		var v := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		f.store_16(v)
	f.close()


func _env(i: int, n: int, a: float, d: float, s: float, r: float) -> float:
	var t := float(i) / float(maxi(1, n - 1))
	if t < a:
		return t / maxf(1e-6, a)
	if t < a + d:
		return 1.0 - (1.0 - s) * ((t - a) / maxf(1e-6, d))
	if t > 1.0 - r:
		return s * ((1.0 - t) / maxf(1e-6, r))
	return s


func _tone(freq: float, dur: float, vol: float = 0.4, kind: String = "sine") -> PackedFloat32Array:
	var n := int(SR * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		phase += TAU * freq / float(SR)
		var s := 0.0
		match kind:
			"square":
				s = 1.0 if sin(phase) >= 0.0 else -1.0
			"saw":
				s = fmod(phase / PI, 2.0) - 1.0
			_:
				s = sin(phase)
		out[i] = s * vol * _env(i, n, 0.02, 0.15, 0.55, 0.25)
	return out


func _noise(dur: float, vol: float = 0.3) -> PackedFloat32Array:
	var n := int(SR * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var state := 1234567
	for i in n:
		state = (1103515245 * state + 12345) & 0x7FFFFFFF
		var s := (float(state) / float(0x7FFFFFFF)) * 2.0 - 1.0
		out[i] = s * vol * _env(i, n, 0.01, 0.2, 0.35, 0.4)
	return out


func _sweep(f0: float, f1: float, dur: float, vol: float = 0.35, kind: String = "sine") -> PackedFloat32Array:
	var n := int(SR * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / float(maxi(1, n - 1))
		var freq := f0 + (f1 - f0) * t
		phase += TAU * freq / float(SR)
		var s := sin(phase) if kind == "sine" else (1.0 if sin(phase) >= 0.0 else -1.0)
		out[i] = s * vol * _env(i, n, 0.01, 0.2, 0.5, 0.35)
	return out


func _silence(dur: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(SR * dur))
	return out


func _concat(a: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(a.size() + b.size())
	for i in a.size():
		out[i] = a[i]
	var off := a.size()
	for i in b.size():
		out[off + i] = b[i]
	return out


func _pad(samples: PackedFloat32Array, silence: float = 0.02) -> PackedFloat32Array:
	return _concat(_concat(_silence(silence), samples), _silence(silence))


func _mix(parts: Array) -> PackedFloat32Array:
	var n := 0
	for p in parts:
		n = maxi(n, (p as PackedFloat32Array).size())
	var out := PackedFloat32Array()
	out.resize(n)
	for p in parts:
		var arr := p as PackedFloat32Array
		for i in arr.size():
			out[i] += arr[i]
	var peak := 0.0
	for i in n:
		peak = maxf(peak, absf(out[i]))
	if peak > 1.0:
		for i in n:
			out[i] = out[i] / peak * 0.95
	return out


## Quiet looping plasma hum/pulse for continuous autofire (not a per-shot click).
func _fire_loop(seconds: float) -> PackedFloat32Array:
	var n := int(SR * seconds)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / float(SR)
		var pulse := 0.55 + 0.45 * sin(TAU * 9.0 * t)
		var hum := sin(TAU * 180.0 * t) * 0.07 * pulse
		var hum2 := sin(TAU * 270.0 * t + 0.4) * 0.04
		var shimmer := sin(TAU * 720.0 * t) * 0.015 * pulse
		var state := (1103515245 * (i + 3) + 12345) & 0x7FFF
		var hiss := (float(state) / 32768.0 - 0.5) * 0.012
		out[i] = clampf(hum + hum2 + shimmer + hiss, -1.0, 1.0)
	# Seamless-ish edges for loop import.
	var fade := int(SR * 0.02)
	for i in fade:
		var g := float(i) / float(fade)
		out[i] *= g
		out[n - 1 - i] *= g
	return out


func _music(kind: String, seconds: float) -> PackedFloat32Array:
	var n := int(SR * seconds)
	var out := PackedFloat32Array()
	out.resize(n)
	var roots: Array[float]
	var bpm := 118.0
	match kind:
		"menu":
			roots = [110.0, 130.81, 146.83, 164.81]
			bpm = 92.0
		"boss":
			roots = [82.41, 98.0, 103.83, 123.47]
			bpm = 132.0
		_:
			roots = [98.0, 116.54, 130.81, 146.83]
			bpm = 118.0
	var beat := 60.0 / bpm
	for i in n:
		var t := float(i) / float(SR)
		var bar := int(t / (beat * 4.0)) % roots.size()
		var freq: float = roots[bar]
		var pulse := 0.5 + 0.5 * sin(TAU * t / beat)
		var bass := sin(TAU * freq * t) * 0.16 * pulse
		var arp_note: float = roots[(int(t / (beat * 0.5)) + bar) % roots.size()] * 2.0
		var arp := sin(TAU * arp_note * t) * 0.07 * (0.4 + 0.6 * pulse)
		var pad_s := sin(TAU * freq * 3.0 * t + 0.3) * 0.05
		var spark := 0.0
		if kind != "menu" and (int(t / (beat * 0.25)) % 4) == 0:
			spark = sin(TAU * arp_note * 2.0 * t) * 0.03
		if kind == "boss":
			bass *= 1.25
			var noise_amt := float(((1103515245 * (i + 7) + 12345) & 0x7FFF)) / 32768.0 - 0.5
			bass += noise_amt * 0.02
		out[i] = clampf(bass + arp + pad_s + spark, -1.0, 1.0)
	var fade := int(SR * 0.04)
	for i in fade:
		var g := float(i) / float(fade)
		out[i] *= g
		out[n - 1 - i] *= g
	return out
