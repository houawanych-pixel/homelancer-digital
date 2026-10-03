# Sky library (not in the game build yet)

360 skies made from the owner's pictures (3 Oct 2026), one per star system, waiting for those systems to be built.
`source/<system>.jpg` is the picture as sent; `pano/<system>.jpg` is the seamless 2048 x 1024 sky.
To use one: copy `pano/<system>.jpg` to `assets/sky/<system id>.jpg` (the "sky" pack; watch the 3 MB pack budget).

Made with: `portrait_to_pano.py src raw.png --lon 112 --lat 150 --bg auto` then
`fix_pano.py raw.png out.jpg --width 2048 --seam 0.02 --pole 0.16`. The picture is kept away from straight up and
straight down (no pinch at the poles) and the background is set to the picture's own edge brightness (`--bg auto`).

The assignments are a first guess by faction colour and theme. The owner corrects them.
57 of the 58 named systems have a sky. Missing: Korrath (Orion) and the 6 unnamed tiles.

| Faction | System | Sky |
|---|---|---|
| Elyza (royal blue + silver) | Aurelion (capital) | deep blue and violet cloud |
| Elyza | Crystara | bright blue and pink, many stars |
| Elyza | Selenvar | blue and purple halves, two crescent moons |
| Elyza | Velanthos | blue wisps, gold stars |
| Elyza | Zillance Major | indigo and violet pillars |
| Unity (white + cyan) | Veranthos (capital) | blue heart with a bright white star, rose cloud |
| Unity | Keldrix | pale lavender and teal, white core |
| Unity | Aurentum | blue, purple and pink with a white core |
| Unity | Federis | blue with a pink and gold streak |
| Solarion (gold + orange) | Synthari Capital | gold and orange pillar on navy |
| Solarion | Nexarion | navy, teal and gold |
| Solarion | Kellova | pink, yellow and green pastel |
| Solarion | Techanis | red and orange with blue light |
| Solarion | Crossma Major | orange cloud on a purple star field |
| Imperium (crimson + gunmetal) | Malachar (capital) | red, black and white |
| Imperium | Shadenvex | dark violet with a pink flare |
| Imperium | Vorreth | crimson and violet threads |
| Imperium | Obsidrath | red and orange fire |
| Imperium | Empire Major | dense rose-pink cloud |
| Covenant (purple + gold) | Sepheron (capital) | gold and purple |
| Covenant | Valdris | gold and violet |
| Covenant | Sanctum Major | purple, blue and amber |
| Orion (emerald + silver-white) | Dreadholm (capital) | green with a pink-white core |
| Orion | Ironvast | green star river |
| Orion | Battlespire | green and magenta band |
| Orion | Vortegan | green, blue and purple |
| Orion | Omicron Major | bright green cloud |
| Savagers (burnt orange + charcoal) | Raptian Major (capital) | orange and magenta fire |
| Savagers | Scavaris | dark, rust pillars and teal |
| Savagers | Plundros | teal ring, rust cloud, a small planet |
| Savagers | Derelicta | dark navy with an ember core |
| Savagers | Ravage Major | orange cloud around a blue bubble |
| Liberator (teal + white) | Vantara (capital) | teal with orange cloud |
| Liberator | Exodus Point | teal and pink swirl |
| Liberator | Republic Major | teal and pink spiral |
| Liberator | Kiral | teal and violet star river |
| Enemy | Void System (Solrath, blood red) | red on black |
| Enemy | Cynthara (Gadversee, toxic green) | neon green, yellow and pink ring |
| Enemy | Kronos (Arctides, ice blue) | dark ice-grey cloud, ember core |
| Enemy | Cybernet (Cybermorphs, neon magenta) | pure magenta |
| Enemy | Noctyra (Phenom, violet) | dark violet web |
| Enemy | Genesis (Kaijurai, radioactive yellow) | yellow and red on black |
| Hidden | Shadow | dark indigo and magenta |
| Hidden | Radiant | rainbow gold and purple |
| Neutral | Shroud | soft pink glow |
| Neutral | Nebulax | pink ring with a blue eye |
| Neutral | Nullpoint | eye with a black pupil |
| Neutral | Vexara | bright pink and teal |
| Neutral | Farreach Outpost | vivid pink and blue |
| Neutral | Rimgate | pink ring around a blue centre |
| Neutral | Voidtex | black hole with blue spirals |
| Neutral | Beta-7 | rainbow bubble |
| Neutral | Perimeter | purple and teal ribbon |
| Neutral | Sigma-19 | purple glow |
| Neutral | Omega | pink and gold eye with a blue star |
| Neutral | Foggiest | pink and blue spiral |
| Neutral | Ogden | purple and orange |

Dropped as duplicates: 3 pictures (two were the Solara and Vega skies already in the game, one was sent twice).
Two pictures carried a watermark (Omega, Voidtex); the strip was cut off. Check picture rights before the game is sold.
