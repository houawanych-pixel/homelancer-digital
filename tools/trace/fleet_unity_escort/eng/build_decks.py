#!/usr/bin/env python3
"""RETIRED v13.119 (class rule v13.118: this class has the main deck only). Kept for reference, outputs removed.
Unity Escort: PROPOSED upper (command) and lower (hold) decks from the proven fleet deck template
(tools/trace/fleetdecks.py, pass 2a style, traced library rooms), mirrored about x 497. Both decks stop at ONE lift
shaft: the main deck's Lift (port), (468, 635), added beside the spine. decklib.check() runs on both."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
import fleetdecks
from shapely.geometry import box

HERE = os.path.dirname(os.path.abspath(__file__))
bad = fleetdecks.build("unity_escort", HERE, ax=497.0, lift=box(455, 622, 481, 648), s=1.0,
                       names={"Observation Dome": "Observation", "Targeting": "Tactical", "Gunnery Control": "Point Defence",
                              "Torpedo Store P": "Missile Store P", "Torpedo Store S": "Missile Store S"})
sys.exit(1 if bad else 0)
