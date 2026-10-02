class_name Brain
extends RefCounted
## NPC chat brain (no AI model): reads what the pilot typed, works out the intent, checks who is being spoken to
## (persona), how they feel about the pilot (memory) and what is going on (context), and answers in that voice.
##
## Three parts, kept apart on purpose so a real language model can replace the middle one later:
##   1. PERSONAS  - who each character is (also the text a model would be given as its role)
##   2. memory    - GS.memory[id]: what this character remembers about the pilot this session
##   3. responder - turns (persona, memory, context, text) into a line. Default: the rule engine below.
##      Set `Brain.responder` to another Callable (e.g. one that calls a relay server) to swap it;
##      `payload()` is exactly what such a responder should send.
## Works offline on any phone. Nothing here needs a network or an API key.

## fn(id, text, ctx, done: Callable) -> void ; must call done.call(line) once. Invalid = use the rule engine.
static var responder: Callable = Callable()

# ---------------------------------------------------------------- personas
## kind: which reply set they use. temper 0..1 (how fast they anger), greed 0..1, warmth 0..1.
const PERSONAS := {
	"vale": {"kind": "control", "temper": 0.2, "greed": 0.1, "warmth": 0.7, "home": "Liberty Hub",
		"about": "Commander Vale runs Liberty Hub traffic control in Solara. Calm, dry, protective of her pilots. Unity officer.",
		"knows": ["station", "gate", "belt", "nebula", "planet", "raiders", "work"]},
	"oduya": {"kind": "control", "temper": 0.15, "greed": 0.1, "warmth": 0.9, "home": "Port Meridian",
		"about": "Port Master Oduya runs the landing field at Port Meridian on New Terra. Warm, practical, proud of her colony.",
		"knows": ["planet", "station", "raiders", "work"]},
	"amari": {"kind": "control", "temper": 0.35, "greed": 0.5, "warmth": 0.5, "home": "Frontier Exchange",
		"about": "Chief Amari runs the Frontier Exchange in Vega. A trader first: friendly while there is profit in it.",
		"knows": ["station", "gate", "belt", "corsairs", "work"]},
	"rennick": {"kind": "hauler", "temper": 0.3, "greed": 0.6, "warmth": 0.6, "home": "the Bright Margin",
		"about": "Captain Rennick flies the cargo hauler Bright Margin. Tired, honest, worried about raiders, always looking for escorts.",
		"knows": ["gate", "belt", "raiders", "work", "station"]},
	"voss": {"kind": "raider", "temper": 0.8, "greed": 0.5, "warmth": 0.05, "home": "the Solara Belt",
		"about": "Shade is Hoard's lieutenant and leads the raiders in Solara. Cold, patient, vengeful. Never begs, never jokes kindly.",
		"knows": ["belt", "nebula", "raiders"]},
	"kessler": {"kind": "warlord", "temper": 0.6, "greed": 0.9, "warmth": 0.0, "home": "the Vega ice field",
		"about": "Hoard is the corsair warlord of Vega. Grand, greedy, speaks of prices and grudges. Everything has a price, including mercy.",
		"knows": ["belt", "corsairs", "gate"]},
}

