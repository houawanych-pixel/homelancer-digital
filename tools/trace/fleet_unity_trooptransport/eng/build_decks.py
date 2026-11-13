#!/usr/bin/env python3
"""unity_trooptransport: PROPOSED extra decks (tools/trace/fleet_compose.py, class table tools/trace/fleet_mine.DECKS), on the traced main deck, shaft (357, 503)."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
from fleet_compose import compose
HERE = os.path.dirname(os.path.abspath(__file__))
bad = compose("unity_trooptransport", HERE, os.path.join(HERE, "..", "source.jpg"), 464.0, (357, 503), "trooptransport", max_y=820, drop=("Security Office", "Admiral's Quarters"), decks=("upper",))   # (the lift is far off the spine: those two rooms make way)
sys.exit(1 if bad else 0)
