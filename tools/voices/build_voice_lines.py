#!/usr/bin/env python3
"""build_voice_lines — v1.8z: turn cloned line recordings into the game's voice clips.

Input:  lines.json (every fixed radio line: voice_id, text, key — see extract.py in the same folder),
        art/voices/voice_map.csv (who borrows which voice), a folder of raw 24 kHz WAVs named <SRC>_<md5(text)[:10]>.wav
        made with Echo Vision's on-device cloner (Pocket TTS) from the samples in art/voices.
Output: assets/voices/v_<pool>/<key>.ogg (trimmed, levelled, effect for MASK / R1), and prints the VOICE_POOL map.
Usage:  python3 tools/voices/build_voice_lines.py lines.json raw_dir"""
import csv, hashlib, json, os, re, subprocess, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
CREW = {"tutor": "Kim", "vale": "Cmdr. Vale", "oduya": "Port Master Oduya", "rennick": "Capt. Rennick", "amari": "Chief Amari",
        "voss": "Shade", "kessler": "Hoard", "jackal": "Scar Jackal", "wraith": "Ember Wraith", "revenant": "Iron Revenant",
        "banshee": "Frost Banshee"}
SRC = {"MASK": "M3"}   # the masked soldiers: Garrik Rend's voice through a helmet radio

def pool_of(vid, rows):
    crew = {r["character"]: r["voice"] for r in rows if r["group"] == "Crew"}
    fac = {}
    for r in rows:
        m = re.match(r"(\d\d) ", r["character"])
        if m: fac[(r["group"].lower(), m.group(1))] = r["voice"]
    if vid in CREW: return crew[CREW[vid]]
    if re.match(r"ax0\d$", vid): return "MASK"
    f, slot = vid.split("_")[:2]
    if f == "cybermorph": return "R1"
    if slot in ("01", "05") and f != "savagers": return "MASK"
    return fac[(f, slot)]

LEVEL = "loudnorm=I=-16:TP=-1.5,silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.05,areverse,silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.12,areverse"   # (loudnorm first: after the trims it can hang the encoder)
FX = {
    "MASK": "highpass=f=320,lowpass=f=3200,acrusher=bits=10:mix=0.25,aecho=0.8:0.4:18:0.25,",
    "R1": "aresample=44100,asplit=3[a][b][c];[a]afftfilt=real='hypot(re,im)':imag='0':win_size=512:overlap=0.75[robo];"
          "[b]asetrate=44100*0.75,aresample=44100,atempo=1.3333[low];[c]asetrate=44100*1.12,aresample=44100,atempo=0.8929,volume=0.4[high];"
          "[robo][low][high]amix=inputs=3:weights=1 0.8 0.35:normalize=0,tremolo=f=45:d=0.35,equalizer=f=90:t=q:w=1:g=6,highpass=f=50,"
          "aecho=0.8:0.6:60|140:0.35|0.2,",
}

def main():
    lines = json.load(open(sys.argv[1]))["lines"]
    raw = sys.argv[2]
    rows = list(csv.DictReader(open(os.path.join(ROOT, "art/voices/voice_map.csv"))))
    vmap, done, missing = {}, set(), 0
    for x in lines:
        p = pool_of(x["voice_id"], rows)
        vmap[x["voice_id"]] = "v_" + p.lower()
        out = os.path.join(ROOT, "assets/voices", "v_" + p.lower(), x["key"] + ".ogg")
        if out in done: continue
        done.add(out)
        src = os.path.join(raw, SRC.get(p, p) + "_" + hashlib.md5(x["text"].encode()).hexdigest()[:10] + ".wav")
        if not os.path.exists(src):
            missing += 1; continue
        os.makedirs(os.path.dirname(out), exist_ok=True)
        if os.path.exists(out) and os.path.getmtime(out) > os.path.getmtime(src): continue
        chain = FX.get(p, "") + LEVEL + ",aresample=24000"
        subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-y", "-i", src, "-filter_complex", "[0]" + chain, "-ac", "1",
                        "-c:a", "libvorbis", "-q:a", "1", out], check=True, timeout=60, stdin=subprocess.DEVNULL)
    print("clips:", len(done), "missing:", missing)
    print(json.dumps(dict(sorted(vmap.items()))))

if __name__ == "__main__":
    main()
