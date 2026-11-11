#!/usr/bin/env python3
"""Station interiors from a spec (v13.01 station rebuild): the same method as build_veranthos.py, for the other stations.

Owner (10 Nov): rooms are purpose-shaped, districts are walled complexes with their own corridors (his ChatGPT
interior study of Veranthos), the outer line is clean geometry (a round body, straight spokes, shaped pods, docking
ports along the spokes), four lift shafts at the same place on every deck, no central lift.

  python3 build_station.py aurelion assets/stations3d assets/stations_int [report_dir]

Each deck: the body is the largest circle that fits inside the measured hull at that height (floor and 18 m of
headroom both inside the model), about the body's own centre (measured; the model need not be centred on its origin).
Needs: numpy, opencv, trimesh.
"""
import json, sys, os
import numpy as np, cv2, trimesh
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_veranthos as B
from build_veranthos import K, PX, N, C, WALL, P, pol, Deck, complex_, shape, scalloped, outlines, _w

SEC = "sector"
SPECS = {
    # Room names: the districts are the ones named on the owner's deck picture
    # (HL_Elyza_Aurelion-CapitalOrbitalCitadel_Hub3Level_HoloDeck_20261110_v3); the rooms inside each are working labels.
    "aurelion": {
        "name": "Aurelion Capital Orbital Citadel", "model": "st3d_aurelion_citadel", "system": "aurelion",
        "centre": (0.0, -210.0), "lift_r": 330.0, "ring": (300.0, 360.0), "av_w": 24.0,
        "arm_names": {0: "North Docking Approach", 180: "South Docking Approach", 90: "East Hangar Approach", 270: "West Hangar Approach"},
        "levels": [
            {"id": "L1", "name": "SPIRE DECK", "y": 130.0, "proposed": True, "hub": "Observation", "hub_doors": (0, 90, 180, 270), "G": 30.0,
             "districts": [(300, 60, [(1, [("Sanctum", 1.4, "apse"), ("Sanctum Antechamber", 1, SEC)])]),
                           (60, 180, [(1, [("Observation Lounge East", 1, "bays"), ("Star Chart Room", 1, "oct")])]),
                           (180, 300, [(1, [("Observation Lounge West", 1, "bays"), ("Archive", 1, SEC)])])]},
            {"id": "L2", "name": "UPPER DECK", "y": 40.0, "proposed": False, "hub": "Command", "hub_doors": (0, 90, 180, 270), "G": 30.0,
             "districts": [(320, 40, [(1, [("Comms Room", 1, "oct"), ("Briefing Room", 1.2, "apse")])]),
                           (40, 140, [(1, [("Rest Quarters %d" % k, 1, (SEC if k != 2 else "oct")) for k in (1, 2, 3)])]),
                           (140, 220, [(1, [("Officers' Mess", 1.3, "capsule"), ("Wardroom", 1, SEC)])]),
                           (220, 320, [(1, [("Crew Quarters %d" % k, 1, (SEC if k != 2 else "keystone")) for k in (1, 2, 3)])])]},
            {"id": "L3", "name": "MAIN DECK", "y": -110.0, "proposed": False, "hub": "Central Public Hub", "hub_doors": (0, 45, 90, 135, 180, 225, 270, 315),
             "G": 34.0, "promenade": 50.0, "arms": True,
             "districts": [(330, 30, [(1.0, [("Arrivals Waiting Lounge", 1, "apse")]), (1.3, [("Customs Hall", 1, SEC), ("Screening Lanes", 1.3, "bays"), ("Baggage Inspection", 1, SEC)])]),
                           (30, 80, [(1.0, [("Pharmacy", 1, "oct")]), (1.3, [("Triage", 1, "keystone"), ("Ward", 1.2, SEC)])]),
                           (80, 130, [(1.0, [("Briefing Room A", 1, "oct")]), (1.3, [("Mission Terminal Hall", 1.3, "bays"), ("Briefing Room B", 1, SEC)])]),
                           (130, 180, [(1.0, [("Security Desk", 1, "apse")]), (1.3, [("Security Office", 1, SEC), ("Holding Cells", 1.2, "bays")])]),
                           (180, 250, [(1.0, [("Cantina Booths", 1, SEC)]), (1.4, [("Cantina Bar", 1.5, "capsule"), ("Lounge", 1, "hex")])]),
                           (250, 330, [(1.0, [("Market Stall %d" % k, 1, SEC) for k in (1, 2)]), (1.3, [("Market Stall %d" % k, 1, (SEC if k != 4 else "oct")) for k in (3, 4, 5, 6)])])]},
            {"id": "L4", "name": "LOWER DECK", "y": -190.0, "proposed": False, "hub": "Engineering", "hub_doors": (0, 90, 180, 270), "G": 34.0, "promenade": 44.0,
             "districts": [(300, 60, [(1.0, [("Security Office", 1, "oct"), ("Armory", 1, SEC)]), (1.3, [("Brig Cells", 1.3, "bays"), ("Security Store 1", 1, SEC), ("Security Store 2", 1, SEC)])]),
                           (60, 180, [(1.0, [("Cargo Office", 1, "oct"), ("Cargo Lift Lobby", 1, SEC)]), (1.3, [("Cargo Hold %d" % k, 1, (SEC if k != 2 else "keystone")) for k in (1, 2, 3, 4)])]),
                           (180, 300, [(1.0, [("Maintenance Office", 1, "oct"), ("Tool Store", 1, SEC)]), (1.3, [("Workshop A", 1.2, "bays"), ("Workshop B", 1, SEC), ("Parts Store", 1, SEC), ("Maintenance Bay", 1, "hex")])])]},
            {"id": "L5", "name": "KEEL DECK", "y": -300.0, "proposed": True, "hub": "Reactor", "hub_doors": (90, 270), "G": 30.0,
             "districts": [(300, 60, [(1, [("Reactor Control", 1.3, "bays"), ("Reactor Monitoring", 1, SEC)])]),
                           (60, 180, [(1, [("Life Support Control", 1, "oct"), ("Air Plant", 1.2, "capsule"), ("Water Plant", 1, SEC)])]),
                           (180, 300, [(1, [("Coolant Store", 1, SEC), ("Escape Pod", 1, "capsule"), ("Keel Store", 1, SEC)])])]},
        ],
    },
}

