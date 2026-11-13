#!/usr/bin/env python3
"""solarion_resupply: PROPOSED extra decks (tools/trace/fleet_compose.py, class table tools/trace/fleet_mine.DECKS), main deck derived from imperium_resupply (tools/trace/fleet_derive.py), shaft (512, 459)."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
from fleet_compose import compose
HERE = os.path.dirname(os.path.abspath(__file__))
bad = compose("solarion_resupply", HERE, os.path.join(HERE, "..", "source.jpg"), 512.0, (512, 459), "resupply", narrow=True, max_y=900, decks=('upper',))
sys.exit(1 if bad else 0)
