#!/usr/bin/env python3
"""liberator_destroyer: PROPOSED upper and lower decks (owner-preferred pass 2a style, tools/trace/fleet_compose.py), on the main deck
derived from imperium_destroyer (tools/trace/fleet_derive.py), shaft (484, 492)."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
from fleet_compose import compose
HERE = os.path.dirname(os.path.abspath(__file__))
bad = compose("liberator_destroyer", HERE, os.path.join(HERE, "..", "source.jpg"), 512.0, (484, 492), "destroyer", narrow=True)
sys.exit(1 if bad else 0)
