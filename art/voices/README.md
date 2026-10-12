# Character voice samples

Source clips for cloned character voices. Not part of the game build (art/ has .gdignore).
Each folder: `<Name>.mp4` (talking clip made by the owner in Grok) and `<Name> voice.mp3` (its sound).

Plan (owner, 2026-10-12): characters read pre-written scripts; no AI brain.
Lines are cloned and pre-recorded to audio files ahead of time, then played in game.

## Voice pool (11)
| Voice | Sample character | Sound |
|---|---|---|
| M1 | Kael Varis (Covenant) | deep, calm leader |
| M2 | Ryan Solace (Orion) | young, eager |
| M3 | Garrik Rend (Imperium) | rough, gravelly |
| M4 | Admiral Caleb Rynn (Orion) | older man |
| F1 | Selene Ward (Unity) | confident, sharp |
| F2 | Mira Dane (Unity) | young, bright |
| F3 | Kai Mori (Liberator) | cool, low |
| F4 | Cmdr. Vale (Crew) | mature woman, warm but firm |
| A1 | Korvax (Orion) | alien male, raspy |
| A2 | Syra N'Tel (Orion) | alien female, melodic |
| R1 | PRIME-NEXUS (Cybermorph) | robot |

Rules: all masked soldiers (slots 01 and 05) share one voice; all Cybermorph share the robot voice.
PRIME-NEXUS: clone from `PRIME-NEXUS original voice (for cloning).mp3`, then apply the robot effect
(three stacked layers: spectral robot, pitch x0.75, pitch x1.12 quiet; 45 Hz pulse; bass boost; echo).
The MP4 and `PRIME-NEXUS voice.mp3` already carry that effect.

## Who uses which voice (for now)
`voice_map.csv` gives every character one of the 11 voices, mixed so that teammates sound different.
MASK = the shared masked-soldier voice: M3 (Garrik Rend) with a helmet-radio filter.
"own voice" = the character the sample was made from. Others borrow a voice until the owner
makes their own talking clip; the plan is to keep each character's talking face for their lines.
