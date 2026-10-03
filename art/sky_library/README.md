# Sky library (not in the game build yet)

360 skies made from the owner's pictures (3 Oct 2026), one per star system, waiting for those systems to be built.
`source/<system>.jpg` is the picture as sent; `pano/<system>.jpg` is the seamless 2048 x 1024 sky.
To use one: copy `pano/<system>.jpg` to `assets/sky/<system id>.jpg` (the "sky" pack; watch the 3 MB pack budget).

Made with: `portrait_to_pano.py src raw.png --lon 112 --lat 150 --bg auto` then
`fix_pano.py raw.png out.jpg --width 2048 --seam 0.02 --pole 0.16`. The picture is kept away from straight up and
straight down (no pinch at the poles) and the background is set to the picture's own edge brightness (`--bg auto`).

The assignments are a first guess by faction colour and theme. The owner corrects them.
All 64 tiles have a sky: the 58 named systems and the 6 unnamed tiles (`void_1` .. `void_6`). 13 spare skies wait in `spare_01` .. `spare_13`.

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
| Orion | Korrath | red fire on dark teal |
| Unnamed tile | void_1 | dark, an edge-on galaxy far off |
| Unnamed tile | void_2 | dark teal, a faint rust core |
| Unnamed tile | void_3 | dim red on navy |
| Unnamed tile | void_4 | dark navy, a low orange glow |
| Unnamed tile | void_5 | black with a thin gold streak |
| Unnamed tile | void_6 | dark teal, a red cloud |

**Void systems (owner, 3 Oct 2026):** some systems are void systems: a small sun, no life, too cold to live in.
The six unnamed tiles are treated as these until the owner says otherwise; they got the darkest, coldest pictures.

Spares (not assigned): spare_01 orange dust lane; spare_02 blue and purple ridge; spare_03 pure blue (good Unity
swap); spare_04 red cloud, blue heart; spare_05 blue-white flare (good Unity swap); spare_06 red and blue (small
picture); spare_07 orange and blue; spare_08 rose spiral; spare_09 orange web on blue; spare_10 pink galaxy (small
picture); spare_11 blue and gold swirl; spare_12 teal and brown clouds; spare_13 gold and blue star field.

More spares (batch 5): spare_14 teal and coral star river; spare_15 teal and amber with dark veins; spare_16 navy with gold and cyan swirls; spare_17 blue heart, rust pillars; spare_18 violet swirl over dark clouds; spare_19 orange fire and blue; spare_20 violet and amber, bright core; spare_21 purple over peach; spare_22 orange and blue ridges; spare_23 purple heart, gold halo; spare_24 amber cloud over navy; spare_25 rust and grey dust; spare_26 gold, rust and violet; spare_27 dark teal and gold; spare_28 orange, pink and violet blaze; spare_29 orange shell, blue core; spare_30 amber pillars; spare_31 teal and amber, dark pillar.
Left out of batch 5: one picture already used (Velanthos) and one with a stock-site watermark across the middle.

More spares (batch 6): spare_32 orange fire on teal; spare_33 orange and magenta, bright core; spare_34 gold and red clouds with painted planets; spare_35 blue, pink and amber bubble; spare_36 red and blue flower burst; spare_37 green-gold eye; spare_38 violet and blue ridge; spare_39 orange shell, blue heart; spare_40 magenta ring, gold spiral; spare_41 crimson and indigo clouds; spare_42 teal, orange and purple swirl; spare_43 navy, teal and red clouds; spare_44 amber and blue heart, dark; spare_45 dark blue with an amber burst; spare_46 rose and blue with a galaxy (small picture); spare_47 rose and blue spiral (small picture); spare_48 amber, magenta and teal; spare_49 amber and violet clouds (small picture); spare_50 blue and orange spiral; spare_51 red-pink over blue.

**Realms (off the grid, first guess):** realm_hova gold and orange light with teal; realm_sai soft gold on deep green;
realm_coola cold blue heart with orange threads; realm_johnvex red and teal spiral with dark veins.

More spares (batch 7): spare_52 gold cloud tower on teal; spare_53 rust-red cloud, blue star; spare_54 red, orange and magenta.

Dropped as duplicates: 3 pictures (two were the Solara and Vega skies already in the game, one was sent twice).
Two pictures carried a watermark (Omega, Voidtex); the strip was cut off. Check picture rights before the game is sold.