# ---------------------------------------------------------------- understanding what was typed
const INTENTS := {   # intent -> words/phrases that point to it (checked in this order; most hits wins)
	"threat": ["kill you", "destroy you", "i'll end", "ill end", "you're dead", "youre dead", "coming for you", "hunt you", "blow you", "die", "finish you"],
	"insult": ["coward", "scum", "idiot", "stupid", "trash", "pathetic", "weak", "ugly", "loser", "shut up", "dog"],
	"surrender": ["surrender", "mercy", "spare me", "don't shoot", "dont shoot", "i give up", "stand down", "let me go", "truce", "peace"],
	"bribe": ["pay you", "bribe", "credits for", "i'll pay", "ill pay", "how much", "name your price", "tribute", "ransom", "buy my way"],
	"apology": ["sorry", "apolog", "my mistake", "forgive"],
	"help": ["help", "assist", "backup", "back up", "mayday", "under attack", "need support", "save me", "cover me"],
	"work": ["work", "job", "mission", "contract", "bounty", "escort", "hire", "earn"],
	"trade": ["buy", "sell", "price", "trade", "cargo", "shop", "weapon", "missile", "upgrade", "repair"],
	"place": ["where", "how do i get", "how far", "which way", "direction", "location", "find the", "route to", "way to"],
	"who": ["who are you", "your name", "what are you", "tell me about you", "who is this"],
	"status": ["status", "report", "what's happening", "whats happening", "situation", "any hostiles", "all clear", "news"],
	"thanks": ["thank", "thanks", "appreciate", "good work", "well done", "nice"],
	"bye": ["bye", "goodbye", "signing off", "out.", "later", "farewell", "over and out"],
	"greet": ["hello", "hi ", "hey", "greetings", "good morning", "good evening", "come in", "do you read", "you there"],
}
const TOPICS := {   # topic -> words that name it
	"station": ["station", "hub", "liberty", "exchange", "dock"],
	"gate": ["gate", "warp", "jump", "vega", "solara", "aquila"],
	"belt": ["belt", "asteroid", "rocks", "ice field", "mining"],
	"nebula": ["nebula", "violet", "cloud", "gas"],
	"planet": ["planet", "new terra", "terra", "meridian", "surface", "land", "city", "capital"],
	"raiders": ["raider", "shade", "pirate", "jackal", "wraith"],
	"corsairs": ["corsair", "hoard", "warlord", "revenant", "banshee"],
}

## What the pilot means. Returns {"intent": String, "topic": String}.
static func understand(text: String) -> Dictionary:
	var t := " " + text.to_lower().strip_edges() + " "
	var best := "unknown"
	var best_n := 0
	for intent: String in INTENTS:
		var n := 0
		for w: String in INTENTS[intent]:
			if t.find(w) >= 0: n += 1
		if n > best_n:
			best_n = n
			best = intent
	var topic := ""
	for tp: String in TOPICS:
		for w: String in TOPICS[tp]:
			if t.find(w) >= 0:
				topic = tp
				break
		if topic != "": break
	if best == "unknown":
		if topic != "": best = "place"
		elif t.strip_edges().ends_with("?"): best = "question"
	return {"intent": best, "topic": topic}

# ---------------------------------------------------------------- memory
## What `id` remembers about the pilot: talks, trust (-1..1), insults, threats, last intent, paid (credits).
static func memory(id: String) -> Dictionary:
	if not GS.memory.has(id):
		var hostile: bool = GS.mood.get(id, "friendly") == "enraged"
		GS.memory[id] = {"talks": 0, "trust": -0.6 if hostile else 0.3, "insults": 0, "threats": 0, "last": "", "paid": 0}
	return GS.memory[id]

static func _remember(id: String, intent: String) -> void:
	var m := memory(id)
	var p: Dictionary = PERSONAS.get(id, {})
	var temper := float(p.get("temper", 0.4))
	m["talks"] = int(m["talks"]) + 1
	m["last"] = intent
	match intent:
		"insult":
			m["insults"] = int(m["insults"]) + 1
			m["trust"] = float(m["trust"]) - 0.15 - 0.25 * temper
		"threat":
			m["threats"] = int(m["threats"]) + 1
			m["trust"] = float(m["trust"]) - 0.2 - 0.3 * temper
		"thanks", "apology": m["trust"] = float(m["trust"]) + 0.12
		"greet", "help", "work", "trade": m["trust"] = float(m["trust"]) + 0.03
	m["trust"] = clampf(float(m["trust"]), -1.0, 1.0)

