# shipkit — fleet GLB → three game ships

1. `tools/shipkit/make_ships.sh fleet.glb` → `shipkit_out/overview.png` (numbered top/side/front views) and `clusters.png` (one thumbnail per ship).
2. `tools/shipkit/make_ships.sh fleet.glb <cargo#> <enemy#> <carrier#>` (use `4,5` if a ship is split into several pieces).

Each ship is cut out, centred, turned nose → -Z / up → +Y, its front 35 % narrowed (`TAPER=0.65` tip width),
textures cut to 1024 px, then polygon-reduced by Godot's meshoptimizer (`decimate.gd`; budgets 6k / 5k / 12k triangles,
override with `TRIS_CARGO=` etc.). Results land in the slots `ShipFactory` already loads:
`assets/ships/civilian/cargo_ship.glb`, `assets/ships/enemy/enemy_fleet.glb`, `assets/ships/civilian/carrier.glb`.
A ship facing backwards: rerun with `FLIP_ENEMY=1` (or CARGO / CARRIER).
Needs only python3 + numpy/scipy/Pillow and the Godot 4.3 binary (`GODOT=` path).

## v1.2 ships (reproduce)
```
tools/shipkit/make_ships.sh look  Enemy_Fleet.glb   --grid 4x4      # 16 alien ships
tools/shipkit/make_ships.sh look  Regular_Fleet.glb --pieces        # 24 ships
tools/shipkit/make_ships.sh build enemy   Enemy_Fleet.glb   --grid=4x4 11
tools/shipkit/make_ships.sh build cargo   Regular_Fleet.glb --pieces   16 flip
tools/shipkit/make_ships.sh build carrier Regular_Fleet.glb --pieces   22
```
Sheets are laid out flat with noses toward +Y and the detailed side toward +Z; `--axis y` is always used.
`flip` turns a ship around when the automatic nose guess picks the tail (it did for cargo #16).

## Rigging a mech or humanoid (rig_mech.sh)
```
tools/shipkit/rig_mech.sh look IN.glb work/name        # -> work/name_grid.png: measured front | side | top views
# read joint x,y (1 m units) off the front view into guess.json: Hips Spine Chest UpperChest Neck Head Head_end,
# and per side Shoulder UpperArm LowerArm Hand Hand_end UpperLeg LowerLeg Foot Toes Toes_end
tools/shipkit/rig_mech.sh rig work/name guess.json \
   --rule "Head : (np.abs(x-CX*3)<0.18)&(y>2.45)" --rule "UpperChest : (np.abs(x-CX*3)>0.39)&(y>2.57)"
# -> work/name_rigged.glb (3 m, Idle + Walk), work/name_bones.png, work/name_walk.png
```
Rules are in rigged units (3x). Weapons held in a hand: `--rule "LeftHand : (x>...)&(y>...)&(y<...)"`.
Shoulder cannons/backpacks: lock to UpperChest. Humans: add `--human`.
