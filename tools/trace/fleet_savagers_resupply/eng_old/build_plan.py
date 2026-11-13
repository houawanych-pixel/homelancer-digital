#!/usr/bin/env python3
"""Savagers Resupply main deck, PROPOSED: no HoloDeck sheet, so composed inside the fleet token's silhouette
(tools/trace/token_source.py) by tools/trace/fleetmain.py from the resupply class rules. 10 px = 1 m, mirrored about
x 512. Writes plan.json / plan.png / plan_on_map.jpg and gameplay.json (cards, guards, targets, lifts)."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
import fleetmain
HERE = os.path.dirname(os.path.abspath(__file__))
if __name__ == "__main__":
    fleetmain.main("savagers_resupply", HERE, "resupply")