# ---- the five stations added from the owner's FRIENDLY EIGHT concept sheets (10 Nov, "concept only"). Station
# names and room names are the ones printed on those sheets. The sheets' hull shapes are NOT used: every deck is the
# largest round body that fits inside the model at that height (so the plan is smaller and rounder than the sheet).
_SH = ("oct", "bays", "keystone", "apse", "hex", "capsule")
def _row(names, k=0): return [(n, 1, (SEC if i % 2 else _SH[(k + i) % len(_SH)])) for i, n in enumerate(names)]
def D1(a0, a1, names, k=0): return (a0, a1, [(1, _row(names, k))])
def D2(a0, a1, inner, outer, k=0): return (a0, a1, [(1.0, _row(inner, k)), (1.25, _row(outer, k + 2))])
UP, DN, ALL4 = ("NE", "NW"), ("SE", "SW"), ("NE", "SE", "SW", "NW")
_NOTE = "rooms named on the owner's concept sheet (concept only)"
SPECS.update({
    "sepheron": {"name": "Library Station", "model": "HL_Station_Covenant_Capital_retopo", "system": "sepheron", "centre": (0.0, -90.0),
        "lift_r": 330.0, "ring": (300.0, 360.0), "av_w": 24.0, "source_note": _NOTE, "arm_names": {},
        "levels": [
            {"id": "U2", "name": "OBSERVATORY & RESEARCH", "y": 280.0, "proposed": False, "hub": "Advanced Research Wing", "hub_doors": (0, 90, 180, 270), "G": 26.0, "lifts": UP,
             "districts": [D1(300, 60, ["Observatory & Skydeck", "Sensor Array", "Comms Relay"]), D1(60, 180, ["Research Offices", "High Archive (Restricted)", "Archive Stack A"], 1), D1(180, 300, ["Data Analysis", "Telescope Control", "Astro Research Lab"], 2)]},
            {"id": "U1", "name": "LIBRARY & SCHOLAR WING", "y": 120.0, "proposed": False, "hub": "Scholar Commons", "hub_doors": (0, 90, 180, 270), "G": 28.0, "lifts": UP,
             "districts": [D1(300, 60, ["Grand Reading Hall", "Library Stacks C", "Archive Catalog"]), D1(60, 180, ["Seminar Halls", "Rare Texts Vault", "Cultural Archives"], 1), D1(180, 300, ["Digital Library", "Study Rooms", "Library Stacks B"], 2)]},
            {"id": "MAIN", "name": "PUBLIC & OPERATIONS HUB", "y": -114.0, "proposed": False, "hub": "Hub (Public Plaza)", "hub_doors": (0, 45, 90, 135, 180, 225, 270, 315), "G": 32.0, "promenade": 44.0, "lifts": ALL4,
             "districts": [D2(315, 45, ["Mission Board Office"], ["Command / Administration", "Medical Bay & Triage", "Crew Quarters"]), D2(45, 135, ["Supplies / Trade Counter"], ["Weapons Shop", "Private Quarters (Block)", "Docking Concourse B"], 1),
                           D2(135, 225, ["Library Operations"], ["Mess / Galley", "Pilots' Lounge", "Mech Dealer"], 2), D2(225, 315, ["Shipyard / Repair Bay"], ["Hangar / Docking Concourse", "Armory", "Security & Brig"], 3)]},
            {"id": "L1", "name": "ENGINEERING & SUPPORT", "y": -156.0, "proposed": False, "hub": "Power Distribution", "hub_doors": (0, 90, 180, 270), "G": 30.0, "lifts": DN,
             "districts": [D1(300, 60, ["Server / Data Center", "Machine Plant", "Waste Processing"]), D1(60, 180, ["Maintenance Workshops", "Cargo Lockers", "Drone Bays"], 1), D1(180, 300, ["Water Reclamation", "Life Support (Atmos)"], 2)]},
            {"id": "L2", "name": "SYSTEMS & EMERGENCY", "y": -200.0, "proposed": False, "hub": "Systems Integrations", "hub_doors": (0, 90, 180, 270), "G": 26.0, "lifts": DN,
             "districts": [D1(300, 60, ["Cold Storage", "Fire Suppression Control", "Laundry"]), D1(60, 180, ["Escape Pod Control", "Lifeboat / Escape Pod Bay"], 1), D1(180, 300, ["Emergency Suit Lockers", "Utility / Janitor", "Air Scrubbers"], 2)]},
        ]},
    "raptian_major": {"name": "Scrap Citadel", "model": "HL_Station_Savagers_Capital_retopo", "system": "raptian_major", "centre": (8.0, 190.0),
        "lift_r": 330.0, "ring": (300.0, 360.0), "av_w": 24.0, "source_note": _NOTE, "arm_names": {}, "start_level": "MAIN",
        "levels": [
            {"id": "U1", "name": "OPERATIONS / COMMAND", "y": 560.0, "proposed": False, "hub": "Strategy Hub", "hub_doors": (0, 90, 180, 270), "G": 30.0, "lifts": UP,
             "districts": [D1(300, 60, ["Command Center", "Comms / Sensor Center", "Admin / Faction Offices", "Ops Control"]), D1(60, 180, ["Briefing Rooms", "Data / Server Rooms", "Surveillance & Records", "Crew Operations"], 1), D1(180, 300, ["Armory", "Security Operations", "Intel / Mission Planning"], 2)]},
            {"id": "MAIN", "name": "PUBLIC HUB / DOCKS", "y": 380.0, "proposed": False, "hub": "Public Hub", "hub_doors": (0, 45, 90, 135, 180, 225, 270, 315), "G": 30.0, "promenade": 40.0, "lifts": ALL4,
             "districts": [D1(315, 45, ["Mech Dealer", "Weapons Shop", "Pilots' Lounge", "Supplies & Trade"]), D1(45, 135, ["Medical Bay (Triage)", "Brig / Detainment", "Security Post", "Fighting Pit"], 1),
                           D1(135, 225, ["Hangar / Docking Concourse", "Boarding Docks"], 2), D1(225, 315, ["Salvage Sorting", "Shipyard / Repair Bay", "Mission Board (Office)"], 3)]},
            {"id": "L1", "name": "CREW / HABITATION / SERVICES", "y": 100.0, "proposed": False, "hub": "Recreation Lounge", "hub_doors": (0, 90, 180, 270), "G": 30.0, "lifts": ALL4,
             "districts": [D1(300, 60, ["Crew Quarters (A)", "Mess / Galley", "Crew Quarters (B)"]), D1(60, 180, ["Laundry & Sanitation", "Waste Processing", "Maintenance Workshops"], 1), D1(180, 300, ["Life Support / Air Scrubbers", "Water Reclamation", "Private Quarters (Block)"], 2)]},
            {"id": "L2", "name": "INFRASTRUCTURE / INDUSTRIAL", "y": -200.0, "proposed": False, "hub": "Engineering Core", "hub_doors": (0, 90, 180, 270), "G": 30.0, "lifts": DN,
             "districts": [D1(300, 60, ["Power Distribution (Alpha)", "Machine / Plant Rooms", "Power Distribution (Beta)"]), D1(60, 180, ["Cargo Lockers (B)", "Fire Suppression & Safety", "Utility Services", "Escape-Pod / Lifeboat Bays"], 1), D1(180, 300, ["Cold Storage", "Drone Bays", "Cargo Lockers (A)"], 2)]},
        ]},
    "malachar": {"name": "Orbital Command", "model": "HL_Station_Imperium_Capital_retopo", "system": "malachar", "centre": (0.0, 300.0),
        "lift_r": 280.0, "ring": (250.0, 310.0), "av_w": 22.0, "source_note": _NOTE, "arm_names": {}, "start_level": "MAIN",
        "levels": [
            {"id": "U2", "name": "HIGH COMMAND", "y": 480.0, "proposed": False, "hub": "War Room", "hub_doors": (0, 90, 180, 270), "G": 26.0, "lifts": UP,
             "districts": [D1(300, 60, ["Intel Analysis", "High Command", "Comms / Sensor"]), D1(60, 180, ["Fleet Operations", "Data Archive", "Secure Briefing"], 1), D1(180, 300, ["Encryption / Cipher", "Strategy Planning", "Situation Center"], 2)]},
            {"id": "U1", "name": "ADMINISTRATION & GARRISON", "y": 380.0, "proposed": False, "hub": "Garrison Barracks", "hub_doors": (0, 90, 180, 270), "G": 28.0, "lifts": UP,
             "districts": [D1(300, 60, ["Officer Quarters", "Administration Offices", "Staff Quarters"]), D1(60, 180, ["Brig / Holding", "Personnel Records", "Training Simulation"], 1), D1(180, 300, ["Armory", "Security Operations"], 2)]},
            {"id": "MAIN", "name": "PRIMARY DECK", "y": 150.0, "proposed": False, "hub": "Public Hub", "hub_doors": (0, 45, 90, 135, 180, 225, 270, 315), "G": 30.0, "promenade": 40.0, "lifts": ALL4,
             "districts": [D2(315, 45, ["Parade Concourse"], ["Mech Dealer", "Throne / Audience Hall", "Weapons Shop"]), D2(45, 135, ["Pilots' Lounge"], ["Supplies (Trade)", "Hangar / Docking Concourse", "Private Quarters (Block B)"], 1),
                           D2(135, 225, ["Security Checkpoint (Arrivals)"], ["Garrison Control", "Command Operations"], 2), D2(225, 315, ["Medical Bay & Triage"], ["Private Quarters (Block A)", "Shipyard / Repair Bay", "Mission Board Office"], 3)]},
            {"id": "L1", "name": "ENGINEERING & LOGISTICS", "y": 60.0, "proposed": False, "hub": "Reactor Support", "hub_doors": (0, 90, 180, 270), "G": 24.0, "lifts": DN,
             "districts": [D1(300, 60, ["Power Distribution", "Engineering Control", "Life Support"]), D1(60, 180, ["Cargo Lockers", "Crew Quarters", "Crew Mess / Galley"], 1), D1(180, 300, ["Laundry", "Maintenance Workshops", "Drone Bays"], 2)]},
            {"id": "L2", "name": "UTILITIES & RESERVES", "y": -60.0, "proposed": False, "hub": "Supply Reserves", "hub_doors": (0, 90, 180, 270), "G": 24.0, "lifts": DN,
             "districts": [D1(300, 60, ["Water Reclamation", "Environmental Processing", "Waste Processing"]), D1(60, 180, ["Utility Plant", "Escape-Pod / Lifeboat Bays"], 1), D1(180, 300, ["Cold Storage", "Air Scrubbers"], 2)]},
        ]},
    "dreadholm": {"name": "Fleet Command", "model": "st3d_veranthos_summit", "system": "dreadholm", "centre": (0.0, 0.0),
        "lift_r": 440.0, "ring": (410.0, 470.0), "av_w": 26.0, "source_note": _NOTE, "start_level": "MAIN",
        "arm_names": {0: "Hangar / Docking Concourse", 180: "Dock / Airlock (South)", 90: "Dock / Airlock (East)", 270: "Dock / Airlock (West)"},
        "levels": [
            {"id": "U1", "name": "COMMAND / FLEET OPS / ACADEMY", "y": -60.0, "proposed": False, "hub": "Academy Halls (Training / Sim)", "hub_doors": (0, 90, 180, 270), "G": 32.0, "lifts": UP,
             "districts": [D1(300, 60, ["Comms / Sensor Array", "Fleet Operations Centre", "Strategic Planning", "Command Bridge (Fleet)"]), D1(60, 180, ["Admin Offices", "Officer Training", "Briefing Theaters"], 1), D1(180, 300, ["Tactical Training", "Data Servers"], 2)]},
            {"id": "MAIN", "name": "HUB / HANGAR / TRADE / SERVICES", "y": -218.0, "proposed": False, "hub": "Public Hub (Concourse)", "hub_doors": (0, 45, 90, 135, 180, 225, 270, 315), "G": 34.0, "promenade": 50.0, "arms": True, "lifts": ALL4,
             "districts": [D2(315, 45, ["Mission Board Office", "Shipyard / Drydock"], ["Docking Concourse Hall", "Arrivals Hall", "Dock Office"]), D2(45, 135, ["Supplies (Trade)"], ["Pilots' Lounge", "Trade Hall", "Quartermaster"], 1),
                           D2(135, 225, ["Medical Bay (Triage / Treatment)"], ["Security Post", "Brig", "Treatment Ward"], 2), D2(225, 315, ["Mech Dealer"], ["Weapons Shop", "Armory", "Munitions Counter"], 3)]},
            {"id": "L1", "name": "CREW / LOGISTICS / SUPPORT", "y": -300.0, "proposed": False, "hub": "Recreation / Crew Lounge", "hub_doors": (0, 90, 180, 270), "G": 32.0, "lifts": UP,
             "districts": [D2(300, 60, ["Mess / Galley"], ["Crew Quarters (A)", "Crew Quarters (B)", "Laundry"]), D2(60, 180, ["Janitor / Utility"], ["Cargo Lockers", "General Maintenance Workshops"], 1), D2(180, 300, ["Water Reclamation"], ["Cold Storage", "Life Support (Air & Env)"], 2)]},
            {"id": "L2", "name": "ENGINEERING / PRODUCTION / EMERGENCY", "y": -380.0, "proposed": False, "hub": "Engineering Plant (Main Systems)", "hub_doors": (0, 90, 180, 270), "G": 30.0, "lifts": DN,
             "districts": [D1(300, 60, ["Machine Rooms (Engines)", "Power Distribution", "Munitions (Ordnance)"]), D1(60, 180, ["Drone Bays", "Lifeboat / Escape-Pod Bays"], 1), D1(180, 300, ["Emergency Suit Lockers", "Waste Processing"], 2)]},
        ]},
    "vantara": {"name": "Resistance Headquarters", "model": "HL_Station_Liberator_Capital_retopo", "system": "vantara", "centre": (0.0, 110.0),
        "lift_r": 300.0, "ring": (270.0, 330.0), "av_w": 22.0, "source_note": _NOTE, "arm_names": {}, "start_level": "MAIN",
        "levels": [
            {"id": "U2", "name": "OPERATIONS & INTEL", "y": 540.0, "proposed": False, "hub": "Ops Strategy Center", "hub_doors": (0, 90, 180, 270), "G": 28.0, "lifts": UP,
             "districts": [D1(300, 60, ["Recon Intel", "Comms / Sensor Array", "Data Core"]), D1(60, 180, ["Sim Training", "Command Bridge"], 1), D1(180, 300, ["R&D Lab", "Intel Annex"], 2)]},
            {"id": "U1", "name": "ADMIN & MISSION", "y": 400.0, "proposed": False, "hub": "Mission Control", "hub_doors": (0, 90, 180, 270), "G": 28.0, "lifts": UP,
             "districts": [D1(300, 60, ["Staff Quarters", "Admin Offices", "Briefing Suites"]), D1(60, 180, ["Intel Analysis", "Field Command Ops"], 1), D1(180, 300, ["Fleet Coordination", "Mission Annex"], 2)]},
            {"id": "MAIN", "name": "PUBLIC / OPERATIONS", "y": 250.0, "proposed": False, "hub": "Public Hub", "hub_doors": (0, 45, 90, 135, 180, 225, 270, 315), "G": 28.0, "promenade": 36.0, "lifts": ALL4,
             "districts": [D1(315, 45, ["Shipyard / Repair Bay", "Hangar / Docking Concourse", "Hangar Control", "Drone Bays"]), D1(45, 135, ["Supplies / Trade", "Cargo Lockers", "Pilots' Lounge", "Command / Administration"], 1),
                           D1(135, 225, ["Private Quarters (Block B)", "Crew Mess / Galley", "Arrivals / Refugee Processing", "Private Quarters (Block A)"], 2), D1(225, 315, ["Security / Brig", "Medical Bay / Triage (Field Hospital)", "Mission Board Office", "Armory", "Weapons Shop", "Mech Dealer"], 3)]},
            {"id": "L1", "name": "ENGINEERING & PLANT", "y": 100.0, "proposed": False, "hub": "Engineering & Plant Operations", "hub_doors": (0, 90, 180, 270), "G": 28.0, "lifts": DN,
             "districts": [D1(300, 60, ["Life Support", "Power Distribution", "Air Scrubbers"]), D1(60, 180, ["Waste Processing", "Maintenance Workshops"], 1), D1(180, 300, ["Water Reclamation", "Plant Store"], 2)]},
            {"id": "L2", "name": "LOGISTICS & SURVIVAL", "y": -20.0, "proposed": False, "hub": "General Services & Storage", "hub_doors": (0, 90, 180, 270), "G": 24.0, "lifts": DN,
             "districts": [D1(300, 60, ["Laundry", "Cold Storage", "Janitor / Utility"]), D1(60, 180, ["Spare Parts & Logistics", "Lifeboat / Escape Pod Bay"], 4), D1(180, 300, ["Emergency Suit Lockers", "Survival Stores"], 2)]},
        ]},
})

