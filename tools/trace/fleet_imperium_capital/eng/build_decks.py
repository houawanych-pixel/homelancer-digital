#!/usr/bin/env python3
"""Imperium Capital Ship: PROPOSED upper (COMMAND) and lower (HOLD) decks, the owner-preferred pass 2a style
(tools/trace/fleet_compose.py: the Covenant Capital's hand-picked traced rooms, moved onto this ship's axis and its
main-deck Lift (port) shaft). decklib.check() runs on both decks against this ship's hull."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
from fleet_compose import compose
HERE = os.path.dirname(os.path.abspath(__file__))
bad = compose("imperium_capital", HERE, os.path.join(HERE, "..", "source.jpg"), 506.0, (466, 478), "capital")
sys.exit(1 if bad else 0)
