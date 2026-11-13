#!/usr/bin/env python3
"""RETIRED v13.119 (class rule v13.118: this class has the main deck only). Kept for reference, outputs removed.
Unity Troop Transport: PROPOSED upper (troop berths) and lower (hold) decks from the proven fleet deck template
(tools/trace/fleetdecks.py, pass 2a style, traced library rooms), mirrored about x 464. Both decks stop at ONE lift
shaft: the main deck's Lift (port), (357, 503), added off the side corridor; a cross corridor joins it to the spine."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
import fleetdecks
from shapely.geometry import box

HERE = os.path.dirname(os.path.abspath(__file__))
bad = fleetdecks.build("unity_trooptransport", HERE, ax=464.0, lift=box(344, 490, 370, 516), s=1.0,
                       names={"Observation Dome": "Drop Control", "Navigation": "Comms", "Security Office": "Squad Armory",
                              "Weapons Locker": "Gear Lockers", "Captain's Quarters": "Officers", "First Officer": "Sergeants",
                              "Targeting": "Barracks A", "Fleet Ops": "Barracks B", "Lounge P": "Barracks C", "Lounge S": "Barracks D",
                              "Cabins A": "Barracks E", "Cabins B": "Barracks F", "Officers' Mess": "Troop Mess", "Wardroom": "Rec Room",
                              "Gunnery Control": "Ready Room", "Torpedo Store P": "Vehicle Store P", "Torpedo Store S": "Vehicle Store S"},
                       upper_title="UPPER DECK - TROOP BERTHS", size={"Targeting": 1.1, "Security Office": 1.15})
sys.exit(1 if bad else 0)
