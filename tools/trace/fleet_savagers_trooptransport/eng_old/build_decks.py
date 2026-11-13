#!/usr/bin/env python3
"""RETIRED v13.119 (class rule v13.118: this class has the main deck only). Kept for reference, outputs removed.
Savagers Troop Transport: PROPOSED upper and lower decks from the proven fleet deck template (tools/trace/fleetdecks.py, pass 2a style,
traced library rooms), mirrored about x 512. Both decks stop at ONE lift shaft: the composed main deck's
Lift (port), (488, 430). decklib.check() runs on both."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
import fleetfit
from shapely.geometry import box

HERE = os.path.dirname(os.path.abspath(__file__))
bad = fleetfit.fit("savagers_trooptransport", HERE, ax=512.0, lift=box(474, 416, 502, 444), s=1.0, names={"Targeting": "Barracks A", "Fleet Ops": "Barracks B", "Cabins A": "Barracks C", "Cabins B": "Barracks D", "Officers' Mess": "Troop Mess", "Gunnery Control": "Ready Room"}, upper_title="UPPER DECK - TROOP BERTHS")
sys.exit(1 if bad else 0)
