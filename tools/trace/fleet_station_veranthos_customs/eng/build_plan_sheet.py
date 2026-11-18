#!/usr/bin/env python3
"""Liberty Hub (st3d_veranthos_customs) MAIN DECK, measured on the owner's sheet "Liberty Hub Inner Map (Main Deck),
Concept v2" (Drive, 11 Nov 2026; concept/main_deck_sheet.png = the map half, 960 x 1024 px), the same way the capital
ships' main decks were measured on their HoloDeck sheets (planlib).

How the sheet is drawn: bright walkways (an atrium walkway, an inner ring through the two plazas, an octagonal outer
ring, the cross, four diagonal spokes, spokes out to the rim districts) and between them the district blocks, filling
every space up to the station's outline. So here: the walkways are hallways (centre line + width, measured), the station
outline is measured, and every block between walkways is a room, named by the sheet label that sits in it. Mirrored
about the middle line x 507 (everything measured on the left, the right is its twin). Docking bays stick out of the four
corner districts, as on the sheet. One door per room per walkway it meets. ~6.6 sheet px = 1 m."""
import os, sys, math
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
from planlib import *
from shapely.geometry import Polygon, LineString, Point, box
from shapely.ops import unary_union

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "concept", "main_deck_sheet.png")
AX, CY = 507.0, 447.0
M = mirror(AX)
def sym(pts):            # left-half points -> whole outline (mirror, reversed)
    return pts + [(2 * AX - x, y) for x, y in reversed(pts)]
def ring_pts(rx, ry, n=96):
    return [(AX + rx * math.cos(2 * math.pi * k / n), CY + ry * math.sin(2 * math.pi * k / n)) for k in range(n + 1)]
def octring_pts(rx, ry, c=0.41):
    return [(AX - rx * c, CY - ry), (AX + rx * c, CY - ry), (AX + rx, CY - ry * c), (AX + rx, CY + ry * c), (AX + rx * c, CY + ry),
            (AX - rx * c, CY + ry), (AX - rx, CY + ry * c), (AX - rx, CY - ry * c), (AX - rx * c, CY - ry)]
def polar(a_deg, r): return (AX + r * math.cos(math.radians(a_deg)), CY + r * math.sin(math.radians(a_deg)))

# ---- the station outline (measured on the sheet, left half; top / bottom middle on the mirror line)
OUTLINE = Polygon(sym([(AX, 112), (462, 112), (440, 100), (300, 100), (150, 236), (150, 262), (50, 262), (50, 640), (150, 640),
                       (150, 660), (296, 820), (380, 858), (470, 858), (AX, 858)]))

# ---- walkways
W1, W2 = 20, 14
HALLS = [
    hall(*ring_pts(80, 80), w=W2),                    # atrium walkway
    hall(*ring_pts(172, 166), w=W1),                  # inner ring, through the two plazas
    hall(*octring_pts(306, 292), w=W1),               # outer ring (octagon)
    hall((50, CY), (964, CY), w=W1),                  # the cross: across, between the cargo terminals to the rim
    hall((AX, 112), (AX, 858), w=W1),                 # the cross: up and down, arrival to transit
]
RING2 = Polygon(octring_pts(306, 292)[:-1])
def spoke(a, r0, r1, clip):
    """a radial walkway at angle a from radius r0 out to r1, clipped to 'clip' so it ends exactly on the walkway / outline"""
    return hall(polar(a, r0), polar(a, r1), w=W2).intersection(clip)
LS = [
    spoke(225, 172, 700, OUTLINE), spoke(135, 172, 700, OUTLINE),          # diagonal spokes, inner ring -> rim
    spoke(250, 172, 400, RING2.buffer(8)), spoke(200, 172, 400, RING2.buffer(8)),   # short walkways between the rings
    spoke(160, 172, 400, RING2.buffer(8)), spoke(110, 172, 400, RING2.buffer(8)),
    spoke(242, 290, 700, OUTLINE),                                         # rim walkways out to the outline (district edges)
    spoke(112, 290, 700, OUTLINE),
    hall((150, 262), (226, 318), w=W2).intersection(OUTLINE), hall((150, 640), (226, 584), w=W2).intersection(OUTLINE),   # corner districts / cargo terminals
]
HALLS += LS + [M(h) for h in LS]
net = unary_union(HALLS).intersection(OUTLINE.buffer(2))

# ---- districts: every block between the walkways, named by the sheet's label in it (left measured, right = twin)
LABELS_L = {"Customs & Security": (420, 128), "Crew District A": (365, 215), "Repair & Maintenance Complex (North)": (245, 240),
            "Residential District (West)": (336, 290), "Ship Dealer & Showroom": (265, 398), "Cargo Terminal A (Freight)": (100, 350),
            "Cargo Terminal B (Freight)": (100, 545), "Medical Complex (Hospital)": (272, 545), "Repair & Maintenance Complex (South)": (196, 694),
            "Manufacturing & Workshops": (300, 700), "Life Support & Utilities": (420, 790), "Atrium Shops (NW)": (430, 370),
            "Atrium Shops (SW)": (430, 525)}
