# Fleet roster tokens

`crop_tokens.py <dir with HL_<Faction>Fleet_TopDown_*.png> <out>` cuts each ship off the owner's roster sheets
(black background) into a transparent PNG token, and writes the crop boxes to `fleet_crops.json`. Which piece is
which class is set by hand in `MAP` (read off the sheet captions). No new art: these are the sheet's own pixels.
Game copies (224 px) live in `assets/fleet_tokens/<faction>_<class>.png`; FleetCatalog points at them.
