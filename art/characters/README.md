# Homelancer characters (source art, not loaded by the game yet — `art/` is ignored by Godot exports)

| File | What | Rig |
|---|---|---|
| `future_soldier_rigged.glb` | Armoured future soldier, 24,862 tris, 1.8 m | New 22-bone humanoid rig (Godot SkeletonProfileHumanoid names: Hips, Spine, Chest, UpperChest, Neck, Head, Left/Right Shoulder, UpperArm, LowerArm, Hand, UpperLeg, LowerLeg, Foot, Toes). Animations: Idle, Walk. Rifle is a **separate object** (`Weapon` node) parented to `RightHand`. |
| `future_soldier_rifle.glb` | The rifle alone: grip at origin, muzzle +Z, sights +Y | none (rigid) |
| `future_soldier_joints.json` | Joint positions used for the rig (body coordinates) | — |

Rebuild: `tools/shipkit/rig_humanoid.py body.glb joints.json out.glb --weapon rifle.glb --weapon-bone RightHand --weapon-at=x,y,z`.
Because bones use Godot humanoid names, any humanoid animation (Mixamo etc.) can be retargeted onto it in Godot.

Checked but not in the repo (too large, source files stay in Drive):
- Ponytail character (`acffb6ed…afraid.glb`): Tripo rig good except the ponytail + a front strand were weighted to the
  right upper arm; fixed with `rigfix.py` (moved to Head). Fixed file delivered to the owner.
- Coat character (`243f0048…agree.glb`): Tripo split the long coat between both legs (and its back between the arms),
  so it tore when she moved. Fixed with `rigfix.py --blend`: coat vertices that sit away from the leg/arm bones now hang
  from Hip, blending up to Spine02 by height. Fixed file delivered to the owner.
- Blue mecha (`c4d26433…fire.glb`) and white mecha (`ba9dc517…dance_03.glb`): Tripo rigs misplaced (skeleton off-centre,
  left-arm bones on the rocket pods, arms bleeding into thighs). Need a re-rig — see owner notes.
