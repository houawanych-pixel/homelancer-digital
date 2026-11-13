#!/usr/bin/env python3
"""RETIRED v13.119 (class rule v13.118: this class has the main deck only). Kept for reference, outputs removed.
Savagers Resupply: PROPOSED upper and lower decks from the proven fleet deck template (tools/trace/fleetdecks.py, pass 2a style,
traced library rooms), mirrored about x 512. Both decks stop at ONE lift shaft: the composed main deck's
Lift (port), (488, 560). decklib.check() runs on both."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
import fleetdecks
from shapely.geometry import box

HERE = os.path.dirname(os.path.abspath(__file__))
bad = fleetdecks.build("savagers_resupply", HERE, ax=512.0, lift=box(474, 546, 502, 574), s=1.0, names={"Targeting": "Cargo Planning", "Fleet Ops": "Comms", "Gunnery Control": "Cargo Control", "Torpedo Store P": "Bulk Hold P", "Torpedo Store S": "Bulk Hold S"}, upper_title="UPPER DECK - COMMAND / CREW", lower_title="LOWER DECK - STORES")
sys.exit(1 if bad else 0)
