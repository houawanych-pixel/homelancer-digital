#!/usr/bin/env python3
"""unity_destroyer: PROPOSED extra decks (tools/trace/fleet_compose.py, class table tools/trace/fleet_mine.DECKS), on the traced main deck, shaft (512, 597)."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
from fleet_compose import compose
HERE = os.path.dirname(os.path.abspath(__file__))
bad = compose("unity_destroyer", HERE, os.path.join(HERE, "..", "source.jpg"), 512.0, (512, 597), "destroyer", narrow=True, max_y=1040, decks=('upper2', 'upper', 'lower'))
sys.exit(1 if bad else 0)
