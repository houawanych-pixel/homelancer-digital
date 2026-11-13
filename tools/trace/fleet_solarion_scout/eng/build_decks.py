#!/usr/bin/env python3
"""solarion_scout: PROPOSED extra decks (tools/trace/fleet_compose.py, class table tools/trace/fleet_mine.DECKS), main deck derived from unity_scout (tools/trace/fleet_derive.py), shaft (472, 800)."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
from fleet_compose import compose
HERE = os.path.dirname(os.path.abspath(__file__))
bad = compose("solarion_scout", HERE, os.path.join(HERE, "..", "source.jpg"), 512.0, (472, 800), "scout", decks=())
sys.exit(1 if bad else 0)
