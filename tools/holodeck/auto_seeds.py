# First-pass seed file for a HoloDeck plan: finds the room names printed on the plan (tesseract OCR on the white
# label text) and puts a seed at each label. Hand-check the result (extract.py debug image) before trusting it;
# unity_capital.json was made by hand and also has per-room wall boxes. Usage: auto_seeds.py <plan.png> <out.json>
import json, subprocess, sys, os, tempfile
import numpy as np
from PIL import Image
SKIP = {"UNITY", "ELYZA", "SOLARION", "COVENANT", "SAVAGERS", "IMPERIUM", "ORION", "LIBERATOR", "SHIP", "CAPITAL", "HOLODECK"}
def words(png):
    im = Image.open(png).convert("RGB"); a = np.asarray(im).astype(int)
    white = (a.min(axis=2) > 170).astype(np.uint8) * 255
    tmp = tempfile.mktemp(suffix=".png")
    Image.fromarray(255 - white).resize((im.width * 2, im.height * 2)).save(tmp)
    out = subprocess.run(["tesseract", tmp, "-", "--psm", "11", "tsv"], capture_output=True, text=True).stdout
    os.remove(tmp); ws = []
    for line in out.splitlines()[1:]:
        p = line.split("\t")
        if len(p) == 12 and p[11].strip() and float(p[10]) > 60:
            t = p[11].strip(); l, tp, w, h = (int(v) // 2 for v in p[6:10])
            if len(t) < 2 and t not in "&/": continue
            ws.append({"t": t, "x": l + w / 2, "y": tp + h / 2, "h": h, "l": l, "r": l + w})
    return ws, im.size
def group(ws, W, H):
    ws = [w for w in ws if w["y"] > H * 0.06]          # the title strip at the top
    ws.sort(key=lambda w: (w["y"], w["x"])); used = [False] * len(ws); labels = []
    for i, w in enumerate(ws):
        if used[i]: continue
        g = [w]; used[i] = True; changed = True
        while changed:
            changed = False
            for j, v in enumerate(ws):
                if used[j]: continue
                for u in g:
                    same_line = abs(v["y"] - u["y"]) < 6 and (v["l"] - u["r"] < 18 and u["l"] - v["r"] < 18)
                    next_line = 8 < v["y"] - u["y"] < 26 and abs(v["x"] - u["x"]) < 45
                    if same_line or next_line: g.append(v); used[j] = True; changed = True; break
        g.sort(key=lambda u: (round(u["y"] / 10), u["x"]))
        name = " ".join(u["t"] for u in g)
        if name.upper().strip("()") in SKIP or all(u["t"].upper() in SKIP for u in g): continue
        labels.append({"name": name.title().replace("&", "&"), "at": [int(sum(u["x"] for u in g) / len(g)), int(sum(u["y"] for u in g) / len(g))]})
    return labels
# Words that appear in room names on the owner's plans. OCR words outside this list are dropped (lift icons read as
# "Tl", stray marks); a label left with an unknown word is dropped, never guessed.
VOCAB = set("""BRIDGE COMMAND DECK SENSORS SENSOR SUITE ROOM CIC COMBAT INFORMATION CENTER CREW QUARTERS GALLEY MEDBAY MESS
HANGAR BAY ARMORY CARGO HOLD VEHICLE ENGINEERING REACTOR CORE ENGINE COOLANT SYSTEMS SYSTEM WEAPON WEAPONS LAUNCH
MISSILE MAGAZINE SUPPLY LOADING GENERAL STORAGE REFRIGERATED STORES MUNITIONS RESUPPLY SPARE PARTS COCKPIT BUNK BUNKS
BOMB TACTICAL MED CRAFT CONTROL SUPPLIES EQUIPMENT TRANSFER HUB LOGISTICS OFFICE WORKSHOP MAINTENANCE RECON ARRAY
MISSION DATA ACCESS COMMS BRIEFING BARRACKS TROOP LOCKERS READY POWER UTILITY & /""".split())
FIX = {"BRIOGE": "BRIDGE", "HOLO": "HOLD"}   # misreads seen on these plans (each checked against the picture)
def clean(labels):
    out = []
    for l in labels:
        ws = []
        ok = True
        for w in l["name"].upper().replace("}", ")").split():
            core = w.strip("()"); core = FIX.get(core, core)
            if core in VOCAB: ws.append(w.replace(w.strip("()"), core))
            elif w.startswith("(") and w.endswith(")") and len(core) <= 2: ws.append(w)   # (2) (L) (R)
            else: ok = False
        if ok and ws and not all(w in "&/" for w in ws): out.append({**l, "name": " ".join(ws).title().replace("Cic", "CIC")})
    # a one-word label right under another is the second line of the same name (GALLEY / MESS, BOMB / BAY)
    out.sort(key=lambda l: l["at"][1]); merged = []
    for l in out:
        up = [m for m in merged if 0 < l["at"][1] - m["at"][1] < 40 and abs(l["at"][0] - m["at"][0]) < 50]
        if up and len(l["name"].split()) == 1 and l["name"] in ("Mess", "Bay", "Systems", "Room", "Hold", "Core"):
            m = up[-1]; m["name"] = m["name"] + (" & " if l["name"] == "Mess" and "&" not in m["name"] else " ") + l["name"]
        else: merged.append(dict(l))
    return merged
if __name__ == "__main__":
    png, out = sys.argv[1], sys.argv[2]
    ws, (W, H) = words(png); labels = clean(group(ws, W, H))
    big = [l for l in labels if any(k in l["name"].upper() for k in ("HANGAR", "BAY", "CARGO", "DECK"))] or labels
    json.dump({"plan": os.path.basename(png), "auto": True, "start": big[0]["at"], "ignore": [], "open": [], "rooms": labels, "lifts": []}, open(out, "w"), indent=1)
    print(len(labels), [l["name"] for l in labels])
