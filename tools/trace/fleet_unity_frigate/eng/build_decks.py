#!/usr/bin/env python3
"""Unity Frigate: PROPOSED upper (command) and lower (hold) decks from the proven fleet deck template
(tools/trace/fleetdecks.py, pass 2a style, traced library rooms), mirrored about x 512. Both decks stop at ONE
lift shaft: the main deck's Lift (port), (475, 568). decklib.check() runs on both."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
import fleetdecks
from shapely.geometry import box

HERE = os.path.dirname(os.path.abspath(__file__))
bad = fleetdecks.build("unity_frigate", HERE, ax=512.0, lift=box(462, 553, 488, 583), s=1.0, decks=("upper",),
                       names={"Observation Dome": "Observation", "Targeting": "Tactical", "Gunnery Control": "Weapons Control",
                              "Torpedo Store P": "Missile Store P", "Torpedo Store S": "Missile Store S"})
sys.exit(1 if bad else 0)