def finish(sp, sid, L, dk, foot, raw, lifts, ports, outdir, repdir, rep, Rin):
    """Lift lobbies, what can be walked to, the report, the deck map and the deck's JSON."""
    lid, y = L["id"], L["y"]
    for (x, z) in lifts:
        m = np.zeros((N, N), np.uint8); cv2.circle(m, P(x, z), int(24 / PX), 1, -1); dk.f |= (m & foot)
    dk.f &= foot
    er = cv2.erode(dk.f, np.ones((3, 3), np.uint8))
    _, lab = cv2.connectedComponents(er, connectivity=4)
    lx = [P(x, z) for x, z in lifts]
    s0 = lab[lx[0][1], lx[0][0]]
    live = cv2.dilate((lab == s0).astype(np.uint8), np.ones((5, 5), np.uint8)) if s0 else np.zeros_like(dk.f)
    cut = [r["name"] for r in dk.rooms if not live[int(C + r["at"][1] / PX), int(C + r["at"][0] / PX)]]
    dk.f &= live
    dk.rooms = [r for r in dk.rooms if r["name"] not in cut]
    outside = int((dk.f & (1 - raw)).sum())
    rep[lid] = {"name": L["name"], "height_m": round(y), "storeys": L.get("storeys", 1), "proposed_addition": L["proposed"], "hull_inscribed_radius_m": round(Rin),
                "floor_area_km2": round(float(dk.f.sum()) * PX * PX / 1e6, 3), "floor_outside_measured_hull_m2": round(outside * PX * PX),
                "rooms": len(dk.rooms), "doors": len(dk.doors), "rooms_dropped_unreachable": cut,
                "lifts_on_walkable_floor": [bool(s0 and lab[p[1], p[0]] == s0) for p in lx],
                "one_door_rooms": sorted(r["name"] for r in dk.rooms if r["doors"] < 2)}
    hullm = cv2.dilate(foot, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (13, 13)))
    im = np.zeros((N, N, 3), np.uint8); im[:] = (40, 16, 8); im[hullm > 0] = (62, 30, 12); im[dk.f > 0] = (110, 62, 20)
    cs, _ = cv2.findContours(hullm, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE); cv2.drawContours(im, cs, -1, (200, 150, 60), 2, cv2.LINE_AA)
    cs, _ = cv2.findContours(dk.f, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_NONE); cv2.drawContours(im, cs, -1, (255, 230, 90), 1, cv2.LINE_AA)
    # crop to the station, so the map fills its frame
    ext = float(Deck(foot).R[foot > 0].max()) + 120.0; h_ = int(min(C, ext / PX))
    for d_ in dk.doors: cv2.circle(im, P(d_["x"], d_["z"]), 3, (90, 255, 90), -1)
    for (x, z), nm in zip(lifts, L.get("lift_names", ("NE", "SE", "SW", "NW"))):
        p = P(x, z); cv2.rectangle(im, (p[0] - 7, p[1] - 7), (p[0] + 7, p[1] + 7), (255, 255, 255), 2)
    im = im[int(C) - h_:int(C) + h_, int(C) - h_:int(C) + h_]
    sc = 1500.0 / im.shape[0]; im = cv2.resize(im, (1500, 1500), interpolation=cv2.INTER_AREA if sc < 1 else cv2.INTER_CUBIC)
    def Q(x, z): return (int(750 + x / PX * sc), int(750 + z / PX * sc))
    for (x, z), nm in zip(lifts, L.get("lift_names", ("NE", "SE", "SW", "NW"))):
        p = Q(x, z); cv2.putText(im, "LIFT " + nm, (p[0] - 26, p[1] - 14), cv2.FONT_HERSHEY_SIMPLEX, 0.4, (255, 255, 255), 1, cv2.LINE_AA)
    for r in dk.rooms:
        t = r["name"].upper(); fs = 0.42 if r["rad"] * sc > 60 else 0.32
        sz = cv2.getTextSize(t, cv2.FONT_HERSHEY_SIMPLEX, fs, 1)[0]; p = Q(*r["at"])
        cv2.putText(im, t, (p[0] - sz[0] // 2, p[1] + 4), cv2.FONT_HERSHEY_SIMPLEX, fs, (255, 255, 255), 1, cv2.LINE_AA)
    cv2.putText(im, "%s  -  %s %s" % (sp["name"].upper(), lid, L["name"]), (30, 44), cv2.FONT_HERSHEY_SIMPLEX, 0.9, (255, 240, 170), 2, cv2.LINE_AA)
    cv2.putText(im, ("DESIGNED ADDITION - not on the blueprint picture" if L["proposed"] else sp.get("source_note", "districts from the blueprint concept")) + "  |  clean outline fitted to %s at %+d m" % (sp["model"], round(y)),
                (30, 72), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (120, 200, 255), 1, cv2.LINE_AA)
    mp = "%s_%s.jpg" % (sid, lid.lower())
    cv2.imwrite(os.path.join(outdir, mp), cv2.resize(im, (1024, 1024), interpolation=cv2.INTER_AREA), [cv2.IMWRITE_JPEG_QUALITY, 85])
    if repdir: cv2.imwrite(os.path.join(repdir, "%s_%s_full.jpg" % (sid, lid.lower())), im, [cv2.IMWRITE_JPEG_QUALITY, 88])
    return ({"id": lid, "name": L["name"], "y": round(y, 1), "proposed": L["proposed"], "map": mp, "map_extent_m": round(2 * h_ * PX, 1), "h": L.get("h", B.ROOM_H), "storeys": L.get("storeys", 1), "decks_in": L.get("decks_in", []),
                       "walls": outlines(dk.f), "doors": dk.doors,
                       "rooms": [{"name": r["name"], "x": round(r["at"][0], 1), "z": round(r["at"][1], 1), "rad": round(r["rad"] * 1.4, 1)} for r in dk.rooms],
                       "lifts": lifts, "ports": ports})


def build(sid, glbdir, outdir, repdir=None):
    sp = SPECS[sid]
    mesh = trimesh.load(os.path.join(glbdir, sp["model"] + ".glb"), force="scene")
    mesh = mesh.to_geometry() if hasattr(mesh, "to_geometry") else mesh.dump(concatenate=True)
    v = np.asarray(mesh.vertices) * K * sp.get("scale", 1.0)
    v[:, 0] -= sp["centre"][0]; v[:, 2] -= sp["centre"][1]            # work about the body's own centre
    tri = v[np.asarray(mesh.faces)]
    B._HM.clear()
    LIFT_R = sp["lift_r"]; ring = sp["ring"]; LIFT_A = (45, 135, 225, 315)
    ANG4 = {"NE": 45, "SE": 135, "SW": 225, "NW": 315}
    lifts_all = [[round(q, 1) for q in pol(LIFT_R, a)] for a in LIFT_A]; lifts = lifts_all
    rep = {"model": sp["model"], "metres_per_model_unit": K, "body_centre_from_model_origin_m": list(sp["centre"]),
           "size_m": {"x": round(float(np.ptp(v[:, 0]))), "z": round(float(np.ptp(v[:, 2]))), "height": round(float(np.ptp(v[:, 1])))}}
    top, bot = B.heightmaps(tri)
    decks = []; levels_out = []
    for L in sp["levels"]:
        lid, y, G = L["id"], L["y"], L.get("G", 34.0)
        L["lift_names"] = tuple(L.get("lifts", ("NE", "SE", "SW", "NW")))      # which shafts stop at this deck
        lifts = [[round(q, 1) for q in pol(LIFT_R, ANG4[nm])] for nm in L["lift_names"]]
        # v13.05 layer method (owner): each layer is two or more storeys tall, as tall as the hull allows up to the layer
        # above; its outline is the model's true section there, mirrored and straightened; where that outline reaches
        # past the round body, the extra floor is kept as an outer bay.
        ups = sorted(q["y"] for q in sp["levels"] if q["y"] > y)
        room_cap = (ups[0] - 6.0 - y) if ups else 9999.0
        base_r = None; storeys = 2
        for st_ in (2, 3, 4, 6):
            if st_ * B.ROOM_H > room_cap: break
            mf_, _ = B.footprint(tri, y, room_h=st_ * B.ROOM_H)
            if not mf_.any(): break
            r_ = float(Deck(mf_).R[mf_ == 0].min())
            if base_r is None: base_r = r_
            if r_ < max(LIFT_R + 50.0, 0.9 * base_r): break
            storeys = st_
        storeys = int(L.get("storeys", storeys)); hgt = storeys * B.ROOM_H
        L["h"] = hgt; L["storeys"] = storeys
        mfoot, raw = B.footprint(tri, y, room_h=hgt)
        sil = B.mirror_clean(raw, sp.get("mirror", "LR"))
        tmp = Deck(mfoot)
        Rin = float(tmp.R[(mfoot == 0) | (sil == 0)].min())
        foot = (tmp.R < Rin).astype(np.uint8)
        arm_parts = []; ports = []; lobes = []
        if not L.get("arms"):
            beyond = (sil & (tmp.R > Rin + WALL + 6).astype(np.uint8))
            beyond = cv2.morphologyEx(beyond, cv2.MORPH_OPEN, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (15, 15)))
            n_, lab_, st2_, cen_ = cv2.connectedComponentsWithStats(beyond, connectivity=8)
            for i_ in range(1, n_):
                if st2_[i_, cv2.CC_STAT_AREA] * PX * PX < 9000.0: continue
                lm = (lab_ == i_).astype(np.uint8)
                dm_ = cv2.distanceTransform(lm, cv2.DIST_L2, 5); yy_, xx_ = np.unravel_index(int(np.argmax(dm_)), dm_.shape)
                if dm_[yy_, xx_] * PX < 22.0: continue                    # (too thin to stand in)
                cx_, cz_ = (xx_ - C) * PX, (yy_ - C) * PX
                ang_ = float(np.degrees(np.arctan2(cx_, -cz_)) % 360)
                neck_ = np.zeros((N, N), np.uint8); cv2.line(neck_, P(*pol(Rin - 10, ang_)), P(cx_, cz_), 1, int(round(30.0 / PX)))
                lobes.append({"mask": lm, "neck": neck_, "a": ang_, "c": (cx_, cz_), "rad": float(dm_[yy_, xx_]) * PX})
                foot |= lm | neck_
        if L.get("arms"):
            # arms: read from the model's outline round this deck's height (the hull within 120 m above or below it)
            sil = ((bot < y + 120.0) & (top > y - 120.0)).astype(np.uint8)
            sil = cv2.morphologyEx(sil, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
            beyond = (sil & (tmp.R > Rin + 60).astype(np.uint8))
            Rmax = float(tmp.R[beyond > 0].max()) if beyond.any() else Rin
            far = beyond & (tmp.R > Rin + 0.45 * (Rmax - Rin)).astype(np.uint8)
            h, _ = np.histogram(tmp.A[far > 0], bins=120, range=(0, 360)); on = h > 0.08 * h.max()
            segs = []; start = next((j for j in range(120) if not on[j]), 0)
            for j in range(start, start + 121):
                jj = j % 120
                if on[jj] and (not segs or segs[-1][0]): segs.append([False, 0.0, 0.0])
                if on[jj]: segs[-1][1] += h[jj] * (j * 3 + 1.5); segs[-1][2] += h[jj]
                elif segs and not segs[-1][0]: segs[-1][0] = True
            dirs = sorted(round((s_[1] / s_[2]) % 360, 1) for s_ in segs if s_[2] > 0)
            rep["arms"] = {"count": len(dirs), "directions_deg_clockwise_from_front": dirs}
            names = sp["arm_names"]; kinds = ("rotunda", "oct", "capsule")
            for ai, a_arm in enumerate(dirs):
                near = min(names, key=lambda q: abs((a_arm - q + 180) % 360 - 180))
                cardinal = abs((a_arm - near + 180) % 360 - 180) < 10
                nm = names[near] if cardinal else "Docking Arm %03d" % int(round(a_arm))
                dev = np.abs((tmp.A - a_arm + 180) % 360 - 180)
                pod = (far & (dev < 9)).astype(np.uint8)
                if pod.sum() == 0: continue
                ys, xs = np.nonzero(pod)
                a_true = float(np.degrees(np.arctan2((xs - C).mean(), -(ys - C).mean())) % 360)
                r_far = float(np.percentile(tmp.R[ys, xs], 97)); wid = float(cv2.distanceTransform(pod, cv2.DIST_L2, 5).max()) * PX
                size = float(np.clip(wid * 1.2, 70.0, 120.0)); r_pod = r_far - size
                if r_pod - size < Rin + 60: continue
                c = np.array(pol(r_pod, a_true))
                pm = shape("cross" if cardinal else kinds[ai % 3], c, a_true, size, size * (1.4 if cardinal else 0.8))
                spk = np.zeros((N, N), np.uint8); cv2.line(spk, P(*pol(Rin - 12, a_true)), P(*c), 1, int(round(36.0 / PX)))
                node = np.zeros((N, N), np.uint8)
                for fr in ((0.5,) if r_pod - size - Rin < 320 else (0.3, 0.7)):     # docking ports on both sides of the spoke
                    rr_p = Rin + (r_pod - size - Rin) * fr
                    for sg in (-1, 1):
                        pc = _w(np.array(pol(rr_p, a_true)), a_true, 0.0, sg * 38.0)
                        node |= shape("oct", pc, a_true, 30.0, 24.0)
                        ports.append({"x": round(float(pc[0]), 1), "z": round(float(pc[1]), 1), "arm": nm, "side": "cw" if sg > 0 else "ccw"})
                foot |= pm | spk | node
                arm_parts.append({"name": nm, "a": a_true, "pod": pm, "spoke": spk | node, "c": c, "r_pod": r_pod})
        dk = Deck(foot)
        dk.corridor(dk.band(ring[0], ring[1]))
        hub = dk.room(L["hub"], scalloped(dk, ring[0] - WALL, 12 if ring[0] < 350 else 16, L["hub_doors"]))
        for a in L["hub_doors"]: dk.rdoor(ring[0] - WALL / 2, a, hub, w=22.0)
        prom = L.get("promenade")
        Ro = Rin - 6
        if prom: dk.corridor(dk.band(Rin - prom, Rin)); Ro = Rin - prom - WALL
        avs = sorted({d[0] for d in L["districts"]})
        for a in avs: dk.avenue(a, ring[1], (Rin - prom) if prom else Ro - 16, sp["av_w"])
        for a0, a1, rows in L["districts"]:
            complex_(dk, ring[1] + WALL, Ro, a0, a1, rows, G=G, av_half=sp["av_w"] / 2)
        got = []
        for ap in arm_parts:
            dk.f |= ap["spoke"] | ap["pod"]
            dm = cv2.distanceTransform(ap["pod"], cv2.DIST_L2, 5); cp = P(*ap["c"])
            dk.rooms.append({"name": ap["name"], "mask": ap["pod"], "at": (float(ap["c"][0]), float(ap["c"][1])), "rad": float(dm[cp[1], cp[0]]) * PX, "doors": 1, "links": set()})
            x, z = pol(Rin + 14, ap["a"])
            dk.doors.append({"x": round(float(x), 1), "z": round(float(z), 1), "yaw": round(ap["a"], 1), "w": 36.0})
            got.append({"name": ap["name"], "direction_deg": round(ap["a"], 1), "pod_centre_from_axis_m": round(ap["r_pod"])})
        if got: rep["main_deck_arms_built"] = got
        used_ = {}
        for lb in lobes:                                         # the outline's outer bays: floor, a neck to the body, a door
            dk.f |= lb["mask"] | lb["neck"]
            q_ = min({0: "North Bay", 90: "East Bay", 180: "South Bay", 270: "West Bay"}.items(), key=lambda q: abs((lb["a"] - q[0] + 180) % 360 - 180))
            nm_ = q_[1] if abs((lb["a"] - q_[0] + 180) % 360 - 180) < 14 else "Outer Bay %03d" % int(round(lb["a"]))
            used_[nm_] = used_.get(nm_, 0) + 1
            if used_[nm_] > 1: nm_ = "%s %d" % (nm_, used_[nm_])
            dk.rooms.append({"name": nm_, "mask": lb["mask"], "at": lb["c"], "rad": lb["rad"], "doors": 1, "links": set()})
            xg, zg = pol(Rin + 4, lb["a"])
            dk.doors.append({"x": round(float(xg), 1), "z": round(float(zg), 1), "yaw": round(lb["a"], 1), "w": 30.0})
        # floors inside the tall hall: balcony rings and ramps, sized to this station's hall
        rw = ring[0] - WALL - 34.0; din = []
        if storeys >= 4 and rw >= 200.0:
            b0 = round(rw * 0.68, 1); r0_ = round(rw * 0.52, 1)
            din.append({"r0": b0, "r1": round(rw - 5.0, 1), "a0": 0.0, "a1": 360.0, "h0": 36.0, "h1": 36.0, "rail_in": True, "rail_out": True, "gaps": [[50, 58], [230, 238], [100, 108], [280, 288]], "name": "Balcony 1"})
            for a in (10.0, 190.0):
                din.append({"r0": r0_, "r1": b0 - 2.0, "a0": a, "a1": a + 40.0, "h0": 0.0, "h1": 36.0, "rail_in": True, "rail_out": True, "name": "Ramp to Balcony 1"})
                din.append({"r0": r0_, "r1": b0, "a0": a + 40.0, "a1": a + 48.0, "h0": 36.0, "h1": 36.0, "rail_in": True, "name": "Landing"})
            if storeys >= 6:
                b1 = round(rw * 0.83, 1)
                din.append({"r0": b1, "r1": round(rw - 5.0, 1), "a0": 0.0, "a1": 360.0, "h0": 72.0, "h1": 72.0, "rail_in": True, "rail_out": True, "gaps": [[140, 148], [320, 328]], "name": "Balcony 2"})
                for a in (100.0, 280.0):
                    din.append({"r0": b0, "r1": b1 - 2.0, "a0": a, "a1": a + 40.0, "h0": 36.0, "h1": 72.0, "rail_in": True, "rail_out": True, "name": "Ramp to Balcony 2"})
                    din.append({"r0": b0, "r1": b1, "a0": a + 40.0, "a1": a + 48.0, "h0": 72.0, "h1": 72.0, "rail_in": True, "name": "Landing"})
        L["decks_in"] = din
        levels_out.append(finish(sp, sid, L, dk, foot, raw, lifts, ports, outdir, repdir, rep, Rin)); decks.append((L, dk))
    rep["lifts"] = {"shafts_xz_m": dict(zip(("NE", "SE", "SW", "NW"), lifts_all)), "distance_from_axis_m": LIFT_R, "stops": {L["id"]: list(L["lift_names"]) for L in sp["levels"]},
                    "serve": "all four shafts serve every deck" if all(all(rep[L["id"]]["lifts_on_walkable_floor"]) for L in sp["levels"]) else "NOT all shafts reach every deck"}
    main = next(L for L in sp["levels"] if L["id"] == sp.get("start_level", "MAIN" if any(q["id"] == "MAIN" for q in sp["levels"]) else "L3"))
    out = {"id": sid, "name": sp["name"], "model": sp["model"], "system": sp["system"], "extent_m": N * PX,
           "start": {"level": main["id"], "x": lifts_all[2][0] + 30.0, "z": lifts_all[2][1], "lift": lifts_all[2]},
           "note": "Clean outline fitted to the exterior model. Districts follow the blueprint concept; room names are working labels. No combat, quests or key locks in this pass.",
           "levels": levels_out}
    json.dump(out, open(os.path.join(outdir, sid + ".json"), "w"), separators=(",", ":"))
    if repdir:
        json.dump(rep, open(os.path.join(repdir, sid + "_report.json"), "w"), indent=1)
        S = 0.25; W_ = 1200; H_ = 700
        im = np.zeros((H_, W_, 3), np.uint8); im[:] = (40, 16, 8)
        pts = np.stack([v[:, 0] * S + W_ / 2, -v[:, 1] * S + H_ / 2], 1)
        cv2.fillPoly(im, list(pts[np.asarray(mesh.faces)].round().astype(np.int32)), (120, 80, 40))
        for L, dk in decks:
            xs = np.nonzero(dk.f.any(axis=0))[0]; x0, x1 = (xs.min() - C) * PX, (xs.max() - C) * PX
            yv = int(-L["y"] * S + H_ / 2)
            cv2.line(im, (int(x0 * S + W_ / 2), yv), (int(x1 * S + W_ / 2), yv), (90, 255, 255) if not L["proposed"] else (90, 160, 255), 3)
            cv2.putText(im, "%s %s  %+d m" % (L["id"], L["name"], round(L["y"])), (20, yv + 4), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (255, 255, 255), 1, cv2.LINE_AA)
        ys_ = [L["y"] for L in sp["levels"]]
        for a in LIFT_A:
            x = pol(LIFT_R, a)[0]
            nm_ = {45: "NE", 135: "SE", 225: "SW", 315: "NW"}[a]; yy_ = [L["y"] for L in sp["levels"] if nm_ in L["lift_names"]]
            cv2.line(im, (int(x * S + W_ / 2), int(-max(yy_) * S + H_ / 2)), (int(x * S + W_ / 2), int(-min(yy_) * S + H_ / 2)), (255, 255, 255), 1)
        cv2.putText(im, "SIDE VIEW (from the front): %s at game scale, deck floors and lift shafts" % sp["model"], (20, 28), cv2.FONT_HERSHEY_SIMPLEX, 0.55, (255, 240, 170), 1, cv2.LINE_AA)
        cv2.imwrite(os.path.join(repdir, sid + "_side.jpg"), im, [cv2.IMWRITE_JPEG_QUALITY, 88])
    print(json.dumps({k: (v_ if not isinstance(v_, dict) or k in ("lifts", "arms") else {q: v_[q] for q in v_ if q in ("hull_inscribed_radius_m", "rooms", "doors", "rooms_dropped_unreachable", "lifts_on_walkable_floor", "one_door_rooms", "floor_outside_measured_hull_m2")}) for k, v_ in rep.items() if k not in ("main_deck_arms_built",)}, indent=0))

# ---- Solarion: a wheel standing on edge. Owner: "four for Solarion (decks stacked along the axle, lower-middle void
# empty, central sphere sealed for now)"; lifts "NW/NE on all levels, SW/SE on L2-L4". The plan of every deck is the
# wheel seen from the front; the decks are slices along the axle (the model's Z), so "up" in the interior is the axle.
def _rows(D, n_out, shapes=("apse", "bays", "oct", "keystone", "hex", "capsule")):
    k = sum(map(ord, D)) % len(shapes)
    return [(1.0, [(D + " Front Hall", 1, shapes[k])]),
            (1.3, [("%s Bay %d" % (D, i + 1), 1, (SEC if i % 2 == 0 else shapes[(k + 1 + i) % len(shapes)])) for i in range(n_out)])]
def _row1(D, n, shapes=("oct", "bays", "keystone", "capsule")):
    k = sum(map(ord, D)) % len(shapes)
    return [(1, [("%s %d" % (D, i + 1), 1, (SEC if i % 2 else shapes[(k + i) % len(shapes)])) for i in range(n)])]

WHEEL = {
    "id": "synthari_capital", "name": "Solarion Capital Station", "model": "HL_Station_Solarion_Capital_retopo", "system": "synthari_capital",
    "lift_r": 1382.0,
    # District names: the owner's deck picture (HL_Solarion-Capital-ClassModel_Hub3Level_BLUEPRINT_GENERATED_20261110_v1).
    # The picture has three decks; the fourth (L3) is a designed addition holding districts the picture puts elsewhere.
    "levels": [
        {"id": "L1", "name": "SOLAR CROWN", "h": -94.0, "proposed": False, "kind": "rail", "arc": (270, 90), "lifts": ("NE", "NW"),
         "districts": [(270, 315, _row1("Crew Quarters", 4)), (315, 45, _row1("Command / Flight Control", 5)), (45, 90, _row1("Comms / Data Relay", 4))]},
        {"id": "L2", "name": "EXCHANGE RING", "h": -130.0, "proposed": False, "kind": "full", "lifts": ("NE", "SE", "SW", "NW"),
         "districts": [(315, 0, _rows("Mech Dealer", 3)), (0, 45, _rows("Medbay", 3)), (45, 90, _rows("Mission Center", 3)), (90, 135, _rows("Weapons & Outfitter", 3)),
                       (135, 180, _rows("Supplies", 3)), (180, 225, _rows("Customs & Tariff Office", 3)), (225, 270, _rows("Pilots Lounge / Cantina", 3)),
                       (270, 315, _rows("Trade Floor / Commodity Exchange", 3))]},
        {"id": "L3", "name": "DOCK RING", "h": -154.0, "proposed": True, "kind": "full", "lifts": ("NE", "SE", "SW", "NW"),
         "districts": [(315, 0, _rows("Guild & Brokerage Offices", 3)), (0, 45, _rows("Executive Suites", 3)), (45, 90, _rows("Arcade East", 3)), (90, 135, _rows("Security Post", 3)),
                       (135, 180, _rows("Hangar Pods East", 2)), (180, 225, _rows("Hangar Pods West", 2)), (225, 270, _rows("Freighter Docks", 2)), (270, 315, _rows("Arcade West", 3))]},
        {"id": "L4", "name": "FOUNDRY HORSESHOE", "h": -190.0, "proposed": False, "kind": "rail", "arc": (20, 340), "lifts": ("NE", "SE", "SW", "NW"),
         "districts": [(20, 45, _row1("Security / Brig", 2)), (45, 135, _row1("Life Support", 6)), (135, 225, _row1("Cargo Hold", 6)), (225, 315, _row1("Engineering", 6)), (315, 340, _row1("Maintenance", 2))]},
    ],
}

def build_wheel(glbdir, outdir, repdir=None):
    sp = WHEEL; sid = sp["id"]
    mesh = trimesh.load(os.path.join(glbdir, sp["model"] + ".glb"), force="scene")
    mesh = mesh.to_geometry() if hasattr(mesh, "to_geometry") else mesh.dump(concatenate=True)
    v0 = np.asarray(mesh.vertices) * K
    v = np.stack([v0[:, 0], v0[:, 2], -v0[:, 1]], 1)        # plan x = model x, plan z = -model y (wheel's top = north), height = model z (the axle)
    tri = v[np.asarray(mesh.faces)]
    B._HM.clear(); top, bot = B.heightmaps(tri)
    ANG = {"NE": 45, "SE": 135, "SW": 225, "NW": 315}
    rep = {"model": sp["model"], "metres_per_model_unit": K, "plan": "front view of the wheel; decks are slices along the axle (model Z)",
           "size_m": {"x": round(float(np.ptp(v0[:, 0]))), "y": round(float(np.ptp(v0[:, 1]))), "axle_z": round(float(np.ptp(v0[:, 2])))},
           "sphere": "sealed: no deck enters the central sphere", "spokes": "not walkable in this pass (they lead only to the sealed sphere)",
           "lower_middle_void": "empty: nothing is built inside the ring"}
    levels_out = []; tmp = Deck(np.ones((N, N), np.uint8))
    for L in sp["levels"]:
        h = L["h"]
        raw = ((bot < h - 3.0) & (top > h + B.ROOM_H + 3.0)).astype(np.uint8)
        raw = cv2.morphologyEx(raw, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
        arc = L.get("arc"); am = tmp.band(0, 9999, arc[0], arc[1]) if arc else np.ones((N, N), np.uint8)
        # the ring at this slice: the widest run of radii where the hull is solid all the way round (the deck's arc)
        cov = {r: float(raw[(tmp.R >= r) & (tmp.R < r + 10) & (am > 0)].mean()) for r in range(900, 1700, 10)}
        runs = []; cur = []
        for r in sorted(cov):
            if cov[r] >= 0.985: cur.append(r)
            elif cur: runs.append(cur); cur = []
        if cur: runs.append(cur)
        runs = [q for q in runs if q[0] <= sp["lift_r"] <= q[-1] + 10]      # the band the lift shafts stand in
        ri, ro = runs[0][0] + B.HULL, runs[0][-1] + 10 - B.HULL
        foot = (tmp.band(ri, ro) & am).astype(np.uint8)
        dk = Deck(foot)
        lifts = [[round(q, 1) for q in pol(sp["lift_r"], ANG[nm])] for nm in L["lifts"]]
        L["lift_names"] = L["lifts"]; L["y"] = h
        avs = sorted({d[0] for d in L["districts"]} | {d[1] for d in L["districts"]})
        if L["kind"] == "full":
            dk.corridor(dk.band(ri, ri + 36.0)); dk.corridor(dk.band(ro - 36.0, ro))
            for a in avs: dk.avenue(a, ri + 30.0, ro - 30.0, 28.0)
            for a0, a1, rows in L["districts"]: complex_(dk, ri + 36.0 + WALL, ro - 36.0 - WALL, a0, a1, rows, G=34.0, av_half=14.0)
        else:
            # a rail deck: the ring is only solid in a narrow outer rail at this slice. A walkway along its inner side,
            # one row of rooms against the outer hull, each with a door to the walkway and a door to its neighbour.
            cw = 26.0; dk.corridor(dk.band(ri, ri + cw))
            for a0, a1, rows in L["districts"]:
                cells = rows[0][1]; span = (a1 - a0) % 360; gapd = np.degrees(WALL / (ri + cw))
                edge = np.degrees(14.0 / ri); prev = None
                for ci, (nm, wgt, kind) in enumerate(cells):
                    b0 = a0 + edge + (span - 2 * edge) * ci / len(cells) + gapd / 2; b1 = a0 + edge + (span - 2 * edge) * (ci + 1) / len(cells) - gapd / 2
                    cell = cv2.morphologyEx(dk.band(ri + cw + WALL, ro, b0, b1), cv2.MORPH_OPEN, B._diamond(4))
                    r = dk.room(nm, cell)
                    if r is None: prev = None; continue
                    dk.rdoor(ri + cw + WALL / 2, (b0 + b1) / 2, r)
                    if prev is not None and dk.tdoor((ri + cw + WALL + ro) / 2, b0 - gapd / 2, r): prev["doors"] += 1
                    prev = r
        levels_out.append(finish(sp, sid, L, dk, foot, raw, lifts, [], outdir, repdir, rep, ro))
        rep[L["id"]]["ring_inner_outer_m"] = [round(ri), round(ro)]; rep[L["id"]]["kind"] = L["kind"]; rep[L["id"]]["lifts"] = list(L["lifts"])
    st = next(l for l in levels_out if l["id"] == "L2"); nw = pol(sp["lift_r"], 315)
    out = {"id": sid, "name": sp["name"], "model": sp["model"], "system": sp["system"], "extent_m": N * PX,
           "start": {"level": "L2", "x": round(nw[0] * 0.985, 1), "z": round(nw[1] * 0.985, 1), "lift": [round(nw[0], 1), round(nw[1], 1)]},
           "note": "A wheel on edge: each deck is the ring seen from the front, the decks are stacked along the axle. The sphere is sealed and nothing is built inside the ring. Room names are working labels. No combat, quests or key locks in this pass.",
           "levels": levels_out}
    json.dump(out, open(os.path.join(outdir, sid + ".json"), "w"), separators=(",", ":"))
    if repdir: json.dump(rep, open(os.path.join(repdir, sid + "_report.json"), "w"), indent=1)
    print(json.dumps({k: v_ for k, v_ in rep.items()}, indent=0))

if __name__ == "__main__":
    if sys.argv[1] == "synthari_capital": build_wheel(sys.argv[2], sys.argv[3], sys.argv[4] if len(sys.argv) > 4 else None)
    else: build(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4] if len(sys.argv) > 4 else None)
