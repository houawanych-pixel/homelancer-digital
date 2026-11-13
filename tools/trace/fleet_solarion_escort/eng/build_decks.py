#!/usr/bin/env python3
"""solarion_escort: PROPOSED extra decks (tools/trace/fleet_compose.py, class table tools/trace/fleet_mine.DECKS), main deck derived from unity_escort (tools/trace/fleet_derive.py), shaft (468, 635)."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
from fleet_compose import compose
HERE = os.path.dirname(os.path.abspath(__file__))
bad = compose("solarion_escort", HERE, os.path.join(HERE, "..", "source.jpg"), 497.0, (468, 635), "escort", decks=())
sys.exit(1 if bad else 0)
