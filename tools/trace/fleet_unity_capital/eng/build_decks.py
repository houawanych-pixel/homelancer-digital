#!/usr/bin/env python3
"""Unity Capital: PROPOSED upper (flag / command) and lower (hold) decks from the proven fleet deck template
(tools/trace/fleetdecks.py, pass 2a style, traced library rooms), scaled 1.2x for the capital hull, mirrored about
x 512. Both decks stop at ONE lift shaft: the main deck's Lift (port), (483, 475). decklib.check() runs on both."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
import fleetdecks
from shapely.geometry import box

HERE = os.path.dirname(os.path.abspath(__file__))
bad = fleetdecks.build("unity_capital", HERE, ax=512.0, lift=box(468, 460, 498, 490), s=1.2,
                       names={"Observation Dome": "Flag Bridge", "Captain's Quarters": "Admiral's Quarters", "First Officer": "Captain's Quarters",
                              "Targeting": "War Room", "Gunnery Control": "Fleet Gunnery", "Torpedo Store P": "Magazine P", "Torpedo Store S": "Magazine S"},
                       move={"Galley": (5, 0)}, upper_title="UPPER DECK - FLAG / COMMAND")
sys.exit(1 if bad else 0)
