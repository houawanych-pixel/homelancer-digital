#!/usr/bin/env python3
"""Savagers Capital: PROPOSED upper and lower decks from the proven fleet deck template (tools/trace/fleetdecks.py, pass 2a style,
traced library rooms), mirrored about x 512. Both decks stop at ONE lift shaft: the composed main deck's
Lift (port), (488, 522). decklib.check() runs on both."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
import fleetdecks
from shapely.geometry import box

HERE = os.path.dirname(os.path.abspath(__file__))
bad = fleetdecks.build("savagers_capital", HERE, ax=512.0, lift=box(474, 508, 502, 536), s=1.0)
sys.exit(1 if bad else 0)
