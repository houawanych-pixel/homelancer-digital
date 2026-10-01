#!/usr/bin/env python3
"""make_sfx — generates Homelancer's original sound effects (no samples, pure synthesis) into assets/audio/.
Radio: comm_open / comm_close chirps (Star Fox-style), 8 'mumble' syllables (a buzzy voice through vowel
formants; pitch is shifted per character at runtime). Combat: laser, laser_enemy, missile, explosion, shield_hit, hull_hit.
"""
import os, sys, wave
import numpy as np
SR = 22050
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "../../assets/audio")
rng = np.random.default_rng(7)

def save(name, x, gain=0.9):
    x = np.asarray(x, float)
    x = x / max(1e-9, np.max(np.abs(x))) * gain
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((x * 32767).astype("<i2").tobytes())

def t(d): return np.arange(int(SR * d)) / SR
def env(n, a=0.005, r=0.05):
    e = np.ones(n); na = max(1, int(SR * a)); nr = max(1, int(SR * r))
    e[:na] = np.linspace(0, 1, na); e[-nr:] *= np.linspace(1, 0, nr) ** 1.5
    return e
def sweep(f0, f1, d, shape="sine"):
    tt = t(d); f = f0 * (f1 / f0) ** (tt / d); ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph) if shape == "sine" else np.sign(np.sin(ph)) * 0.6
def biquad_bp(x, fc, q):
    w0 = 2 * np.pi * fc / SR; al = np.sin(w0) / (2 * q)
    b = np.array([al, 0, -al]); a = np.array([1 + al, -2 * np.cos(w0), 1 - al])
    b /= a[0]; a /= a[0]; y = np.zeros_like(x); x1 = x2 = y1 = y2 = 0.0
    for i, s in enumerate(x):
        o = b[0] * s + b[1] * x1 + b[2] * x2 - a[1] * y1 - a[2] * y2
        x2, x1, y2, y1 = x1, s, y1, o; y[i] = o
    return y
def lowpass(x, fc):
    a = np.exp(-2 * np.pi * fc / SR); y = np.zeros_like(x); p = 0.0
    for i, s in enumerate(x): p = (1 - a) * s + a * p; y[i] = p
    return y

# --- radio chirps: two quick square-ish blips, rising (open) / falling (close), a bit of radio noise
def chirp(up=True):
    a = sweep(900, 1500, 0.05, "sq") * env(int(SR * 0.05), 0.002, 0.02)
    b = sweep(1300, 2100, 0.07, "sq") * env(int(SR * 0.07), 0.002, 0.03)
    gap = np.zeros(int(SR * 0.025))
    x = np.concatenate([a, gap, b]) if up else np.concatenate([b[::-1] * 0.9, gap, a[::-1]])
    x = x + rng.normal(0, 0.04, len(x)) * env(len(x), 0.002, 0.02)
    return biquad_bp(x, 1800, 0.9) * 2.5 + x * 0.3
save("comm_open", chirp(True), 0.7)
save("comm_close", chirp(False), 0.6)

# --- mumble syllables: glottal buzz through two vowel formants, pitch glide, radio band-pass
VOWELS = [(730, 1090), (530, 1840), (270, 2290), (570, 840), (300, 870), (660, 1700), (440, 1020), (390, 1990)]
for i, (f1, f2) in enumerate(VOWELS):
    d = 0.085 + 0.03 * (i % 3)
    tt = t(d); f0 = 170 * (1 + 0.12 * np.sin(np.pi * tt / d) * (1 if i % 2 else -1))
    ph = np.cumsum(f0) / SR
    buzz = (ph % 1.0) * 2 - 1                      # sawtooth glottal source
    buzz += rng.normal(0, 0.05, len(buzz))
    v = biquad_bp(buzz, f1, 5) + 0.6 * biquad_bp(buzz, f2, 7)
    v = biquad_bp(v, 1400, 0.5) + 0.35 * v          # thin 'radio' band
    save("syl_%d" % i, v * env(len(v), 0.008, 0.03), 0.75)

