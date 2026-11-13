#!/usr/bin/env python3
"""Unity Destroyer: PROPOSED upper (command) and lower (hold) decks from the proven fleet deck template
(tools/trace/fleetdecks.py, pass 2a style, traced library rooms), mirrored about x 512. Both decks stop at ONE lift
shaft: the main deck's centreline Lift, (512, 597), doors fore and aft. decklib.check() runs on both."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
import fleetdecks
from shapely.geometry import box

HERE = os.path.dirname(os.path.abspath(__file__))
bad = fleetdecks.build("unity_destroyer", HERE, ax=512.0, lift=box(498, 583, 526, 611), s=1.0, lift_room="Lift",
                       names={"Observation Dome": "Observation", "Targeting": "Tactical", "Gunnery Control": "Weapons Control"})
sys.exit(1 if bad else 0)
