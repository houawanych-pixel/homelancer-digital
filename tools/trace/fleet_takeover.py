#!/usr/bin/env python3
"""Owner, Nov 13 2026: "take their ships, put them to scale ... match yours": Covenant, Unity, Solarion and Savagers in
the same format as Imperium / Elyza / Orion / Liberator.
  - REDERIVE (no traced plan, or a main deck too small / boxy): the traced main deck of the class (fleet_mine.DONOR)
    inside the ship's own token (fleet_derive.py), the gameplay of that class (already checked on Orion), then the
    class's extra decks (fleet_mine.DECKS). The old work goes to eng_old/.
  - RECOMPOSE (traced main deck from the official HoloDeck art, kept): only the extra decks are rebuilt with
    fleet_compose.py and the class table; the old decks go to eng/decks_old/.
usage: python3 -I tools/trace/fleet_takeover.py [<id> ...]   (no id: list the ships)"""
import json, os, shutil, sys
TR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, TR)
from fleet_mine import DONOR, DECKS

CLS = ["scout", "escort", "frigate", "trooptransport", "resupply", "destroyer", "cruiser", "capital"]
REDERIVE = ["solarion_" + c for c in CLS] + ["savagers_" + c for c in CLS] + ["covenant_scout", "covenant_escort", "covenant_frigate"]
RECOMPOSE = ["unity_" + c for c in CLS] + ["covenant_" + c for c in CLS[3:]]
GAMEPLAY_FROM = {c: "orion_" + c for c in CLS}      # same donor plan, gameplay already fixed and boarding-tested
GAMEPLAY_FROM["scout"] = "unity_scout"   # (unity_scout got lifts after Orion was derived: its own gameplay matches its plan now)

# the best-fitting donor would break the class size order (owner: bigger class, bigger ship): a bigger deck of the class
FORCE_DONOR = {"solarion_trooptransport": "imperium_trooptransport", "savagers_trooptransport": "imperium_trooptransport",
               "savagers_destroyer": "imperium_destroyer"}

def traced(c):
    """the ships of class c with a main deck traced from official HoloDeck art (possible donors)"""
    out = []
    for f in ("imperium", "elyza", "covenant", "unity"):
        p = os.path.join(TR, "fleet_%s_%s" % (f, c), "eng", "plan.json")
        if os.path.exists(p):
            P = json.load(open(p))
            if "derived_from" not in P and any("ift" in k for k in P["rooms"]): out.append("%s_%s" % (f, c))   # (needs a main lift)
    return out

def best_donor(sid, cls):
    """the traced deck of the class that fits this ship's token at the smallest scale (ties: fleet_mine.DONOR)"""
    import io, contextlib, fleet_derive
    tmp = "zz_try_" + sid; tok = os.path.join(TR, "..", "..", "assets", "fleet_tokens")
    shutil.copy(os.path.join(tok, sid + ".png"), os.path.join(tok, tmp + ".png"))
    res = []
    try:
        for d in traced(cls):
            with contextlib.redirect_stdout(io.StringIO()): fleet_derive.derive(tmp, d)
            res.append((round(fleet_derive.LAST_K, 2), d != DONOR[cls], d))
    finally:
        os.remove(os.path.join(tok, tmp + ".png")); shutil.rmtree(os.path.join(TR, "fleet_" + tmp), ignore_errors=True)
    print("  donor fit (token scale):", sorted(res))
    return sorted(res)[0][2]

def _shaft(P, ax):
    lifts = {k: shape_c(g) for k, g in P["rooms"].items() if "ift" in k and "Lower" not in k and "Aft" not in k}
    port = [v for k, v in sorted(lifts.items()) if v[0] <= ax + 1]
    return tuple(port[0] if port else sorted(lifts.values())[0])

def shape_c(g):
    from shapely.geometry import shape
    return [round(v) for v in shape(g).centroid.coords[0]]

def _write_builder(here, sid, ax, shaft, cls, kw, note):
    with open(os.path.join(here, "build_decks.py"), "w") as f:
        f.write('''#!/usr/bin/env python3
"""%s: PROPOSED extra decks (tools/trace/fleet_compose.py, class table tools/trace/fleet_mine.DECKS), %s, shaft %s."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
from fleet_compose import compose
HERE = os.path.dirname(os.path.abspath(__file__))
bad = compose("%s", HERE, os.path.join(HERE, "..", "source.jpg"), %s, %s, "%s"%s)
sys.exit(1 if bad else 0)
''' % (sid, note, shaft, sid, ax, shaft, cls, "".join(", %s=%r" % kv for kv in kw.items())))

def build(sid):
    from fleet_compose import compose
    cls = sid.split("_", 1)[1]
    folder = os.path.join(TR, "fleet_" + sid); here = os.path.join(folder, "eng")
    if sid in REDERIVE:
        from fleet_derive import derive
        if os.path.isdir(here) and not os.path.isdir(os.path.join(folder, "eng_old")):
            shutil.move(here, os.path.join(folder, "eng_old"))
            if os.path.exists(os.path.join(folder, "source.jpg")):
                shutil.copy(os.path.join(folder, "source.jpg"), os.path.join(folder, "eng_old", "source.jpg"))
        if os.path.exists(os.path.join(folder, "source_mask.png")):   # (the old composed silhouette: the token decides now)
            shutil.move(os.path.join(folder, "source_mask.png"), os.path.join(folder, "eng_old", "source_mask.png"))
        donor = FORCE_DONOR.get(sid) or best_donor(sid, cls)
        ax, lifts = derive(sid, donor)
        gsrc = GAMEPLAY_FROM[cls] if donor == DONOR[cls] else donor
        g = json.load(open(os.path.join(TR, "fleet_" + gsrc, "eng", "gameplay.json")))
        g.pop("retired_decks", None); g.pop("decks", None); g.pop("elevators", None)
        g["derived_from"] = donor; g["gameplay_from"] = gsrc
        json.dump(g, open(os.path.join(here, "gameplay.json"), "w"), indent=1)
        note = "main deck derived from %s (tools/trace/fleet_derive.py)" % donor
    else:
        old = os.path.join(here, "decks_old"); os.makedirs(old, exist_ok=True)
        for f in os.listdir(here):
            if (f.startswith("deck_") or f.startswith("decks") or f.startswith("build_decks")) and os.path.isfile(os.path.join(here, f)):
                shutil.move(os.path.join(here, f), os.path.join(old, f))
        ax = float(json.load(open(os.path.join(here, "plan.json")))["mirror_x"])
        note = "on the traced main deck"
    P = json.load(open(os.path.join(here, "plan.json")))
    shaft = _shaft(P, ax)
    kw = dict(DECKS.get(cls, {"decks": ()}))
    _write_builder(here, sid, ax, shaft, cls, kw, note)
    return compose(sid, here, os.path.join(folder, "source.jpg"), ax, shaft, cls, **kw)

if __name__ == "__main__":
    ids = sys.argv[1:]
    if not ids: print("\n".join(REDERIVE + RECOMPOSE)); sys.exit(0)
    bad = []
    for sid in ids:
        b = build(sid); print("==", sid, "failures:", len(b)); bad += b
    sys.exit(1 if bad else 0)
