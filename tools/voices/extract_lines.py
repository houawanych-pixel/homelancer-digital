#!/usr/bin/env python3
"""Extract every fixed radio line Homelancer speaks through Sfx, with the voice_id and clip key the game uses.

Read-only on the repo. Writes lines.json next to this script.
  lines:   one entry per (voice_id, spoken text). kind = "literal" (text is a literal in the source) or
           "resolved" (a template whose placeholders are constants for that speaker, so the text is still fixed).
  dynamic: lines that carry runtime values (counts, credits, system names, typed-text facts...), with a note.
  speakers: every voice_id that can speak, with display name and group.
"""
import json, os, re, sys
from collections import Counter, OrderedDict

REPO = sys.argv[1] if len(sys.argv) > 1 else "/home/claude/homelancer-digital"
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "lines.json")


# ------------------------------------------------------------------ a tiny GDScript literal parser
class S(str):
    """A string literal that remembers file:line."""
    src = ""


def _tokens(text, fname, start_line):
    i, line, n = 0, start_line, len(text)
    while i < n:
        c = text[i]
        if c == "\n":
            line += 1; i += 1; continue
        if c in " \t\r":
            i += 1; continue
        if c == "#":
            while i < n and text[i] != "\n": i += 1
            continue
        if c == '"':
            j, buf = i + 1, []
            while text[j] != '"':
                if text[j] == "\\":
                    nx = text[j + 1]
                    buf.append({"n": "\n", "t": "\t", '"': '"', "\\": "\\", "'": "'"}.get(nx, nx)); j += 2
                else:
                    buf.append(text[j]); j += 1
            s = S("".join(buf)); s.src = "%s:%d" % (fname, line)
            yield ("str", s); i = j + 1; continue
        if c in "{}[](),:":
            yield (c, c); i += 1; continue
        m = re.match(r"-?\d+(\.\d+)?", text[i:])
        if m:
            v = m.group(0); yield ("num", float(v) if "." in v else int(v)); i += len(v); continue
        m = re.match(r"[A-Za-z_][A-Za-z_0-9.]*", text[i:])
        if m:
            yield ("id", m.group(0)); i += len(m.group(0)); continue
        yield ("op", c); i += 1


class P:
    def __init__(self, toks): self.t = list(toks); self.k = 0
    def peek(self): return self.t[self.k][0]
    def nxt(self): v = self.t[self.k]; self.k += 1; return v
    def value(self):
        kind, v = self.nxt()
        if kind == "{":
            d = OrderedDict()
            while self.peek() != "}":
                key = self.value(); assert self.nxt()[0] == ":"; d[key] = self.value()
                if self.peek() == ",": self.nxt()
            self.nxt(); return d
        if kind == "[":
            a = []
            while self.peek() != "]":
                a.append(self.value())
                if self.peek() == ",": self.nxt()
            self.nxt(); return a
        if kind in ("str", "num"): return v
        if kind == "id":
            if v == "true": return True
            if v == "false": return False
            if self.k < len(self.t) and self.peek() == "(":   # Color(...), Vector3(...): args parsed, value dropped
                self.nxt()
                while self.peek() != ")":
                    self.value()
                    if self.peek() == ",": self.nxt()
                self.nxt(); return None
            return ("ident", v)
        raise ValueError("unexpected %r %r" % (kind, v))


def const(fname, name):
    path = os.path.join(REPO, fname)
    text = open(path, encoding="utf-8").read()
    m = re.search(r"^(?:const|static var)\s+%s\b[^=\n]*:?=\s*" % re.escape(name), text, re.M)
    if not m: raise KeyError(name)
    start_line = text.count("\n", 0, m.end()) + 1
    return P(_tokens(text[m.end():], fname, start_line)).value()


def strip_tag(line):
    """hud.gd open_comms: a leading "[expr]" is cut off, then strip_edges()."""
    if line.startswith("[") and line.find("]") > 0:
        return line[line.find("]") + 1:].strip()
    return line   # (no strip when there is no tag)


def clip_key(text, key_len):
    """sfx.gd clip_path(): lower, non [a-z0-9] -> _, collapse __, strip_edges, trim one _ each end, left(60)."""
    key = "".join(ch if ("a" <= ch <= "z") or ("0" <= ch <= "9") else "_" for ch in text.lower())
    while "__" in key: key = key.replace("__", "_")
    key = key.strip()   # strip_edges (no-op on underscores)
    if key.startswith("_"): key = key[1:]
    if key.endswith("_"): key = key[:-1]
    return key[:key_len]


