# Sky panoramas (nebula backgrounds)

`fix_pano.py` turns any nebula picture into a seamless 360° sky for the game (equirectangular, 2:1).

    python3 tools/sky/fix_pano.py in.png out.jpg --preview check.jpg          # defaults: 4096 wide, --seam 0.09 --pole 0.24

- Seam: matches the colour of the left and right edges, then folds the right strip over the left, so there is no
  line behind the player.
- Poles: rows near the top and bottom are blurred sideways (they are stretched there) and fade to the row's average
  colour, so looking straight up or down shows no pinch.
- `--preview` renders forward / behind (the seam) / up / down, after and before, into one contact sheet. Check it.
- Only numpy, scipy and Pillow. The owner's images: clouds only, no stars (stars are drawn in code).
