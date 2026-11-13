#!/usr/bin/env python3
"""Fit the fleet deck template (fleetdecks.py) into a hull it was not drawn for (the composed Solarion / Savagers
ships): run it, and for every room the check finds outside the hull, first pull it towards the axis (2 m, then 4 m),
then shrink it, then leave it out (only rooms the deck can do without). Repeats until the check passes or nothing is
left to try. Each step is printed, so the final call can be copied into the ship's build_decks.py."""
import io, contextlib, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fleetdecks

TWIN = {"Sensors": "Navigation", "Weapons Locker": "Security Office", "First Officer": "Captain's Quarters", "Fleet Ops": "Targeting",
        "Lounge S": "Lounge P", "Cabins B": "Cabins A", "Wardroom": "Galley", "Water Recycling": "Life Support", "Cargo Hold B": "Cargo Hold A",
        "Torpedo Store S": "Torpedo Store P", "Fuel Store": "Machine Shop", "Shield Gen S": "Shield Gen P", "Battery S": "Battery P",
        "Detention": "Cell 1", "Cell 4": "Cell 2", "Cell 5": "Cell 3"}
AXIAL = {"Observation Dome", "Officers' Mess", "Coolant Pumps", "Gunnery Control", "Escape Pods", "Brig", "Battery P", "Galley", "Life Support",
         "Cell 1", "Cell 2", "Cell 3"}   # (not moved: shrunk, then left out)
KEEP = {"Observation Dome", "Officers' Mess", "Life Support"}
ORDER = ["Escape Pods", "Battery P", "Coolant Pumps", "Gunnery Control", "Machine Shop", "Torpedo Store P", "Galley", "Lounge P",
         "Cabins A", "Cargo Hold A", "Shield Gen P", "Targeting", "Security Office", "Navigation", "Captain's Quarters"]


def fit(sid, here, ax, lift, names=None, drop=(), move=None, size=None, rounds=14, **kw):
    names = dict(names or {}); inv = {v: k for k, v in names.items()}
    drop, move, size = list(drop), dict(move or {}), dict(size or {})
    tries = {}
    for r in range(rounds):
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            try:
                bad = fleetdecks.build(sid, here, ax, lift, names=names, drop=tuple(drop), move=move, size=size, **kw)
            except (Exception, SystemExit) as e:      # a room squeezed to nothing or a connector missing it
                bad = ["error: %s" % e]
        out = [b.split(": ", 1)[1].split("; ") for b in bad if b.startswith("outside the hull")]
        out = [n for l in out for n in l]
        if not bad:
            print("FIT %s: drop=%r move=%r size=%r" % (sid, tuple(drop), move, size)); print(buf.getvalue().splitlines()[-1]); return []
        keys = []
        for n in out:
            k = inv.get(n, n); k = TWIN.get(k, k)
            if k.startswith("Cell"): k = "Brig"     # (the brig and its cells go as one)
            if k not in keys: keys.append(k)
        if not keys:   # anything else wrong with a room that was moved or shrunk: leave it out
            hit = []
            for bb in bad:
                for k0 in list(move) + list(size):
                    for nm in {k0, names.get(k0, k0)} | {n for n, t in TWIN.items() if t == k0}:
                        if nm in bb and k0 not in KEEP and k0 not in drop and k0 not in hit: hit.append(k0)
            if hit:
                for k0 in hit:
                    drop.append(k0); move.pop(k0, None); size.pop(k0, None)
                    if k0 == "Coolant Pumps" and "Escape Pods" not in drop: drop.append("Escape Pods")
                continue
            cov = [b for b in bad if b.startswith("rooms cover")]
            if cov and r < rounds - 1:
                pct = float(cov[0].split()[2].rstrip("%"))
                victim = next((k for k in ORDER if k not in drop and k not in KEEP), None)
                if pct > 65 and victim: drop.append(victim); continue
                if pct < 55:
                    for k in ("Targeting", "Cabins A", "Captain's Quarters"):
                        if k not in drop: size[k] = round(size.get(k, 1.0) + 0.06, 2)
                    continue
            if bad[0].startswith("error") and "link " in bad[0]:
                k = bad[0].split("link ", 1)[1].split(" ->")[0]; k = inv.get(k, k); k = TWIN.get(k, k)
                if k not in KEEP and k not in drop: drop.append(k); continue
            if bad[0].startswith("error") and tries:
                last = list(tries)[-1]
                if last not in KEEP and last not in drop: drop.append(last); continue
            print("FIT %s FAILED: %s" % (sid, bad[:6])); return bad
        for k in keys:
            t = tries.get(k, 0); tries[k] = t + 1
            if k == "Observation Dome" and t < 3:      # the nose is narrow: slide the dome aft first
                dx, dy = move.get(k, (0, 0)); move[k] = (dx, dy + 24)
            elif k == "Officers' Mess" and t < 3:     # a short tail: slide the mess forward
                dx, dy = move.get(k, (0, 0)); move[k] = (dx, dy - 16); move["Galley"] = (move.get("Galley", (0, 0))[0], dy - 16)
                if "Gunnery Control" not in drop: drop.append("Gunnery Control")
            elif k not in AXIAL and t < 2:
                dx, dy = move.get(k, (0, 0)); move[k] = (dx + 20, dy)
            elif t < 4 and (k in KEEP or t < 3):
                size[k] = round(size.get(k, 1.0) * 0.88, 2)
            elif k not in KEEP:
                drop.append(k)
                if k == "Coolant Pumps" and "Escape Pods" not in drop: drop.append("Escape Pods")
            else:
                print("FIT %s FAILED on %s: %s" % (sid, k, bad[:6])); return bad
    print("FIT %s gave up: %s" % (sid, bad[:6])); return bad


if __name__ == "__main__":
    pass
