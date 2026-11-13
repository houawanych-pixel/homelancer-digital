#!/usr/bin/env python3
"""covenant_resupply: PROPOSED extra decks (tools/trace/fleet_compose.py, class table tools/trace/fleet_mine.DECKS), on the traced main deck, shaft (434, 775)."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
from fleet_compose import compose
HERE = os.path.dirname(os.path.abspath(__file__))
bad = compose("covenant_resupply", HERE, os.path.join(HERE, "..", "source.jpg"), 567.0, (567, 389), "resupply", narrow=True, max_y=900, decks=('upper',))
sys.exit(1 if bad else 0)
