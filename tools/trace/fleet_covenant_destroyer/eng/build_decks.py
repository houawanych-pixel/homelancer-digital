#!/usr/bin/env python3
"""covenant_destroyer: PROPOSED extra decks (tools/trace/fleet_compose.py, class table tools/trace/fleet_mine.DECKS), on the traced main deck, shaft (482, 484)."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
from fleet_compose import compose
HERE = os.path.dirname(os.path.abspath(__file__))
bad = compose("covenant_destroyer", HERE, os.path.join(HERE, "..", "source.jpg"), 512.0, (482, 484), "destroyer", narrow=True, decks=('upper2', 'upper', 'lower'))
sys.exit(1 if bad else 0)
