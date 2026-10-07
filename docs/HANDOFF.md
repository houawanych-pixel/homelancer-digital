# Homelancer — working handoff (for a new Claude session)

## Where things are
- Repo: github.com/houawanych-pixel/homelancer-digital (public read). Work branch: `homelancer-v1.2`.
  Never force-push, never merge to main, deploy only via GitHub Pages (workflow "Homelancer web playtest").
- Claude cannot push (GitHub not linked). Changes go out as **chief jobs**: a git bundle + TASK.md zipped, the owner
  uploads it to Drive "FOR THE CHIEF - uploads", the "Chief of Staff" bot pushes it and reports the hash.
- Live game: https://houawanych-pixel.github.io/homelancer-digital/ (Godot 4.3 web, gl_compatibility, phone landscape).

## Fresh session setup
    git clone -b homelancer-v1.2 https://github.com/houawanych-pixel/homelancer-digital /home/claude/hl
    bash /home/claude/hl/tools/setup_env.sh          # Godot 4.3 binary (+ --web for export templates)
    export GODOT=/home/claude/godot/Godot_v4.3-stable_linux.x86_64
    cd /home/claude/hl && $GODOT --headless --import --path .
    xvfb-run -a $GODOT --audio-driver Dummy --rendering-driver opengl3 --resolution 1280x720 --path . -- --autotest --quit-after-test
      -> must print RESULT 259/259 PASS on a screen, 259/259 with no screen as GitHub runs it (the web build prints its own count)  (HL_SHOT_DIR=/dir saves screenshots; HL_SHOWCASE=1 = short combat demo; HL_CITY=1 = city prototype shots only; HL_MISSILE=1 = the Job M combat checks only; HL_ART=1 = the Job N art map and Lockon checks only; HL_O=1 = the Job O checks only; HL_P=1 = the Job P checks only; HL_Q=1 = the Job Q checks only; HL_S=1 = the Job S checks only; HL_U=1 = the Job U Savagers ship checks only; HL_AA=1 = the Job AA faction-cast checks only; HL_Z=1 = the Job Z station-name checks only; HL_Y=1 = the Job Y spacing / prompt / lane-tunnel checks only; HL_X=1 = the Job X voice checks only; HL_W=1 = the Job W hub-background checks only; HL_V=1 = the Job V faction, reputation, station and beacon checks only (HL_V=2 adds review shots in Plundros))

## Game layout (scripts/)
main.gd (states, calls, hub/map), space.gd (world, combat, enemies, missiles, stations), hud.gd (mobile HUD, call box
with portraits, enemy bars), ships.gd (ShipFactory: GLB map key -> [path, length, yaw]), data.gd (systems, ships,
weapons, ENEMIES with shields, CHARACTERS with face/voice, PILOTS), sfx.gd (autoload Sfx: chirp, mumble, combat SFX,
optional text-to-speech), autotest.gd (route test + showcase), game_state.gd (autoload GS).

## Assets
- Ships/weapons/stations: assets/ships|weapons|stations/*.glb, textures imported as lossy WebP (compress/mode=1,
  lossy_quality=0.8 in the .import files) to keep the web pck small (~12 MB now).
- Portraits: assets/portraits/<face>_<normal|serious|angry|sad|smile>.png (256 px, cropped from character sheets).
- Sounds: assets/audio/*.wav from tools/sfx/make_sfx.py (pure synthesis).
- Source art (not in the build, folders have .gdignore): art/characters (rigged mechs/soldier), art/portraits.

## Tools (tools/shipkit)
rig_mech.sh (Tripo GLB -> rigged mech), auto_joints.py, rig_humanoid.py, rigfix.py, bonemap.py, grid.py, studio.sh/.gd
(in-engine renders), decimate.gd (polygon reduction), shipkit.py (inspect/export/repack fleet sheets), shipfix.py,
make_ships.sh, make_booster.py. tools/setup_env.sh. See tools/shipkit/README.md.

## Sky panoramas
tools/sky/fix_pano.py makes any nebula image a seamless 360 sky (seam fold + pole blur + 4096x2048). See tools/sky/README.md.

## Design rules
docs/DESIGN.md is the authoritative design (superseded rules are marked). Read it before changing gameplay.

## Loading / content packs (read docs/PERFORMANCE.md)
Only what is needed to start is in the main download. Mechs, planet terrain and the Lancer are content packs
(scripts/packs.gd, written next to the export by addons/content_packs). New planets, systems and big model sets get
their own pack and are excluded in export_presets.cfg. Measure with tools/perf/measure_web.py and web_route.py,
HL_PROFILE=1 (startup steps and memory), and HL_SOAK=n (memory over round trips).

## Limits learned
- Drive connector downloads only files < 10 MB: ask the owner to attach bigger GLBs in chat.
- Sending files back: max 30 MB each. pip/npm registries may be blocked; everything here needs only numpy + Pillow.
- Tripo auto-rigs mis-weight coats/capes/ponytails and arms near thighs; unrigged mechs are rigged with rig_mech.sh.

## Open items
- Blue mecha (c4d26433…) needs a re-rig from a T-pose/unrigged version.
- Starfield: layered sky wanted (Freelancer style). The owner sends nebula images (clouds only); run them through
  tools/sky/fix_pano.py, then put one per system into the game; star layers to be built in code. First one: a
  red/violet nebula (Sept 30), system not chosen yet.
- Combat stage 2 (owner's spec): light missile ~1,000 cr and heavy ~5,000 cr (needs bigger rewards first), two mine
  sizes, hub equip screen for the three weapon slots. Stage 3: waypoints with distance countdown.
- Planets, next steps: preload the neighbour tile in the background, weather (storms, rain), missions on tiles,
  more landmark art, a moon (1 tile), ground-hugging enemies.
- Mechs, next steps: player-flown mech, more mech types (all rigged mechs in art/characters share the 22-bone rig),
  big-battle test with 30–40 units.
- Human characters (~480k tris) need a rig-preserving reducer before going in-game; no on-foot mode yet.
- Spare portrait set art/portraits/homelancer_operative_* (black/white suit operative) not used yet.

## Version number (owner's scheme)
`Data.VERSION` and the `hl-version` meta in `web_shell.html` carry the beta version, e.g. v1.2x. The letter is the
Chief job letter. After z the number goes up and the letter restarts: v1.2z -> v1.3a. Bump both for every job. The
Hova Matrix landing page (repo hova-matrix) reads the meta from the live game page and shows it on its PLAY TEST BETA
button, so the site always shows the current version without being edited.
