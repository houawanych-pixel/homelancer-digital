#!/usr/bin/env python3
"""elyza_destroyer: PROPOSED upper and lower decks, owner-preferred pass 2a style (tools/trace/fleet_compose.py: the Covenant
Capital's hand-picked traced rooms moved onto this ship's axis and main-deck lift shaft, names by class destroyer).
decklib.check() runs on both decks against this ship's own hull."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
from fleet_compose import compose
HERE = os.path.dirname(os.path.abspath(__file__))
bad = compose("elyza_destroyer", HERE, os.path.join(HERE, "..", "source.jpg"), 511.0, (511, 567), "destroyer", narrow=True, decks=("upper2", "upper", "lower"))
sys.exit(1 if bad else 0)
