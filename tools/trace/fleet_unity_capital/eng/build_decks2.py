#!/usr/bin/env python3
"""Unity Capital: the second extra decks (class rule v13.118: capital 5 decks), PROPOSED, from the fleet deck template with crew rooms
above and reserve stores below (fleetdecks.DECK2 names), fitted by fleetfit. Same ONE lift shaft as the other decks."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
import fleetdecks, fleetfit
from shapely.geometry import box

HERE = os.path.dirname(os.path.abspath(__file__))
bad = fleetfit.fit("unity_capital", HERE, ax=512.0, lift=box(468, 460, 498, 490), s=1.0, lift_room="Lift (port)", names=fleetdecks.DECK2, tag="2", decks=("upper", "lower"),
                   upper_title="UPPER DECK 2 - CREW", lower_title="LOWER DECK 2 - RESERVE")
sys.exit(1 if bad else 0)