TWIN = {"Customs & Security": "Passenger Services", "Crew District A": "Crew District B",
        "Repair & Maintenance Complex (North)": "Shipyard & Overhaul Docks (North)", "Residential District (West)": "Commerce District (East)",
        "Ship Dealer & Showroom": "Outfitting & Gear", "Cargo Terminal A (Freight)": "Cargo Terminal C (General)",
        "Cargo Terminal B (Freight)": "Cargo Terminal D (Industrial)", "Medical Complex (Hospital)": "Supplies & Administration",
        "Repair & Maintenance Complex (South)": "Shipyard & Overhaul Docks (South)", "Manufacturing & Workshops": "Workshops (East)",
        "Life Support & Utilities": "Security Control", "Atrium Shops (NW)": "Atrium Shops (NE)", "Atrium Shops (SW)": "Atrium Shops (SE)",
}
LABELS = {"Central Hub (Atrium)": (AX, CY), "Arrival Complex (A/B)": (AX, 60), "Commerce District (North)": (AX + 30, 200),
          "Commerce District (South)": (AX + 30, 668), "Commerce District (North, west wing)": (AX - 30, 200), "Commerce District (South, west wing)": (AX - 30, 668), "Crew & Staff Services": (AX + 30, 815), "Transit Hub": (AX, 930)}
for k, p in LABELS_L.items():
    LABELS[k] = p; LABELS[TWIN[k]] = (2 * AX - p[0], p[1])

R = {}
R["Central Hub (Atrium)"] = circle(AX, CY, 66)
R["Arrival Complex (A/B)"] = Polygon([(478, 22), (536, 22), (536, 40), (552, 40), (552, 112), (462, 112), (462, 40), (478, 40)]).difference(net.buffer(T / 2))
R["Transit Hub"] = box(470, 858, 544, 990)
R["Crew & Staff Services"] = box(472, 790, 542, 838)          # the spine runs into it from both ends (door each end)
net = net.difference(R["Crew & Staff Services"].buffer(T / 2))
cells = OUTLINE.difference(net.buffer(T / 2)).difference(circle(AX, CY, 66 + T)).difference(R["Arrival Complex (A/B)"].buffer(T / 2)).difference(R["Crew & Staff Services"].buffer(T / 2))
n_unnamed = 0
for c in sorted(getattr(cells, "geoms", [cells]), key=lambda c: (round(c.centroid.y / 40), c.centroid.x)):
    if c.area < 300: continue
    name = next((k for k, p in LABELS.items() if k not in R and c.contains(Point(p))), None)
    if name is None:
        n_unnamed += 1; side = "W" if c.centroid.x < AX - 1 else ("E" if c.centroid.x > AX + 1 else "")
        name = "Service Block %s%d" % (side, n_unnamed)
    R[name] = c.simplify(0.6)
# docking bays out of the four corner districts
DOCK_OF = {}
def bays(block, tag, n=3, ln=58, gap=24, w=20):
    g = R[block]; bc = g.centroid; dx, dy = bc.x - AX, bc.y - CY; L_ = math.hypot(dx, dy); u = (dx / L_, dy / L_); v = (-u[1], u[0])
    for k in range(n):
        s_ = (k - (n - 1) / 2) * gap
        t = 0
        while g.contains(Point(bc.x + u[0] * t + v[0] * s_, bc.y + u[1] * t + v[1] * s_)) and t < 300: t += 1
        bx, by = bc.x + u[0] * (t - 3) + v[0] * s_, bc.y + u[1] * (t - 3) + v[1] * s_
        d = LineString([(bx, by), (bx + u[0] * ln, by + u[1] * ln)]).buffer(w / 2, cap_style=2).difference(g)
        if d.geom_type != "Polygon": d = max(d.geoms, key=lambda p: p.area)
        R["%s %d" % (tag, k + 1)] = d; DOCK_OF["%s %d" % (tag, k + 1)] = block
for blk, tag in (("Repair & Maintenance Complex (North)", "Dock NW"), ("Shipyard & Overhaul Docks (North)", "Dock NE"),
                 ("Repair & Maintenance Complex (South)", "Dock SW"), ("Shipyard & Overhaul Docks (South)", "Dock SE")):
    if blk in R: bays(blk, tag)

# ---- doors: one per room per walkway piece it meets; bays open into their district
pieces = list(getattr(net, "geoms", [net]))
DOORS = []
def door_on(g, seg):
    p = seg.interpolate(0.5, normalized=True)
    d = g.exterior.project(p); q0, q1 = g.exterior.interpolate(max(0, d - 4)), g.exterior.interpolate(d + 4)
    return (round(p.x, 1), round(p.y, 1), "h" if abs(q1.x - q0.x) >= abs(q1.y - q0.y) else "v")
for k, g in R.items():
    if k in DOCK_OF: continue
    for hp in pieces:
        touch = g.exterior.intersection(hp.buffer(T))
        segs = sorted([p for p in getattr(touch, "geoms", [touch]) if not p.is_empty and p.length > 0], key=lambda p: -p.length)
        if segs and segs[0].length >= DOOR: DOORS.append(door_on(g, segs[0]))
for k, blk in DOCK_OF.items():
    touch = R[k].exterior.intersection(R[blk].buffer(T))
    segs = sorted([p for p in getattr(touch, "geoms", [touch]) if not p.is_empty and p.length > 0], key=lambda p: -p.length)
    if segs: DOORS.append(door_on(R[k], segs[0]))

HALLS = pieces
S = Ship("liberty_hub_main", HERE, SRC, AX, R, HALLS, DOORS, start=(AX, 70), center_y=CY)
if __name__ == "__main__":
    print("unnamed blocks:", n_unnamed)
    print("labels with no block:", [k for k in LABELS if k not in R])
    bad = run(S)
    sys.exit(1 if bad else 0)
