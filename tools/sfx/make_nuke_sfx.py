#!/usr/bin/env python3
"""v11.85 (owner: "fix the sound on the nuclear missile"): the nuke's own launch and blast sounds (22 kHz mono WAV).
    python3 tools/sfx/make_nuke_sfx.py   -> assets/audio/nuke_launch.wav, nuke_blast.wav"""
import os, wave
import numpy as np
SR = 22050
rng = np.random.default_rng(11)
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio")

def lowpass(x, k):
    y = np.empty_like(x); a = 0.0
    for i, v in enumerate(x): a += k * (v - a); y[i] = a
    return y

def save(name, x):
    x = x / (np.max(np.abs(x)) + 1e-9) * 0.92
    with wave.open(os.path.join(OUT, name), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((x * 32767).astype(np.int16).tobytes())

def launch():
    d = 2.2; t = np.arange(int(SR * d)) / SR
    thump = np.sin(2 * np.pi * (55 - 25 * t) * t) * np.exp(-t * 5.0) * 1.2          # the heavy kick out of the bay
    noise = lowpass(rng.standard_normal(t.size), 0.08)
    roar = noise * np.minimum(1, t * 6) * np.exp(-t * 0.9) * 0.9                     # the motor
    f = 180 + 900 * (1 - np.exp(-t * 1.6))                                            # the rising charge whine
    whine = np.sin(2 * np.pi * np.cumsum(f) / SR) * 0.35 * np.minimum(1, t * 3) * np.exp(-t * 0.6)
    swirl = 0.5 + 0.5 * np.sin(2 * np.pi * 7.0 * t)                                   # the 4 swirling streams: a phaser wobble
    sh = lowpass(rng.standard_normal(t.size), 0.35) * swirl * 0.35 * np.exp(-t * 1.1)
    return thump + roar + whine * (0.6 + 0.4 * swirl) + sh

def blast():
    d = 4.5; t = np.arange(int(SR * d)) / SR
    boom = np.sin(2 * np.pi * (48 - 20 * np.minimum(t, 1)) * t) * np.exp(-t * 1.4) * 1.4
    crack = rng.standard_normal(t.size) * np.exp(-t * 9.0) * 0.9
    rumble = lowpass(rng.standard_normal(t.size), 0.02) * 6.0 * np.exp(-t * 0.55) * np.minimum(1, t * 10)
    zaps = np.zeros(t.size)                                                           # the electricity inside: crackles
    for _ in range(26):
        s = int(rng.uniform(0.15, 3.6) * SR); n = int(rng.uniform(0.03, 0.09) * SR)
        e = min(t.size, s + n); k = np.arange(e - s) / SR
        zaps[s:e] += np.sign(np.sin(2 * np.pi * rng.uniform(900, 2400) * k)) * rng.standard_normal(e - s) * np.exp(-k * 40) * 0.25
    hum = np.sin(2 * np.pi * 110 * t) * 0.12 * np.exp(-t * 0.7) * (0.6 + 0.4 * np.sin(2 * np.pi * 3 * t))
    fade = np.minimum(1, (d - t) / 0.6)
    return (boom + crack + rumble + zaps * np.exp(-t * 0.4) + hum) * fade

save("nuke_launch.wav", launch())
save("nuke_blast.wav", blast())