## How they feel right now: "warm", "cool" or "cold".
static func feeling(id: String) -> String:
	var tr := float(memory(id)["trust"])
	return "warm" if tr >= 0.25 else ("cool" if tr >= -0.25 else "cold")

# ---------------------------------------------------------------- what they know
const FACTS := {
	"station": {"solara": "Liberty Hub sits near the centre of Solara. Dock there for repairs, weapons and ships.",
		"vega": "The Frontier Exchange is the only friendly dock in Vega. Repairs and trade."},
	"gate": {"solara": "The Aquila Warp Gate is far out past the Violet Reach. It jumps to Vega.",
		"vega": "The gate back to Solara is behind you, the way you came in."},
	"belt": {"solara": "The Solara Belt is port side of the Hub lane. Raiders hide in the rocks.",
		"vega": "The ice field is corsair ground. Go in armed or not at all."},
	"nebula": {"solara": "The Violet Reach is the purple cloud before the gate. Sensors go short in there.",
		"vega": "No nebula worth the name out here. Just ice and corsairs."},
	"planet": {"solara": "New Terra is the green world past the Hub. Land at Port Meridian. The capital block is north-west of it.",
		"vega": "Nothing to land on in Vega that would have you."},
	"raiders": {"solara": "Raiders answer to Shade here, and Shade answers to Hoard. They work the belt and the gate approach.",
		"vega": "Raiders are Solara's problem. Out here it is corsairs."},
	"corsairs": {"solara": "Corsairs are Vega's trouble. Their warlord is Hoard.",
		"vega": "Corsairs own the ice field. Hoard runs them and puts prices on ships that cross him."},
	"work": {"solara": "Clear raiders off the lanes and the Hub pays per kill. Haulers want escorts on the Vega run.",
		"vega": "Bring back what the corsairs take and the Exchange pays for it."},
}

