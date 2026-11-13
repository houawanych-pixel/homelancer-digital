#!/usr/bin/env python3
"""covenant_capital: PROPOSED extra decks (tools/trace/fleet_compose.py, class table tools/trace/fleet_mine.DECKS), on the traced main deck, shaft (481, 490)."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
from fleet_compose import compose
HERE = os.path.dirname(os.path.abspath(__file__))
bad = compose("covenant_capital", HERE, os.path.join(HERE, "..", "source.jpg"), 527.0, (481, 490), "capital", decks=('upper2', 'upper', 'lower', 'lower2'))
sys.exit(1 if bad else 0)
