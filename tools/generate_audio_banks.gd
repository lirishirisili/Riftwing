extends SceneTree
## Headless modern sci-fi SFX/music synthesizer → assets/audio (ffmpeg → ogg).
## godot --headless --path . --script res://tools/generate_audio_banks.gd
##
## Direction: premium mobile shooter — soft UI, layered combat, atmospheric loops.
## Not chiptune. Cue IDs/paths must stay stable for AudioManager.

const SR := 44100
const SFX_DIR := "res://assets/audio/sfx"
const MUSIC_DIR := "res://assets/audio/music"
const TMP_DIR := "user://audio_gen_tmp"
const TAU_F := TAU


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SFX_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MUSIC_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TMP_DIR))

	var sfx := {
		"ui_click": _pad(_mix([
			_tone(1240.0, 0.045, 0.18, "sine", 0.01, 0.25, 0.2, 0.45),
			_tone(1860.0, 0.035, 0.08, "sine", 0.005, 0.3, 0.15, 0.5),
			_noise_filtered(0.04, 0.04, 0.55),
		])),
		"ui_confirm": _pad(_mix([
			_tone(523.25, 0.1, 0.16, "sine", 0.02, 0.2, 0.45, 0.4),
			_tone(659.25, 0.12, 0.14, "sine", 0.03, 0.22, 0.4, 0.4),
			_tone(784.0, 0.14, 0.1, "triangle", 0.04, 0.25, 0.35, 0.4),
			_noise_filtered(0.06, 0.03, 0.4),
		])),
		"ui_back": _pad(_mix([
			_sweep(520.0, 280.0, 0.1, 0.14, "sine"),
			_tone(220.0, 0.08, 0.08, "sine", 0.02, 0.3, 0.3, 0.45),
		])),
		"fire": _pad(_mix([
			_sweep(980.0, 420.0, 0.055, 0.12, "sine"),
			_noise_filtered(0.045, 0.05, 0.5),
		])),
		"hit": _pad(_mix([
			_tone(180.0, 0.06, 0.22, "sine", 0.005, 0.25, 0.25, 0.45),
			_tone(420.0, 0.04, 0.1, "triangle", 0.002, 0.35, 0.15, 0.5),
			_noise_filtered(0.07, 0.12, 0.35),
		])),
		"player_hit": _pad(_mix([
			_sweep(380.0, 90.0, 0.22, 0.28, "sine"),
			_tone(70.0, 0.2, 0.18, "sine", 0.01, 0.2, 0.4, 0.45),
			_noise_filtered(0.18, 0.16, 0.28),
		])),
		"shield_impact": _pad(_mix([
			_tone(740.0, 0.09, 0.14, "sine", 0.01, 0.25, 0.35, 0.4),
			_tone(1110.0, 0.11, 0.1, "sine", 0.015, 0.28, 0.3, 0.4),
			_fm(520.0, 90.0, 1.8, 0.1, 0.08),
		])),
		"pickup": _pad(_mix([
			_tone(784.0, 0.08, 0.12, "sine", 0.02, 0.2, 0.4, 0.4),
			_concat(_silence(0.04), _tone(988.0, 0.09, 0.12, "sine", 0.02, 0.2, 0.35, 0.4)),
			_concat(_silence(0.08), _tone(1318.5, 0.12, 0.1, "triangle", 0.02, 0.25, 0.3, 0.45)),
		])),
		"explosion_small": _pad(_mix([
			_noise_filtered(0.16, 0.22, 0.22),
			_sweep(220.0, 55.0, 0.18, 0.2, "sine"),
			_tone(48.0, 0.14, 0.14, "sine", 0.01, 0.2, 0.35, 0.45),
		])),
		"explosion_large": _pad(_mix([
			_noise_filtered(0.32, 0.28, 0.18),
			_sweep(160.0, 35.0, 0.38, 0.26, "sine"),
			_tone(42.0, 0.4, 0.22, "sine", 0.02, 0.15, 0.45, 0.4),
			_tone(85.0, 0.22, 0.1, "triangle", 0.01, 0.25, 0.3, 0.45),
		])),
		"ability": _pad(_mix([
			_sweep(320.0, 960.0, 0.16, 0.16, "sine"),
			_fm(640.0, 120.0, 2.2, 0.12, 0.1),
			_tone(1280.0, 0.1, 0.08, "sine", 0.04, 0.3, 0.25, 0.45),
		])),
		"upgrade_open": _pad(_mix([
			_tone(392.0, 0.14, 0.12, "sine", 0.04, 0.2, 0.45, 0.4),
			_tone(493.88, 0.16, 0.11, "sine", 0.05, 0.22, 0.4, 0.4),
			_tone(587.33, 0.18, 0.1, "triangle", 0.06, 0.25, 0.35, 0.4),
			_noise_filtered(0.08, 0.03, 0.35),
		])),
		"upgrade_select": _pad(_mix([
			_tone(659.25, 0.1, 0.14, "sine", 0.02, 0.2, 0.4, 0.4),
			_tone(830.61, 0.13, 0.12, "sine", 0.03, 0.22, 0.35, 0.4),
			_tone(1046.5, 0.16, 0.11, "triangle", 0.04, 0.25, 0.3, 0.45),
			_fm(523.0, 40.0, 1.2, 0.12, 0.06),
		])),
		"boss_warning": _pad(_mix([
			_sweep(160.0, 95.0, 0.42, 0.22, "sine"),
			_tone(70.0, 0.42, 0.18, "sine", 0.08, 0.15, 0.55, 0.35),
			_tone(140.0, 0.35, 0.08, "triangle", 0.1, 0.2, 0.4, 0.4),
			_noise_filtered(0.25, 0.06, 0.2),
		])),
		"boss_laser": _pad(_mix([
			_fm(160.0, 55.0, 3.5, 0.28, 0.16),
			_tone(220.0, 0.28, 0.1, "triangle", 0.02, 0.2, 0.5, 0.35),
			_noise_filtered(0.28, 0.08, 0.45),
		])),
		"boss_phase": _pad(_mix([
			_sweep(70.0, 180.0, 0.42, 0.2, "sine"),
			_tone(48.0, 0.42, 0.2, "sine", 0.05, 0.15, 0.5, 0.4),
			_noise_filtered(0.2, 0.1, 0.25),
		])),
		"boss_defeated": _pad(_mix([
			_tone(392.0, 0.14, 0.14, "sine", 0.03, 0.2, 0.4, 0.4),
			_concat(_silence(0.08), _tone(523.25, 0.16, 0.13, "sine", 0.03, 0.22, 0.35, 0.4)),
			_concat(_silence(0.16), _tone(659.25, 0.2, 0.12, "triangle", 0.04, 0.25, 0.3, 0.45)),
		])),
		"victory_fanfare": _pad(_mix([
			_tone(523.25, 0.16, 0.14, "sine", 0.03, 0.2, 0.4, 0.4),
			_concat(_silence(0.1), _tone(659.25, 0.16, 0.13, "sine", 0.03, 0.22, 0.35, 0.4)),
			_concat(_silence(0.2), _tone(783.99, 0.18, 0.12, "triangle", 0.04, 0.25, 0.35, 0.4)),
			_concat(_silence(0.32), _tone(1046.5, 0.32, 0.14, "sine", 0.05, 0.2, 0.4, 0.4)),
			_concat(_silence(0.32), _fm(523.0, 30.0, 0.8, 0.28, 0.05)),
		])),
		"run_failed": _pad(_mix([
			_sweep(360.0, 90.0, 0.48, 0.22, "sine"),
			_tone(82.0, 0.48, 0.18, "sine", 0.05, 0.15, 0.45, 0.4),
			_tone(110.0, 0.35, 0.08, "triangle", 0.08, 0.25, 0.3, 0.45),
		])),
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
	var code := OS.execute("ffmpeg", args, out, true, false)
	if code != 0:
		printerr("ffmpeg code=%d %s" % [code, str(out)])
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


func _wave(phase: float, kind: String) -> float:
	match kind:
		"triangle":
			var x := fmod(phase / TAU_F, 1.0)
			return 1.0 - 4.0 * absf(x - 0.5)
		"square_soft":
			# Soft square via tanh of sine — far less harsh than hard square.
			return tanh(sin(phase) * 2.2)
		"saw_soft":
			var x := fmod(phase / PI, 2.0) - 1.0
			return tanh(x * 1.4) * 0.85
		_:
			return sin(phase)


func _tone(
	freq: float,
	dur: float,
	vol: float = 0.35,
	kind: String = "sine",
	a: float = 0.03,
	d: float = 0.18,
	s: float = 0.45,
	r: float = 0.35
) -> PackedFloat32Array:
	var n := int(SR * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		phase += TAU_F * freq / float(SR)
		out[i] = _wave(phase, kind) * vol * _env(i, n, a, d, s, r)
	return out


func _fm(carrier: float, mod_hz: float, index: float, dur: float, vol: float) -> PackedFloat32Array:
	var n := int(SR * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var c_phase := 0.0
	var m_phase := 0.0
	for i in n:
		m_phase += TAU_F * mod_hz / float(SR)
		var mod := sin(m_phase) * index
		c_phase += TAU_F * (carrier + mod * mod_hz) / float(SR)
		out[i] = sin(c_phase) * vol * _env(i, n, 0.03, 0.2, 0.4, 0.4)
	return out


func _noise_filtered(dur: float, vol: float = 0.2, cutoff: float = 0.3) -> PackedFloat32Array:
	## One-pole LPF on LCG noise — combat tails without harsh hiss.
	var n := int(SR * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var state := 1234567
	var lp := 0.0
	var alpha := clampf(cutoff, 0.05, 0.95)
	for i in n:
		state = (1103515245 * state + 12345) & 0x7FFFFFFF
		var s := (float(state) / float(0x7FFFFFFF)) * 2.0 - 1.0
		lp += alpha * (s - lp)
		out[i] = lp * vol * _env(i, n, 0.015, 0.22, 0.3, 0.45)
	return out


func _sweep(f0: float, f1: float, dur: float, vol: float = 0.3, kind: String = "sine") -> PackedFloat32Array:
	var n := int(SR * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / float(maxi(1, n - 1))
		# Smoothstep for less clicky sweeps.
		var u := t * t * (3.0 - 2.0 * t)
		var freq := f0 + (f1 - f0) * u
		phase += TAU_F * freq / float(SR)
		out[i] = _wave(phase, kind) * vol * _env(i, n, 0.02, 0.22, 0.45, 0.38)
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
	return _normalize(_concat(_concat(_silence(silence), samples), _silence(silence)))


func _normalize(samples: PackedFloat32Array, peak_target: float = 0.92) -> PackedFloat32Array:
	var peak := 0.0
	for i in samples.size():
		peak = maxf(peak, absf(samples[i]))
	if peak <= 1e-6:
		return samples
	var g := peak_target / peak
	for i in samples.size():
		samples[i] *= g
	return samples


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
	return _normalize(out)


## Deeper modulated plasma bed for continuous autofire.
func _fire_loop(seconds: float) -> PackedFloat32Array:
	var n := int(SR * seconds)
	var out := PackedFloat32Array()
	out.resize(n)
	var state := 424242
	var lp := 0.0
	for i in n:
		var t := float(i) / float(SR)
		var pulse := 0.62 + 0.38 * sin(TAU_F * 7.5 * t)
		var hum := sin(TAU_F * 95.0 * t) * 0.09 * pulse
		var hum2 := sin(TAU_F * 142.0 * t + 0.6) * 0.055
		var sub := sin(TAU_F * 47.5 * t) * 0.04
		var shimmer := sin(TAU_F * 480.0 * t + sin(TAU_F * 3.0 * t) * 0.8) * 0.018 * pulse
		state = (1103515245 * state + 12345) & 0x7FFF
		var raw := float(state) / 32768.0 - 0.5
		lp += 0.12 * (raw - lp)
		out[i] = clampf(hum + hum2 + sub + shimmer + lp * 0.018, -1.0, 1.0)
	# Equal-power-ish edge fades for seamless loop import.
	var fade := int(SR * 0.04)
	for i in fade:
		var g := sin(0.5 * PI * float(i) / float(fade))
		out[i] *= g
		out[n - 1 - i] *= g
	return _normalize(out, 0.85)


func _music(kind: String, seconds: float) -> PackedFloat32Array:
	## Menu: calm low pad only (no mid/high motif — those read as a whine/"meow").
	## Run/boss: stepped bass + soft pad; sparse low motif, never gliding leads.
	var n := int(SR * seconds)
	var out := PackedFloat32Array()
	out.resize(n)
	var roots: Array[float]
	var bpm := 108.0
	match kind:
		"menu":
			roots = [65.41, 73.42, 82.41, 98.0] # deep C / D / E / G
			bpm = 72.0
		"boss":
			roots = [55.0, 65.41, 73.42, 82.41]
			bpm = 118.0
		_:
			roots = [73.42, 82.41, 98.0, 110.0]
			bpm = 102.0
	var beat := 60.0 / bpm
	var state := 777777
	var lp_noise := 0.0
	for i in n:
		var t := float(i) / float(SR)
		# Stepped roots only — no pitch glide (glide = meow).
		var bar := int(t / (beat * 4.0)) % roots.size()
		var bass_f: float = roots[bar]
		var breath := 0.7 + 0.3 * sin(TAU_F * t / (beat * 16.0))
		var bass := sin(TAU_F * bass_f * t) * 0.13 * breath
		bass += sin(TAU_F * bass_f * 0.5 * t) * 0.07
		# Warm pad: octave + gentle fifth, tiny static detune (not LFO sweep).
		var pad := sin(TAU_F * bass_f * 2.0 * t) * 0.04
		pad += sin(TAU_F * bass_f * 2.0 * t + 0.15) * 0.025
		pad += sin(TAU_F * bass_f * 1.5 * t) * 0.018
		var motif := 0.0
		if kind == "menu":
			# Ambient only — no lead motif.
			pass
		else:
			# Rare low pulse on downbeats (octave above root max), sine only.
			var step := int(t / (beat * 2.0))
			if step % 4 == 0:
				var m_f: float = bass_f * 2.0
				var local := fmod(t, beat * 2.0) / (beat * 2.0)
				var m_env := 0.0
				if local < 0.08:
					m_env = local / 0.08
				elif local < 0.35:
					m_env = 1.0 - (local - 0.08) * 0.9
				else:
					m_env = 0.0
				motif = sin(TAU_F * m_f * t) * (0.028 if kind == "run" else 0.022) * m_env
		if kind == "boss":
			bass *= 1.15
			state = (1103515245 * state + 12345) & 0x7FFF
			var raw := float(state) / 32768.0 - 0.5
			lp_noise += 0.06 * (raw - lp_noise)
			bass += lp_noise * 0.012
		out[i] = clampf(bass + pad + motif, -1.0, 1.0)
	var fade := int(SR * 0.1)
	for i in fade:
		var g := sin(0.5 * PI * float(i) / float(fade))
		out[i] *= g
		out[n - 1 - i] *= g
	return _normalize(out, 0.86)
