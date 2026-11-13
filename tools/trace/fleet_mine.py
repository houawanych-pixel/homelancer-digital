#!/usr/bin/env python3
"""v13.115: this session's share of the fleet (owner's split: IMPERIUM, ELYZA, ORION, LIBERATOR; the other session
builds Covenant, Unity, Solarion, Savagers). For every ship that has no HoloDeck sheet: the main deck derived from
the traced ship of its class (fleet_derive.py), then its upper / lower decks (fleet_compose.py) when its class has
them. Run one ship:  python3 -I tools/trace/fleet_mine.py <id>   (no id: list the ships)."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
TR = os.path.dirname(os.path.abspath(__file__))
DONOR = {"capital": "imperium_capital", "cruiser": "imperium_cruiser", "destroyer": "imperium_destroyer", "resupply": "imperium_resupply",
         "trooptransport": "imperium_trooptransport", "frigate": "elyza_frigate", "escort": "unity_escort", "scout": "unity_scout"}
# upper / lower deck settings by class (as on the donor); escort and scout are one deck (class rules)
# owner (Nov 13): the ship gets bigger with the class, in the game's order: scout < escort < frigate (1 extra deck) <
# troop transport (main deck only) < resupply (1 short extra) < destroyer (narrow, 3 extra) < cruiser (3 extra) < capital (4 extra)
# (owner Nov 13: resupply bigger than troop transport, as the game's ship lengths)
DECKS = {"capital": {"decks": ("upper2", "upper", "lower", "lower2")}, "cruiser": {"max_y": 1040, "decks": ("upper", "lower", "lower2")},
         "destroyer": {"narrow": True, "decks": ("upper2", "upper", "lower")}, "frigate": {"narrow": True, "max_y": 900, "decks": ("upper",)},
         "trooptransport": {"decks": ()}, "resupply": {"narrow": True, "max_y": 900, "decks": ("upper",)}}
EXTRA = {"elyza_trooptransport": {"drop": ("Magazine P",)}, "orion_cruiser": {"drop": ("Magazine P",)}}   # (frame names: their twins go too)
SHIPS = ["orion_" + c for c in DONOR] + ["liberator_" + c for c in DONOR] + \
        ["imperium_frigate", "imperium_escort", "imperium_scout", "elyza_trooptransport", "elyza_escort", "elyza_scout"]

def build(sid):
    from fleet_derive import derive
    cls = sid.split("_", 1)[1]
    ax, lifts = derive(sid, DONOR[cls])
    here = os.path.join(TR, "fleet_" + sid, "eng")
    if cls not in DECKS: print(sid, "one deck (class rules): main deck only"); return []
    kw = dict(DECKS[cls]); kw.update(EXTRA.get(sid, {}))
    port = [v for k, v in sorted(lifts.items()) if "Aft" not in k and v[0] <= ax + 1]
    shaft = tuple(port[0] if port else sorted(lifts.values())[0])
    with open(os.path.join(here, "build_decks.py"), "w") as f:
        f.write('''#!/usr/bin/env python3
"""%s: PROPOSED upper and lower decks (owner-preferred pass 2a style, tools/trace/fleet_compose.py), on the main deck
derived from %s (tools/trace/fleet_derive.py), shaft %s."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
from fleet_compose import compose
HERE = os.path.dirname(os.path.abspath(__file__))
bad = compose("%s", HERE, os.path.join(HERE, "..", "source.jpg"), %s, %s, "%s"%s)
sys.exit(1 if bad else 0)
''' % (sid, DONOR[cls], shaft, sid, ax, shaft, cls, "".join(", %s=%r" % kv for kv in kw.items())))
    from fleet_compose import compose
    return compose(sid, here, os.path.join(here, "..", "source.jpg"), ax, shaft, cls, **kw)

if __name__ == "__main__":
    if len(sys.argv) < 2: print("\n".join(SHIPS)); sys.exit(0)
    bad = build(sys.argv[1])
    sys.exit(1 if bad else 0)
