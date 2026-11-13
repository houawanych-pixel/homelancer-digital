#!/usr/bin/env python3
"""orion_capital: PROPOSED upper and lower decks (owner-preferred pass 2a style, tools/trace/fleet_compose.py), on the main deck
derived from imperium_capital (tools/trace/fleet_derive.py), shaft (466, 478)."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
from fleet_compose import compose
HERE = os.path.dirname(os.path.abspath(__file__))
bad = compose("orion_capital", HERE, os.path.join(HERE, "..", "source.jpg"), 506.0, (466, 478), "capital")
sys.exit(1 if bad else 0)