# --- combat
x = sweep(2400, 380, 0.16, "sq") * env(int(SR * 0.16), 0.001, 0.09)
save("laser", lowpass(x, 5000) + 0.4 * sweep(3200, 600, 0.16) * env(int(SR * 0.16), 0.001, 0.1), 0.55)
x = sweep(1100, 190, 0.2, "sq") * env(int(SR * 0.2), 0.001, 0.12)
save("laser_enemy", lowpass(x, 2600), 0.5)
n = rng.normal(0, 1, int(SR * 0.9)); e = env(len(n), 0.02, 0.55)
roar = lowpass(n, 1400) * e + 0.5 * sweep(160, 90, 0.9) * e
save("missile", roar + 0.3 * biquad_bp(n, 2600, 2) * env(len(n), 0.005, 0.8), 0.7)
n = rng.normal(0, 1, int(SR * 1.3)); tt = t(1.3)
boom = lowpass(n, 700) * np.exp(-tt * 3.2) + 0.8 * np.sin(2 * np.pi * np.cumsum(70 * np.exp(-tt * 1.5)) / SR) * np.exp(-tt * 4)
crack = lowpass(n, 5000) * np.exp(-tt * 18)
save("explosion", boom + 0.6 * crack, 0.9)
x = sweep(1800, 900, 0.14) * env(int(SR * 0.14), 0.001, 0.1)
x += 0.5 * biquad_bp(rng.normal(0, 1, len(x)), 3200, 3) * env(len(x), 0.001, 0.08)
save("shield_hit", x, 0.5)
n = rng.normal(0, 1, int(SR * 0.22)); tt = t(0.22)
save("hull_hit", lowpass(n, 1200) * np.exp(-tt * 18) + 0.6 * np.sin(2 * np.pi * 110 * tt) * np.exp(-tt * 20), 0.7)
# --- utility
tt = t(0.9)
hum = sweep(90, 240, 0.9) * env(len(tt), 0.05, 0.3) + 0.4 * sweep(180, 480, 0.9) * env(len(tt), 0.05, 0.3)
save("tractor", lowpass(hum * (0.7 + 0.3 * np.sin(2 * np.pi * 9 * tt)), 2200), 0.6)
a = np.sin(2 * np.pi * 1320 * t(0.09)) * env(int(SR * 0.09), 0.002, 0.07)
b = np.sin(2 * np.pi * 1980 * t(0.16)) * env(int(SR * 0.16), 0.002, 0.14)
save("pickup", np.concatenate([a, b]), 0.5)
bp = np.sin(2 * np.pi * 880 * t(0.07)) * env(int(SR * 0.07), 0.002, 0.05)
save("mine_wake", np.concatenate([bp, np.zeros(int(SR * 0.05)), bp]), 0.5)
save("button", sweep(1400, 900, 0.035) * env(int(SR * 0.035), 0.001, 0.03), 0.35)
# --- travel
n = rng.normal(0, 1, int(SR * 3.5)); tt = t(3.5)
rum = lowpass(n, 260) * (0.4 + 0.6 * np.sin(np.pi * tt / 3.5)) + 0.5 * lowpass(n, 1800) * np.sin(np.pi * tt / 3.5) ** 3
save("atmo", rum * env(len(n), 0.3, 0.8), 0.8)
n = rng.normal(0, 1, int(SR * 0.9)); tt = t(0.9)
save("whoosh", biquad_bp(n, 500, 0.8) * np.sin(np.pi * tt / 0.9) ** 2 + 0.4 * biquad_bp(n, 2400, 1.5) * np.sin(np.pi * tt / 0.9) ** 4, 0.6)
# --- warp: 5 s rising spool, then the launch
tt = t(5.0)
spool = sweep(70, 520, 5.0) * (0.3 + 0.7 * tt / 5.0) + 0.5 * sweep(140, 1040, 5.0, "sq") * (tt / 5.0) ** 2
spool *= 0.8 + 0.2 * np.sin(2 * np.pi * (4 + 18 * tt / 5.0) * tt)
save("warp_spool", lowpass(spool, 3000) * env(len(tt), 0.2, 0.05), 0.6)
n = rng.normal(0, 1, int(SR * 1.2)); tt = t(1.2)
go = lowpass(n, 2500) * np.exp(-tt * 3.5) + 0.8 * sweep(900, 60, 1.2) * np.exp(-tt * 2.5)
save("warp_go", go, 0.8)
print("wrote", sorted(os.listdir(OUT)))
