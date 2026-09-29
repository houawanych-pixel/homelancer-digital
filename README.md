# Homelancer Digital — v1.2

Original space-action RPG inspired by the *flow* of classic open-space trading/combat games. All names, ships,
places and art here are original Homelancer content. Engine: Godot 4.3, Compatibility renderer, single-threaded Web export.

**Branch:** `homelancer-v1.2` (not merged to `main`). The old branch name `build01-mobile-combat` is legacy; normal
versions go v1.2 → v1.3 → v1.4.

## Play loop (all working in v1.2)
START → launch from Liberty Hub → fly → target and fight raiders → earn credits → cross the Solara Belt → fly
through the Violet Reach nebula → approach New Terra or Liberty Hub → DOCK → hub → repair/resupply → buy weapons
and missiles → buy/switch ships → launch → fly to the Aquila Jump Gate → JUMP (warp) → Vega → dock at Frontier
Exchange or Eden Prime → fight corsairs → jump back to Solara.

## Controls (phone, landscape)
- Left thumb: floating stick — thrust forward/back and strafe.
- Right thumb: floating stick — aim (yaw/pitch).
- Extra fingers: FIRE (hold), MISSILE, REPAIR, TARGET (cycle), AUTO/MANUAL fire, MAP, CRUISE, GO TO (autopilot).
- DOCK appears near a station or planet; JUMP appears near a gate.
- Every finger belongs to what it first touched, so dragging the aim stick never presses a button.
- Desktop: W/S thrust, A/D strafe, arrows or Q/E aim, Space fire, mouse clicks act as touches.

## Structure
```
main.tscn                 root (scripts/main.gd)
scripts/data.gd           ships, weapons, enemies, both star systems
scripts/game_state.gd     autoload GS: credits, ship, equipment, discovery (session-persistent)
scripts/main.gd           screen flow: title, flight, docking, hub, launch, jump, map, rescue
scripts/space.gd          a star system in flight: world, flight model, combat, AI, docking/gate ranges
scripts/ships.gd          ship visuals: real GLBs when present, otherwise labelled stand-ins
scripts/hud.gd            flight HUD + multi-touch controls, radar, target box
scripts/hub.gd            hub, equipment dealer, ship dealer (3D showroom), repair/resupply
scripts/navmap.gd         system map + known-space map, SET COURSE autopilot
scripts/fx.gd             fades, captions, warp tunnel
scripts/autotest.gd       automated route test (desktop: -- --autotest ; web: ?autotest)
web_shell.html            web loading page with progress and load timings
assets/ships/{player,enemy,civilian}/   drop-in slots for real GLB ships (see docs/V1.2_BUILD.md)
```

## Test
`godot --headless --path . -- --autotest --quit-after-test` runs the full route and prints `RESULT 20/20 PASS`.
The GitHub workflow runs the same test before every Web export.

See `docs/V1.2_BUILD.md` for the build report, asset status and known issues.