# ---------------------------------------------------------------- replies (rule engine)
## kind -> intent -> lines. {home} {sys} {kills} {fact} {n} are filled in. A leading [tag] is the face/voice mood.
const LINES := {
	"control": {
		"greet": ["[smile]{home} reads you, pilot. Go ahead.", "[normal]Receiving you clear. What do you need?"],
		"greet_again": ["[smile]You again. Good. I like pilots who check in.", "[normal]Still here, still listening."],
		"help": ["[serious]{n} hostile{s} on your scope. Break toward {home}, our guns will cover you.", "[serious]Hold on. Keep them off your tail and come to us."],
		"help_clear": ["[normal]Scope is clear around you. Breathe. If your hull is low, dock for repairs.", "[smile]Nothing on you right now. You are doing fine."],
		"work": ["[serious]{fact}", "[normal]There is always work. {fact}"],
		"trade": ["[normal]Dock at {home} and the outfitters will see to you. Repairs first, then guns.", "[smile]We sell it if you can pay for it. Dock and look."],
		"place": ["[normal]{fact}", "[serious]{fact} Mark it on your map: tap the radar."],
		"place_unknown": ["[normal]Not my sector, pilot. Tap the radar and check your map.", "[normal]I cannot help you with that one. Try the map."],
		"who": ["[smile]{about_short}", "[normal]{about_short} And you are the pilot with {kills} kills on the board."],
		"status": ["[serious]{n} hostile{s} near you. Stay sharp.", "[normal]Quiet for now. {sys} never stays quiet."],
		"thanks": ["[smile]Just fly it home in one piece.", "[smile]That is what we are here for."],
		"apology": ["[normal]Noted. Keep it clean out there.", "[smile]Forgotten. Carry on."],
		"insult": ["[serious]Watch your tone on an open channel, pilot.", "[serious]I will put that down to a long patrol."],
		"insult_cold": ["[angry]One more like that and you can find another dock.", "[serious]This channel is for traffic. You are not traffic. Out."],
		"threat": ["[serious]Threatening Unity control is a fast way to lose docking rights.", "[angry]Say that again and the turrets hear it too."],
		"surrender": ["[normal]You have nothing to surrender to us. Dock and stand easy.", "[smile]We are on your side, pilot."],
		"bribe": ["[serious]Keep your credits. Spend them on shields.", "[normal]We do not work that way here."],
		"bye": ["[smile]{home} out. Fly safe.", "[normal]Channel closed. Good hunting."],
		"question": ["[normal]Say again, plainer. Ask me about the station, the gate, the belt, work, or hostiles.", "[normal]I can tell you where things are, what pays, and what is hunting you. Which?"],
		"unknown": ["[normal]Copy. Anything you need from {home}?", "[normal]Understood, pilot.", "[smile]Logged. Keep talking, it gets lonely up here."],
	},
	"hauler": {
		"greet": ["[smile]Rennick here. Good to hear a friendly voice.", "[normal]Bright Margin reads you."],
		"greet_again": ["[smile]Back on my channel. You must want an escort job.", "[normal]Still hauling. Still nervous."],
		"help": ["[sad]I haul cargo, friend. I have one turret and a prayer. Run for the Hub.", "[serious]{n} on you? I would only be another target. Get to the station."],
		"help_clear": ["[normal]Nobody on you that I can see. Lucky.", "[smile]Clear skies. Enjoy it while it lasts."],
		"work": ["[smile]Escort me on the Vega run and I split the margin. Raiders have been bold.", "[serious]{fact}"],
		"trade": ["[normal]I carry freight, not a shop. The Hub sells what you want.", "[smile]If it fits in a crate I have moved it. Buying is at the station."],
		"place": ["[normal]{fact}", "[serious]I have flown it a hundred times. {fact}"],
		"place_unknown": ["[normal]Never hauled there. Could not tell you.", "[normal]Off my routes. Check the map."],
		"who": ["[smile]{about_short}", "[normal]Captain of the Bright Margin. Twenty years of freight and not one medal."],
		"status": ["[serious]{n} hostile{s} out there. I am keeping my head down.", "[normal]Quiet lane today. Makes me nervous."],
		"thanks": ["[smile]Any time. You keep them off me, I keep you in credits.", "[smile]Appreciated, pilot."],
		"apology": ["[normal]Forget it. Long days out here for everyone.", "[smile]No harm."],
		"insult": ["[sad]I have been called worse by customs.", "[serious]Easy. I am not the one shooting at you."],
		"insult_cold": ["[angry]Find your own escort work then.", "[serious]We are done talking."],
		"threat": ["[sad]You would shoot a freighter? Then you are no better than the raiders.", "[serious]I am logging that with the Hub."],
		"surrender": ["[normal]Surrender to me? I am a cargo hauler.", "[smile]You have the wrong ship, friend."],
		"bribe": ["[smile]I take pay for freight, not favours. But I like how you think.", "[normal]Save it for the outfitters."],
		"bye": ["[smile]Safe lanes, pilot.", "[normal]Bright Margin out."],
		"question": ["[normal]Ask me about the lanes, the gate or escort work. That is what I know.", "[normal]Say that simpler?"],
		"unknown": ["[normal]Copy that.", "[smile]If you say so.", "[normal]Hm. Keep your scanner on."],
	},
	"raider": {
		"greet": ["[serious]You have my channel. You should not.", "[smile]The cadet calls. Brave, or bored."],
		"greet_again": ["[serious]Again. You are making this easy to trace.", "[smile]You keep calling. I keep listening for your engine."],
		"help": ["[smile]Help? I am the reason you need it.", "[serious]Nobody is coming for you out here."],
		"help_clear": ["[smile]No one near you. Yet.", "[serious]Enjoy the quiet. I arranged it. I can end it."],
		"work": ["[smile]Work for us? Bring me a Unity hull and we will talk.", "[serious]Hoard does not hire strays."],
		"trade": ["[serious]We do not trade. We take.", "[smile]Your cargo is already ours. You are only carrying it for now."],
		"place": ["[smile]You want directions from me. Come into the belt. I will show you.", "[serious]{fact_taunt}"],
		"place_unknown": ["[serious]Find it yourself.", "[smile]Lost already?"],
		"who": ["[serious]Shade. Remember it. You will hear it again.", "[smile]{about_short}"],
		"status": ["[smile]{kills} of ours dead by your guns. I am counting.", "[serious]My wing is closer than your scope says."],
		"thanks": ["[serious]Do not thank me. It unsettles the crew.", "[smile]Strange thing to say to me."],
		"apology": ["[serious]Sorry does not rebuild a ship.", "[smile]Say it again when I am standing over your wreck."],
		"apology_warm": ["[serious]...Noted. It changes nothing in the belt.", "[normal]Words. But I heard them."],
		"insult": ["[angry]Keep talking. It helps me find you.", "[smile]Is that all? My wingmate hit harder, before you killed them."],
		"insult_cold": ["[angry]I am done listening. Watch your six.", "[angry]Every word costs you a wing."],
		"threat": ["[smile]Good. Come to the belt and try.", "[angry]You threatened me on an open channel. Every raider heard it."],
		"surrender": ["[smile]Mercy is Hoard's to sell, not mine. Bring credits.", "[serious]Power down and drift. Then we will see."],
		"bribe": ["[smile]Now you speak our language. Take it to Hoard. He sets the price.", "[serious]Credits do not bring back my wing. But they are a start."],
		"bye": ["[serious]Run along.", "[smile]Until the belt, cadet."],
		"question": ["[serious]I do not answer questions. I ask them.", "[smile]Wrong channel for curiosity."],
		"unknown": ["[serious]Noise.", "[smile]Keep transmitting. Please.", "[serious]Say something worth the signal."],
	},
	"warlord": {
		"greet": ["[smile]A Unity pilot greets Hoard. How polite the dead can be.", "[serious]You have reached the one who prices your ship."],
		"greet_again": ["[smile]Back again. Come to haggle?", "[serious]You return. Good. Debts like company."],
		"help": ["[smile]Help has a price. Everything has.", "[serious]Hoard helps what Hoard owns."],
		"help_clear": ["[smile]Nothing hunts you this minute. That, too, I can sell.", "[serious]Quiet is a favour. Favours are owed."],
		"work": ["[smile]Bring me a hauler's manifest and you may keep your hull.", "[serious]My work is for corsairs. Are you one?"],
		"trade": ["[smile]I sell one thing to outsiders: passage. It is not cheap.", "[serious]Cargo, ships, pilots. All have a price in Vega."],
		"place": ["[serious]{fact_taunt}", "[smile]Vega is mine. Ask where you may fly, not where things are."],
		"place_unknown": ["[serious]Not mine. Not my concern.", "[smile]Beyond Vega I do not care."],
		"who": ["[serious]I am Hoard. Vega pays me so it may keep breathing.", "[smile]{about_short}"],
		"status": ["[serious]{kills} kills. I have the list. Each has a price on your ship.", "[smile]The ice field is full and patient."],
		"thanks": ["[smile]Gratitude. I accept it at market rate.", "[serious]Thank me with tribute."],
		"apology": ["[serious]Some secrets should never die. Neither should grudges.", "[smile]Apology noted. The price stands."],
		"apology_warm": ["[serious]Hm. You bend. That is worth something.", "[smile]Better. Now bring credits with the words."],
		"insult": ["[angry]The price on your ship just went up.", "[smile]Insults are free. Passage is not. You will want passage."],
		"insult_cold": ["[angry]Enough. Vega will be your grave.", "[angry]I am finished pricing you. Now I am only hunting."],
		"threat": ["[smile]Run back through your gate while you still can.", "[angry]Threats, in my space. My crews heard that."],
		"surrender": ["[smile]Mercy is for sale. Say the word tribute and bring credits.", "[serious]Power down, pay, and you may leave with your ship."],
		"bribe": ["[smile]Now we understand each other. {tribute} credits and my crews look away, for a while.", "[serious]{tribute} credits. That buys a quiet hour, not forgiveness."],
		"bye": ["[serious]Go. The debt goes with you.", "[smile]Until you are worth collecting."],
		"question": ["[serious]Ask plainly or pay for my patience.", "[smile]Hoard answers questions with prices."],
		"unknown": ["[serious]Speak of credits or do not speak.", "[smile]Mm.", "[serious]Words. I deal in ships."],
	},
}
const TRIBUTE := 300

