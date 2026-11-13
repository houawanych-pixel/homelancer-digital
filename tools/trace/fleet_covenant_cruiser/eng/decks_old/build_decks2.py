#!/usr/bin/env python3
"""Covenant Cruiser: the second extra deck (class rule v13.118: cruiser 4 decks), PROPOSED, from the fleet deck template with crew rooms
above and reserve stores below (fleetdecks.DECK2 names), fitted by fleetfit. Same ONE lift shaft as the other decks."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
import fleetdecks, fleetfit
from shapely.geometry import box

HERE = os.path.dirname(os.path.abspath(__file__))
bad = fleetfit.fit("covenant_cruiser", HERE, ax=591.0, lift=box(553, 470, 583, 500), s=1.0, lift_room="Lift (port)", names=fleetdecks.DECK2, tag="2", decks=("lower",),
                   upper_title="UPPER DECK 2 - CREW", lower_title="LOWER DECK 2 - RESERVE")
sys.exit(1 if bad else 0)
