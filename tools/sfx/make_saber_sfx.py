#!/usr/bin/env python3
"""v12.15 (owner: "saber blade noises", a laser shield): the mech's sword and laser shield sounds, synthesized.
saber_on (ignite), saber_off, saber_swing (a whoosh with the hum bending in pitch), saber_hit (sizzle + crack),
saber_spin (two quick swings), shield_block (a shot fizzing off the laser shield).
    python3 tools/sfx/make_saber_sfx.py"""
import os, wave
import numpy as np
SR = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio")
rng = np.random.default_rng(15)
def save(name, x, g=0.9):
    x = np.asarray(x, float); x = x / (np.max(np.abs(x)) + 1e-9) * g
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((x * 32767).astype("<i2").tobytes())
def T(d): return np.arange(int(SR * d)) / SR
def hum(f, t, wob=0.0):   # a saber's buzzing hum: a low tone with a rough harmonic and a slow wobble
    ph = 2 * np.pi * np.cumsum(f * (1 + wob)) / SR
    return np.sin(ph) * 0.6 + np.sign(np.sin(ph * 2.01)) * 0.18 + np.sin(ph * 3.02) * 0.15
def smooth(x, k):
    return np.convolve(x, np.ones(k) / k, mode="same")
# ignite: a rising buzz that settles into the hum
t = T(0.7); k = t / t[-1]
f = 90 + 70 * np.minimum(1, k / 0.25) + 10 * np.sin(2 * np.pi * 5 * t)
x = hum(f, t) * np.minimum(1, k / 0.06) * (1 - 0.4 * k) + smooth(rng.standard_normal(t.size), 6) * 0.25 * np.exp(-k * 6)
x *= np.minimum(1, (t[-1] - t) * 15)
save("saber_on", x, 0.75)
# off: the hum drops away
t = T(0.45); k = t / t[-1]
x = hum(160 - 110 * k, t) * (1 - k) ** 1.5
save("saber_off", x, 0.6)
# swing: doppler bend on the hum + an airy whoosh
t = T(0.38); k = t / t[-1]
bend = np.sin(np.pi * k)
x = hum(140 + 120 * bend, t) * bend + smooth(rng.standard_normal(t.size), 3) * 0.45 * bend ** 2
save("saber_swing", x, 0.8)
# hit: sizzle + crack + a low thump
t = T(0.5); k = t / t[-1]
sizzle = rng.standard_normal(t.size) * np.exp(-k * 5) * (0.6 + 0.4 * np.sin(2 * np.pi * 70 * t))
crack = np.zeros(t.size); n = int(SR * 0.02); crack[:n] = rng.standard_normal(n) * np.hanning(n * 2)[n:] * 2.0
thump = np.sin(2 * np.pi * (70 - 30 * k) * t) * np.exp(-k * 9) * 0.9
x = sizzle * 0.6 + crack + thump + hum(180 + 60 * k, t) * np.exp(-k * 4) * 0.4
save("saber_hit", x, 0.9)
# spin: two quick swings
t = T(0.55); k = t / t[-1]
b = np.abs(np.sin(2 * np.pi * k))
x = hum(150 + 140 * b, t) * b + smooth(rng.standard_normal(t.size), 3) * 0.4 * b ** 2
save("saber_spin", x, 0.8)
# block: a bright fizz and a shimmering ping
t = T(0.35); k = t / t[-1]
fizz = rng.standard_normal(t.size) * np.exp(-k * 10)
ping = np.sin(2 * np.pi * (1500 + 400 * k) * t) * np.exp(-k * 6) * 0.5 + np.sin(2 * np.pi * 2400 * t) * np.exp(-k * 9) * 0.3
x = fizz * 0.5 + ping + hum(220, t) * np.exp(-k * 5) * 0.3
save("shield_block", x, 0.7)
print("ok")
