#!/usr/bin/env python3
"""elyza_capital: PROPOSED upper and lower decks, owner-preferred pass 2a style (tools/trace/fleet_compose.py: the Covenant
Capital's hand-picked traced rooms moved onto this ship's axis and main-deck lift shaft, names by class capital).
decklib.check() runs on both decks against this ship's own hull."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
from fleet_compose import compose
HERE = os.path.dirname(os.path.abspath(__file__))
bad = compose("elyza_capital", HERE, os.path.join(HERE, "..", "source.jpg"), 510.0, (482, 494), "capital", decks=("upper2", "upper", "lower", "lower2"))
sys.exit(1 if bad else 0)
