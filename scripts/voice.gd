class_name Voice
## Voice system, stage 1 (v1.5j): who sounds like what. Playback itself is in the Sfx autoload
## (Sfx.play_character_voice), which asks the providers in order:
##   PRELOADED_AUDIO  a recorded / generated file for that character and line (assets/voices/<id>/<line>.ogg)
##   LIVE_API         off: needs a secure server (never a key in this public client)
##   PHONE_TTS        the device's own text-to-speech, shaped by the character's voice profile (the default today)
## and the radio blips when none of them can speak. The rest of the game only ever calls Sfx (through hud.open_comms).
##
## A voice profile: {character_id, persona_id, preferred_voice, voice_type, pitch, speaking_rate, volume,
##   fallback_voice, effect}. voice_type is "male" | "female" | "machine"; effect is "" | "radio" | "robot" | "alien".
## Values come from Data.VOICE_PERSONAS (by the persona the roster documents give: "male", "female_alien",
## "neutral_machine_echo"...) with Data.VOICE_PROFILES on top for one character. preferred_voice is the device voice
## picked for that character (closest male / female voice the device actually has), remembered in the settings file.

const PROVIDERS := ["PRELOADED_AUDIO", "LIVE_API", "PHONE_TTS"]

## Names device voices commonly carry, to tell a male voice from a female one (browsers give no gender field).
const FEMALE_HINTS := ["female", "woman", "girl", "samantha", "victoria", "karen", "zira", "susan", "hazel", "moira", "tessa", "fiona",
	"serena", "allison", "ava", "kate", "kathy", "vicki", "veena", "joanna", "salli", "kimberly", "ivy", "emma", "amy", "aria", "jenny",
	"libby", "sonia", "natasha", "clara", "sara", "michelle", "heather", "catherine", "linda", "nicole", "olivia", "zoe", "martha", "nora"]
const MALE_HINTS := ["male", " man", "david", "mark", "daniel", "alex", "fred", "george", "james", "tom", "oliver", "aaron", "arthur",
	"bruce", "ralph", "albert", "rishi", "matthew", "joey", "justin", "brian", "guy", "ryan", "eric", "christopher", "william", "thomas",
	"liam", "gordon", "lee", "rocko", "reed", "junior", "grandpa", "evan", "richard", "steffan", "andrew", "roger"]

## "female" | "male" | "" (cannot tell) from a device voice's name.
static func voice_gender(name: String) -> String:
	var n := " " + name.to_lower() + " "
	for h in FEMALE_HINTS:
		if n.find(h) >= 0: return "female"
	for h in MALE_HINTS:
		if n.find(h) >= 0: return "male"
	return ""

## Is this character on the new profile system yet? (Stage 1 rolls out to a few test characters first.)
static func profiled(character_id: String) -> bool:
	return character_id != "" and ("*" in Data.VOICE_PROFILE_ROLLOUT or character_id in Data.VOICE_PROFILE_ROLLOUT)

## What the game knows about a character's voice: [persona_id, sex] from the roster documents or the story cast;
## a generic pilot (not in either) goes by the sex its own entry gives (female_hint).
static func _persona(character_id: String, female_hint := false) -> Array:
	if Data.CHARACTERS.has(character_id):
		var c: Dictionary = Data.CHARACTERS[character_id]
		var persona := str(c.get("voice_persona", "female" if c.get("female", false) else "male"))
		return [persona, "female" if c.get("female", false) else "male"]
	for f in Data.ROSTERS:
		for p in Data.ROSTERS[f]["pilots"]:
			if str(p.get("voice_id", "")) == character_id or str(p.get("character_id", "")) == character_id:
				return [str(p.get("voice_persona", "male")), str(p.get("voice_sex", p.get("sex", "male")))]
	for g in Data.GENERIC_PILOTS:
		if "gp/" + str(g.get("id", "")) == character_id or str(g.get("id", "")) == character_id:
			return ["female" if g.get("female", false) else "male_masked", "female" if g.get("female", false) else "male"]
	return ["female", "female"] if female_hint else ["male", "male"]

## The full profile for one character (device voice not chosen here: see pick_voice).
static func profile(character_id: String, female_hint := false) -> Dictionary:
	var pr: Array = _persona(character_id, female_hint)
	var persona: String = pr[0]
	var base: Dictionary = Data.VOICE_PERSONAS.get(persona, {})
	if base.is_empty():   # an unlisted persona: go by its first word ("female_x" -> "female")
		base = Data.VOICE_PERSONAS.get(persona.split("_")[0], Data.VOICE_PERSONAS["male"])
	var out := {"character_id": character_id, "persona_id": persona, "preferred_voice": "", "fallback_voice": "",
		"voice_type": base.get("voice_type", "female" if pr[1] == "female" else "male"), "pitch": 1.0, "speaking_rate": 1.0, "volume": 80, "effect": ""}
	for k in base: out[k] = base[k]
	var own: Dictionary = Data.VOICE_PROFILES.get(character_id, {})
	for k in own: out[k] = own[k]
	out["pitch"] = clampf(float(out["pitch"]), Data.VOICE_PITCH_RANGE[0], Data.VOICE_PITCH_RANGE[1])
	out["speaking_rate"] = clampf(float(out["speaking_rate"]), Data.VOICE_RATE_RANGE[0], Data.VOICE_RATE_RANGE[1])
	return out

## Choose the device voice for a profile from the voices this device actually has ([{id, name, language}]).
## Returns {voice, fallback, matched}: matched = a voice of the right sex was found; when not, the caller nudges the
## pitch instead (Data.VOICE_SEX_PITCH_NUDGE) so a woman is not read in a man's voice at the same pitch.
static func pick_voice(prof: Dictionary, voices: Array, saved := "") -> Dictionary:
	var en: Array = voices.filter(func(v): return str(v.get("language", "")).to_lower().begins_with("en"))
	if en.is_empty(): en = voices
	if en.is_empty(): return {"voice": "", "fallback": "", "matched": false}
	var want: String = "female" if prof["voice_type"] == "female" else "male"   # machines use the masculine voice family (owner's rule)
	var same: Array = en.filter(func(v): return voice_gender(str(v.get("name", ""))) == want)
	var other: Array = en.filter(func(v): return not (v in same))
	for v in same + en:
		if str(v.get("id", "")) == saved and saved != "": return {"voice": saved, "fallback": str((other[0] if not other.is_empty() else en[0])["id"]), "matched": v in same}
	var pool: Array = same if not same.is_empty() else en
	var pick: Dictionary = pool[absi(hash(str(prof["character_id"]))) % pool.size()]
	var fb: Dictionary = en[0] if en[0] != pick or en.size() == 1 else en[1]
	return {"voice": str(pick["id"]), "fallback": str(fb["id"]), "matched": not same.is_empty()}
