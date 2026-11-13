#!/usr/bin/env python3
"""Unity Resupply: PROPOSED upper (command / crew) and lower (stores) decks from the proven fleet deck template
(tools/trace/fleetdecks.py, pass 2a style, traced library rooms), mirrored about x 514. Both decks stop at ONE
lift shaft: the main deck's Lift (port), (473, 464). decklib.check() runs on both."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
import fleetdecks
from shapely.geometry import box

HERE = os.path.dirname(os.path.abspath(__file__))
bad = fleetdecks.build("unity_resupply", HERE, ax=514.0, lift=box(460, 450, 486, 478), s=1.0,
                       names={"Observation Dome": "Flight Control", "Navigation": "Logistics", "Security Office": "Quartermaster",
                              "Weapons Locker": "Security", "Targeting": "Cargo Planning", "Fleet Ops": "Comms",
                              "Gunnery Control": "Cargo Control", "Torpedo Store P": "Bulk Hold P", "Torpedo Store S": "Bulk Hold S",
                              "Brig": "Cold Stores", "Cell 1": "Freezer 1", "Cell 2": "Freezer 2", "Cell 3": "Freezer 3",
                              "Detention": "Freezer 4", "Cell 4": "Freezer 5", "Cell 5": "Freezer 6", "Shield Gen P": "Fuel Tank P",
                              "Shield Gen S": "Fuel Tank S", "Machine Shop": "Spare Parts", "Fuel Store": "Med Store"},
                       upper_title="UPPER DECK - COMMAND / CREW", lower_title="LOWER DECK - STORES")
sys.exit(1 if bad else 0)
