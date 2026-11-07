# Homelancer — Planet Wildlife (Fauna)

Animals living on planets. **Not** enemy factions, kaiju fleets or station bio-weapons.
Status: **proposal / placeholders** (branch `wildlife-test`, not deployed). The owner said these animals are placeholders.
What matters is each animal's **role**: prey, defense or predator. Names, looks and stats can all change.

Art style: Epic Seven anime splash art + Homelancer sci-fi. That means crisp ink lines, cel-shaded colour and readable silhouettes.
It never means photo-real or movie-CGI creatures, and animals never wear armour or uniforms.
In game the animals use toon shading plus an ink outline (`Data.WILDLIFE_TOON`).

## The three roles

| Role | What it does | Never does |
|---|---|---|
| **Prey** | Grazes and roams. It notices you, warns the herd, then runs. | Fights back. |
| **Defense** | Stands its ground. It warns you and keeps warning while you stand off. It fights only if you come right up or hurt it, and gives up at the edge of its territory. | Hunts. Chases you out of its ground. |
| **Predator** | Hunts prey animals, and you can watch a chase. It warns you once, briefly, then attacks if you stay in its ground. It gives up past its territory. | Follows you into a base or pad area. |

Rules for all of them:
- No hit kills you outright. Every attack is telegraphed first (a warn pose, a ring or a wind-up).
- Nothing spawns within 260 m of a base, facility or landing pad, and hunters stop at that edge.
- Active animals are capped per tile (`WILDLIFE_BIOMES.max`), with one giant per area. They spawn 80–260 m away and are gone past 420 m.

## Species shortlist (placeholders)

| Species | Role | Body / brain | Biome (tile kind) | Size | Group | Notes |
|---|---|---|---|---|---|---|
| Mossfleece | prey | woolly grazer | forest, coast, mountains (Meridian, Fields, Verdance) | 2.4 m tall | 4–7 | moss saddle on its back with glowing spores |
| Drift woolly | prey | Mossfleece recolour | ice (Prism, Frost, Glacier) | 2.6 m | 3–6 | snow coat |
| Glow grazer | prey | fluffy grazer | jungle, coast, toxic | 5 m | 1–3 | in game since v12.28 |
| Strider | prey | six-legged deer | jungle, forest, mountains | 6 m | 2–4 | white tail flag alerts every animal within 60 m; in game since v12.28 |
| Prismhart | prey | Strider + crystal shards | crystal (Crystara, Geode, Lumen) | 6 m | 2–3 | |
| Hopper | prey | small hopper in the flowers | jungle, forest, coast, crystal | 1.8 m | 2–5 | in game since v12.28 |
| Grumbark | defense | bear-like, bark plates down its hump | forest, mountains | 6.5 m | 1 | rears up to warn |
| Rime grumbark | defense | Grumbark recolour | ice | 6.8 m | 1 | |
| Rimeback | defense | giant snow ape (ref 2) | ice | 14 m standing | 1 | threat display, charge, ground slam, ice throw |
| Sandmaw | defense | giant burrower | desert, canyon (planet TBD: Keld Minor?) | 45 m long, 18 m out of the ground | 1 | ripple, ring, bite, exposed |
| Vexmaw | predator | lean red reptile hunter (ref 1) | jungle (Thornwild, Brood, Eden Prime) | 4.5 m tall, 12 m long | 1–2 | hunts striders |
| Shale stalker | predator | Vexmaw recolour, rock skin | desert, canyon | 4.5 m | 1–2 | |

Biome split (proposal, needs approval):
- Forest: Mossfleece, Strider, Hopper, Grumbark.
- Jungle: Strider, Glow grazer, Hopper, Vexmaw.
- Farmland is the terran worlds' forest and coast tiles: Mossfleece herds.
- Crystal: Prismhart.
- Snow and ice: Drift woolly, Rime grumbark, Rimeback.
- Desert and canyon: Sandmaw, Shale stalker.

Capital planets mix many biomes because they have many tile kinds.
Scale is set against the 10 m mech (blocks are 5 m), so the animals are bigger than real ones.

## States

- Prey: GRAZE / ROAM → ALERT (head up; a Strider flashes its tail flag) → FLEE (grazers bunch up, prey zig-zag) → GRAZE.
- Defense:
  - PATROL → WARN (jaws open, rearing, spines up; repeats while you stand off).
  - Then ATTACK, only if you come within about 45% of its notice range or hurt it.
  - If you leave its territory it GIVES UP and goes back (RETURN → PATROL).
- Predator:
  - PATROL ↔ HUNT (chases a prey animal near by).
  - WARN (short) → ATTACK (lunge and bite, circles between lunges) → GIVE UP past its territory → RETURN.
- Burrower (Sandmaw), each step one you can read and get away from:
  - UNDER → RIPPLE: a sand wake comes at you. It feels footsteps only, so high flyers are safe.
  - TELEGRAPH: a ring shakes for 1.5 s.
  - EMERGE: it bites inside the ring only, for 18 damage.
  - EXPOSED for 4 s, when it takes double damage.
  - RE-BURROW, then 3 s before it can come again.
- Giant (Rimeback):
  - ROAM → THREAT DISPLAY (arms high, chest beat).
  - CHARGE → SLAM: a 0.55 s wind-up, then a shock ring of 22 m. Jump it (more than 4 m up) or dash out.
  - It throws ice chunks if you stay at range.
- Shots near an animal hurt it (`Data.WILDLIFE_DMG`). Defense animals and predators then turn on you; prey scatter.
- Hunting, loot, taming and mounts are optional and not built.

## Animation list (procedural for now, all on pivots)

| Archetype | Animations |
|---|---|
| Grazer | idle (chewing), graze (head down), walk, run, alert (head up), startle, lie down / sleep* |
| Prey | idle, graze, walk, gallop (six-leg tripod gait), alert freeze (ears up), tail-flag flash, zig-zag bolt, drink* |
| Predator | idle crouch*, stalk, run, warn (hiss, jaws open, spines up), lunge bite, claw swipe*, circle, hit react*, give up (turn away) |
| Burrower | sand wake, ripple, telegraph shake, emerge + bite, exposed sway (mouth opens), hit react*, re-burrow |
| Giant | idle*, knuckle walk, run, threat display (rear + chest beat), charge, ground slam (shock ring), ice throw, give up (walk home) |

\* = not in the placeholder yet.

## Data

`scripts/data.gd` holds all of this:
- `WILDLIFE`: per species `role`, `arch`, `model`, `size`, `walk` / `run`, `notice` / `flee`, `territory`, `reach`, `dmg`, `cd`, `herd`, `cap`, `ground`, `hp`, `diet`, `active`, `col`.
- `WILDLIFE_BIOMES`, `WILDLIFE_PAD_CLEAR`, `WILDLIFE_DMG`, `WILDLIFE_TOON`, `WILDLIFE_PARK`.

`active` (day / dusk / night) is data only, because the surface has no clock yet.

## The test area

- Web: `?wildtest`.
- PC: `HL_WILDTEST=1` or `--wildtest`.

After START you land on Eden Prime's jungle with every species at fixed spots round you (`Data.WILDLIFE_PARK`).
Anything that dies comes back after 20 s.
The automated check is the same env flag with `--autotest` (10 checks). `HL_WILDLINEUP=1` renders every model in a line-up.

## Concept sheets

`tools/fauna/sheets.py OUT_DIR` draws the five archetype sheets and the scale chart.
They are vector art in code, with no paid generation. The art goes to Drive, not the repo.
