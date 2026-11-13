#!/usr/bin/env python3
"""Unity Cruiser: PROPOSED upper (command) and lower (hold) decks from the proven fleet deck template
(tools/trace/fleetdecks.py, pass 2a style, traced library rooms), mirrored about x 627. Both decks stop at ONE lift
shaft: the main deck's Lift (port), (587, 503). decklib.check() runs on both."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
import fleetdecks
from shapely.geometry import box

HERE = os.path.dirname(os.path.abspath(__file__))
bad = fleetdecks.build("unity_cruiser", HERE, ax=627.0, lift=box(575, 490, 600, 516), s=1.0,
                       names={"Observation Dome": "Observation", "Targeting": "Tactical", "Gunnery Control": "Weapons Control"},
                       drop=("Torpedo Store P",), size={"Cabins A": 1.03}, move={"Battery P": (10, -6)})
sys.exit(1 if bad else 0)