# ------------------------------------------------------------------ data
KEY_LEN = const("scripts/data.gd", "VOICE_KEY_LEN")
CHARACTERS = const("scripts/data.gd", "CHARACTERS")
PILOTS = const("scripts/data.gd", "PILOTS")
ENEMY_LEADER = const("scripts/data.gd", "ENEMY_LEADER")
GENERIC = const("scripts/data.gd", "GENERIC_PILOTS")
CHATTER = const("scripts/data.gd", "CHATTER")
ROSTER_HAIL = const("scripts/data.gd", "ROSTER_HAIL")
CONGRATS = const("scripts/data.gd", "CONGRATS")
TUTORIAL = const("scripts/data.gd", "TUTORIAL")
TUTOR_ID = const("scripts/data.gd", "TUTOR_ID")
ENEMIES = const("scripts/data.gd", "ENEMIES")
COORD_HINTS = const("scripts/data.gd", "COORDINATOR_HINTS")
ROSTERS = OrderedDict(const("scripts/data.gd", "ROSTERS_CORE"))
for f, r in const("scripts/roster_data.gd", "ROSTERS").items(): ROSTERS[f] = r   # RosterData.merged()
FDEFS = const("scripts/factions.gd", "DEFS")
TAUNTS = const("scripts/space.gd", "TAUNTS")
PERSONAS = const("scripts/brain.gd", "PERSONAS")
BLINES = const("scripts/brain.gd", "LINES")
TRIBUTE = const("scripts/brain.gd", "TRIBUTE")

PILOT_GROUP = {"raider": "Raiders (%s's squad)", "corsair": "Corsairs (%s's squad)"}

lines, dynamic, speakers = [], [], OrderedDict()
seen = set()


def speaker(vid, name, group, how):
    if vid not in speakers: speakers[vid] = {"voice_id": vid, "speaker": name, "group": group, "how": how}


def add(vid, text_raw, src, kind="literal", note=""):
    sp = speakers[vid]
    text = strip_tag(text_raw)
    key = clip_key(text, KEY_LEN)
    if (vid, key) in seen:   # same file name: one clip already covers it (e.g. "Target... acquired..." / "Target acquired.")
        for e in lines:
            if e["voice_id"] == vid and e["key"] == key and e["text"] != text:
                e.setdefault("also_covers", []).append(text)
        return
    seen.add((vid, key))
    e = OrderedDict([("voice_id", vid), ("speaker", sp["speaker"]), ("group", sp["group"]), ("text", text),
                     ("key", clip_key(text, KEY_LEN)), ("source", src), ("kind", kind)])
    if note: e["note"] = note
    lines.append(e)


def dyn(where, src, template, speakers_, note):
    for e in dynamic:
        if e["template"] == template and e["where"] == where:
            e["voice_ids"] += [v for v in speakers_ if v not in e["voice_ids"]]
            return
    dynamic.append(OrderedDict([("where", where), ("source", src), ("template", template), ("voice_ids", speakers_), ("note", note)]))


def flies(p):  # roster_pick: only pilots whose fighter is in the game fly (and so chatter / hail / answer CALL)
    return str(p.get("fighter_primary", "")) in ENEMIES


# ---- 1. story cast (Data.CHARACTERS): main.gd call_character / say_as / _tutor_call pass the character id
for cid, c in CHARACTERS.items():
    grp = "Crew"
    if cid in ENEMY_LEADER.values(): grp = "Raiders" if cid == ENEMY_LEADER.get("raider") else "Corsairs"
    speaker(cid, c["name"], grp, "Data.CHARACTERS id (main.gd call_character/say_as)")
    for mood, pool in c["lines"].items():
        for l in pool: add(cid, l, l.src)

# tutorial lessons (main.gd _tutor_call, voice_id = Data.TUTOR_ID; spoken because TUTOR_VIDEO is false)
for l in TUTORIAL: add(TUTOR_ID, l["line"], l["line"].src)

