#!/usr/bin/env python3
"""orion_trooptransport: PROPOSED upper and lower decks (owner-preferred pass 2a style, tools/trace/fleet_compose.py), on the main deck
derived from imperium_trooptransport (tools/trace/fleet_derive.py), shaft (459, 490)."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
from fleet_compose import compose
HERE = os.path.dirname(os.path.abspath(__file__))
bad = compose("orion_trooptransport", HERE, os.path.join(HERE, "..", "source.jpg"), 494.0, (459, 490), "trooptransport")
sys.exit(1 if bad else 0)
