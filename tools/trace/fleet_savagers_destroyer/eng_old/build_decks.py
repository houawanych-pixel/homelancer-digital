#!/usr/bin/env python3
"""Savagers Destroyer: PROPOSED upper and lower decks from the proven fleet deck template (tools/trace/fleetdecks.py, pass 2a style,
traced library rooms), mirrored about x 512. Both decks stop at ONE lift shaft: the composed main deck's
Lift (port), (488, 521). decklib.check() runs on both."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
import fleetfit
from shapely.geometry import box

HERE = os.path.dirname(os.path.abspath(__file__))
bad = fleetfit.fit("savagers_destroyer", HERE, ax=512.0, lift=box(474, 507, 502, 535), s=1.0)
sys.exit(1 if bad else 0)
