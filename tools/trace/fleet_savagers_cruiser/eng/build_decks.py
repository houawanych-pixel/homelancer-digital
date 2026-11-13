#!/usr/bin/env python3
"""savagers_cruiser: PROPOSED extra decks (tools/trace/fleet_compose.py, class table tools/trace/fleet_mine.DECKS), main deck derived from imperium_cruiser (tools/trace/fleet_derive.py), shaft (556, 539)."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
from fleet_compose import compose
HERE = os.path.dirname(os.path.abspath(__file__))
bad = compose("savagers_cruiser", HERE, os.path.join(HERE, "..", "source.jpg"), 587.0, (556, 539), "cruiser", max_y=1040, decks=('upper', 'lower', 'lower2'))
sys.exit(1 if bad else 0)
