# shipkit — fleet GLB → three game ships

1. `tools/shipkit/make_ships.sh fleet.glb` → `shipkit_out/overview.png` (numbered top/side/front views) and `clusters.png` (one thumbnail per ship).
2. `tools/shipkit/make_ships.sh fleet.glb <cargo#> <enemy#> <carrier#>` (use `4,5` if a ship is split into several pieces).

Each ship is cut out, centred, turned nose → -Z / up → +Y, its front 35 % narrowed (`TAPER=0.65` tip width),
textures cut to 1024 px, then polygon-reduced by Godot's meshoptimizer (`decimate.gd`; budgets 6k / 5k / 12k triangles,
override with `TRIS_CARGO=` etc.). Results land in the slots `ShipFactory` already loads:
`assets/ships/civilian/cargo_ship.glb`, `assets/ships/enemy/enemy_fleet.glb`, `assets/ships/civilian/carrier.glb`.
A ship facing backwards: rerun with `FLIP_ENEMY=1` (or CARGO / CARRIER).
Needs only python3 + numpy/scipy/Pillow and the Godot 4.3 binary (`GODOT=` path).
