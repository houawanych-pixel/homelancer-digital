#!/usr/bin/env python3
"""station_liberty_hub (Liberty Hub): extra decks with the SHIP tool (tools/trace/fleet_compose.py) round the same lift
shaft as the main deck, exactly as the capital ships: upper2 / upper / lower / lower2 (five decks)."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
from fleet_compose import compose
HERE = os.path.dirname(os.path.abspath(__file__))
bad = compose("station_liberty_hub", HERE, os.path.join(HERE, "..", "source.jpg"), 512.0, (488, 698), "capital", decks=('upper2', 'upper', 'lower', 'lower2'))
sys.exit(1 if bad else 0)
