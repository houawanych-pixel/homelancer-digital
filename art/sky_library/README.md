# Sky library (not in the game build yet)

360 skies made from the owner's pictures (3 Oct 2026), one per star system, waiting for those systems to be built.
`source/<system>.jpg` is the picture as sent; `pano/<system>.jpg` is the seamless 2048 x 1024 sky.
To use one: copy `pano/<system>.jpg` to `assets/sky/<system id>.jpg` (the "sky" pack; watch the 3 MB pack budget).

Made with: `portrait_to_pano.py src raw.png --lon 112 --lat 150` then `fix_pano.py raw.png out.jpg --width 2048 --seam 0.02 --pole 0.16`
(the picture is kept away from straight up and straight down, so there is no pinch at the poles).

The assignments are a first guess by faction colour and theme. The owner corrects them.

| System | Faction / role | Sky |
|---|---|---|
| Aurelion | Elyza capital (royal blue + silver) | deep blue and violet cloud |
| Crystara | Elyza, crystal worlds | bright blue and pink, many stars |
| Selenvar | Elyza, moonlit worlds | blue and purple halves, two crescent moons |
| Velanthos | Elyza, ocean world | blue wisps, gold stars |
| Vantara | Liberator capital (teal + white) | teal with orange cloud |
| Exodus Point | Liberator | teal and pink swirl |
| Republic Major | Liberator | teal and pink spiral |
| Kiral | Liberator, harsh frontier | teal and violet star river |
| Sepheron | Covenant capital (purple + gold) | gold and purple, strongest one |
| Valdris | Covenant | gold and violet |
| Sanctum Major | Covenant, light nebula | purple, blue and amber |
| Raptian Major | Savagers capital (burnt orange) | orange and magenta fire |
| Cybernet | Enemy: Cybermorphs (black + neon magenta) | pure magenta |
| Noctyra | Enemy: Phenom (black + violet) | dark violet web |
| Kronos | Enemy: Arctides (black + ice blue) | dark ice-grey cloud, ember core |
| Shadow | Hidden, spooky | dark indigo and magenta |
| Radiant | Hidden, the beautiful system | rainbow gold and purple |
| Nebulax | Neutral, dense nebula | pink ring with a blue eye |
| Shroud | Neutral, veiled world | soft pink glow |

One picture came twice (the dark ice-grey one); it is used once, for Kronos.
Not yet covered: 39 named systems and the 6 unnamed tiles.
