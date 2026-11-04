#!/usr/bin/env python3
"""v12.4 (owner: the border crossing is a static glitch, "you hit a static noise, turns white ... the static comes back"):
border_glitch.wav: crackles and stutters building to a full TV-static hiss with a rising whine.
border_refix.wav:  static burst that breaks up into crackles and clicks off.
    python3 tools/sfx/make_border_sfx.py"""
import os, wave
import numpy as np
SR = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio")
rng = np.random.default_rng(11)
def hp(x, k=0.5):   # a cheap high-pass: hissier static
    return np.concatenate([[0], np.diff(x)]) * k + x * (1 - k)
def save(name, x):
    x = x / (np.max(np.abs(x)) + 1e-9) * 0.9
    with wave.open(os.path.join(OUT, name), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((x * 32767).astype(np.int16).tobytes())
def gate(t, rate, duty, seed):   # stutter: on/off chops
    r = np.random.default_rng(seed); n = int(t[-1] * rate) + 2; g = (r.random(n) < duty).astype(float)
    return g[(t * rate).astype(int)]
d = 1.7; t = np.arange(int(SR * d)) / SR; k = t / d
noise = hp(rng.standard_normal(t.size), 0.7)
crack = (rng.random(t.size) < 0.002 + 0.02 * k) * rng.standard_normal(t.size) * 3
stut = np.maximum(gate(t, 22, 0.35 + 0.6 * 0, 3), np.clip((k - 0.45) / 0.3, 0, 1))
whine = np.sin(2 * np.pi * np.cumsum(900 + 5200 * k ** 2) / SR) * 0.12 * np.clip((k - 0.3) / 0.5, 0, 1)
hum = np.sin(2 * np.pi * 60 * t) * 0.15 * (1 - k)
x = noise * stut * (0.15 + 0.85 * np.clip(k / 0.75, 0, 1)) + crack + whine + hum
x *= np.minimum(1, (d - t) * 12)
save("border_glitch.wav", x)
d = 1.1; t = np.arange(int(SR * d)) / SR; k = t / d
noise = hp(rng.standard_normal(t.size), 0.7)
env = np.exp(-k * 2.5) * gate(t, 18, 0.55, 5) * np.where(k < 0.2, 1, 1) + np.exp(-k * 9) * 0.6
crack = (rng.random(t.size) < 0.01 * (1 - k)) * rng.standard_normal(t.size) * 2.5
click = np.zeros(t.size); click[int(SR * 0.9):int(SR * 0.9) + 60] = np.hanning(60) * 1.2
x = noise * env + crack + click
x *= np.minimum(1, (d - t) * 20)
save("border_refix.wav", x)
print("ok")
