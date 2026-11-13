#!/usr/bin/env python3
"""solarion_destroyer: PROPOSED extra decks (tools/trace/fleet_compose.py, class table tools/trace/fleet_mine.DECKS), main deck derived from imperium_destroyer (tools/trace/fleet_derive.py), shaft (484, 492)."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
from fleet_compose import compose
HERE = os.path.dirname(os.path.abspath(__file__))
bad = compose("solarion_destroyer", HERE, os.path.join(HERE, "..", "source.jpg"), 512.0, (484, 492), "destroyer", narrow=True, decks=('upper2', 'upper', 'lower'))
sys.exit(1 if bad else 0)
