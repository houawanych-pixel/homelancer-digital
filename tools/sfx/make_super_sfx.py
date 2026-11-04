#!/usr/bin/env python3
"""v12.2 (owner: "give the super a special sound ... a bass-like sound, and then a sound wave"): the super's sound
(22 kHz mono WAV): a deep bass drop that hits hard, then a wave that sweeps out and rolls away.
    python3 tools/sfx/make_super_sfx.py   -> assets/audio/super_wave.wav"""
import os, wave
import numpy as np
SR = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio")
rng = np.random.default_rng(7)
def lowpass(x, k):
    y = np.empty_like(x); a = 0.0
    for i, v in enumerate(x): a += k * (v - a); y[i] = a
    return y
d = 3.0; t = np.arange(int(SR * d)) / SR
f = 32 + 90 * np.exp(-t * 3.0)                                       # the drop: 122 Hz falling to a 32 Hz sub
bass = np.tanh(2.2 * np.sin(2 * np.pi * np.cumsum(f) / SR)) * np.exp(-t * 0.9) * np.minimum(1, t * 40)
hit = np.sin(2 * np.pi * 60 * t) * np.exp(-t * 14) * 1.3             # the punch at the start
wob = 0.5 + 0.5 * np.sin(2 * np.pi * (6.0 - 4.0 * t / d) * t)        # the wave: a sweep that wobbles slower as it goes out
fs = 300 + 2200 * np.exp(-t * 1.4)
sweep = np.sin(2 * np.pi * np.cumsum(fs) / SR) * 0.25 * wob * np.exp(-t * 0.8) * np.minimum(1, t * 6)
air = lowpass(rng.standard_normal(t.size), 0.06) * 2.5 * wob * np.exp(-t * 1.0)
x = bass * 1.1 + hit + sweep + air
x = x / (np.max(np.abs(x)) + 1e-9) * 0.95
with wave.open(os.path.join(OUT, "super_wave.wav"), "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes((x * 32767).astype(np.int16).tobytes())
print("ok")
