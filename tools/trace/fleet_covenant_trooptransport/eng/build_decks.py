#!/usr/bin/env python3
"""Covenant Troop Transport: ONE short upper deck (troop berths), PROPOSED (v13.120). The class rule says main deck only,
but this ship's traced main deck is smaller than its resupply ship's, and the owner's first rule is that floor grows
with the class (scout < escort < frigate < resupply < troop transport < destroyer ...): the short deck puts it back in
order. From the fleet deck template (fleetdecks.SHORT_UPPER), one lift shaft = the main deck's Lift (port)."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
import fleetdecks
from shapely.geometry import box

HERE = os.path.dirname(os.path.abspath(__file__))
bad = fleetdecks.build("covenant_trooptransport", HERE, ax=512.0, lift=box(430, 503, 458, 531), s=1.0, decks=("upper",), **fleetdecks.SHORT_UPPER,
                       names={"Observation Dome": "Drop Control", "Navigation": "Comms", "Security Office": "Squad Armory",
                              "Weapons Locker": "Gear Lockers", "Captain's Quarters": "Barracks A", "First Officer": "Barracks B",
                              "Targeting": "Barracks C", "Fleet Ops": "Barracks D", "Officers' Mess": "Troop Mess"},
                       upper_title="UPPER DECK - TROOP BERTHS")
sys.exit(1 if bad else 0)
