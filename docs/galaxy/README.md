# Galaxy map, 11 x 11 — FIRST DRAFT (owner voice call, 3 Oct 2026)

`python3 galaxy_draft.py` draws `galaxy_11x11_draft.jpg` and writes `galaxy_11x11_tiles.csv` and `galaxy_11x11_gates.csv`.
Move a system by changing its tile in the `S` table and run it again; the jump gates re-link themselves.

Owner decisions (replace the 8 x 8 map):
- Grid is 11 x 11 = 121 tiles, every edge wraps. One special system dead centre: the Heart (F6).
- One realm live now (it gets the most unique skybox); three more realms come later. Art for all four is done.
- Gates may skip tiles nobody needs. Draft rule used here: a jump gate reaches the next system and may hop over one open tile.
- Every tile crossing is a load, the same as a gate. The phone holds one system at a time.
- Each system has nebula cloud as a radius: clear in the middle, thick at the rim. Rim haze is painted into the sky,
  with a few live wisps on top (a full live ring costs too much on a phone).
- The rim is the trigger: entering it starts loading the next tile. Turbulence (camera shake) and a short blur build up
  to the swap and clear fast after it.
- Layout: evenly spread, nothing cluttered, factions grouped, enemy homes next to the factions they press on.

Draft choices made by Claude (owner to correct): faction wedges go round the Heart in alliance order (Unity north, then
Solarion, Imperium, Covenant, Orion, Savagers, Liberator, Elyza); capitals sit two tiles from the Heart; the Heart links
only to Veranthos and Dreadholm, so it is the one Unity-Orion crossing; the realm's rift gate sits on the Heart; Shadow
and Radiant sit in opposite corners and are reached by warp gate only; the 6 void systems sit on the outer edge.

- Enemy (grey) factions control the open tiles next to their home (owner, 3 Oct 2026): every open tile touching an
  enemy home, corners included, is that enemy's space. 17 tiles in this draft.
