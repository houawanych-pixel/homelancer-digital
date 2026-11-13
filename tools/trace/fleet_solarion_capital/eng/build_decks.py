#!/usr/bin/env python3
"""solarion_capital: PROPOSED extra decks (tools/trace/fleet_compose.py, class table tools/trace/fleet_mine.DECKS), main deck derived from elyza_capital (tools/trace/fleet_derive.py), shaft (482, 494)."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
from fleet_compose import compose
HERE = os.path.dirname(os.path.abspath(__file__))
bad = compose("solarion_capital", HERE, os.path.join(HERE, "..", "source.jpg"), 510.0, (482, 494), "capital", decks=('upper2', 'upper', 'lower', 'lower2'))
sys.exit(1 if bad else 0)
