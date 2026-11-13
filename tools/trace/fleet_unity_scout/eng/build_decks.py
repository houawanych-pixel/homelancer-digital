#!/usr/bin/env python3
"""RETIRED v13.119 (class rule v13.118: this class has the main deck only). Kept for reference, outputs removed.
Unity Scout: PROPOSED upper (command) and lower (hold) decks from the proven fleet deck template
(tools/trace/fleetdecks.py, pass 2a style, traced library rooms), mirrored about x 512, cut short for the small
hull (no gunnery, pods, batteries, coolant or machine shop: the engine pods start at y 1180). Both decks stop at
ONE lift shaft: the main deck's Lift (port), (472, 800), added in the bunk room's aft corner."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
import fleetdecks
from shapely.geometry import box

HERE = os.path.dirname(os.path.abspath(__file__))
bad = fleetdecks.build("unity_scout", HERE, ax=512.0, lift=box(458, 786, 486, 814), s=1.0,
                       names={"Observation Dome": "Recon Dome", "Navigation": "Signals", "Targeting": "Data Analysis",
                              "Fleet Ops": "Mission Planning", "Torpedo Store P": "Drone Store P", "Torpedo Store S": "Drone Store S"},
                       drop=("Galley", "Gunnery Control", "Escape Pods", "Battery P", "Coolant Pumps", "Machine Shop"),
                       upper_title="UPPER DECK - RECON / CREW", size={"Targeting": 1.12, "Navigation": 1.12, "Officers' Mess": 1.12})
sys.exit(1 if bad else 0)
