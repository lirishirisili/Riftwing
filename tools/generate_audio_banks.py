#!/usr/bin/env python3
"""Legacy helper — canonical banks come from generate_audio_banks.gd (modern sci-fi).

Prefer:
  godot --headless --path . --script res://tools/generate_audio_banks.gd
"""
from __future__ import annotations

import math
import os
import struct
import subprocess
import sys
import wave
from pathlib import Path

SR = 44100
ROOT = Path(__file__).resolve().parents[1]
SFX_DIR = ROOT / "assets" / "audio" / "sfx"
MUSIC_DIR = ROOT / "assets" / "audio" / "music"
TMP = ROOT / "build" / "audio_tmp"


def clamp(x: float, lo: float = -1.0, hi: float = 1.0) -> float:
    return lo if x < lo else hi if x > hi else x


def write_wav(path: Path, samples: list[float]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        frames = bytearray()
        for s in samples:
            v = int(clamp(s) * 32767.0)
            frames += struct.pack("<h", v)
        w.writeframes(frames)


def env(i: int, n: int, a: float, d: float, s: float, r: float) -> float:
    t = i / max(1, n - 1)
    if t < a:
        return t / max(1e-6, a)
    if t < a + d:
        return 1.0 - (1.0 - s) * ((t - a) / max(1e-6, d))
    if t > 1.0 - r:
        return s * ((1.0 - t) / max(1e-6, r))
    return s


def tone(freq: float, dur: float, vol: float = 0.4, wave_kind: str = "sine") -> list[float]:
    n = int(SR * dur)
    out: list[float] = []
    phase = 0.0
    for i in range(n):
        phase += 2.0 * math.pi * freq / SR
        if wave_kind == "square":
            s = 1.0 if math.sin(phase) >= 0.0 else -1.0
        elif wave_kind == "saw":
            s = (phase / math.pi % 2.0) - 1.0
        else:
            s = math.sin(phase)
        e = env(i, n, 0.02, 0.15, 0.55, 0.25)
        out.append(s * vol * e)
    return out


def noise(dur: float, vol: float = 0.3) -> list[float]:
    n = int(SR * dur)
    # Simple LCG for deterministic noise
    state = 1234567
    out: list[float] = []
    for i in range(n):
        state = (1103515245 * state + 12345) & 0x7FFFFFFF
        s = (state / 0x7FFFFFFF) * 2.0 - 1.0
        e = env(i, n, 0.01, 0.2, 0.35, 0.4)
        out.append(s * vol * e)
    return out


def mix(*parts: list[float]) -> list[float]:
    n = max((len(p) for p in parts), default=0)
    out = [0.0] * n
    for p in parts:
        for i, v in enumerate(p):
            out[i] += v
    peak = max((abs(x) for x in out), default=1.0)
    if peak > 1.0:
        out = [x / peak * 0.95 for x in out]
    return out


def sweep(f0: float, f1: float, dur: float, vol: float = 0.35, wave_kind: str = "sine") -> list[float]:
    n = int(SR * dur)
    out: list[float] = []
    phase = 0.0
    for i in range(n):
        t = i / max(1, n - 1)
        freq = f0 + (f1 - f0) * t
        phase += 2.0 * math.pi * freq / SR
        s = math.sin(phase) if wave_kind == "sine" else (1.0 if math.sin(phase) >= 0 else -1.0)
        e = env(i, n, 0.01, 0.2, 0.5, 0.35)
        out.append(s * vol * e)
    return out


def pad(samples: list[float], silence: float = 0.02) -> list[float]:
    z = [0.0] * int(SR * silence)
    return z + samples + z


def make_sfx() -> dict[str, list[float]]:
    return {
        "ui_click": pad(tone(880, 0.05, 0.28, "square")),
        "ui_confirm": pad(mix(tone(523, 0.08, 0.25), tone(784, 0.1, 0.22))),
        "ui_back": pad(tone(392, 0.07, 0.22, "square")),
        "fire": pad(mix(sweep(1400, 700, 0.06, 0.22), noise(0.05, 0.08))),
        "hit": pad(mix(tone(220, 0.05, 0.2, "square"), noise(0.04, 0.12))),
        "player_hit": pad(mix(sweep(300, 80, 0.18, 0.4), noise(0.15, 0.25))),
        "shield_impact": pad(mix(tone(660, 0.08, 0.2), tone(990, 0.1, 0.15))),
        "pickup": pad(mix(tone(740, 0.07, 0.22), tone(988, 0.1, 0.2), tone(1175, 0.12, 0.18))),
        "explosion_small": pad(mix(noise(0.18, 0.35), sweep(180, 40, 0.2, 0.3))),
        "explosion_large": pad(mix(noise(0.35, 0.45), sweep(140, 30, 0.4, 0.4), tone(55, 0.35, 0.25))),
        "ability": pad(mix(sweep(400, 900, 0.15, 0.28), tone(1200, 0.1, 0.18))),
        "upgrade_open": pad(mix(tone(440, 0.12, 0.22), tone(554, 0.14, 0.2), tone(659, 0.16, 0.18))),
        "upgrade_select": pad(mix(tone(659, 0.1, 0.25), tone(880, 0.14, 0.22), tone(1175, 0.16, 0.2))),
        "boss_warning": pad(mix(sweep(200, 120, 0.35, 0.4, "square"), tone(100, 0.35, 0.2))),
        "boss_laser": pad(mix(tone(180, 0.25, 0.25, "saw"), noise(0.25, 0.15))),
        "boss_phase": pad(mix(sweep(90, 220, 0.4, 0.35), tone(55, 0.4, 0.22))),
        "boss_defeated": pad(mix(tone(523, 0.15, 0.25), tone(659, 0.18, 0.22), tone(784, 0.22, 0.2))),
        "victory_fanfare": pad(
            mix(
                tone(523, 0.18, 0.28),
                [0.0] * int(SR * 0.12) + tone(659, 0.18, 0.26),
                [0.0] * int(SR * 0.24) + tone(784, 0.22, 0.28),
                [0.0] * int(SR * 0.36) + tone(1047, 0.35, 0.3),
            )
        ),
        "run_failed": pad(mix(sweep(400, 120, 0.45, 0.35), tone(98, 0.45, 0.25))),
    }


def make_music_loop(kind: str, seconds: float = 28.0) -> list[float]:
    n = int(SR * seconds)
    out = [0.0] * n
    if kind == "menu":
        roots = [110.0, 130.81, 146.83, 164.81]
        bpm = 92.0
    elif kind == "boss":
        roots = [82.41, 98.0, 103.83, 123.47]
        bpm = 132.0
    else:  # run
        roots = [98.0, 116.54, 130.81, 146.83]
        bpm = 118.0
    beat = 60.0 / bpm
    # Bass pulse
    for i in range(n):
        t = i / SR
        bar = int(t / (beat * 4)) % len(roots)
        freq = roots[bar]
        phase = 2.0 * math.pi * freq * t
        pulse = 0.5 + 0.5 * math.sin(2.0 * math.pi * t / beat)
        bass = math.sin(phase) * 0.16 * pulse
        # Arp
        arp_note = roots[(int(t / (beat * 0.5)) + bar) % len(roots)] * 2.0
        arp = math.sin(2.0 * math.pi * arp_note * t) * 0.07 * (0.4 + 0.6 * pulse)
        # Soft pad
        pad_f = freq * 3.0
        pad_s = math.sin(2.0 * math.pi * pad_f * t + 0.3) * 0.05
        # Hi sparkle on run/boss
        spark = 0.0
        if kind != "menu" and (int(t / (beat * 0.25)) % 4) == 0:
            spark = math.sin(2.0 * math.pi * (arp_note * 2.0) * t) * 0.03
        if kind == "boss":
            bass *= 1.25
            noise_amt = ((1103515245 * (i + 7) + 12345) & 0x7FFF) / 32768.0 - 0.5
            bass += noise_amt * 0.02
        out[i] = clamp(bass + arp + pad_s + spark)
    # Fade edges for loop friendliness
    fade = int(SR * 0.04)
    for i in range(fade):
        g = i / fade
        out[i] *= g
        out[-1 - i] *= g
    return out


def ffmpeg_to_ogg(wav: Path, ogg: Path) -> None:
    ogg.parent.mkdir(parents=True, exist_ok=True)
    cmd = [
        "ffmpeg",
        "-y",
        "-i",
        str(wav),
        "-c:a",
        "libvorbis",
        "-q:a",
        "5",
        str(ogg),
    ]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        print(r.stderr[-800:], file=sys.stderr)
        raise RuntimeError(f"ffmpeg failed for {ogg.name}")


def main() -> int:
    TMP.mkdir(parents=True, exist_ok=True)
    SFX_DIR.mkdir(parents=True, exist_ok=True)
    MUSIC_DIR.mkdir(parents=True, exist_ok=True)

    for name, samples in make_sfx().items():
        wav = TMP / f"{name}.wav"
        ogg = SFX_DIR / f"{name}.ogg"
        write_wav(wav, samples)
        ffmpeg_to_ogg(wav, ogg)
        print("sfx", ogg.name, f"{len(samples)/SR:.2f}s")

    for kind, filename in (
        ("menu", "music_menu.ogg"),
        ("run", "music_run.ogg"),
        ("boss", "music_boss.ogg"),
    ):
        samples = make_music_loop(kind, 28.0)
        wav = TMP / f"{kind}.wav"
        ogg = MUSIC_DIR / filename
        write_wav(wav, samples)
        ffmpeg_to_ogg(wav, ogg)
        print("music", ogg.name, f"{len(samples)/SR:.1f}s")

    print("GENERATE_AUDIO_BANKS_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