# _comms_line(): vale / amari when you CALL them (main.gd call_character, not incoming), and the launch greeting (788)
mtext = open(os.path.join(REPO, "scripts/main.gd"), encoding="utf-8").read().split("\n")
fstart = next(i for i, t in enumerate(mtext) if t.startswith("func _comms_line"))
comms_lit = []
for i in range(fstart + 1, len(mtext)):
    t = mtext[i]
    if t and not t.startswith(("\t", " ")): break
    m = re.search(r'return "((?:[^"\\]|\\.)*)"(.*)$', t)
    if not m: continue
    if "%" in m.group(2): dyn("main.gd _comms_line", "scripts/main.gd:%d" % (i + 1), m.group(1), ["vale", "amari"], "hostile count / current objective filled in at runtime")
    else: comms_lit.append((m.group(1), "scripts/main.gd:%d" % (i + 1)))
greet_ln = next(i + 1 for i, t in enumerate(mtext) if "You're clear, pilot. \" + _comms_line()" in t)
for ctl in ("vale", "amari"):
    for txt, src in comms_lit:
        add(ctl, txt, src)
        # launch greeting: "[smile]You're clear, pilot. " + _comms_line() minus its tag (substr after "]": no strip)
        add(ctl, "[smile]You're clear, pilot. " + txt[txt.find("]") + 1:], "scripts/main.gd:%d" % greet_ln, "resolved",
            "launch greeting + a literal _comms_line variant")
dyn("main.gd launch greeting", "scripts/main.gd:%d" % greet_ln, "[smile]You're clear, pilot. <_comms_line hostiles/objective variant>",
    ["vale", "amari"], "the hostile-count and objective variants of _comms_line are runtime")

# Brain rule-engine replies (main.gd say_as, voice_id = on_call). on_call is only ever a Data.CHARACTERS id;
# ids missing from Brain.PERSONAS (the tutor) answer with vale's persona.
for cid in CHARACTERS:
    per = PERSONAS.get(cid, PERSONAS["vale"])
    about_short = per["about"].split(". ")[0] + "."
    const_fill = {"home": per["home"], "about_short": about_short, "tribute": str(TRIBUTE)}
    for key, pool in BLINES[per["kind"]].items():
        for l in pool:
            ph = set(re.findall(r"\{(\w+)\}", l))
            if not ph:
                add(cid, l, l.src)
            elif ph <= set(const_fill):
                t = l
                for p_, v in const_fill.items(): t = t.replace("{%s}" % p_, v)
                add(cid, t, l.src, "resolved", "Brain placeholders %s are constants for this persona" % sorted(ph))
            else:
                dyn("brain.gd LINES[%s][%s]" % (per["kind"], key), l.src, l, [cid],
                    "runtime placeholders %s (hostile count, kills, system name, or a FACTS entry)" % sorted(ph - set(const_fill)))
dynamic.append(OrderedDict([("where", "brain.gd responder"), ("source", "scripts/brain.gd:250"), ("template", "<free text from Brain.responder>"),
                            ("voice_ids", list(CHARACTERS)), ("note", "only if a relay/LLM responder is plugged in (off by default)")]))

# ---- 2. old enemy squad leaders (Data.PILOTS): main.gd 644 passes str(p["face"]) as the voice_id
for ek, plist in PILOTS.items():
    lead = CHARACTERS[ENEMY_LEADER[ek]]["name"]
    for p in plist:
        speaker(p["face"], "%s (%s)" % (p["name"], p["unit"]), PILOT_GROUP[ek] % lead, "Data.PILOTS face (main.gd _pilot_call)")
        for l in p["lines"]: add(p["face"], l, l.src)

# ---- 3. generic wing pilots AX-01..06: voice_id = p.get("voice_id", p["id"]) = the id
for g in GENERIC:
    speaker(g["id"], "%s %s" % (g["unit"], g["type"]), "Generic wing pilot", "Data.GENERIC_PILOTS id (main.gd 640/664)")

# ---- 4. faction roster pilots: voice_id = their "voice_id"
for f, r in ROSTERS.items():
    for p in r["pilots"]:
        speaker(p["voice_id"], "%s (%s)" % (p["name"], p["unit"]), f, "roster voice_id" + ("" if flies(p) else " (no fighter in game: never flies)"))

chatters = [g["id"] for g in GENERIC] + [p["voice_id"] for f, r in ROSTERS.items() for p in r["pilots"] if flies(p)]
for vid in chatters:
    for ev, pool in CHATTER.items():   # space.gd _chatter (+ main.gd 640: target_acquired when you CALL them)
        for l in pool: add(vid, l, l.src)
