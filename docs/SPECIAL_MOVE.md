# Special lock-on super move (owner's combat spec, 8 Oct 2026)

Saved as the working spec. Not built yet. Summary:
earn the special lock -> cinematic activation -> huge shield-breaking cannon strike -> real-ammo missile swarm ->
the defender survives through lock breaking, manoeuvring, countermeasures, shields and component durability.

## The sequence
1. Special lock on a target. The target can BREAK the lock before it is committed (its only real chance against the beam).
2. Cut-in (Epic Seven style, a few seconds): the pilot's face large on screen with the activation gesture. The HUD
   stays visible under / around it (shield, hull, targeting, mobile controls).
3. Back to the 3D ship: a dramatic manoeuvre (barrel roll), energy particles building round the weapons.
4. Main energy blast: a large cannon / energy wave with a big visible hit area toward the target; near impossible
   to evade once the lock is complete. Strips or removes shields; overflow goes into hull / components depending on
   the shield left and the impact angle; a hard side hit can take off a wing / component.
5. Missile swarm right after: about 12 missiles with paired launchers. They keep tracking after the beam hits, have
   a lifetime / range limit and self-destruct; expiring or destroyed missiles leave round explosion zones in space
   (the Robotech missile-trail look).

## Evasion
- Normal homing missiles: beatable by flying (climb, dive, hard turns, reversing, U-turn so they overshoot);
  turning back into them is still dangerous. Outlast their lifetime and they detonate harmlessly.
- The special swarm is harder to out-fly. Countermeasure: drop a mine / decoy into its path: missiles hit it, lose
  tracking or detonate round it.

## Twin-launcher rule (ties to the hangar / loadout system)
- Two identical launchers share one targeting sequence. Six-lock weapon: 1 lock = 2 missiles, 3 locks = 6, 6 locks = 12.
- Each launcher's ammunition is used separately; an empty or low launcher does not stop the other.
- Normal missiles fire on a partial lock (one lock = fire that one missile now).
- Heavy torpedo: a longer timed lock (roughly the time of several normal locks; it may still show the six-step
  indicator), much bigger hit area and damage. Two identical torpedo launchers: 1 heavy lock = 2 torpedoes.

## Critical-health special
The special becomes available again at the low-health / critical threshold; the cinematic can be more dramatic.
The special makes the lock and the opening; the missiles fired are still the ship's real installed ammunition
(no free ammo).

## What exists today to build on (v1.5n)
- Missile locks: `LOCK_CONE_DEG`, `LOCK_RANGE`, `LOCK_STEP` 0.5 s per lock; racks "triple" (3) and "Six Rack" (6);
  heavy missile with `HEAVY_LOCKS` 1; volleys (`VOLLEY_GAP`, `VOLLEY_SPREAD`); dodging inside `DODGE_RANGE`.
- Enemy missiles with a lifetime (`ENEMY_MISSILE_LIFE`); signature attacks (Job N).
- Ships with left / right wing sections that can be shot off (`SECTION_SHARE`), shields that soak first.
- Mines (`MINE_DAMAGE`, `MINE_RADIUS`) — the base for the decoy countermeasure.
- Pilot portraits (clean / damaged) for the cut-in.
- Not there yet: two launchers per ship (needs the hangar / loadout slots), missile self-destruct explosion zones for
  the player's missiles, a beam weapon, lock breaking, the cut-in layer.
