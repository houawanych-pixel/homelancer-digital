# Sky panoramas (nebula backgrounds)

`fix_pano.py` turns any nebula picture into a seamless 360° sky for the game (equirectangular, 2:1).

    python3 tools/sky/fix_pano.py in.png out.jpg --preview check.jpg          # defaults: 4096 wide, --seam 0.09 --pole 0.24

- Seam: matches the colour of the left and right edges, then folds the right strip over the left, so there is no
  line behind the player.
- Poles: rows near the top and bottom are blurred sideways (they are stretched there) and fade to the row's average
  colour, so looking straight up or down shows no pinch.
- `--preview` renders forward / behind (the seam) / up / down, after and before, into one contact sheet. Check it.
- Only numpy, scipy and Pillow. The owner's images: clouds only, no stars (stars are drawn in code).

## Portrait or non-2:1 pictures

    python3 tools/sky/portrait_to_pano.py in.jpg raw.png            # 2048 wide; picture ahead + dimmer echo behind
    python3 tools/sky/fix_pano.py raw.png out.jpg --width 2048 --seam 0.02 --pole 0.12 --preview check.jpg

Then roll the result by half its width if the main cloud should face -Z (toward the gate) and save it as
`assets/sky/<system id>.jpg` (the "sky" pack; lossy import, no mipmaps). 2048 x 1024 costs ~8 MB of GPU memory.