for g in GENERIC: add(g["id"], g["hurt"], g["hurt"].src)
for f, r in ROSTERS.items():
    for p in r["pilots"]:
        if flies(p): add(p["voice_id"], p["hurt"], p["hurt"].src)
        if flies(p) and int(p["slot"]) <= 5:   # main.gd 493: a peaceful patrol (patrols never fly slot 06)
            for h in ROSTER_HAIL:
                add(p["voice_id"], h.replace("{name}", p["name"]).replace("{faction}", f), h.src, "resolved", "ROSTER_HAIL with this pilot's name/faction")

# ---- 5. station contacts (Factions.coordinator / leader): hub.gd 303 / 803 / 834, main.gd 184 / 761
def coordinator(f):
    pl = ROSTERS.get(f, {}).get("pilots", [])
    for p in pl:
        if int(p["slot"]) in (2, 3, 4):
            role = str(p.get("type", "")).lower()
            if any(h in role for h in COORD_HINTS): return p
    for p in pl:
        if int(p["slot"]) == 3: return p
    return None

hub_src = open(os.path.join(REPO, "scripts/hub.gd"), encoding="utf-8").read().split("\n")
coord_ln = next(i + 1 for i, t in enumerate(hub_src) if "I have work for you on the Mission Board." in t)
coords = []
for f in ROSTERS:
    co = coordinator(f)
    if not co: continue
    coords.append(co["voice_id"])
    speakers[co["voice_id"]]["contact"] = "coordinator" + ("" if FDEFS.get(f, {}).get("reputation_mode") == "normal" else " (enemy faction: no hub TALK, but still calls in congrats/briefs if it owns a station)")
    if FDEFS.get(f, {}).get("reputation_mode") == "normal":   # Factions.people_at: only main factions show contacts in the hub
        add(co["voice_id"], "%s here. I have work for you on the Mission Board." % co["name"], "scripts/hub.gd:%d" % coord_ln, "resolved",
            "hub TALK line with this coordinator's name")
leaders = [p["voice_id"] for f, r in ROSTERS.items() for p in r["pilots"] if int(p["slot"]) == 6 and FDEFS.get(f, {}).get("reputation_mode") == "normal"]
dyn("hub.gd TALK (leader)", "scripts/hub.gd:%d" % coord_ln, "%s, %s. Welcome to %s.", leaders, "leader's name, faction title and the capital station's name (per leader it is one fixed line, but the station name comes from the galaxy data)")
dyn("main.gd _on_mission_done (Data.CONGRATS)", CONGRATS[0].src, " | ".join(CONGRATS), coords, "{pay} = credits paid; empty coordinator -> '<station> dispatch' with no voice_id")
dyn("main.gd 760 / hub.gd 834 mission brief", "scripts/missions.gd:41-72", "<title>. <brief>  /  <brief>", coords, "system, planet, faction and sector names filled in")
dyn("hub.gd read_bounty", "scripts/hub.gd:800", "Bounty: %s, %s. %s. Reward %d credits, wanted %s. ...", coords, "pilot name, rank, reward")

# ---- 6. anonymous hostiles: no voice_id at all
dyn("main.gd 489 / 672 (space.gd 3389) TAUNTS", TAUNTS[0].src, " | ".join(TAUNTS), [""],
    "'<ship> pilot' with voice_id '' -> Voice.profiled('') is false -> _speak_legacy with no clip path: device TTS only, a clip can never play")


out = OrderedDict()
out["total_lines"] = len(lines)
out["per_voice_id"] = OrderedDict(sorted(Counter(l["voice_id"] for l in lines).items()))
out["speakers"] = list(speakers.values())
out["lines"] = lines
out["dynamic_count"] = len(dynamic)
out["dynamic"] = dynamic
json.dump(out, open(OUT, "w", encoding="utf-8"), indent=1, ensure_ascii=False)
k = Counter(l["kind"] for l in lines)
print("lines", len(lines), dict(k), "speakers", len(speakers), "with lines", len(out["per_voice_id"]), "dynamic", len(dynamic))
print("shared keys:", [(l["voice_id"], l["text"], l["also_covers"]) for l in lines if "also_covers" in l])