## Everything a responder needs. This is also what would be sent to a language model through a relay.
static func payload(id: String, text: String, ctx: Dictionary) -> Dictionary:
	var c: Dictionary = Data.CHARACTERS.get(id, {})
	var p: Dictionary = PERSONAS.get(id, {})
	return {"character": id, "name": c.get("name", id), "role": c.get("role", ""), "persona": p.get("about", ""),
		"knows": p.get("knows", []), "mood": GS.mood.get(id, "friendly"), "memory": memory(id).duplicate(), "feeling": feeling(id),
		"context": ctx, "pilot_said": text,
		"rules": "Answer in one or two short radio lines, in character. Start with a mood tag: [smile] [normal] [serious] [angry] [sad]."}

## Ask `id` something. `done` gets the reply line (with its mood tag). Always answers, even offline.
static func ask(id: String, text: String, ctx: Dictionary, done: Callable) -> void:
	var u := understand(text)
	_remember(id, u["intent"])
	if responder.is_valid():
		responder.call(id, text, ctx, done)
		return
	done.call(reply(id, text, ctx, u))

## The rule engine: pick the line this character would say.
static func reply(id: String, _text: String, ctx: Dictionary, u := {}) -> String:
	if u.is_empty(): u = understand(_text)
	var p: Dictionary = PERSONAS.get(id, PERSONAS["vale"])
	var set: Dictionary = LINES[p["kind"]]
	var m := memory(id)
	var intent: String = u["intent"]
	var topic: String = u["topic"]
	var sys: String = ctx.get("system", GS.system_id)
	var n := int(ctx.get("hostiles", 0))
	var key := intent
	var fact := ""
	match intent:
		"greet":
			if int(m["talks"]) > 2: key = "greet_again"
		"help", "status":
			if n == 0 and intent == "help": key = "help_clear"
		"insult":
			if feeling(id) == "cold" and int(m["insults"]) > 1: key = "insult_cold"
		"apology":
			if set.has("apology_warm") and int(m["talks"]) > 3: key = "apology_warm"
		"place", "work":
			if intent == "work" and topic == "": topic = "work"
			if topic != "" and topic in (p["knows"] as Array) and FACTS.has(topic):
				fact = FACTS[topic].get(sys, FACTS[topic].values()[0])
			elif intent == "place":
				key = "place_unknown"
	if not set.has(key): key = "unknown"
	var pool: Array = set[key]
	var line: String = pool[(int(m["talks"]) + text_hash(_text)) % pool.size()]
	if intent == "status" and p["kind"] in ["control", "hauler"]: line = pool[0 if n > 0 else 1]
	if fact == "" and line.find("{fact}") >= 0: line = (set["unknown"] as Array)[0]
	var about: String = p["about"]
	line = line.format({"home": p["home"], "sys": str(Data.SYSTEMS.get(sys, {}).get("name", sys)), "kills": GS.kills, "fact": fact,
		"fact_taunt": ("%s Come and see." % fact) if fact != "" else "Find it yourself.",
		"n": n, "s": "" if n == 1 else "s", "about_short": about.split(". ")[0] + ".", "tribute": TRIBUTE})
	return line

static func text_hash(t: String) -> int: return absi(t.hash()) % 97
