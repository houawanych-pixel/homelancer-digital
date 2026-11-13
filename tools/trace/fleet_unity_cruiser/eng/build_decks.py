#!/usr/bin/env python3
"""unity_cruiser: PROPOSED extra decks (tools/trace/fleet_compose.py, class table tools/trace/fleet_mine.DECKS), on the traced main deck, shaft (588, 503)."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
from fleet_compose import compose
HERE = os.path.dirname(os.path.abspath(__file__))
bad = compose("unity_cruiser", HERE, os.path.join(HERE, "..", "source.jpg"), 627.0, (588, 503), "cruiser", narrow=True, max_y=1040, decks=('upper2', 'upper', 'lower', 'lower2'), outer={'lower2': (True, 1040)})   # (a small traced main deck: + the crew deck, so the cruiser outgrows the destroyer)
sys.exit(1 if bad else 0)
