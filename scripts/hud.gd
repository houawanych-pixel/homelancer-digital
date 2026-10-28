extends Control
## Freelancer-style mobile HUD: two button blocks in the top corners (v1.9 owner layout, Oct 19).
## Top left:  weapons FIRE · LIGHT MISSILE · HEAVY MISSILE · MINE, and under them speed STOP · ENGINE · THRUST · WARP.
## Top right: defence SHIELD · REPAIR (two spares beside them), and under them TRANSFORM · GROUND · SPECIAL · TRACTOR.
## Top centre: colour bars for SHIELD / HULL / ENERGY (no numbers), then MAP · VIEW · LOG · CALL · TARGET · GO TO.
## Bottom: FLIGHT stick, dashboard (SPEED · radar · WAYPOINT/SCAN), AIM stick. Lasers fire on their own.
## Each finger belongs to whatever it first touched, so dragging a stick never presses a button.

signal pressed(id: String)

const CYAN := Color(0.33, 0.8, 1.0)
const CYAN_HI := Color(0.6, 0.92, 1.0)
const BLUE := Color(0.13, 0.55, 1.0)
const PANEL := Color(0.02, 0.07, 0.14, 0.86)
const EDGE := Color(0.3, 0.72, 1.0, 0.85)
const WHITE := Color(0.94, 0.97, 1.0)
const RED := Color(1.0, 0.28, 0.25)
const GOLD := Color(1.0, 0.84, 0.3)
const GREEN := Color(0.45, 1.0, 0.55)
const YELLOW := Color(1.0, 0.92, 0.3)
const ORANGE := Color(1.0, 0.6, 0.2)

var space: SpaceSystem
var controls: Controls   # Job J: desktop keyboard + mouse (null-safe: touch never needs it)
var font: Font = ThemeDB.fallback_font
var owners := {} # touch index -> "move" | "aim" | button id
var origins := {}
var move_vec := Vector2.ZERO
var aim_vec := Vector2.ZERO
var buttons := {} # id -> Rect2 (touch areas)
var fs_on := false   # v1.9: the browser is in full screen (web only, polled)
var btn := 94.0 # corner button size
var log_rect := Rect2()
var held := {}
var msg := ""
var msg_t := 0.0
var damage_flash := 0.0
var radar_overview := 0.0   # v1.7o: seconds the radar stays zoomed out to show the station, bases and the job
var radar_range: float = Data.RADAR_RANGE   # what the radar shows right now (v1.4m: it zooms out when you are far from everything)
var objective := ""
var comms_open := false
var comms_line := ""
var comms_from := ""
var comms_mode := "" # incoming | talk | roster (= comms console open) | picker
var comms_hostile := false
## Side comms screens: "l" = enemies, "r" = friendlies. Both can be on at once. Each slot: from, line, face, expr,
## voice, female, hostile, mode (incoming | talk), timer, generic, anim (slide-in 0..1). Empty = closed.
var slots := {"l": {}, "r": {}}
var _last := "r"
var console_open := false
signal typed(text: String)
var _typer: LineEdit
## Seconds left on the newest incoming line (kept as one value for older callers).
var comms_timer: float:
	get: return float(slots[_last].get("timer", 0.0)) if not slots[_last].is_empty() else 0.0
	set(v):
		if not slots[_last].is_empty(): slots[_last]["timer"] = v
var comms_face := ""        # portrait set id (assets/portraits/<face>_<expr>.png), "" = no face (waveform)
var comms_expr := "normal"
var comms_voice := 1.0
var comms_voice_id := ""   # v1.4t: whose recorded voice the line on screen looks for
var comms_female := false
var comms_generic := false   # a generic enemy pilot (face "gp/<id>") is on the line
var _faces := {}
var contacts: Array = []
var planet_map := false   # v1.8y: the planet map is open (on a planet the radar / MAP opens it)
var pick := ""   # v1.8q: who is picked in LOG ("" = nobody, "hail" = your target / control, or a character id): their picture is up on the friendly side with CALL
var history: Array = [] # recent messages and calls for LOG
var roster_t := 1.0 # drop-down animation 0..1
var roster_closing := false
var roster_idle := 0.0
var S := Vector2(1280, 720)
var stick_r := 92.0
var col_w := 140.0
var flash := {}
var t := 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	GS.changed.connect(queue_redraw)
	# typing box for the comms console (phones get their on-screen keyboard)
	_typer = LineEdit.new()
	_typer.visible = false
	_typer.placeholder_text = "Type a message…"
	_typer.max_length = 120
	_typer.add_theme_font_size_override("font_size", Data.ts(18))
	add_child(_typer)
	_typer.text_submitted.connect(func(txt: String):
		_typer.visible = false
		_typer.release_focus()
		txt = txt.strip_edges()
		_typer.text = ""
		if txt != "":
			_log("YOU: " + txt)
			typed.emit(txt))

func _log(line: String) -> void:
	history.push_front(line)
	if history.size() > 30: history.pop_back()

func flash_message(txt: String) -> void:
	msg = txt
	msg_t = 4.0
	_log(txt)

func hurt() -> void:
	damage_flash = 0.6

func pulse(id: String) -> void:
	flash[id] = 0.6

## A voice on the radio. Enemies appear on the LEFT side screen, friendlies on the RIGHT; one of each can be on
## at the same time. Placing a call closes the comms console.
func open_comms(from: String, line: String, mode := "talk", hostile := false, face := "", voice := 1.0, female := false, voice_id := "", video := "") -> void:
	var expr := "angry" if hostile else "normal"
	if line.begins_with("[") and line.find("]") > 0:   # "[smile]Text" picks the face for this line
		expr = line.substr(1, line.find("]") - 1)
		line = line.substr(line.find("]") + 1).strip_edges()
	var side := "l" if hostile else "r"
	var old: Dictionary = slots[side]
	var v := voice if face != "" else (0.8 if hostile else 1.0)
	slots[side] = {"from": from, "line": line, "face": face, "expr": expr, "voice": v, "female": female, "hostile": hostile,
		"mode": mode, "timer": 7.0 if mode == "incoming" else 0.0, "generic": face.begins_with("gp/"),
		"anim": float(old.get("anim", 0.0)) if not old.is_empty() else 0.0, "video": video}
	_last = side
	comms_from = from
	comms_expr = expr
	comms_face = face
	comms_generic = face.begins_with("gp/")
	comms_line = line
	comms_voice = v
	comms_female = female
	comms_hostile = hostile
	if mode == "talk": console_open = false
	if side == "l" and console_open:   # v1.8s (owner: no layering): a hostile caller takes the left side; the panel there goes away
		console_open = false
		if _typer: _typer.visible = false
	comms_voice_id = voice_id
	if video != "": _play_video(video)   # v1.7r: an acted clip speaks for itself (its own voice and gestures)
	elif video_playing() and side == "l": pass   # (a hostile line shows as text while the guide's clip talks)
	elif Time.get_ticks_msec() / 1000.0 >= Sfx.keep_until or not Sfx.voice_busy(): Sfx.speak(line, v, female, voice_id)   # v1.7n: not over a brief
	_sync()
	_log("%s: %s" % [from, line])

## Is that side's screen busy with a call you placed (don't talk over it)?
func side_busy(hostile: bool) -> bool:
	return slots["l" if hostile else "r"].get("mode", "") == "talk"

## v1.7r: the guide's acted clips play in the comms portrait (same size as the other faces).
var vid: VideoStreamPlayer = null
func _play_video(path: String) -> void:
	var st := load(path) as VideoStream
	if st == null: return
	if vid == null:
		vid = VideoStreamPlayer.new()
		vid.name = "CommsVideo"
		vid.size = Vector2(2, 2)
		vid.modulate = Color(1, 1, 1, 0)   # (decoded here, drawn by _side into the portrait frame)
		vid.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(vid)
	Sfx.stop_voice()
	vid.stream = st
	vid.play()

func video_playing() -> bool:
	return vid != null and vid.is_playing()

func slot(side: String) -> Dictionary:
	return slots[side]

func close_side(side: String) -> void:
	slots[side] = {}
	if slots[_last].is_empty(): _last = "l" if side == "r" else "r"
	_sync()

## Keep the old single-panel view of the state (comms_open / comms_mode) in step with the side screens + console.
func _sync() -> void:
	var any: bool = not slots["l"].is_empty() or not slots["r"].is_empty()
	comms_open = any or console_open
	if console_open: comms_mode = "roster"
	elif not slots[_last].is_empty(): comms_mode = slots[_last]["mode"]
	elif any: comms_mode = (slots["l"] if not slots["l"].is_empty() else slots["r"])["mode"]
	else: comms_mode = ""

func open_picker(list: Array) -> void:
	contacts = list
	comms_open = true
	comms_mode = "picker"
	comms_hostile = false

## v1.8q (owner): a name tapped in LOG: the picture comes up on the friendly side (right) with a CALL button under it.
## info: {name, face, ok (can be called from here), sub (why not)}.
func pick_contact(id: String, info: Dictionary) -> void:
	var old: Dictionary = slots["r"]
	if old.get("mode", "") == "talk": return   # (a call is on that screen: hang up first)
	pick = id
	var face := str(info.get("face", ""))
	slots["r"] = {"from": str(info.get("name", "")), "line": "", "face": face, "expr": "normal", "voice": 1.0, "female": false, "hostile": false,
		"mode": "pick", "timer": 0.0, "generic": face.begins_with("gp/"), "anim": float(old.get("anim", 0.0)) if old.get("mode", "") == "pick" else 0.0, "video": "",
		"ok": bool(info.get("ok", true)), "sub": str(info.get("sub", ""))}
	roster_idle = 0.0
	_sync()

## LOG = the comms console: drops down under the centre buttons with your contacts (call anyone who is in THIS
## star system, like a codec but with names instead of frequencies), the chat log, and a box to type in.
## Tap LOG again (or wait) and it rolls back up.
var console_view := "list"   # v1.8s: what the left panel shows: "list" (LOG: who to call) or "chat" (the text screen of a call)

## The text screen: comes up on the left when you press CALL or tap a caller's screen. CLOSE (or LOG) puts it away.
func open_chat() -> void:
	if not console_open or roster_closing: roster_t = 0.0
	console_view = "chat"
	console_open = true
	roster_closing = false
	roster_idle = 0.0
	_sync()

func open_log() -> void:
	console_view = "list"
	console_open = true
	roster_t = 0.0
	roster_closing = false
	roster_idle = 0.0
	_sync()

## v1.4n: the console is two panels at the screen edges, so the middle (your ship, the view) stays clear.
## Contacts sit flush against the RIGHT edge, the message log against the LEFT edge. Both slide in from their side.
func _panel_w() -> float:
	return clampf(S.x * Data.COMMS_PANEL_FRAC, Data.COMMS_PANEL_W[0], Data.COMMS_PANEL_W[1])

func _panel_span() -> Vector2:   # top and bottom of both panels: under the corner buttons, above the sticks
	var top := 8.0 + btn * 2.0 + 8.0 + 14.0
	var bottom := _home("move").y - stick_r - 10.0
	return Vector2(top, maxf(top + 150.0, bottom))

func contacts_rect() -> Rect2:   # v1.8r (owner): the call list is on the LEFT; the picked face comes up on the right
	var w := _panel_w()
	var sp := _panel_span()
	var e := ease(roster_t, 0.35)
	return Rect2(-w * (1.0 - e), sp.x, w, sp.y - sp.x)

func msglog_rect() -> Rect2:   # v1.8s: the text screen takes the call list's place (one panel, on the left)
	return contacts_rect()

## v1.8r (owner): who is on the call list: people you have met who are still on speaking terms with you (not enraged,
## and their faction, if they have one, yellow or better). Lose their good will and they drop off the list.
func call_list() -> Array:   # v5.0 (owner): Evee rides with you, so she is always first on the list
	return ["assistant"] + GS.met.filter(func(id): return id != "assistant").filter(func(id): return Data.CHARACTERS.has(id) and GS.mood.get(id, "neutral") != "enraged" and not (Data.CHARACTERS[id].has("faction") and Factions.hostile(str(Data.CHARACTERS[id]["faction"]))))

var contact_scroll := 0   # the first person shown (UP / DOWN in the list's header)
func contact_at(k: int) -> String:
	var cl := call_list()
	return str(cl[k + contact_scroll]) if k >= 0 and k + contact_scroll < cl.size() else ""

func scroll_contacts(d: int) -> void:
	contact_scroll = clampi(contact_scroll + d, 0, maxi(0, call_list().size() - (contact_rows() - 1)))
	roster_idle = 0.0

## How many contact rows fit (up to 5).
func contact_rows() -> int:
	return clampi(int((contacts_rect().size.y - 38.0) / Data.COMMS_ROW_H), 2, 6)

## Kept for older callers: the area the console covers = the contacts panel.
func roster_rect() -> Rect2:
	return contacts_rect()

## Can you call this contact from here? Only people in the same star system answer.
static func in_range(id: String) -> bool:
	return Data.CHARACTERS[id].get("system", GS.system_id) == GS.system_id

func close_roster() -> void:
	roster_closing = true

func _face_tex(face: String, expr: String) -> Texture2D:
	var k := face + "_" + expr
	if face.begins_with("gp/"):   # generic enemy pilot: enemies pack, normal / damaged only; not cached until it exists
		var gp := "res://assets/enemy_pilots/%s_%s.jpg" % [face.substr(3), "damaged" if expr == "damaged" else "normal"]
		if expr != "damaged" and not ResourceLoader.exists(gp): gp = "res://assets/enemy_pilots/%s_clean.jpg" % face.substr(3)   # roster characters: clean / damaged
		if _faces.get(k) == null: _faces[k] = load(gp) if ResourceLoader.exists(gp) else null
		return _faces[k]
	if not _faces.has(k):
		var path := "res://assets/portraits/%s.png" % k
		_faces[k] = load(path) if ResourceLoader.exists(path) else null
		if _faces[k] == null and expr != "normal": _faces[k] = _face_tex(face, "normal")
	return _faces[k]

func close_comms() -> void:
	if not slots["l"].is_empty() or not slots["r"].is_empty(): Sfx.hang_up()
	slots = {"l": {}, "r": {}}
	console_open = false
	if _typer: _typer.visible = false
	_sync()

## Where a side screen sits: under the corner buttons, clear of the sticks.
# ---------------------------------------------------------------- v6.7 (owner, from Freelancer): contact list + ship panel
## LEFT, where the enemy calls come in: the contact list. Tap a row = target it (its red arrow then points the way).
## RIGHT, where your calls come in: hull, shield, repairs, and every gun on the ship to switch on or off.
## Each folds to a small tab. A call on that side covers it while it lasts.
var cl_open := true
var sp_open := true
const FL_ROWS := 6
const FL_TAB_H := 30.0   # v7.3: the WEAPONS / COMMS / VIEW row under the right window's title
const FL_TGT_H := 26.0   # v7.6: just the NEXT · GO TO · SCAN row (the target itself is the red card above)   # v6.9: the target block on top of the contact list (name, distance, shield + hull, SCAN, NEXT)
func fl_rect(side: String) -> Rect2:
	var sr := side_rect(side)
	var open: bool = cl_open if side == "l" else sp_open
	if not open: return Rect2(sr.position if side == "l" else Vector2(sr.end.x - clampf(S.x * 0.2, 190.0, 250.0), sr.position.y), Vector2(sr.size.x if side == "l" else clampf(S.x * 0.2, 190.0, 250.0), 26.0 if side == "l" else 26.0 + FL_TAB_H))
	var w := clampf(S.x * 0.2, 190.0, 250.0)
	var r := Rect2(sr.position.x if side == "l" else sr.end.x - w, sr.position.y, w, sr.size.y)
	return r

const FL_TABS := ["weapons", "log"]   # v7.6 (owner): WEAPONS and COMMS in the right window (SPEED is the cockpit button)
func fl_tab_rect(i: int) -> Rect2:
	var r := fl_rect("r")
	var bw := (r.size.x - 12.0) / 2.0
	return Rect2(r.position + Vector2(4.0 + i * (bw + 4.0), 28.0), Vector2(bw, 26.0))

func fl_shown(side: String) -> bool:
	return space != null and space.controls and slots[side].is_empty() and not console_open and not planet_map

## The contacts on the list: ships nearest first (hostiles, then others), then the places.
func fl_contacts() -> Array:
	var out: Array = []
	var p: Vector3 = space.player.global_position
	var ships: Array = space.enemies.duplicate()
	ships.sort_custom(func(a, b): return a["node"].global_position.distance_to(p) < b["node"].global_position.distance_to(p))
	for e in ships:
		var hostile: bool = e["node"].get_meta("kind", "enemy") == "enemy" and Factions.hostile(str(e["def"].get("faction", "Enemy")))
		out.append({"node": e["node"], "name": str(e["node"].name), "kind": "ship", "col": RED if hostile else GOLD})
	for tr in space.traffic:
		if is_instance_valid(tr["node"]): out.append({"node": tr["node"], "name": str(tr["node"].name), "kind": "ship", "col": GREEN})
	for n in [space.station, space.planet] + space.gates:
		if is_instance_valid(n) and n.get_meta("kind", "") != "none" and n.visible: out.append({"node": n, "name": str(n.name), "kind": str(n.get_meta("kind", "")), "col": CYAN})
	return out

var cl_scroll := 0
var gun_scroll := 0
var _list_drag := {}   # v7.7 (owner): touch index -> {y, s0, side, moved}: a drag on a list scrolls it, a tap picks the row
const CL_ROW_H := 24.0
const GUN_ROW_H := 22.0
func cl_rows_fit() -> int:
	return maxi(2, int((fl_rect("l").size.y - (30.0 + FL_TGT_H + 4.0) - 6.0) / CL_ROW_H))
func gun_rows_fit() -> int:
	return maxi(1, int((fl_rect("r").size.y - (82.0 + FL_TAB_H) - 6.0) / GUN_ROW_H))
func list_max_scroll(side: String) -> int:
	return maxi(0, (fl_contacts().size() - cl_rows_fit()) if side == "l" else (gun_rows().size() - gun_rows_fit()))
func _fl_buttons() -> void:
	if space == null: return
	for side in ["l", "r"]:
		if not fl_shown(side): continue
		var r := fl_rect(side)
		buttons["fl_tab_" + side] = Rect2(r.position, Vector2(r.size.x, 26))
		if side == "r":
			for i in FL_TABS.size(): buttons[FL_TABS[i]] = fl_tab_rect(i)
		if not (cl_open if side == "l" else sp_open): continue
		if side == "l":
			var list := fl_contacts()
			var bw2: float = (r.size.x - 16) / 3.0
			buttons["target"] = Rect2(r.position + Vector2(4, 30 + FL_TGT_H - 26), Vector2(bw2, 24))   # v6.9: NEXT target
			buttons["goto"] = Rect2(r.position + Vector2(8 + bw2, 30 + FL_TGT_H - 26), Vector2(bw2, 24))   # v7.4 (owner): GO TO next to NEXT (job, waypoint, then target)
			if space.target != null and is_instance_valid(space.target):
				buttons["scan"] = Rect2(r.position + Vector2(12 + bw2 * 2, 30 + FL_TGT_H - 26), Vector2(bw2, 24))
			var y1: float = 30 + FL_TGT_H + 4
			cl_scroll = clampi(cl_scroll, 0, list_max_scroll("l"))
			for i in mini(cl_rows_fit(), list.size() - cl_scroll):
				buttons["cl_%d" % (cl_scroll + i)] = Rect2(r.position + Vector2(4, y1 + i * CL_ROW_H), Vector2(r.size.x - 14, 22))
		else:
			var gs := gun_rows()
			gun_scroll = clampi(gun_scroll, 0, list_max_scroll("r"))
			for i in mini(gun_rows_fit(), gs.size() - gun_scroll):
				buttons["gun_%s" % str(gs[gun_scroll + i][0])] = Rect2(r.position + Vector2(4, 82 + FL_TAB_H + i * GUN_ROW_H), Vector2(r.size.x - 14, 20))

## [slot key, name] for every gun on the ship (front guns, then the wing mounts).
func gun_rows() -> Array:
	var out: Array = []
	for k in GS.core_slots():
		var gid: String = GS.core_item(k)
		if Data.WEAPONS.has(gid): out.append(["core%d" % k, str(Data.WEAPONS[gid]["name"])])
	var items: Array = GS.mount_items()
	for g in items.size():
		if Data.WEAPONS.has(str(items[g])): out.append([str(g), str(Data.WEAPONS[str(items[g])]["name"])])
	return out

func fl_tap(id: String) -> bool:
	if id == "fl_tab_l": cl_open = not cl_open
	elif id == "fl_tab_r": sp_open = not sp_open
	elif id == "cl_more": cl_scroll = (cl_scroll + FL_ROWS) if cl_scroll + FL_ROWS < fl_contacts().size() else 0
	elif id.begins_with("cl_"):
		var list := fl_contacts()
		var i := int(id.substr(3))
		if i < list.size() and is_instance_valid(list[i]["node"]): space.pick_target(list[i]["node"])
	elif id.begins_with("gun_"):
		var k := id.substr(4)
		if GS.gun_off.has(k): GS.gun_off.erase(k)
		else: GS.gun_off[k] = true
	else: return false
	return true

## v6.9: the target (or the job) on top of the contact list, with its shield and hull, and SCAN / NEXT under it.
func _fl_target(r: Rect2) -> void:   # v7.6: the row of NEXT · GO TO · SCAN (the target is the red card above)
	for id in ["target", "goto", "scan"]:
		if not buttons.has(id): continue
		var br: Rect2 = buttons[id]
		var on: bool = id == "goto" and space.autopilot != null
		var bc: Color = {"target": GOLD, "goto": GREEN, "scan": CYAN}[id]   # v7.7 (owner): NEXT yellow, GO TO green
		_box(br, Color(bc, 0.35 if on else 0.16), Color(bc, 0.85), 6, 1)
		_text(Vector2(br.position.x, br.position.y + 17), {"target": "NEXT ▸", "scan": "SCAN", "goto": "GO TO"}[id], 12, WHITE, HORIZONTAL_ALIGNMENT_CENTER, br.size.x)

## v7.6 (owner's mockup): the enemy card over the contact list: only while there are hostiles. Your target if it is
## hostile, else the nearest hostile that is after you.
func card_enemy() -> Dictionary:
	if space == null: return {}
	var p: Vector3 = space.player.global_position
	var best := {}
	var bd := INF
	for e in space.enemies:
		var n: Node3D = e["node"]
		if not is_instance_valid(n) or n.get_meta("kind", "enemy") != "enemy": continue
		if n == space.target: return e
		if not e.get("aggro", false): continue
		var d := n.global_position.distance_to(p)
		if d < bd:
			bd = d
			best = e
	return best

func _card(r: Rect2, col: Color, title: String, k_sh: float, k_hp: float) -> void:
	var c := 14.0
	var pts := PackedVector2Array([r.position + Vector2(c, 0), Vector2(r.end.x - c, r.position.y), Vector2(r.end.x, r.position.y + c),
		Vector2(r.end.x, r.end.y - c), Vector2(r.end.x - c, r.end.y), Vector2(r.position.x + c, r.end.y), Vector2(r.position.x, r.end.y - c), Vector2(r.position.x, r.position.y + c)])
	draw_colored_polygon(pts, Color(col.darkened(0.75), 0.88))
	draw_polyline(pts + PackedVector2Array([pts[0]]), Color(col, 0.95), 2.5, true)
	var ic := r.position + Vector2(36, r.size.y * 0.5)
	_jet_icon(ic, 20.0, col.lightened(0.2))
	_text(r.position + Vector2(68, 22), title, 15, WHITE, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 76)
	var br := Rect2(r.position + Vector2(68, 30), Vector2(r.size.x - 82, 9))
	if k_sh >= 0.0: _seg_bar(Rect2(br.position, Vector2(br.size.x, 5)), k_sh, Color(0.45, 0.75, 1.0), 12)
	_seg_bar(Rect2(br.position + Vector2(0, 10), Vector2(br.size.x, 8)), k_hp, col if col != CYAN else Color(0.3, 0.75, 1.0), 12, k_hp < 0.25 and fmod(t, 0.6) < 0.3)

func _jet_icon(c: Vector2, s2: float, col: Color) -> void:   # v7.7 (owner): a delta fighter, no tail
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s2), c + Vector2(s2 * 0.2, -s2 * 0.25), c + Vector2(s2, s2 * 0.42), c + Vector2(s2, s2 * 0.6),
		c + Vector2(s2 * 0.24, s2 * 0.45), c + Vector2(s2 * 0.16, s2 * 0.62), c + Vector2(-s2 * 0.16, s2 * 0.62), c + Vector2(-s2 * 0.24, s2 * 0.45),
		c + Vector2(-s2, s2 * 0.6), c + Vector2(-s2, s2 * 0.42), c + Vector2(-s2 * 0.2, -s2 * 0.25)]), col)

func _card_target(r: Rect2) -> void:
	var e := card_enemy()
	if e.is_empty(): return
	var n: Node3D = e["node"]
	var hp: float = clampf(float(e["hp"]) / maxf(float(e.get("max", e["hp"])), 1.0), 0.0, 1.0)
	var shm: float = float(e.get("sh_max", 0.0))
	_card(Rect2(r.position.x, r.position.y - 64.0, r.size.x, 58.0), RED, "%s  %s" % [str(n.name).to_upper(), _dist(space.distance_to(n))], clampf(float(e.get("sh", 0.0)) / shm, 0.0, 1.0) if shm > 0.0 else -1.0, hp)

func _card_ship(r: Rect2) -> void:
	_card(Rect2(r.position.x, r.position.y - 64.0, r.size.x, 58.0), CYAN, "YOUR SHIP", clampf(GS.shield / maxf(GS.max_shield(), 1.0), 0.0, 1.0), clampf(GS.hull / maxf(GS.max_hull(), 1.0), 0.0, 1.0))

func _fl_panels() -> void:
	for side in ["l", "r"]:
		if not fl_shown(side): continue
		var r := fl_rect(side)
		var open: bool = cl_open if side == "l" else sp_open
		_box(r, Color(PANEL, 0.72), Color(EDGE, 0.8), 8, 2)
		_text(r.position + Vector2(8, 18), ("CONTACTS" if side == "l" else "SHIP") + ("  ▾" if open else "  ▸"), 13, CYAN_HI)
		pass   # (v7.8 owner: no YOUR SHIP card: the rings round the radar already show it)
		if side == "r":   # v7.3: WEAPONS · COMMS · VIEW
			var lit := [weapons_shown(), console_open or comms_open]
			var names := ["WEAPONS", "COMMS"]
			var cols := [Color(0.25, 0.6, 1.0), Color(0.7, 0.45, 1.0)]   # v7.7 (owner): WEAPONS blue, COMMS purple
			for i in 2:
				var tr: Rect2 = fl_tab_rect(i)
				_box(tr, Color(cols[i], 0.3 if lit[i] else 0.12), Color(cols[i], 0.85), 6, 1)
				_text(Vector2(tr.position.x, tr.position.y + 18), names[i], 12, WHITE, HORIZONTAL_ALIGNMENT_CENTER, tr.size.x)
		if not open: continue
		if side == "l":
			var list := fl_contacts()
			var tg: Node3D = space.target
			_fl_target(Rect2(r.position + Vector2(4, 28), Vector2(r.size.x - 8, FL_TGT_H)))
			_card_target(r)
			_scrollbar(r, 30.0 + FL_TGT_H + 4.0, cl_scroll, cl_rows_fit(), list.size())
			for i in mini(cl_rows_fit(), list.size() - cl_scroll):
				var c: Dictionary = list[cl_scroll + i]
				var y: float = r.position.y + 30 + FL_TGT_H + 4 + i * 24
				var sel: bool = c["node"] == tg
				if sel: draw_rect(Rect2(r.position.x + 4, y, r.size.x - 8, 22), Color(c["col"], 0.22))
				draw_circle(Vector2(r.position.x + 13, y + 11), 4, c["col"])
				_text(Vector2(r.position.x + 22, y + 16), _dist(space.player.global_position.distance_to(c["node"].global_position)), 12, Color(c["col"], 0.9), HORIZONTAL_ALIGNMENT_LEFT, 56)
				_text(Vector2(r.position.x + 80, y + 16), c["name"], 12, WHITE if sel else Color(WHITE, 0.85), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 86)
			pass
		else:
			var x: float = r.position.x + 8
			var bw: float = r.size.x - 16
			var y0: float = r.position.y + 30 + FL_TAB_H
			_text(Vector2(x, y0 + 10), "HULL %d%%" % int(100.0 * GS.hull / maxf(GS.max_hull(), 1.0)), 12, GREEN, HORIZONTAL_ALIGNMENT_LEFT, bw * 0.5)
			_text(Vector2(x + bw * 0.5, y0 + 10), "SHIELD %d%%" % int(100.0 * GS.shield / maxf(GS.max_shield(), 1.0)), 12, Color(0.45, 0.75, 1.0), HORIZONTAL_ALIGNMENT_LEFT, bw * 0.5)
			_text(Vector2(x, y0 + 30), "REPAIR KITS %d   SHIELD CELLS %d" % [GS.repairs, GS.shield_charges], 11, Color(WHITE, 0.85), HORIZONTAL_ALIGNMENT_LEFT, bw)
			var gs := gun_rows()
			_scrollbar(r, 82.0 + FL_TAB_H, gun_scroll, gun_rows_fit(), gs.size())
			bw -= 6.0
			for i2 in mini(gun_rows_fit(), gs.size() - gun_scroll):
				var i := gun_scroll + i2
				var on: bool = not GS.gun_off.has(str(gs[i][0]))
				var y: float = r.position.y + 82 + FL_TAB_H + i2 * GUN_ROW_H
				draw_rect(Rect2(x - 4, y, bw + 8, 20), Color(GREEN if on else RED, 0.14))
				_text(Vector2(x, y + 15), "%d  %s" % [i + 1, gs[i][1]], 12, GREEN if on else Color(RED, 0.8), HORIZONTAL_ALIGNMENT_LEFT, bw - 34)
				_text(Vector2(x + bw - 34, y + 15), "ON" if on else "OFF", 11, GREEN if on else RED, HORIZONTAL_ALIGNMENT_RIGHT, 34)

## v7.7 (owner): a thin scroll bar down a window's right edge when its list is longer than the window.
func _scrollbar(r: Rect2, top: float, at: int, fit: int, total: int) -> void:
	if total <= fit: return
	var tr := Rect2(r.end.x - 7.0, r.position.y + top, 3.0, r.size.y - top - 6.0)
	draw_rect(tr, Color(CYAN, 0.18))
	var h := maxf(14.0, tr.size.y * fit / float(total))
	var y := tr.position.y + (tr.size.y - h) * (at / float(maxi(1, total - fit)))
	draw_rect(Rect2(tr.position.x - 1.0, y, 5.0, h), Color(CYAN_HI, 0.9))

func side_rect(side: String) -> Rect2:
	var w := clampf(S.x * 0.14, 150.0, 190.0)
	var top := 8.0 + 70.0   # v7.6: room for the target card above (v7.8: the small buttons moved down to the console)
	var bottom := _home("move").y - stick_r - 12.0
	var h := minf(w + 90.0, bottom - top)
	top = bottom - h   # v7.5 (owner): the two windows sit right above the sticks
	var inset := 8.0 + ((_panel_w() + 6.0) * ease(roster_t, 0.35) if console_open and side == "l" else 0.0)   # v1.4n: a caller floats in NEXT to the console panel (v1.8s: the panel is on the left only)
	return Rect2(inset if side == "l" else S.x - inset - w, top, w, h)

# ---------------------------------------------------------------- layout
func _home(which: String) -> Vector2:
	var x := 36 + stick_r if which == "move" else S.x - 36 - stick_r
	return Vector2(x, S.y - stick_r - 28)

## The radar screen (chase: centre dash panel; cockpit: the art's centre screen). It is a button: tap = radar map.
func radar_rect() -> Rect2:
	if GS.view == "cockpit" and cockpit_texture():
		var cr := cockpit_rect()
		return Rect2(cr.position + cr.size * Vector2(0.433, 0.66), cr.size * Vector2(0.136, 0.155))
	var g := dash_geo()   # v7.1: the radar globe on the dash
	var rad: float = g["rad"]
	return Rect2((g["rc"] as Vector2) - Vector2(rad, rad), Vector2(rad, rad) * 2.0)

## Where a stick can be grabbed: the bottom corners only (not the radar / middle of the dash).
func stick_zone(which: String) -> Rect2:
	var top := btn * 2.0 + 30.0
	var w := clampf(S.x * 0.36, 260.0, 520.0)
	return Rect2(0.0, top, w, S.y - top) if which == "move" else Rect2(S.x - w, top, w, S.y - top)

func _console() -> Rect2:
	var l := _home("move").x + stick_r + 14
	var r := _home("aim").x - stick_r - 14
	return Rect2(l, S.y - 150, r - l, 140)

func _comms_rect() -> Rect2:
	# over the dashboard, between the two sticks
	var l := _home("move").x + stick_r + 10
	var r := _home("aim").x - stick_r - 10
	var w := minf(720.0, r - l)
	return Rect2(S.x * 0.5 - w * 0.5, S.y - 272, w, 262)

## Width of one corner block (three buttons).
func _block_w() -> float:
	return btn * 4 + 24   # v1.8q: four buttons wide

func _layout() -> void:
	S = get_viewport_rect().size
	stick_r = clampf(S.y * 0.105, 62.0, 84.0)   # v7.6 (owner's console mockup)
	btn = clampf(S.y * 0.118, 74.0, 96.0)
	btn = maxf(56.0, minf(btn, (S.x - 5 * 66.0 - 24.0 - 92.0) / 8.0))   # v1.8q: two blocks of four must leave room for the centre strip
	col_w = 24.0
	buttons.clear()
	# v7.6 (owner's console mockup): everything you fly with sits on one console at the bottom, between the sticks:
	#   left wing:  SHIELD bar (+ shield boost), HULL bar in three (+ repair), then MISSILE 1 · FIRE · ENGINE KILL · THRUST
	#   centre:     SPEED (tap = cockpit / chase view) over the RADAR (tap = map)
	#   right wing: POWER bar (+ MECH transform), SUPER bar (+ the super / barrel roll), then STOP · WARP · MINE · MISSILE 2
	# TRACTOR and GROUND pop up top-left when you open WEAPONS (or fight); FULL SCREEN sits top-right on the web.
	var dg := dash_geo()
	for id in ["fire", "kill", "thrust", "stop", "warp", "shield", "repair", "form", "special"]: buttons[id] = dg[id]
	for k in GS.slots.size():
		var it: String = GS.slots[k]
		var key := "missile1" if it == "light_missile" else ("missile2" if it == "heavy_missile" else ("mine" if it == "mine" else ""))
		if key != "": buttons["slot_%d" % k] = dg[key]
	# v7.8 (owner): TRACTOR and FULL SCREEN sit down with the other buttons: on top of each block, by the radar
	var sb := Vector2(dg["small"], dg["small"])
	var lt: Rect2 = dg["shield"]
	var rt: Rect2 = dg["repair"]
	buttons["tractor"] = Rect2(Vector2(lt.end.x - sb.x, lt.position.y - 6.0 - sb.y), sb)
	buttons["ground"] = Rect2(buttons["tractor"].position - Vector2(sb.x + 6.0, 0), sb)
	if OS.has_feature("web") or OS.get_environment("HL_FS_BUTTON") != "":   # v1.9 (owner): FULL SCREEN
		buttons["fullscreen"] = Rect2(Vector2(rt.position.x, rt.position.y - 6.0 - sb.y), sb)
	if not weapons_shown():
		for id in COMBAT_IDS: buttons.erase(id)
	if space and space.mech_fpv():   # v1.7z: looking out of the mech, KILL (no use to a mech) becomes the rifle's ZOOM
		buttons["zoom"] = buttons["kill"]
		buttons.erase("kill")
	var hm := _home("move")
	buttons["goto"] = Rect2(hm.x - 70, hm.y - stick_r - 62, 140, 42)   # v7.4: GO TO is in the left window; this is only while that window is away
	# v7.3 (owner): WEAPONS, COMMS and VIEW sit in the right window (_fl_buttons); when that window is away (a call,
	# the comms console, the planet map) COMMS and VIEW stay reachable above the aim stick
	buttons["log"] = comms_rect()
	buttons["view"] = dg["speed"]   # v7.6 (owner): the SPEED readout is the cockpit button
	log_rect = buttons["log"]
	if space and space.controls and not console_open: buttons["radar"] = radar_rect()
	if not scan.is_empty(): buttons["scan_close"] = scan_rect()
	if space and space.controls:
		var db := Rect2(S.x * 0.5 - 150, 8, 300, 44)   # v7.0 (owner): DOCK and the other prompts at the very top
		var pr: String = space.prompt()   # v1.4u: one prompt, the nearest thing wins
		if pr != "": buttons[pr] = db
	_fl_buttons()   # v6.7: the Freelancer-style contact list (left) and ship panel (right)
	for side in ["l", "r"]:
		var sd: Dictionary = slots[side]
		if sd.is_empty(): continue
		var sr := side_rect(side)
		if sd["mode"] == "talk": buttons["hangup"] = Rect2(sr.end.x - 34, sr.position.y + 2, 32, 22)   # before the body, so it wins
		if sd["mode"] == "pick": buttons["call_pick"] = Rect2(sr.position.x + 5, sr.end.y - 63, sr.size.x - 10, 58)   # v1.8q: CALL under the picked face
		buttons["side_" + side] = sr
	if planet_map:   # v1.8y: the map is up: its own buttons only (it covers the view until closed)
		if space == null or not space.surface_mode:
			planet_map = false
		else:
			var mr := planet_map_rect()
			buttons.clear()
			buttons["pmap_close"] = Rect2(mr.end.x - 96, mr.position.y + 6, 90, 40)
			var spots: Array = space.base_spots()
			for i in spots.size():
				var bp := _pmap_point(mr, int(spots[i]["tile"]), float(spots[i]["x"]), float(spots[i]["z"]))
				buttons["pmap_b%d" % i] = Rect2(bp - Vector2(70, 22), Vector2(140, 44))
			return
	if console_open:
		var rr := contacts_rect()
		var lg := msglog_rect()
		if roster_t > 0.95 and not roster_closing and console_view == "chat":
			var hw2 := (lg.size.x - 24.0) / 3.0
			buttons["chat_close"] = Rect2(lg.end.x - 86, lg.position.y + 3, 78, 26)
			buttons["type"] = Rect2(lg.position.x + 6, lg.end.y - 44, hw2, 38)
			buttons["talk"] = Rect2(lg.position.x + 12 + hw2, lg.end.y - 44, hw2, 38)   # v1.5j hold-to-talk
			buttons["voice"] = Rect2(lg.position.x + 18 + hw2 * 2.0, lg.end.y - 44, hw2, 38)
		elif roster_t > 0.95 and not roster_closing:
			buttons["met_hail"] = Rect2(rr.position.x, rr.position.y + 32, rr.size.x - 6, Data.COMMS_ROW_H - 4)   # v1.8q: the first row: your target / control
			var cn := call_list().size()
			contact_scroll = clampi(contact_scroll, 0, maxi(0, cn - (contact_rows() - 1)))
			if cn > contact_rows() - 1:   # more people than fit: UP / DOWN in the header
				buttons["met_up"] = Rect2(rr.end.x - 108, rr.position.y + 3, 50, 26)
				buttons["met_down"] = Rect2(rr.end.x - 54, rr.position.y + 3, 50, 26)
			for k in mini(cn - contact_scroll, contact_rows() - 1):
				buttons["met_%d" % k] = Rect2(rr.position.x, rr.position.y + 32 + (k + 1) * Data.COMMS_ROW_H, rr.size.x - 6, Data.COMMS_ROW_H - 4)

## v1.9k (owner: after a capture I didn't know where to go): the job line at the top is a button. Added after the
## layout, last, so a real button under it always wins.
func _objective_button() -> void:
	if false and objective != "" and space != null and not space.mission_waypoint().is_empty():   # (v7.0: the job line is gone; tap the target box for the job)
		var w := minf(S.x - col_w * 2.0, Data.OBJECTIVE_TAP_W)
		buttons["objective"] = Rect2((S.x - w) * 0.5, 144.0 - Data.OBJECTIVE_TAP_H * 0.5, w, Data.OBJECTIVE_TAP_H)

# ---------------------------------------------------------------- input
func _input(e: InputEvent) -> void:
	if not visible or space == null: return
	if e is InputEventScreenTouch:
		_layout()
		_objective_button()
		if e.pressed:
			for id in buttons:
				if (buttons[id] as Rect2).grow(3).has_point(e.position):
					owners[e.index] = id
					if (id.begins_with("cl_") and id != "cl_more") or id.begins_with("gun_"):   # v7.7: a list row: scroll on drag, pick on release
						_list_drag[e.index] = {"y": e.position.y, "s0": cl_scroll if id.begins_with("cl_") else gun_scroll, "side": "l" if id.begins_with("cl_") else "r", "moved": false, "id": id}
						get_viewport().set_input_as_handled()
						return
					held[id] = true
					Sfx.play("button", -14.0)
					if id == "radar": radar_pick = radar_pick_at(e.position)   # v1.4p: which blip the tap landed on, if any
					if id == "talk":   # v1.5j: held, not tapped
						talk_press()
						get_viewport().set_input_as_handled()
						return
					if id != "thrust" and id != "special": pressed.emit(id)   # THRUST and SPECIAL work while held
					get_viewport().set_input_as_handled()
					return
			if console_open:
				if contacts_rect().has_point(e.position) or msglog_rect().has_point(e.position):
					owners[e.index] = "comms_body"
					roster_idle = 0.0
					return   # v1.4n: a touch anywhere else flies the ship; LOG (or leaving it alone) closes the console
			if _mouse_in_kbm(e): return   # Job J: in keyboard + mouse mode the MOUSE flies (left-drag); real touches are unchanged
			var on_side: bool = stick_zone("move").has_point(e.position) or stick_zone("aim").has_point(e.position)
			var by_stick: bool = e.position.distance_to(_home("move")) < stick_r * 1.7 or e.position.distance_to(_home("aim")) < stick_r * 1.7
			if space.controls and not by_stick:   # v1.5g: tap a ship = target it (v1.8u: also at the sides of the screen, right on its box)
				var tapped: Node3D = space.ship_at_screen(e.position, Data.SHIP_TAP_STICK if on_side else -1.0)
				if tapped != null:
					space.pick_target(tapped)
					Sfx.play("button", -14.0)
					get_viewport().set_input_as_handled()
					return
			if stick_zone("move").has_point(e.position) and not owners.values().has("move"):
				owners[e.index] = "move"
				origins["move"] = e.position
			elif stick_zone("aim").has_point(e.position) and not owners.values().has("aim"):
				owners[e.index] = "aim"
				origins["aim"] = e.position
		else:
			var o: String = owners.get(e.index, "")
			owners.erase(e.index)
			if _list_drag.has(e.index):
				var ld: Dictionary = _list_drag[e.index]
				_list_drag.erase(e.index)
				if not ld["moved"]:
					Sfx.play("button", -14.0)
					pressed.emit(str(ld["id"]))
				get_viewport().set_input_as_handled()
				return
			if o == "move":
				move_vec = Vector2.ZERO
				origins.erase("move")
			elif o == "aim":
				aim_vec = Vector2.ZERO
				origins.erase("aim")
			elif o != "":
				held.erase(o)
				if o == "talk": talk_release()
	elif e is InputEventScreenDrag:
		if _list_drag.has(e.index):
			var ld2: Dictionary = _list_drag[e.index]
			var dy: float = e.position.y - float(ld2["y"])
			if absf(dy) > 10.0: ld2["moved"] = true
			if ld2["moved"]:
				var rh := CL_ROW_H if ld2["side"] == "l" else GUN_ROW_H
				var ns := clampi(int(ld2["s0"]) - int(round(dy / rh)), 0, list_max_scroll(ld2["side"]))
				if ld2["side"] == "l": cl_scroll = ns
				else: gun_scroll = ns
			get_viewport().set_input_as_handled()
			return
		var o2: String = owners.get(e.index, "")
		if o2 == "move": move_vec = ((e.position - origins["move"]) / stick_r).limit_length(1.0)
		elif o2 == "aim": aim_vec = ((e.position - origins["aim"]) / stick_r).limit_length(1.0)

func _process(dt: float) -> void:
	if OS.has_feature("web") and Engine.get_process_frames() % 30 == 0:   # v1.9: is the browser in full screen (for the FULL / EXIT label)
		fs_on = bool(JavaScriptBridge.eval("window.__hlFsIsOn ? window.__hlFsIsOn() : false", true))
	if space == null: return
	t += dt
	if vid != null and vid.is_playing() and str(slots["r"].get("video", "")) == "" and str(slots["l"].get("video", "")) == "": vid.stop()   # v1.7r: hung up: the clip stops
	_tick_scan(dt)
	_tick_talk(dt)
	msg_t = maxf(0.0, msg_t - dt)
	damage_flash = maxf(0.0, damage_flash - dt)
	for k in flash.keys(): flash[k] = maxf(0.0, float(flash[k]) - dt)
	var kb := Vector2(_axis("strafe_left", "strafe_right"), _axis("back", "forward"))
	var ka := Vector2(_axis("yaw_left", "yaw_right"), _axis("pitch_up", "pitch_down"))
	if kb.y == 0.0 and controls and controls.is_kbm() and not controls.blocked: kb.y = controls.wheel_throttle   # Job J: wheel throttle
	space.move = Vector2(move_vec.x, -move_vec.y) if kb == Vector2.ZERO else kb
	var a := aim_vec if ka == Vector2.ZERO else ka
	if a == Vector2.ZERO and controls: a = controls.mouse_steer(S)   # Job J: left-drag steer / mouse flight (keyboard + mouse only)
	space.aim = a * a.length()
	space.fire_held = controls.held("fire") if controls else Input.is_action_pressed("fire")   # Job J: right-click by default
	space.thrust_held = held.has("thrust") or (controls != null and controls.held("afterburner"))   # Job J: afterburner key (Tab)
	space.special_held = held.has("special") or (controls != null and controls.held("special"))   # v1.5o: SPECIAL (F)
	if console_open:
		if roster_closing:
			roster_t = maxf(0.0, roster_t - dt * 6.0)
			if roster_t <= 0.0:
				console_open = false
				_typer.visible = false
				_sync()
		else:
			roster_t = minf(1.0, roster_t + dt * 6.0)
			if not _typer.visible: roster_idle += dt
			if roster_idle > Data.COMMS_IDLE_CLOSE: close_roster() # rolls itself back up if you leave it
	if not console_open and slots["r"].get("mode", "") == "pick":   # v1.8q: the picked face goes when LOG rolls up
		pick = ""
		close_side("r")
	for side in ["l", "r"]:
		var sd: Dictionary = slots[side]
		if sd.is_empty(): continue
		sd["anim"] = minf(1.0, float(sd["anim"]) + dt * 4.0)
		if sd["mode"] == "incoming":
			sd["timer"] = float(sd["timer"]) - dt
			if sd["timer"] <= 0.0: close_side(side)
	queue_redraw()

## Job J: a held keyboard axis (paused while the Settings screen is open).
func _axis(neg: String, pos: String) -> float:
	if controls and controls.blocked: return 0.0
	return Input.get_axis(neg, pos)

## Job J: an emulated touch made by the MOUSE (not a finger) while in keyboard + mouse mode.
func _mouse_in_kbm(e: InputEvent) -> bool:
	return controls != null and controls.is_kbm() and e.device == InputEvent.DEVICE_ID_EMULATION

## Job J: which HUD button (if any) is under a screen point.
func button_at(p: Vector2) -> String:
	if not visible: return ""
	_layout()
	_objective_button()
	for id in buttons:
		if (buttons[id] as Rect2).grow(3).has_point(p): return id
	return ""

# ---------------------------------------------------------------- drawing helpers
var _boxes := {}   # v1.7q: one style box per look, made once (not a new one for every box, every frame)
func _box(r: Rect2, bg := PANEL, edge := EDGE, radius := 10, bw := 2) -> void:
	var key := Vector4i(bg.to_rgba32(), edge.to_rgba32(), radius, bw)
	var sb: StyleBoxFlat = _boxes.get(key)
	if sb == null:
		sb = StyleBoxFlat.new()
		sb.bg_color = bg
		sb.border_color = edge
		sb.set_border_width_all(bw)
		sb.set_corner_radius_all(radius)
		sb.corner_detail = 4   # (v1.7q: fewer points per rounded corner and no soft glow: much cheaper to draw every frame)
		if _boxes.size() > 400: _boxes.clear()
		_boxes[key] = sb
	draw_style_box(sb, r)

var _fit := {}   # v1.7q: label -> the size that fits its box
func _text(p: Vector2, txt: String, size := 18, col := WHITE, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	if size < Data.TEXT_BUMP_BELOW: size = maxi(Data.TEXT_MIN, size + Data.TEXT_BUMP)   # v1.4m: small print is a little bigger
	size = Data.ts(size)   # v1.7p: bigger for phones
	if width > 0.0:   # ...but a label in a box shrinks to fit it rather than being cut off (worked out once, remembered)
		var fk := "%s|%d|%d" % [txt, size, int(width)]
		if _fit.has(fk): size = _fit[fk]
		else:
			while size > 11 and font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width: size -= 1
			if _fit.size() > 2000: _fit.clear()
			_fit[fk] = size
	draw_string_outline(font, p, txt, align, width, size, 5, Color(0, 0.03, 0.08, 0.8))
	draw_string(font, p, txt, align, width, size, col)

func _icon(id: String, c: Vector2, s: float, col: Color) -> void:
	match id:
		"view":   # v7.1: a pilot seat
			draw_polyline(PackedVector2Array([c + Vector2(-s * 0.5, s), c + Vector2(-s * 0.55, -s * 0.2), c + Vector2(-s * 0.3, -s), c + Vector2(s * 0.3, -s), c + Vector2(s * 0.55, -s * 0.2), c + Vector2(s * 0.5, s)]), col, 2.5, true)
			draw_line(c + Vector2(-s * 0.9, s * 0.3), c + Vector2(s * 0.9, s * 0.3), col, 2.5)
			draw_line(c + Vector2(-s * 0.9, s), c + Vector2(s * 0.9, s), col, 2.5)
			return
		"goto":   # v7.1: a nav arrow
			draw_colored_polygon(PackedVector2Array([c + Vector2(s, -s), c + Vector2(-s * 0.15, s), c + Vector2(-s * 0.05, s * 0.05), c + Vector2(-s, -s * 0.15)]), col)
			return
		"fullscreen":   # four corner brackets
			for sx in [-1.0, 1.0]:
				for sy in [-1.0, 1.0]:
					var k := c + Vector2(sx, sy) * s
					draw_line(k, k - Vector2(sx * s * 0.7, 0), col, 3.0, true)
					draw_line(k, k - Vector2(0, sy * s * 0.7), col, 3.0, true)
		"ground":   # v1.8r: an arrow down onto a line
			draw_line(c + Vector2(-s * 1.1, s * 0.95), c + Vector2(s * 1.1, s * 0.95), col, 3.0, true)
			draw_line(c + Vector2(0, -s), c + Vector2(0, s * 0.3), col, 3.0, true)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.55, s * 0.05), c + Vector2(s * 0.55, s * 0.05), c + Vector2(0, s * 0.75)]), col)
		"special":   # v1.5o: a burst in a lock ring
			draw_arc(c, s * 0.95, 0, TAU, 28, col, 2.5, true)
			var pts := PackedVector2Array()
			for i in 16:
				var a := i * TAU / 16.0 - PI / 2
				pts.append(c + Vector2(cos(a), sin(a)) * (s * 0.7 if i % 2 == 0 else s * 0.3))
			draw_colored_polygon(pts, col)
		"shield":
			var pts := PackedVector2Array([c + Vector2(0, -s), c + Vector2(s * 0.85, -s * 0.62), c + Vector2(s * 0.72, s * 0.25), c + Vector2(0, s), c + Vector2(-s * 0.72, s * 0.25), c + Vector2(-s * 0.85, -s * 0.62), c + Vector2(0, -s)])
			draw_polyline(pts, col, 3.0, true)
			draw_polyline(PackedVector2Array([c + Vector2(0, -s * 0.6), c + Vector2(s * 0.5, -s * 0.36), c + Vector2(s * 0.42, s * 0.14), c + Vector2(0, s * 0.6)]), Color(col, 0.6), 2.0, true)
		"hull":
			draw_line(c + Vector2(-s * 0.7, s * 0.7), c + Vector2(s * 0.25, -s * 0.25), col, s * 0.28)
			draw_arc(c + Vector2(s * 0.45, -s * 0.45), s * 0.42, deg_to_rad(-20), deg_to_rad(250), 16, col, s * 0.2)
		"repair":
			_icon("hull", c, s, col)
		"energy":
			draw_rect(Rect2(c + Vector2(-s * 0.45, -s * 0.8), Vector2(s * 0.9, s * 1.7)), col, false, 3.0)
			draw_rect(Rect2(c + Vector2(-s * 0.2, -s * 0.98), Vector2(s * 0.4, s * 0.18)), col)
			draw_colored_polygon(PackedVector2Array([c + Vector2(s * 0.12, -s * 0.6), c + Vector2(-s * 0.25, s * 0.08), c + Vector2(0, s * 0.08), c + Vector2(-s * 0.12, s * 0.62), c + Vector2(s * 0.25, -s * 0.08), c + Vector2(0, -s * 0.08)]), col)
		"guns":
			for dx in [-s * 0.55, 0.0, s * 0.55]:
				draw_rect(Rect2(c + Vector2(dx - s * 0.16, -s * 0.5), Vector2(s * 0.32, s * 1.3)), col)
				draw_colored_polygon(PackedVector2Array([c + Vector2(dx - s * 0.16, -s * 0.5), c + Vector2(dx, -s * 1.0), c + Vector2(dx + s * 0.16, -s * 0.5)]), col)
		"missile":
			var dir := Vector2(1, -1).normalized()
			var perp := Vector2(-dir.y, dir.x)
			draw_line(c - dir * s * 0.8, c + dir * s * 0.55, col, s * 0.36)
			draw_colored_polygon(PackedVector2Array([c + dir * s * 0.95, c + dir * s * 0.5 + perp * s * 0.19, c + dir * s * 0.5 - perp * s * 0.19]), col)
			draw_colored_polygon(PackedVector2Array([c - dir * s * 0.55 + perp * s * 0.45, c - dir * s * 0.9, c - dir * s * 0.55 - perp * s * 0.45]), col)
		"mine":
			draw_circle(c, s * 0.62, col)
			draw_rect(Rect2(c + Vector2(-s * 1.0, -s * 0.1), Vector2(s * 2.0, s * 0.2)), Color(0.02, 0.07, 0.14))
			for k in 5: draw_circle(c + Vector2(-s * 0.5 + k * s * 0.25, s * 0.3), s * 0.08, Color(0.02, 0.07, 0.14))
			draw_rect(Rect2(c + Vector2(-s * 0.12, -s * 0.95), Vector2(s * 0.24, s * 0.35)), col)
		"heavy":
			var hdir := Vector2(1, -1).normalized()
			var hperp := Vector2(-hdir.y, hdir.x)
			draw_line(c - hdir * s * 0.85, c + hdir * s * 0.5, col, s * 0.56)
			draw_colored_polygon(PackedVector2Array([c + hdir * s * 1.05, c + hdir * s * 0.45 + hperp * s * 0.3, c + hdir * s * 0.45 - hperp * s * 0.3]), col)
			draw_colored_polygon(PackedVector2Array([c - hdir * s * 0.5 + hperp * s * 0.6, c - hdir * s * 0.95, c - hdir * s * 0.5 - hperp * s * 0.6]), col)
			draw_line(c - hdir * s * 0.1 + hperp * s * 0.3, c - hdir * s * 0.1 - hperp * s * 0.3, RED, 3.0)
		"tractor":
			# a beam cone pulling a crate in
			draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.2, -s * 0.85), c + Vector2(s * 0.2, -s * 0.85), c + Vector2(s * 0.75, s * 0.35), c + Vector2(-s * 0.75, s * 0.35)]), Color(col, 0.35))
			draw_rect(Rect2(c + Vector2(-s * 0.35, -s * 1.0), Vector2(s * 0.7, s * 0.25)), col)
			draw_rect(Rect2(c + Vector2(-s * 0.4, s * 0.3), Vector2(s * 0.8, s * 0.6)), GOLD)
			draw_rect(Rect2(c + Vector2(-s * 0.4, s * 0.3), Vector2(s * 0.8, s * 0.6)), Color(0.3, 0.2, 0.05), false, 2.0)
			for k in 3: draw_arc(c + Vector2(0, -s * 0.8), s * (0.45 + k * 0.35), deg_to_rad(60), deg_to_rad(120), 10, Color(col, 0.8), 2.0)
		"warp":
			for k in 3: draw_arc(c + Vector2(k * 1.5, 0), s * (0.35 + k * 0.28), deg_to_rad(40 + k * 60), deg_to_rad(330 + k * 60), 20, col, 3.0, true)
		"call":
			draw_arc(c + Vector2(s * 0.3, -s * 0.3), s * 0.85, deg_to_rad(92), deg_to_rad(178), 16, col, s * 0.42)
			draw_circle(c + Vector2(s * 0.28, s * 0.55), s * 0.3, col)
			draw_circle(c + Vector2(-s * 0.55, -s * 0.28), s * 0.3, col)
		"log":
			for k in 3:
				var hc := c + Vector2((k - 1) * s * 0.62, -s * 0.2 + (0 if k == 1 else s * 0.1))
				draw_circle(hc, s * 0.26, col)
				draw_arc(hc + Vector2(0, s * 0.62), s * 0.36, PI, TAU, 12, col, s * 0.28)
		"hangup":
			draw_arc(c + Vector2(0, s * 0.7), s * 0.95, deg_to_rad(215), deg_to_rad(325), 18, RED, s * 0.42)
			draw_circle(c + Vector2(-s * 0.8, s * 0.2), s * 0.3, RED)
			draw_circle(c + Vector2(s * 0.8, s * 0.2), s * 0.3, RED)
		"stop":
			draw_rect(Rect2(c - Vector2(s * 0.6, s * 0.6), Vector2(s * 1.2, s * 1.2)), col)
		"form":   # two arrows chasing each other: ship <-> mech
			draw_arc(c, s * 0.8, deg_to_rad(200), deg_to_rad(340), 16, col, 3.0, true)
			draw_arc(c, s * 0.8, deg_to_rad(20), deg_to_rad(160), 16, col, 3.0, true)
			var a1 := c + Vector2(cos(deg_to_rad(340)), sin(deg_to_rad(340))) * s * 0.8
			var a2 := c + Vector2(cos(deg_to_rad(160)), sin(deg_to_rad(160))) * s * 0.8
			draw_colored_polygon(PackedVector2Array([a1 + Vector2(-s * 0.35, -s * 0.1), a1 + Vector2(s * 0.25, -s * 0.05), a1 + Vector2(0, s * 0.4)]), col)
			draw_colored_polygon(PackedVector2Array([a2 + Vector2(s * 0.35, s * 0.1), a2 + Vector2(-s * 0.25, s * 0.05), a2 + Vector2(0, -s * 0.4)]), col)
		"zoom":   # v1.7z: a scope reticle with a plus
			draw_arc(c, s * 0.7, 0, TAU, 28, col, 3.0, true)
			for k in 4:
				var ang2 := k * PI / 2.0
				draw_line(c + Vector2(cos(ang2), sin(ang2)) * s * 0.35, c + Vector2(cos(ang2), sin(ang2)) * s * 0.95, col, 2.5)
			draw_circle(c, s * 0.1, col)
		"kill":
			draw_circle(c, s * 0.55, col, false, 3.0)
			for k in 4:
				var ang := k * PI / 2.0 + t * 0.0
				draw_line(c + Vector2(cos(ang), sin(ang)) * s * 0.55, c + Vector2(cos(ang), sin(ang)) * s * 0.9, col, 3.0)
			draw_line(c + Vector2(-s, -s * 0.9), c + Vector2(s, s * 0.9), RED, 3.0)
		"thrust":
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s), c + Vector2(s * 0.55, -s * 0.1), c + Vector2(s * 0.6, s * 0.45), c + Vector2(0, s * 0.95), c + Vector2(-s * 0.6, s * 0.45), c + Vector2(-s * 0.4, -s * 0.2)]), ORANGE)
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s * 0.3), c + Vector2(s * 0.3, s * 0.3), c + Vector2(0, s * 0.8), c + Vector2(-s * 0.3, s * 0.3)]), YELLOW)

## v1.5o SPECIAL button: locked until the hull is down to half (then critical); held while locked on.
func _special_button() -> void:
	var st: String = space.special_state
	var ready: String = space.special_ready()
	var sub := "HOLD"
	var cd := 0.0
	if st == "charging":   # v1.9c: hold to charge (missile locks build), let go to turn and fire
		var full: int = space.special_full()
		sub = "FULL · LET GO" if space.special_locks >= full else "CHARGE %d/%d" % [space.special_locks, full]
		cd = 1.0 - space.special_charge()
	elif st != "idle": sub = "FIRING"
	elif ready != "": sub = "LIGHTNING"   # v6.9: the electric storm
	elif ready == "": sub = "TAP · STICK"   # v1.9l (owner): until it arms, a tap is an evasive move (stick picks which)
	elif ready == "crit": sub = "CRITICAL · HOLD"
	var armed := ready != "" or st != "idle"
	var evade: bool = not armed and GS.form != "mech"
	if cockpit_texture() and GS.view == "cockpit": _icon_btn("special", "special", ORANGE, armed, "", 0.0, armed)   # (v7.6: else the console draws it)

## v7.5 (owner's UI sheet): the octagon-cut square frame for the action buttons: a thin inner line, a bright tab on top.
func _tech_square(f: Rect2, fill: Color, edge: Color, on: bool) -> void:
	var c := minf(f.size.x, f.size.y) * 0.16
	var pts := PackedVector2Array([f.position + Vector2(c, 0), Vector2(f.end.x - c, f.position.y), Vector2(f.end.x, f.position.y + c),
		Vector2(f.end.x, f.end.y - c), Vector2(f.end.x - c, f.end.y), Vector2(f.position.x + c, f.end.y), Vector2(f.position.x, f.end.y - c), Vector2(f.position.x, f.position.y + c)])
	draw_colored_polygon(pts, fill)
	draw_polyline(pts + PackedVector2Array([pts[0]]), edge, 3.0 if on else 2.0, true)
	var g := f.grow(-5.0)
	var c2 := c * 0.7
	var inner := PackedVector2Array([g.position + Vector2(c2, 0), Vector2(g.end.x - c2, g.position.y), Vector2(g.end.x, g.position.y + c2),
		Vector2(g.end.x, g.end.y - c2), Vector2(g.end.x - c2, g.end.y), Vector2(g.position.x + c2, g.end.y), Vector2(g.position.x, g.end.y - c2), Vector2(g.position.x, g.position.y + c2), g.position + Vector2(c2, 0)])
	draw_polyline(inner, Color(edge, 0.3), 1.0, true)
	draw_rect(Rect2(f.position.x + f.size.x * 0.3, f.position.y - 1.0, f.size.x * 0.4, 3.0), Color(edge, 0.95))

## v7.5 (owner's UI sheet): alert panels at the top: yellow WARNING when a missile is locked on you, red DANGER when
## the hull is critical. A cut frame, a title tab with ///, an icon box on the left and a strip of segments.
func _alerts() -> void:
	if space == null or not space.controls or space.player == null: return
	var list: Array = []
	var hk: float = GS.hull / maxf(GS.max_hull(), 1.0)
	if hk < 0.25: list.append(["DANGER", "Hull critical. Repair or get out.", RED, "danger", hk / 0.25])
	var inbound := 0
	for m in space.enemy_missiles:
		if not m.get("lost", false) and is_instance_valid(m["node"]): inbound += 1
	if inbound > 0 or space.missile_warn >= 0.0:
		var ln := "Missile lock. Evade!" if inbound <= 1 else "Missile lock: %d inbound. Evade!" % inbound
		if space.missile_warn >= 0.0: ln = "Missile %d m: %s" % [int(space.missile_warn), "BOOST SIDEWAYS NOW" if space.missile_warn < Data.DODGE_RANGE else "turn sideways"]
		list.append(["WARNING", ln, GOLD, "warning", 1.0])
	var y := 112.0
	for a in list:
		_alert_panel(Rect2(S.x * 0.5 - 170.0, y, 340.0, 62.0), a[0], a[1], a[2], a[3], a[4])
		y += 80.0

func _alert_panel(r: Rect2, title: String, line: String, col: Color, icon: String, level: float) -> void:
	var blink := fmod(t, 0.7) < 0.45
	var c := 12.0
	var pts := PackedVector2Array([r.position + Vector2(c, 0), Vector2(r.end.x - c, r.position.y), Vector2(r.end.x, r.position.y + c),
		Vector2(r.end.x, r.end.y - c), Vector2(r.end.x - c, r.end.y), Vector2(r.position.x + c, r.end.y), Vector2(r.position.x, r.end.y - c), Vector2(r.position.x, r.position.y + c)])
	draw_colored_polygon(pts, Color(0.02, 0.06, 0.1, 0.9))
	draw_polyline(pts + PackedVector2Array([pts[0]]), Color(col, 0.95 if blink else 0.6), 2.0, true)
	# title tab with ///
	var tx := r.position.x + 64.0
	var tab := PackedVector2Array([Vector2(tx, r.position.y - 14), Vector2(tx + 168, r.position.y - 14), Vector2(tx + 182, r.position.y + 8), Vector2(tx - 14, r.position.y + 8)])
	draw_colored_polygon(tab, col)
	_text(Vector2(tx + 4, r.position.y + 3), title, 15, Color(0.05, 0.05, 0.08), HORIZONTAL_ALIGNMENT_LEFT, 120)
	for k in 3: draw_line(Vector2(tx + 140 + k * 8, r.position.y + 4), Vector2(tx + 147 + k * 8, r.position.y - 10), Color(0.05, 0.05, 0.08), 3.0)
	# icon box
	var ib := Rect2(r.position + Vector2(8, 10), Vector2(46, 44))
	draw_rect(ib, Color(col, 0.12))
	draw_rect(ib, Color(col, 0.7), false, 1.5)
	var ic := ib.get_center()
	if icon == "warning":
		draw_polyline(PackedVector2Array([ic + Vector2(0, -15), ic + Vector2(16, 13), ic + Vector2(-16, 13), ic + Vector2(0, -15)]), col, 3.0, true)
		draw_line(ic + Vector2(0, -5), ic + Vector2(0, 4), col, 3.0)
		draw_circle(ic + Vector2(0, 9), 2.0, col)
	else:
		draw_arc(ic, 15, 0, TAU, 32, col, 2.5, true)
		for k in 3:
			var a0 := -PI / 2 + k * TAU / 3.0 - 0.45
			var fan := PackedVector2Array([ic])
			for j in 7: fan.append(ic + Vector2.from_angle(a0 + j * 0.15) * 12.0)
			draw_colored_polygon(fan, col)
		draw_circle(ic, 3.5, Color(0.02, 0.06, 0.1))
	_text(Vector2(r.position.x + 64, r.position.y + 34), line, 14, WHITE, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 74)
	for k in 8:   # the segment strip
		var sr := Rect2(r.position.x + 64 + k * 16, r.end.y - 14, 12, 6)
		if (k + 1) / 8.0 <= maxf(level, 0.13): draw_rect(sr, col)
		else: draw_rect(sr, Color(col, 0.6), false, 1.0)

## v7.5 (owner): the super meter. A slanted-stripe bar that fills while you fight (hits you land and take); the orb at
## its end pulses gold when full: tap it for the lightning storm. Until then a tap is an evasive move.
func _super_meter(armed: bool) -> void:
	var g := dash_geo()
	var r: Rect2 = g["super"]
	var oc: Vector2 = g["orb_c"]
	var orr: float = g["orb_r"]
	var k: float = clampf(GS.super_charge, 0.0, 1.0)
	var pulse := 0.5 + 0.5 * sin(t * 6.0)
	var col := GOLD if armed else CYAN
	_dash_frame(Rect2(r.position - Vector2(6, 4), r.size + Vector2(12, 8)), Color(col, 0.8))
	var n := 22
	var sw := r.size.x / n
	var sk := r.size.y * 0.55
	for i in n:
		var x := r.position.x + i * sw
		var lit := (i + 1) / float(n) <= k + 0.001
		var c2 := Color(GOLD.lerp(WHITE, pulse * 0.4), 1.0) if armed else (Color(0.3, 0.75, 1.0, 0.95) if lit else Color(0.1, 0.18, 0.26, 0.8))
		draw_colored_polygon(PackedVector2Array([Vector2(x + sk, r.position.y), Vector2(x + sw - 2.0 + sk, r.position.y), Vector2(x + sw - 2.0, r.end.y), Vector2(x, r.end.y)]), c2)
	draw_line(Vector2(r.end.x + 6.0, oc.y), oc - Vector2(orr, 0), Color(col, 0.8), 2.0)
	draw_circle(oc, orr + 3.0, Color(0.01, 0.05, 0.1, 0.9))
	if armed:
		draw_circle(oc, orr + 4.0 + pulse * 6.0, Color(GOLD, 0.25 * (1.0 - pulse)))
		draw_circle(oc, orr - 3.0, Color(GOLD.darkened(0.2), 0.55 + 0.35 * pulse))
	draw_arc(oc, orr, -PI / 2, -PI / 2 + TAU * k, 40, Color(col, 1.0), 3.5, true)
	draw_arc(oc, orr, 0, TAU, 40, Color(col, 0.35), 1.5, true)
	_icon("special", oc, orr * 0.5, WHITE if armed else Color(CYAN_HI, 0.8))

func _draw_special() -> void:
	if space == null: return
	var st: String = space.special_state
	if st == "charging" and is_instance_valid(space.special_target):
		var cam := get_viewport().get_camera_3d()
		var p: Vector3 = space.special_target.global_position
		if cam and not cam.is_position_behind(p):
			var c := cam.unproject_position(p)
			var k: float = space.special_charge()
			var rr := lerpf(70.0, 30.0, k)
			draw_arc(c, rr, -PI / 2, -PI / 2 + TAU * k, 48, GOLD, 4.0, true)
			for i in 4:
				var a := i * PI / 2 + t * 2.0
				draw_line(c + Vector2(cos(a), sin(a)) * (rr + 6), c + Vector2(cos(a), sin(a)) * (rr + 18), Color(GOLD, 0.9), 3.0)
			_text(c + Vector2(-130, rr + 34), ("%d MISSILE%s · LET GO TO FIRE" % [space.special_locks, "" if space.special_locks == 1 else "S"]) if space.special_locks > 0 else "CHARGING", 15, GOLD, HORIZONTAL_ALIGNMENT_CENTER, 260)
	if st != "cutin": return
	# the cut-in: a slanted band across the middle, the pilot large on it, "SPECIAL ATTACK"; bars and buttons stay visible
	var k := clampf(space.special_t / Data.SPECIAL_CUTIN_TIME, 0.0, 1.0)
	var slide := clampf(k * 5.0, 0.0, 1.0) * (1.0 - clampf((k - 0.85) * 6.7, 0.0, 1.0))
	var h := S.y * 0.34
	var y := S.y * 0.5 - h * 0.5
	var sk := h * 0.35
	var x0 := lerpf(-S.x, 0.0, slide)
	var band := PackedVector2Array([Vector2(x0 + sk, y), Vector2(x0 + S.x + sk, y), Vector2(x0 + S.x - sk, y + h), Vector2(x0 - sk, y + h)])
	draw_colored_polygon(band, Color(0.02, 0.05, 0.12, 0.82 * slide))
	draw_polyline(PackedVector2Array([band[0], band[1]]), Color(GOLD, slide), 4.0)
	draw_polyline(PackedVector2Array([band[3], band[2]]), Color(GOLD, slide), 4.0)
	for i in 6:   # speed lines
		var ly := y + h * (0.15 + i * 0.14)
		var lx := fmod(t * 1400.0 + i * 260.0, S.x + 400.0) - 200.0
		draw_line(Vector2(lx, ly), Vector2(lx + 180, ly), Color(1, 1, 1, 0.25 * slide), 2.0)
	# v1.5q (owner): the character's picture big in the middle of the screen, framed, the words under it
	var fsz := S.y * 0.46 * (0.85 + 0.15 * slide)
	var face_r := Rect2(Vector2(S.x * 0.5 - fsz * 0.5, S.y * 0.40 - fsz * 0.5), Vector2(fsz, fsz))
	draw_rect(face_r.grow(8), Color(0.02, 0.05, 0.12, 0.92 * slide))
	var tex: Texture2D = _face_tex(Data.PLAYER_PILOT_FACE, "normal") if Data.PLAYER_PILOT_FACE != "" else null
	if tex: draw_texture_rect(tex, face_r, false, Color(1, 1, 1, slide))
	else:   # no picture: a helmeted silhouette
		var fc := face_r.get_center()
		var fs := face_r.size.x * 0.32
		draw_circle(fc + Vector2(0, -fs * 0.2), fs, Color(0.1, 0.16, 0.26, slide))
		draw_colored_polygon(PackedVector2Array([fc + Vector2(-fs * 0.75, -fs * 0.3), fc + Vector2(fs * 0.75, -fs * 0.3), fc + Vector2(fs * 0.55, fs * 0.05), fc + Vector2(-fs * 0.55, fs * 0.05)]), Color(0.45, 0.85, 1.0, 0.9 * slide))
	draw_rect(face_r.grow(8), Color(GOLD, slide), false, 4.0)
	var crit: bool = space.special_which == "crit"
	_text(Vector2(0, face_r.end.y + 46), "SPECIAL ATTACK", 44, Color(GOLD, slide), HORIZONTAL_ALIGNMENT_CENTER, S.x)
	_text(Vector2(0, face_r.end.y + 72), "LAST STAND" if crit else "LOCK CONFIRMED", 22, Color(RED if crit else CYAN, slide), HORIZONTAL_ALIGNMENT_CENTER, S.x)

## One big corner button: raised face, icon, label, optional count badge and cooldown ring.
func _corner(id: String, label: String, icon: String, col: Color, active := false, badge := "", cd := 0.0, locked := false, sub := "") -> void:
	if not buttons.has(id): return
	var r: Rect2 = buttons[id]
	var down := held.has(id) or float(flash.get(id, 0.0)) > 0.3
	var on := down or active
	var f := Rect2(r.position + (Vector2(0, 3) if down else Vector2.ZERO), r.size)
	_tech_square(f, Color(col.darkened(0.45), 0.92) if on else Color(0.02, 0.08, 0.15, 0.88), Color(col, 1.0) if on else Color(col, 0.8), on)
	var small := f.size.x < 92.0   # v7.6 (owner: clean and tight): console buttons show an icon and a name only
	if small: sub = ""
	_icon(icon, f.position + Vector2(f.size.x * 0.5, f.size.y * (0.36 if small and label.length() > 9 and label.find(" ") > 0 else 0.42)), f.size.x * 0.19, col.lightened(0.25) if icon != "tractor" else col)
	var fs := clampi(int(f.size.x * 0.145), 10, 15)
	if small and label.length() > 9 and label.find(" ") > 0:   # v7.7: SHIELD REPAIR / HULL REPAIR on two lines
		var sp := label.find(" ")
		_text(Vector2(f.position.x, f.end.y - 9 - fs), label.substr(0, sp), fs, WHITE, HORIZONTAL_ALIGNMENT_CENTER, f.size.x)
		_text(Vector2(f.position.x, f.end.y - 7), label.substr(sp + 1), fs, WHITE, HORIZONTAL_ALIGNMENT_CENTER, f.size.x)
	else: _text(Vector2(f.position.x, f.end.y - (22 if sub != "" else 9)), label, fs, WHITE, HORIZONTAL_ALIGNMENT_CENTER, f.size.x)
	if sub != "": _text(Vector2(f.position.x, f.end.y - 7), sub, 11, Color(col.lightened(0.35), 0.95), HORIZONTAL_ALIGNMENT_CENTER, f.size.x)
	if badge != "":
		var bc := f.position + Vector2(f.size.x - 17, 17)
		var empty := badge == "0" or badge == "00"
		draw_circle(bc, 14, RED if empty else Color(0.02, 0.07, 0.14))
		draw_arc(bc, 14, 0, TAU, 24, Color(col, 0.9), 2.0, true)
		_text(bc + Vector2(-14, 6), badge, 15, WHITE, HORIZONTAL_ALIGNMENT_CENTER, 28)
	if cd > 0.0:
		draw_arc(f.get_center(), f.size.x * 0.46, -PI / 2, -PI / 2 + TAU * (1.0 - cd), 40, Color(WHITE, 0.8), 3.0, true)
	if locked:
		draw_rect(f, Color(0, 0, 0, 0.62))
		_text(Vector2(f.position.x, f.get_center().y + 6), "LOCKED", 14, GOLD, HORIZONTAL_ALIGNMENT_CENTER, f.size.x)

## v1.8y (owner): the planet map: the sectors (with their land), every base (tap one = fly there), you, and the job.
func planet_map_rect() -> Rect2:
	var side := minf(S.y - 40.0, S.x * 0.62)
	return Rect2(S.x * 0.5 - side * 0.5, S.y * 0.5 - side * 0.5, side, side)

func _pmap_point(mr: Rect2, t: int, x: float, z: float) -> Vector2:
	var g := Surface.grid(space.planet_id)
	var inner := Rect2(mr.position + Vector2(10, 52), mr.size - Vector2(20, 62))
	var cell := inner.size / float(g)
	return inner.position + Vector2((t % g) + (x + Surface.EDGE) / Surface.TILE, (t / g) + (z + Surface.EDGE) / Surface.TILE) * cell

func _planet_map() -> void:
	var mr := planet_map_rect()
	var pid: String = space.planet_id
	var g := Surface.grid(pid)
	_box(mr, Color(0.01, 0.05, 0.1, 0.94), Color(CYAN, 0.8), 12, 2)
	_text(mr.position + Vector2(14, 32), "%s  ·  PLANET MAP" % str(Surface.PLANETS[pid]["name"]).to_upper(), 20, WHITE)
	_pill("pmap_close", "CLOSE", false, CYAN)
	var inner := Rect2(mr.position + Vector2(10, 52), mr.size - Vector2(20, 62))
	var cell := inner.size / float(g)
	for t2 in g * g:
		var cr := Rect2(inner.position + Vector2(t2 % g, t2 / g) * cell, cell)
		var b: Dictionary = Surface.biome(pid, t2)
		draw_rect(cr.grow(-2), Color((b.get("horizon", Color(0.3, 0.4, 0.5)) as Color).darkened(0.55), 0.9))
		if t2 == space.tile: draw_rect(cr.grow(-2), Color(CYAN, 0.9), false, 2.0)
		_text(cr.position + Vector2(6, 18), "%s%d %s" % ["ABCDEFG"[t2 / g], t2 % g + 1, str(b.get("name", "")).to_upper()], 12, Color(1, 1, 1, 0.75))
	var mi: Dictionary = GS.mission   # the job's point, when it is down here
	if mi.get("kind", "") == "ground" and str(mi.get("planet", "")) == pid and int(mi.get("stage", 0)) < (mi.get("points", []) as Array).size():
		var mp: Dictionary = mi["points"][int(mi["stage"])]
		var mv := _pmap_point(mr, int(mi["tile"]), float(mp["x"]), float(mp["z"]))
		draw_colored_polygon(PackedVector2Array([mv + Vector2(0, -9), mv + Vector2(9, 0), mv + Vector2(0, 9), mv + Vector2(-9, 0)]), GOLD)
		_text(mv + Vector2(12, 5), "JOB", 13, GOLD)
	var spots: Array = space.base_spots()
	for i in spots.size():
		var bp := _pmap_point(mr, int(spots[i]["tile"]), float(spots[i]["x"]), float(spots[i]["z"]))
		var on: bool = held.has("pmap_b%d" % i) or (not space.surf_goal.is_empty() and str(space.surf_goal.get("name", "")) == str(spots[i]["name"]))
		draw_circle(bp, 7.0, GREEN if not on else GOLD)
		draw_arc(bp, 11.0, 0, TAU, 20, Color(GREEN, 0.7), 2.0)
		_text(bp + Vector2(-70, 26), str(spots[i]["name"]), 12, WHITE, HORIZONTAL_ALIGNMENT_CENTER, 140)
	var pp: Vector3 = space.player.global_position   # you: an arrow the way you face
	var yv := _pmap_point(mr, space.tile, pp.x, pp.z)
	var f3: Vector3 = -space.player.global_basis.z
	var f2 := Vector2(f3.x, f3.z).normalized()
	if f2 == Vector2.ZERO: f2 = Vector2.UP
	var sd := Vector2(-f2.y, f2.x)
	draw_colored_polygon(PackedVector2Array([yv + f2 * 12.0, yv - f2 * 7.0 + sd * 7.0, yv - f2 * 7.0 - sd * 7.0]), CYAN_HI)
	_text(Vector2(mr.position.x, mr.end.y - 8), "Tap a base to fly there (GO TO).", 12, Color(1, 1, 1, 0.6), HORIZONTAL_ALIGNMENT_CENTER, mr.size.x)

## v1.8q: a spare button: the frame, a small padlock, its name if it has one.
func _padlocked(id: String, label: String) -> void:
	if not buttons.has(id): return
	var r: Rect2 = buttons[id]
	var down := held.has(id)
	var f := Rect2(r.position + (Vector2(0, 4) if down else Vector2.ZERO), r.size)
	_box(f, Color(0.03, 0.07, 0.12, 0.8), Color(0.5, 0.6, 0.7, 0.55), 14, 2)
	var c := f.position + Vector2(f.size.x * 0.5, f.size.y * (0.42 if label != "" else 0.5))
	var s := f.size.x * 0.13
	var col := Color(0.75, 0.82, 0.9, 0.85)
	draw_arc(c + Vector2(0, -s * 0.5), s * 0.62, PI, TAU, 14, col, 3.0, true)
	draw_rect(Rect2(c + Vector2(-s, -s * 0.5), Vector2(s * 2.0, s * 1.5)), col)
	draw_circle(c + Vector2(0, s * 0.2), s * 0.22, Color(0.03, 0.07, 0.12))
	if label != "": _text(Vector2(f.position.x, f.end.y - 11), label, 14, Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_CENTER, f.size.x)

## Freelancer-style status: segmented colour bars, no numbers. Shield blue, hull green→yellow→red, energy gold.
## v7.0 (owner mockup): COMMS sits above the aim stick, on the right.
func comms_rect() -> Rect2:
	var h := _home("aim")
	return Rect2(h.x - 70, h.y - stick_r - 62, 140, 42)

## v7.0 (owner): weapons and abilities pop up only when you fight. They show while hostiles are engaging you, or when
## you open them (WEAPONS); otherwise only the flight row (engine, stop, thrust, warp) stays on screen.
var weapons_open := false
var weapons_pinned := false   # (the route test keeps every button up)
const COMBAT_IDS := ["ground"]   # (v7.6: the rest live on the console; v7.8 owner: TRACTOR always shows)   # (v7.5: SPECIAL is the super meter on the dash)
func weapons_shown() -> bool:
	return weapons_pinned or weapons_open or (space != null and is_instance_valid(space.player) and space.hostiles_engaged() > 0)

func _status_bars(at := Rect2(), pct := false) -> void:
	var w := clampf(S.x - (8 + _block_w() + 14) * 2 - 60, 220.0, 420.0)
	var x := S.x * 0.5 - w * 0.5 + 16
	var y0 := 6.0
	if at != Rect2():   # v6.9: drawn on the dash
		w = at.size.x - 44.0
		x = at.position.x + 38.0
		y0 = at.position.y
	var rows := [["shield", GS.shield / GS.max_shield(), Color(0.35, 0.7, 1.0)],
		["hull", GS.hull / GS.max_hull(), _hull_col(GS.hull / GS.max_hull())],
		["energy", GS.energy / Data.ENERGY_MAX, YELLOW]]
	_box(Rect2(x - 38, y0, w + 44, 66), Color(0.01, 0.05, 0.1, 0.72), Color(CYAN, 0.45), 10, 1)
	# (v1.8q, owner: the round green ship picture beside the bars is gone; the hull bar already shows left / core / right)
	for k in 3:
		var y := y0 + 6.0 + k * 20.0
		var v: float = clampf(rows[k][1], 0.0, 1.0)
		var col: Color = rows[k][2]
		var low := v < 0.25 and k < 2 and fmod(t, 0.6) < 0.3
		_icon(rows[k][0], Vector2(x - 18, y + 7), 7.0, RED if low else col)
		if pct: _text(Vector2(x + w - 40, y + 13), "%d%%" % int(round(v * 100.0)), 12, WHITE, HORIZONTAL_ALIGNMENT_RIGHT, 40)
		if k == 1:
			_three_part(Rect2(Vector2(x, y + 2), Vector2(w - (52 if pct else 8), 11)), GS.wing_l / GS.wing_max(), v, GS.wing_r / GS.wing_max(), low)
			continue
		var segs := 20
		var sw := (w - (52 if pct else 8)) / segs
		for i in segs:
			var fill := clampf(v * segs - i, 0.0, 1.0)
			var sr := Rect2(Vector2(x + i * sw, y + 2), Vector2(sw - 2, 11))
			draw_rect(sr, Color(col, 0.14))
			if fill > 0.0: draw_rect(Rect2(sr.position, Vector2(sr.size.x * fill, sr.size.y)), RED if low else col)

func _square(id: String, label: String, active := false, col := CYAN, sub := "") -> void:
	if not buttons.has(id): return
	var r: Rect2 = buttons[id]
	var on := held.has(id) or active
	_box(r, Color(col, 0.32) if on else PANEL, Color(col, 0.95) if on else EDGE, 10, 2)
	_icon(id, r.position + Vector2(r.size.x * 0.5, 28), 15.0, col if id != "hangup" else RED)
	_text(Vector2(r.position.x, r.end.y - (20 if sub != "" else 10)), label, 15, WHITE, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	if sub != "": _text(Vector2(r.position.x, r.end.y - 5), sub, 10, Color(col.lightened(0.3), 0.95), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)

func _pill(id: String, label: String, active := false, col := CYAN, sub := "") -> void:
	if not buttons.has(id): return
	var r: Rect2 = buttons[id]
	if id in ["dock", "lane", "jump", "land", "launch"] and r.position.y < 20.0:   # v7.6 (owner's mockup): « DOCK • LIBERTY HUB »
		_prompt_pill(r, label + ("  •  " + sub if sub != "" else ""), col, held.has(id) or active)
		return
	var on := held.has(id) or active
	_box(r, Color(col, 0.35) if on else PANEL, Color(col, 0.95 if on else 0.65), 10, 2)
	var y := r.size.y * 0.5 + (6.0 if sub == "" else 0.0)
	_text(r.position + Vector2(0, y), label, 16, WHITE, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	if sub != "": _text(r.position + Vector2(0, y + 15), sub, 11, Color(col.lightened(0.2), 0.95), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)

func _prompt_pill(r: Rect2, txt: String, col: Color, on: bool) -> void:
	var c := r.size.y * 0.5
	var pts := PackedVector2Array([r.position + Vector2(c, 0), Vector2(r.end.x - c, r.position.y), Vector2(r.end.x, r.position.y + c),
		Vector2(r.end.x - c, r.end.y), Vector2(r.position.x + c, r.end.y), Vector2(r.position.x, r.position.y + c)])
	draw_colored_polygon(pts, Color(col.darkened(0.7), 0.85 if on else 0.7))
	draw_polyline(pts + PackedVector2Array([pts[0]]), Color(col, 0.95), 2.0, true)
	var pulse := 0.5 + 0.5 * sin(t * 4.0)
	for sgn in [-1.0, 1.0]:
		for k in 2:
			var x: float = (r.position.x - 10.0 - k * 10.0) if sgn < 0 else (r.end.x + 10.0 + k * 10.0)
			var cy := r.position.y + c
			draw_polyline(PackedVector2Array([Vector2(x - sgn * -6.0, cy - 9), Vector2(x + sgn * 4.0, cy), Vector2(x - sgn * -6.0, cy + 9)]), Color(col, 0.5 + 0.5 * pulse), 2.5, true)
	_text(Vector2(r.position.x, r.position.y + c + 6), txt.to_upper(), 16, WHITE, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)

func _stick(which: String, label: String) -> void:
	# v7.6 (owner's mockup): a thick ring in four glowing segments round a thin inner ring, a diamond for the knob
	var active := owners.values().has(which)
	var c: Vector2 = origins.get(which, _home(which))
	var v := move_vec if which == "move" else aim_vec
	var R := stick_r
	draw_circle(c, R, Color(0.01, 0.06, 0.12, 0.45 if active else 0.3))
	for k in 4:
		var a0 := k * TAU / 4.0 - PI / 4.0 + 0.12
		draw_arc(c, R - 4.0, a0, a0 + TAU / 4.0 - 0.24, 24, Color(CYAN, 0.95 if active else 0.75), 7.0, true)
		draw_arc(c, R + 4.0, a0 + 0.3, a0 + TAU / 4.0 - 0.54, 16, Color(CYAN, 0.35), 2.0, true)
	draw_arc(c, R * 0.66, 0, TAU, 56, Color(CYAN, 0.5), 2.0, true)
	var knob := c + v * R * 0.55
	var d := R * 0.34
	var dia := PackedVector2Array([knob + Vector2(0, -d), knob + Vector2(d, 0), knob + Vector2(0, d), knob + Vector2(-d, 0)])
	draw_colored_polygon(dia, Color(0.2, 0.55, 0.85, 0.75 if active else 0.55))
	draw_polyline(dia + PackedVector2Array([dia[0]]), Color(CYAN_HI, 0.95), 3.0, true)
	var d2 := d * 0.62
	draw_polyline(PackedVector2Array([knob + Vector2(0, -d2), knob + Vector2(d2, 0), knob + Vector2(0, d2), knob + Vector2(-d2, 0), knob + Vector2(0, -d2)]), Color(WHITE, 0.4), 1.5, true)

func _screen(p3: Vector3) -> Variant:
	var cam: Camera3D = space.cam
	if cam.is_position_behind(p3): return null
	return cam.unproject_position(p3)

# ---------------------------------------------------------------- cockpit frame
var _cockpit_tex: Texture2D
const COCKPIT_PATH := "res://assets/cockpit/cockpit_b.png"
## The owner's cockpit art (cockpit pack): glass keyed out so space shows through. 1280 x 720, scaled to cover the
## screen and anchored to the bottom so the dashboard always shows.
## Scaled up 1.3x and pushed down so the dashboard sits low and you see more space; the spare margin lets the
## cockpit slide the opposite way when you look around (free-look), without showing its edges.
const COCKPIT_SCALE := 1.3
func cockpit_rect() -> Rect2:
	var sc := maxf(S.x / 1280.0, S.y / 720.0) * COCKPIT_SCALE
	var sz := Vector2(1280.0, 720.0) * sc
	var base := Vector2((S.x - sz.x) * 0.5, S.y - 4.0 - sz.y * 0.82)   # centre dash screen's bottom edge on the screen bottom
	var lk: Vector2 = space.look if space else Vector2.ZERO
	var mx := (sz.x - S.x) * 0.5 * 0.85
	base += Vector2(-lk.x * mx, clampf(-lk.y * 70.0, -40.0, maxf(0.0, -base.y)))
	return Rect2(base, sz)

## v1.7z: the scope view: a dark armoured frame round a clear window, cyan corner brackets and side lights, a reticle.
func _scope() -> void:
	var w := Rect2(S * Vector2(0.21, 0.17), S * Vector2(0.58, 0.66))
	var dark := Color(0.03, 0.04, 0.05, 0.96)
	draw_rect(Rect2(0, 0, S.x, w.position.y), dark)
	draw_rect(Rect2(0, w.end.y, S.x, S.y - w.end.y), dark)
	draw_rect(Rect2(0, w.position.y, w.position.x, w.size.y), dark)
	draw_rect(Rect2(w.end.x, w.position.y, S.x - w.end.x, w.size.y), dark)
	draw_rect(w.grow(10), Color(0.16, 0.17, 0.19), false, 14.0)
	draw_rect(w.grow(3), Color(0.08, 0.09, 0.1), false, 4.0)
	var c := CYAN
	var L := minf(w.size.x, w.size.y) * 0.16
	for corner in [w.position, Vector2(w.end.x, w.position.y), w.end, Vector2(w.position.x, w.end.y)]:
		var sx := 1.0 if corner.x < w.get_center().x else -1.0
		var sy := 1.0 if corner.y < w.get_center().y else -1.0
		var p0: Vector2 = corner + Vector2(sx, sy) * 18.0
		draw_line(p0, p0 + Vector2(sx * L, 0), c, 4.0)
		draw_line(p0, p0 + Vector2(0, sy * L), c, 4.0)
	for side in [-1.0, 1.0]:   # glowing side lights
		var x: float = w.position.x - 24.0 if side < 0.0 else w.end.x + 16.0
		draw_rect(Rect2(x, w.get_center().y - w.size.y * 0.18, 8, w.size.y * 0.36), Color(c, 0.85))
	var m := w.get_center()
	var r := minf(w.size.x, w.size.y) * 0.13
	draw_arc(m, r, 0, TAU, 40, c, 3.0, true)
	for k in 4:
		var d := Vector2.RIGHT.rotated(k * PI / 2.0)
		draw_line(m + d * r * 0.45, m + d * r * 1.9, c, 2.5)
	draw_circle(m, 4.0, c, false, 2.0)

func cockpit_texture() -> Texture2D:
	if GS.form == "mech": return null   # v1.7z: the mech's first-person view has no ship cockpit around it
	if _cockpit_tex == null and ResourceLoader.exists(COCKPIT_PATH): _cockpit_tex = load(COCKPIT_PATH)
	return _cockpit_tex

func _cockpit() -> void:
	var tex := cockpit_texture()
	if tex:
		var cr := cockpit_rect()
		draw_texture_rect(tex, cr, false)
		_cockpit_instruments(cr)
		return
	_cockpit_old()

## Cockpit-view instruments: the centre dash screen becomes the radar; heading tape, SPD and ALT/RNG bars and a
## ring reticle on the glass (like the owner's concept).
func _cockpit_instruments(cr: Rect2) -> void:
	var scr := Rect2(cr.position + cr.size * Vector2(0.433, 0.66), cr.size * Vector2(0.136, 0.155))
	_radar(scr.get_center(), minf(scr.size.x, scr.size.y) * 0.46, false)
	var c := S * 0.5
	var col := Color(0.55, 0.88, 1.0, 0.9)
	# heading tape
	var hdg := fposmod(rad_to_deg(-space.yaw), 360.0)
	var ty := c.y - 98.0   # between the DOCK / WARP GATE button and the reticle
	var span := 40.0
	var px := 260.0 / span
	draw_line(Vector2(c.x - 130, ty + 8), Vector2(c.x + 130, ty + 8), Color(col, 0.6), 1.5)
	var start := int(floor((hdg - span * 0.5) / 5.0)) * 5
	for k in range(start, int(hdg + span * 0.5) + 1, 5):
		var x := c.x + (k - hdg) * px
		if absf(x - c.x) > 130.0: continue
		var big := k % 10 == 0
		draw_line(Vector2(x, ty + 8), Vector2(x, ty + (0.0 if big else 4.0)), col, 1.5)
		if big and absf(x - c.x) > 18.0: _text(Vector2(x - 20, ty - 4), "%03d" % posmod(k, 360), 11, col, HORIZONTAL_ALIGNMENT_CENTER, 40)
	_box(Rect2(c.x - 24, ty - 18, 48, 20), Color(0.02, 0.08, 0.16, 0.8), col, 4, 1)
	_text(Vector2(c.x - 24, ty - 3), "%03d" % int(hdg), 13, WHITE, HORIZONTAL_ALIGNMENT_CENTER, 48)
	draw_colored_polygon(PackedVector2Array([Vector2(c.x - 5, ty + 10), Vector2(c.x + 5, ty + 10), Vector2(c.x, ty + 16)]), col)
	# speed (left) and altitude / range (right) bars
	var top_speed: float = float(GS.ship()["speed"]) * Data.THRUST_MULT
	_cockpit_bar(Vector2(c.x - 170, c.y), "SPD", "%d m/s" % int(space.speed_now), clampf(space.speed_now / top_speed, 0.0, 1.0), col, true)
	var right_lbl := "RNG"
	var right_val := "—"
	var right_k := 0.0
	if space.surface_mode:
		right_lbl = "ALT"
		right_val = "%d m" % int(space.altitude)
		right_k = clampf(space.altitude / Surface.CEILING, 0.0, 1.0)
	elif space.target and is_instance_valid(space.target):
		var dd: float = space.distance_to(space.target)
		right_val = _dist(dd)
		right_k = clampf(dd / 3000.0, 0.0, 1.0)
	_cockpit_bar(Vector2(c.x + 170, c.y), right_lbl, right_val, right_k, col, false)

func _cockpit_bar(p: Vector2, lbl: String, val: String, k: float, col: Color, left: bool) -> void:
	var h := 150.0
	var r := Rect2(p - Vector2(4, h * 0.5), Vector2(8, h))
	draw_rect(r, Color(col, 0.18))
	draw_rect(Rect2(Vector2(r.position.x, r.end.y - h * k), Vector2(8, h * k)), col)
	for i in 6: draw_line(Vector2(r.position.x - 4, r.position.y + i * h / 5.0), Vector2(r.end.x + 4, r.position.y + i * h / 5.0), Color(col, 0.6), 1)
	var tx := r.position.x - 92 if left else r.end.x + 10
	_text(Vector2(tx, p.y - 8), lbl, 12, col, HORIZONTAL_ALIGNMENT_RIGHT if left else HORIZONTAL_ALIGNMENT_LEFT, 82)
	_text(Vector2(tx, p.y + 14), val, 17, WHITE, HORIZONTAL_ALIGNMENT_RIGHT if left else HORIZONTAL_ALIGNMENT_LEFT, 82)

func _cockpit_old() -> void:
	var w := S.x
	var h := S.y
	var shell := Color(0.5, 0.54, 0.6)
	var shell_lt := Color(0.72, 0.75, 0.8)
	var metal := Color(0.13, 0.15, 0.2)
	var orange := Color(1.0, 0.62, 0.2)
	for side in [-1.0, 1.0]:
		var x0: float = w * 0.5 + side * (w * 0.5 - col_w - 8)
		draw_colored_polygon(PackedVector2Array([Vector2(x0, 0), Vector2(x0 - side * 26, 0), Vector2(x0 - side * w * 0.1, h * 0.62), Vector2(x0 - side * w * 0.06, h * 0.64), Vector2(x0, h * 0.3)]), shell)
		draw_line(Vector2(x0 - side * 16, h * 0.02), Vector2(x0 - side * w * 0.085, h * 0.6), Color(orange, 0.95), 4)
	var top := h * 0.66
	draw_colored_polygon(PackedVector2Array([Vector2(col_w, h * 0.72), Vector2(w * 0.3, top), Vector2(w * 0.7, top), Vector2(w - col_w, h * 0.72), Vector2(w - col_w, h), Vector2(col_w, h)]), shell_lt)
	draw_colored_polygon(PackedVector2Array([Vector2(col_w + 20, h * 0.76), Vector2(w * 0.32, top + 18), Vector2(w * 0.68, top + 18), Vector2(w - col_w - 20, h * 0.76), Vector2(w - col_w - 20, h), Vector2(col_w + 20, h)]), metal)
	for side in [-1.0, 1.0]:
		for k in 3:
			var cx: float = w * 0.5 + side * (w * 0.12 + k * w * 0.07)
			draw_colored_polygon(PackedVector2Array([Vector2(cx - 26, top + 30 + k * 6), Vector2(cx + 26, top + 26 + k * 6), Vector2(cx + 22, top + 42 + k * 6), Vector2(cx - 30, top + 46 + k * 6)]), Color(0.2, 0.6, 1.0, 0.85) if k != 1 else Color(orange, 0.9))

# ---------------------------------------------------------------- main draw
func _draw() -> void:
	if space == null or not is_instance_valid(space.player): return
	_layout()
	_objective_button()
	var cam: Camera3D = space.cam
	var cockpit := GS.view == "cockpit"
	if space.zoomed: _scope()   # v1.7z: looking down the rifle's scope (under everything else)
	if space.underwater: draw_rect(Rect2(Vector2.ZERO, S), Color(Data.UNDERWATER_TINT, Data.UNDERWATER_TINT.a * (0.85 + 0.15 * sin(t * 1.7))))   # v1.8j: light through water
	if space.in_nebula > 0.0:
		var lit: float = space.beacon_lit   # v1.4r: a light beacon lights the cloud: the haze thins and warms near the lamp
		draw_rect(Rect2(Vector2.ZERO, S), Color(space.nebula_tint.lerp(Data.BEACON_LIGHT_COLOR, lit * 0.6), Data.NEBULA_HUD_TINT * space.in_nebula * (1.0 - Data.BEACON_HAZE_CLEAR * lit)))   # (v1.9s: real fog does most of it now)
		if space.nebula_flash > 0.01: draw_rect(Rect2(Vector2.ZERO, S), Color(0.85, 0.92, 1.0, 0.22 * space.nebula_flash))   # lightning in the cloud
	if space.screen_flash > 0.01: draw_rect(Rect2(Vector2.ZERO, S), Color(1.0, 0.93, 0.8, space.screen_flash))   # v6.7: a big blast close by
	if space.sun_surface:   # on a star: everything is seen through a hot yellow haze (your heat shield, if you have one)
		draw_rect(Rect2(Vector2.ZERO, S), Color(1.0, 0.82, 0.25, 0.16 + 0.04 * sin(t * 3.1)))
	if space.sun_flare > 0.01:   # sun bloom: washes the view out the closer and more head-on you fly at it
		var sc: Color = (space.sys["star"] as Color).lerp(Color.WHITE, 0.55)
		draw_rect(Rect2(Vector2.ZERO, S), Color(sc, minf(0.92, space.sun_flare * 0.95)))
	for n in [space.station, space.planet, space.gate]:
		if not n.visible and n.get_meta("kind", "") != "station": continue
		if n.get_meta("kind", "") == "none": continue
		var pos: Vector3 = space.dock_point(n) if n != space.gate else n.global_position
		var sp = _screen(pos)
		var col := GOLD if n == space.gate else GREEN
		if sp != null and Rect2(Vector2(col_w, 0), Vector2(S.x - col_w * 2, S.y)).has_point(sp):
			draw_arc(sp, 14, 0, TAU, 4, Color(col, 0.85), 2.0)
			_text(sp + Vector2(20, 6), "%s  %s" % [n.name, _dist(space.distance_to(n))], 14, Color(col, 0.95))
	# v1.5a: the mission waypoint: a gold marker with what it is and how far, and an arrow at the screen edge when it is out of view
	var mw: Dictionary = space.mission_waypoint()
	if not mw.is_empty():
		var mnode: Node3D = mw["node"]
		var view := Rect2(Vector2(col_w + 30, 40), Vector2(S.x - col_w * 2 - 60, S.y - 80))
		var msp = _screen(mnode.global_position)
		if msp != null and view.has_point(msp):
			draw_colored_polygon(PackedVector2Array([msp + Vector2(0, -14), msp + Vector2(12, 0), msp + Vector2(0, 14), msp + Vector2(-12, 0)]), Color(GOLD, 0.25))
			draw_polyline(PackedVector2Array([msp + Vector2(0, -14), msp + Vector2(12, 0), msp + Vector2(0, 14), msp + Vector2(-12, 0), msp + Vector2(0, -14)]), GOLD, 2.5)
			_text(msp + Vector2(18, -8), "MISSION  " + _dist(space.distance_to(mnode)), 14, GOLD)
		else:
			_edge_arrow(mnode.global_position, GOLD, view, true)
	if is_instance_valid(space.waypoint):
		var wsp = _screen(space.waypoint.global_position)
		if wsp != null:
			draw_colored_polygon(PackedVector2Array([wsp + Vector2(0, -10), wsp + Vector2(10, 0), wsp + Vector2(0, 10), wsp + Vector2(-10, 0)]), Color(GOLD, 0.9))
			_text(wsp + Vector2(16, 6), "WAYPOINT  " + _dist(space.distance_to(space.waypoint)), 14, GOLD)
		elif space.autopilot == space.waypoint:
			_edge_arrow(space.waypoint.global_position, GOLD, Rect2(Vector2(col_w + 30, 40), Vector2(S.x - col_w * 2 - 60, S.y - 80)), true)
	for tr in space.traffic:
		var tp0 = _screen(tr["node"].global_position)
		if tp0 != null and space.player.global_position.distance_to(tr["node"].global_position) < 900.0:
			_brackets(tp0, 18.0, Color(GREEN, 0.85))
	# off-screen hostiles: red arrows at the view edge; friendlies green
	var view := Rect2(Vector2(col_w + 30, 40), Vector2(S.x - col_w * 2 - 60, S.y - 80))
	for e in space.enemies:
		_edge_arrow(e["node"].global_position, RED, view, e["node"] == space.target)
		if e["node"] == space.target: continue
		var ep = _screen(e["node"].global_position)
		var edist: float = space.player.global_position.distance_to(e["node"].global_position)
		if ep != null and view.has_point(ep):
			_brackets(ep, Data.SHIP_BOX, Color(RED if e["node"].get_meta("kind", "enemy") == "enemy" else GOLD, 0.95))   # v1.8u (owner): every ship has a lock box you can tap
			for row in _lock_rows():   # v1.9r: the shared locks on this one: red pips on top, purple underneath
				var nl := _locks_on(row[0], e["node"])
				for k in nl: _lock_pip(ep + Vector2((k - (nl - 1) * 0.5) * 12.0, -Data.SHIP_BOX - 22.0 if row[1] else Data.SHIP_BOX + 9.0), row[2], true, 4.5)   # (red above its bars)
		if ep != null and view.has_point(ep) and edist < 900.0:
			_enemy_bars(ep + Vector2(-22, -30), 44.0, 4.0, e)
	for pu in space.popups:
		var pp = _screen(pu["pos"])
		if pp != null:
			var a: float = clampf(pu["life"] / 0.9, 0.0, 1.0)
			_text(pp - Vector2(110, 0), pu["text"], 18, Color(pu["col"], a), HORIZONTAL_ALIGNMENT_CENTER, 220)
	var tgt: Node3D = space.target
	if tgt and is_instance_valid(tgt):
		var tp = _screen(tgt.global_position)
		var tcol := RED if tgt.get_meta("kind", "") == "enemy" else GOLD
		if tp != null and view.has_point(tp):
			_brackets(tp, 30.0, tcol)
			if tgt.get_meta("kind", "") == "enemy":
				var e2: Dictionary = space._enemy_entry(tgt)
				if not e2.is_empty(): _enemy_bars(tp + Vector2(-40, 38), 80.0, 7.0, e2, true)
				if not e2.is_empty():
					# The aim box (Freelancer style, v1.4l): a RED box ahead of the enemy, where your shots will meet it.
					# Put the crosshair on the box and fire. It shows for any targeted enemy on screen.
					var lp = _screen(space.lead_point(tgt))
					if lp != null and space.distance_to(tgt) < float(GS.weapon()["range"]) * Data.LEAD_BOX_RANGE:
						var on: bool = lp.distance_to(S * 0.5) < Data.LEAD_BOX_ON
						var lc := Color(1.0, 0.95, 0.3) if on else RED
						var hs: float = Data.LEAD_BOX_SIZE
						draw_line(tp, lp, Color(RED, 0.45), 1.5)
						draw_rect(Rect2(lp - Vector2(hs, hs), Vector2(hs, hs) * 2.0), Color(lc, 1.0), false, 3.0)
						draw_line(lp + Vector2(-hs * 0.45, 0), lp + Vector2(hs * 0.45, 0), lc, 2.0)
						draw_line(lp + Vector2(0, -hs * 0.45), lp + Vector2(0, hs * 0.45), lc, 2.0)
					# Job M / v1.9r: missile locks. The rack's full count as pips (filled = locks on THIS target; the shared
					# locks on other hostiles show on their own boxes): light missile RED on top, heavy PURPLE underneath.
					for row in _lock_rows():
						var item: String = row[0]
						var cap: int = mini(GS.max_locks(item), GS.slot_ammo(item))
						var on_me := _locks_on(item, tgt)
						var y: float = -46.0 if row[1] else 98.0   # (under the target's bars and their labels)
						for k in cap: _lock_pip(tp + Vector2((k - (cap - 1) * 0.5) * 16.0, y), row[2], k < on_me, 6.0)
						var all_n: int = space.lock_count(item)
						if all_n > 0: _text(tp + Vector2(-70, y - 28.0 if row[1] else y + 26.0), "%s %d/%d" % ["LOCK" if row[1] else "HEAVY", all_n, cap], 14, row[2], HORIZONTAL_ALIGNMENT_CENTER, 140)
		elif tgt.get_meta("kind", "") != "enemy":
			_edge_arrow(tgt.global_position, GOLD, view, true)
	if space.warp_state == "on":
		var cc0 := S * 0.5
		for i in 48:
			var a := i * 2.399 + t * 0.4
			var ph := fmod(i * 0.137 + t * 1.8, 1.0)
			var d0 := Vector2(cos(a), sin(a))
			var r0 := 60.0 + ph * ph * S.x * 0.6
			draw_line(cc0 + d0 * r0, cc0 + d0 * (r0 + 30 + 160 * ph), Color(0.75, 0.85, 1.0, 0.55 * ph), 1.5 + 2.0 * ph)
	if cockpit and GS.form != "mech": _cockpit()   # (v1.7z: the mech's first-person view has its own arms instead)
	# warp spool countdown and the planet warning
	if space.warp_state == "charging":
		var left := int(ceil(Data.WARP_CHARGE - space.warp_t))
		_text(Vector2(0, S.y * 0.5 - 62), str(maxi(1, left)), 60, Color(0.75, 0.85, 1.0), HORIZONTAL_ALIGNMENT_CENTER, S.x)
		_text(Vector2(0, S.y * 0.5 - 44), "WARP SPOOLING · WEAPONS LOCKED", 15, Color(0.75, 0.85, 1.0), HORIZONTAL_ALIGNMENT_CENTER, S.x)
	elif space.warp_flash > 0.0:
		_text(Vector2(0, S.y * 0.5 - 62), "WARP", 64, Color(0.85, 0.92, 1.0, minf(1.0, space.warp_flash * 2.0)), HORIZONTAL_ALIGNMENT_CENTER, S.x)
	if space.sun_hazard > 0 and fmod(t, 0.5) < 0.32:
		_text(Vector2(0, S.y * 0.5 - 132), "HEAT WARNING", 34, RED, HORIZONTAL_ALIGNMENT_CENTER, S.x)
		_text(Vector2(0, S.y * 0.5 - 100), "NO HEAT SHIELD — CLIMB OUT NOW" if space.sun_surface else "TURN AWAY FROM THE STAR", 24, RED, HORIZONTAL_ALIGNMENT_CENTER, S.x)
	elif space.sun_surface and space.heat_shielded:
		_text(Vector2(0, 182), "HEAT SHIELD HOLDING", 15, Color(1.0, 0.85, 0.4), HORIZONTAL_ALIGNMENT_CENTER, S.x)
	# (Job M's missile distance and the dodge tip: v7.6, in the WARNING panel at the top)
	if space.planet_hazard > 0 and fmod(t, 0.5) < 0.32:
		_text(Vector2(0, S.y * 0.5 - 132), "PLANETARY MASS DETECTED", 34, RED, HORIZONTAL_ALIGNMENT_CENTER, S.x)
		_text(Vector2(0, S.y * 0.5 - 100), "DROP WARP NOW", 24, RED, HORIZONTAL_ALIGNMENT_CENTER, S.x)
	# reticle (cockpit view: a wider ring with ticks and a chevron, like the concept)
	var c := S * 0.5
	var locked: bool = is_instance_valid(space.target) and space._in_fire_cone(space.target)
	var rc2 := RED if locked else WHITE
	if cockpit and cockpit_texture():
		var nose = _screen(space.player.global_position - space.player.global_basis.z * 400.0)
		if nose != null: c = nose   # the crosshair marks where the nose points, even while you look around
		var rcol := RED if locked else Color(0.6, 0.9, 1.0)
		draw_arc(c, 46, 0, TAU, 64, Color(rcol, 0.95), 2.0, true)
		draw_arc(c, 52, deg_to_rad(200), deg_to_rad(340), 32, Color(rcol, 0.5), 1.5, true)
		for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			draw_line(c + d * 46, c + d * 60, Color(rcol, 0.95), 2.0)
		draw_line(c + Vector2(-110, 0), c + Vector2(-64, 0), Color(rcol, 0.5), 1.5)
		draw_line(c + Vector2(64, 0), c + Vector2(110, 0), Color(rcol, 0.5), 1.5)
		draw_polyline(PackedVector2Array([c + Vector2(-9, 64), c + Vector2(0, 74), c + Vector2(9, 64)]), rcol, 2.0)
		draw_circle(c, 3, rcol)
	else:
		draw_arc(c, 32, 0, TAU, 48, Color(rc2, 0.95), 2.5, true)
		for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			draw_line(c + d * 20, c + d * 52, Color(rc2, 0.95), 2.5)
		draw_circle(c, 4, rc2)
	if cockpit and cockpit_texture(): _status_bars()   # (v6.9: otherwise they are on the dash)
	_fl_panels()
	_alerts()
	# v7.0 (owner: what are those yellow words?): no standing hint line; the job is on the contact list. Short messages
	# still flash up, small and white, under the top prompt.
	if msg_t > 0.0: _text(Vector2(col_w, 86), msg, 15, Color(WHITE, minf(1.0, msg_t * 2.0)), HORIZONTAL_ALIGNMENT_CENTER, S.x - col_w * 2)
	var zone := ""
	if space.surface_mode: zone = "%s  ·  ALT %d m" % [Surface.tile_name(space.planet_id, space.tile), int(space.altitude)]
	elif space.in_nebula > 0.0:
		var wx: String = Data.NEBULA_WEATHER_NAME.get(space.nebula_weather(), "")
		zone = ("%s NEBULA" % space.nebula_name().to_upper()) if space.nebula_name() != "" else "NEBULA"
		zone += ("  ·  " + wx if wx != "" else "") + "  ·  SENSORS DEGRADED"   # v1.9z: the cloud's weather
	elif space.in_belt: zone = ("%s RINGS — MINE THE ROCKS" % str(Data.SYSTEMS[GS.system_id]["planet"]["name"]).to_upper()) if space.in_ring(space.player.global_position) else "%s — WATCH FOR ROCKS" % Data.SYSTEMS[GS.system_id]["asteroids"]["name"].to_upper()
	if zone != "": _text(Vector2(col_w, 164), zone, 14, CYAN_HI, HORIZONTAL_ALIGNMENT_CENTER, S.x - col_w * 2)
	# defence and special moves (right block), speed (left block)
	var sh_cd: float = space.shield_cd / Data.SHIELD_BOOST_COOLDOWN
	if cockpit and cockpit_texture():   # (v7.6: on the console otherwise)
		_corner("shield", "SHIELD", "shield", Color(0.35, 0.7, 1.0), false, str(GS.shield_charges), sh_cd)
		_corner("repair", "REPAIR", "repair", GREEN, false, str(GS.repairs), space.repair_cd / 1.5)
	_corner("tractor", "TRACTOR", "tractor", Color(0.45, 0.9, 1.0), space.tractor_t > 0.0, str(space.loot.size()) if space.loot.size() > 0 else "")
	var tf: bool = space.transform_t > 0.0
	if cockpit and cockpit_texture(): _corner("form", "…" if tf else ("SHIP" if GS.form == "mech" else "MECH"), "form", GOLD, tf, "", 0.0, space.warp_state != "off", "TRANSFORM")
	var wsub := ""
	if space.warp_state == "charging": wsub = "%d s" % int(ceil(Data.WARP_CHARGE - space.warp_t))
	elif space.warp_state == "on": wsub = "DROP OUT"
	_corner("warp", "WARP", "warp", Color(0.62, 0.55, 1.0), space.warp_state != "off", "", 0.0, GS.form == "mech", wsub)
	_special_button()   # v1.5o
	var gm: bool = space.ground_mode   # v1.8r: GROUND: gravity on, walk / land
	_corner("ground", "GROUND", "ground", GREEN, gm, "", 0.0, false, ("WALKING" if GS.form == "mech" else "LANDED") if gm and space.grounded else ("FALLING" if gm else ("WALK" if GS.form == "mech" else "LAND")))
	for lid in ["lock_a", "lock_c"]: _padlocked(lid, "")
	_corner("fullscreen", "FULL", "fullscreen", CYAN, fs_on, "", 0.0, false, "EXIT" if fs_on else "SCREEN")
	_corner("stop", "STOP", "stop", RED, space.braking or space.holding, "", 0.0, false, "STOPPED" if space.holding else "FULL STOP")
	if space.warp_state == "charging":
		var wr: Rect2 = buttons["warp"]
		draw_rect(Rect2(wr.position + Vector2(8, wr.size.y - 5), Vector2((wr.size.x - 16) * space.warp_t / Data.WARP_CHARGE, 3)), Color(0.8, 0.75, 1.0))
	# weapons (left block) and the rest of the speed row
	for k in GS.slots.size():
		var item: String = GS.slots[k]
		var it: Dictionary = Data.SLOT_ITEMS[item]
		var ammo := GS.slot_ammo(item)
		var scol := ORANGE if item == "light_missile" else (RED if item == "heavy_missile" else GOLD)
		var cdk: float = (space.mine_cd / 2.5) if item == "mine" else (space.missile_cd / 1.2)
		var ssub: String = it["sub"]
		if item != "mine":   # Job M: how many this button fires, and the locks held right now
			var lk: int = space.lock_count(item)
			ssub = "LOCK %d/%d" % [lk, GS.max_locks(item)] if lk > 0 else "MISSILE ×%d" % GS.max_locks(item)
		var nm: String = {"light_missile": "MISSILE 1", "heavy_missile": "MISSILE 2", "mine": "MINE"}.get(item, str(it["label"]))   # v7.6 (owner's names)
		_corner("slot_%d" % k, nm, it["icon"], scol, false, "%d" % ammo, cdk, space.warp_active(), ssub)
	var mech: bool = GS.form == "mech"
	_corner("thrust", "JUMP" if gm else ("BOOST" if mech else "THRUST"), "thrust", ORANGE, space.boosting, "", 0.0, false, "STICK = DASH" if mech or gm else "")
	_corner("fire", "FIRE", "guns", RED, space.fire_lock, "", 0.0, space.warp_active() or not space.lane.is_empty(), "ON · TAP OFF" if space.fire_lock else "TAP = ON")
	_corner("kill", "ENGINE KILL", "kill", GOLD, space.engine_kill, "", 0.0, mech, "DRIFTING" if space.engine_kill else "ENGINE")
	_corner("zoom", "ZOOM", "zoom", CYAN, space.zoomed, "", 0.0, false, "SCOPE ON" if space.zoomed else "SCOPE")
	if not fl_shown("l"):   # v7.4: GO TO lives in the left window; only when it's away does it float above the flight stick
		_pill("goto", "GO TO", space.autopilot != null, CYAN)
	if not fl_shown("r"):   # v7.3: these live in the right window; only when it's away do they float above the aim stick
		_pill("log", "COMMS", comms_mode == "roster", CYAN)
	if buttons.has("dock"): _pill("dock", "DOCK", true, GREEN, space.dock_candidate().name.to_upper())
	if buttons.has("lane"):
		if space.lane.is_empty(): _pill("lane", "TRADE LANE", true, CYAN, "TO %s" % str(space.lane_candidate().get("to", "")).to_upper())
		else: _pill("lane", "IN LANE · %d m/s" % int(space.speed_now), true, CYAN, "TAP TO LEAVE · TO %s" % str(space.lane.get("to", "")).to_upper())
	if buttons.has("jump"):
		var gi: Dictionary = space.near_gate().get_meta("info")
		var dest: String = str(Surface.PLANETS[gi["planet_to"]]["name"]) if gi.has("planet_to") and Surface.PLANETS.has(gi["planet_to"]) else str(Data.SYSTEMS.get(str(gi.get("to", "")), {}).get("name", "?"))   # (v6.9: a planet's rift leads to a planet)
		_pill("jump", "%s GATE" % str(gi.get("gkind", "warp")).to_upper() if space.sys.get("generated", false) or gi.has("planet_to") else "WARP GATE", true, GOLD, "DOCK · TO %s" % dest.to_upper())
	if not (cockpit and cockpit_texture()): _dashboard()   # the cockpit art has its own dash screens
	_stick("move", "FLIGHT")
	_stick("aim", "AIM")
	if comms_open: _comms()
	_draw_scan()   # v1.5g
	if planet_map: _planet_map()   # v1.8y
	_draw_special()   # v1.5o: lock ring + the pilot cut-in (drawn over the view, the HUD stays readable)
	if damage_flash > 0.0:
		for i in 6: draw_rect(Rect2(Vector2.ZERO, S), Color(RED, damage_flash * 0.08), false, 60.0 - i * 9.0)

func _hull_col(k: float) -> Color:
	return GREEN.lerp(YELLOW, clampf((0.75 - k) / 0.35, 0, 1)).lerp(RED, clampf((0.4 - k) / 0.3, 0, 1))

## Structural status: a circle split like a "Y" into three wedges — HULL (top, between the arms of the Y), LEFT and
## RIGHT wing (or arm, for a mech) — each green > yellow > red, dark grey when destroyed, with the silhouette on top.
func _damage_icon(c: Vector2, r: float, lk: float, ck: float, rk: float, mech := false) -> void:
	var wedges := [[-150.0, -30.0, ck, false], [90.0, 210.0, lk, true], [-30.0, 90.0, rk, true]]   # degrees, screen y down
	draw_circle(c, r + 3, Color(0.01, 0.05, 0.1, 0.85))
	for wd in wedges:
		var k: float = clampf(wd[2], 0.0, 1.0)
		var col := Color(0.25, 0.27, 0.3) if (wd[3] and k <= 0.0) else _hull_col(k)
		if not wd[3] and k <= 0.0: col = Color(0.25, 0.27, 0.3)
		var pts := PackedVector2Array([c])
		for i in 13:
			var a := deg_to_rad(lerpf(wd[0], wd[1], i / 12.0))
			pts.append(c + Vector2(cos(a), sin(a)) * r)
		draw_colored_polygon(pts, Color(col, 0.85))
	for a2 in [-150.0, -30.0, 90.0]:
		draw_line(c, c + Vector2(cos(deg_to_rad(a2)), sin(deg_to_rad(a2))) * r, Color(0.01, 0.05, 0.1), 2.5)
	draw_arc(c, r, 0, TAU, 40, Color(CYAN_HI, 0.9), 2.0, true)
	var s := r / 28.0
	var sil: PackedVector2Array
	if mech:
		sil = PackedVector2Array([Vector2(-5, -17), Vector2(5, -17), Vector2(6, -11), Vector2(16, -9), Vector2(18, 6), Vector2(12, 6), Vector2(10, -3), Vector2(7, -2),
			Vector2(8, 18), Vector2(2, 18), Vector2(0, 6), Vector2(-2, 18), Vector2(-8, 18), Vector2(-7, -2), Vector2(-10, -3), Vector2(-12, 6), Vector2(-18, 6), Vector2(-16, -9), Vector2(-6, -11)])
	else:
		sil = PackedVector2Array([Vector2(0, -19), Vector2(4, -7), Vector2(19, 6), Vector2(19, 10), Vector2(5, 7), Vector2(4, 15), Vector2(-4, 15), Vector2(-5, 7), Vector2(-19, 10), Vector2(-19, 6), Vector2(-4, -7)])
	for i in sil.size(): sil[i] = c + sil[i] * s
	sil.append(sil[0])
	draw_polyline(sil, WHITE, 2.0, true)

## [ LEFT ] [ CORE ] [ RIGHT ]: side sections are short bars at each end, the core is the long middle bar.
## A destroyed side shows as a dark red box with an X.
func _three_part(r: Rect2, lk: float, ck: float, rk: float, blink := false) -> void:
	var gap := maxf(2.0, r.size.x * 0.02)
	var sw := r.size.x * 0.2
	var parts := [[Rect2(r.position, Vector2(sw, r.size.y)), lk], [Rect2(r.position + Vector2(sw + gap, 0), Vector2(r.size.x - sw * 2 - gap * 2, r.size.y)), ck],
		[Rect2(r.position + Vector2(r.size.x - sw, 0), Vector2(sw, r.size.y)), rk]]
	for i in 3:
		var pr: Rect2 = parts[i][0]
		var k: float = clampf(parts[i][1], 0.0, 1.0)
		draw_rect(pr, Color(0, 0, 0, 0.55))
		if i != 1 and k <= 0.0:
			draw_rect(pr, Color(0.45, 0.05, 0.05, 0.9))
			draw_line(pr.position, pr.end, RED, 1.5)
			draw_line(Vector2(pr.position.x, pr.end.y), Vector2(pr.end.x, pr.position.y), RED, 1.5)
			continue
		var c := RED if (blink and i == 1) else _hull_col(k)
		draw_rect(Rect2(pr.position, Vector2(pr.size.x * k, pr.size.y)), c)

## Shield (cyan) over hull (green -> red) bars for one enemy.
func _enemy_bars(p: Vector2, w: float, h: float, e: Dictionary, labels := false) -> void:
	var shk: float = float(e["sh"]) / maxf(1.0, float(e["sh_max"]))
	var hk: float = clampf(float(e["hp"]) / float(e["max"]), 0.0, 1.0)
	draw_rect(Rect2(p - Vector2(1, 1), Vector2(w + 2, h * 2 + 5)), Color(0, 0, 0, 0.55))
	if float(e["sh_max"]) > 0.0:
		draw_rect(Rect2(p, Vector2(w * shk, h)), CYAN_HI)
	var sm: float = maxf(1.0, float(e.get("side_max", 1.0)))
	var capital: bool = e["def"].get("capital", false)   # v1.9n: a capital ship has one hull, no wings
	if capital: draw_rect(Rect2(p + Vector2(0, h + 2), Vector2(w * hk, h)), _hull_col(hk))
	else: _three_part(Rect2(p + Vector2(0, h + 2), Vector2(w, h)), float(e.get("l", sm)) / sm, hk, float(e.get("r", sm)) / sm)
	if labels and capital:
		_text(p + Vector2(w + 6, h + 1), "SH %d" % roundi(float(e["sh"])), 12, CYAN_HI)
		_text(p + Vector2(w + 6, h * 2 + 12), "HULL %d" % roundi(float(e["hp"])), 12, _hull_col(hk))
	elif labels:
		_text(p + Vector2(w + 6, h + 1), "SH %d" % roundi(float(e["sh"])), 12, CYAN_HI)
		_text(p + Vector2(w + 6, h * 2 + 12), "CORE %d" % roundi(float(e["hp"])), 12, _hull_col(hk))
		var lab := "ARM" if e.get("mech", false) else "WING"
		_text(p + Vector2(0, h * 2 + 16), "L " + lab, 10, Color(1, 1, 1, 0.75))
		_text(p + Vector2(0, h * 2 + 16), "R " + lab, 10, Color(1, 1, 1, 0.75), HORIZONTAL_ALIGNMENT_RIGHT, w)

func _edge_arrow(p3: Vector3, col: Color, view: Rect2, big: bool) -> void:
	var sp = _screen(p3)
	if sp != null and view.has_point(sp): return
	var cam: Camera3D = space.cam
	var v: Vector3 = cam.global_basis.inverse() * (p3 - cam.global_position)
	var dir := Vector2(v.x, -v.y).normalized()
	if dir == Vector2.ZERO: dir = Vector2.DOWN
	var half := view.size * 0.5
	var k := minf(half.x / maxf(absf(dir.x), 0.001), half.y / maxf(absf(dir.y), 0.001))
	var at := view.get_center() + dir * k
	var perp := Vector2(-dir.y, dir.x)
	var s := 16.0 if big else 11.0
	draw_colored_polygon(PackedVector2Array([at + dir * s * 1.2, at - dir * s * 0.6 + perp * s, at - dir * s * 0.6 - perp * s]), col)

## v1.9r: the missile lock rows to draw: [item, on top?, colour] for each missile type fitted.
func _lock_rows() -> Array:
	var out: Array = []
	if "light_missile" in GS.slots: out.append(["light_missile", true, Data.LIGHT_LOCK_COLOR])
	if "heavy_missile" in GS.slots: out.append(["heavy_missile", not ("light_missile" in GS.slots), Data.HEAVY_LOCK_COLOR])
	return out

## v1.9r: how many of the shared locks of `item` sit on node `n` right now.
var _lock_cache := {}   # item -> [frame, spread]
func _locks_on(item: String, n: Node3D) -> int:
	var f := Engine.get_process_frames()
	if not _lock_cache.has(item) or int(_lock_cache[item][0]) != f: _lock_cache[item] = [f, space.lock_spread(item)]
	for pr in _lock_cache[item][1]:
		if pr[0] == n: return int(pr[1])
	return 0

func _lock_pip(pc: Vector2, col: Color, filled: bool, r: float) -> void:
	var dia := PackedVector2Array([pc + Vector2(0, -r), pc + Vector2(r, 0), pc + Vector2(0, r), pc + Vector2(-r, 0)])
	if filled: draw_colored_polygon(dia, col)
	dia.append(dia[0])
	draw_polyline(dia, Color(col, 0.95), 1.5)

func _brackets(p: Vector2, s: float, col: Color) -> void:
	for cr in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var corner: Vector2 = p + cr * s
		draw_line(corner, corner - Vector2(cr.x * s * 0.45, 0), col, 3)
		draw_line(corner, corner - Vector2(0, cr.y * s * 0.45), col, 3)

# ---------------------------------------------------------------- dashboard: SPEED · status/radar · WAYPOINT
## v7.1 (owner's dash art): one console between the sticks. Left: COCKPIT and GO TO stacked. Middle: the radar globe in
## its ring (tap = map) with SPEED under it. Right: SHIELDS, HULL (LEFT WING / CORE / RIGHT WING) and ENERGY, each with
## its percentage. Sized to the gap between the two sticks.
func dash_geo() -> Dictionary:
	# v7.7 (owner's ring mockup): the radar in the middle of two rings. Inner ring: the hull (BODY on top, L WING and
	# R WING low on each side). Outer ring: SHIELD over the top, POWER low left, SUPER low right. SPEED sits on top.
	# Two blocks of six buttons, one each side:
	#   FIRE · TRANSFORM · SHIELD REPAIR        HULL REPAIR · SUPER · MINE
	#   MISSILE 1 · ENGINE KILL · THRUST        STOP · WARP · MISSILE 2
	var ro := clampf(S.y * 0.155, 92.0, 124.0)   # v7.8 (owner): smaller, so your ship shows above it
	var rad := ro - 40.0
	var rc := Vector2(S.x * 0.5, S.y - ro - 6.0)
	var xl0 := _home("move").x + stick_r + 16.0
	var xl1 := rc.x - ro - 12.0
	var xr0 := rc.x + ro + 12.0
	var ww := xl1 - xl0
	var gap := 6.0
	var bsz := clampf((ww - gap * 2.0) / 3.0, 48.0, S.y * 0.12)
	var by2 := S.y - 8.0 - bsz
	var by1 := by2 - gap - bsz
	var row := bsz * 3.0 + gap * 2.0
	var lx0 := xl1 - row
	var rx0 := xr0
	var lb := func(k: int, y: float) -> Rect2: return Rect2(lx0 + k * (bsz + gap), y, bsz, bsz)
	var rb := func(k: int, y: float) -> Rect2: return Rect2(rx0 + k * (bsz + gap), y, bsz, bsz)
	return {"rc": rc, "rad": rad, "ro": ro, "small": roundf(bsz * 0.68),
		"speed": Rect2(rc.x - 86.0, rc.y - ro - 24.0, 172.0, 40.0),
		"fire": lb.call(0, by1), "form": lb.call(1, by1), "shield": lb.call(2, by1),
		"missile1": lb.call(0, by2), "kill": lb.call(1, by2), "thrust": lb.call(2, by2),
		"repair": rb.call(0, by1), "special": rb.call(1, by1), "super_btn": rb.call(1, by1), "mine": rb.call(2, by1),
		"stop": rb.call(0, by2), "warp": rb.call(1, by2), "missile2": rb.call(2, by2)}

func _ring_hull_col(v: float) -> Color:
	return YELLOW if v > 0.5 else (ORANGE if v > 0.25 else RED)

## A ring gauge: `segs` blocks along the arc a0 -> a1 (radians, Godot's y-down angles), lit from a0 by v.
func _ring_gauge(c: Vector2, r: float, w: float, a0: float, a1: float, v: float, col: Color, segs: int, blink := false) -> void:
	var step := (a1 - a0) / segs
	var pad := signf(step) * minf(0.025, absf(step) * 0.18)
	for i in segs:
		var b0 := a0 + i * step + pad
		var b1 := a0 + (i + 1) * step - pad
		var lit := (i + 1) / float(segs) <= v + 0.0001
		var part := clampf(v * segs - i, 0.0, 1.0)
		draw_arc(c, r, b0, b1, 6, Color(0.08, 0.15, 0.22, 0.85), w, true)
		if part > 0.0: draw_arc(c, r, b0, b0 + (b1 - b0) * part, 6, (RED if blink else col) if not lit or part > 0.0 else col, w, true)

func _dash_frame(r: Rect2, col := CYAN) -> void:   # the cut-corner tech frame of the art
	var c := minf(14.0, r.size.y * 0.3)
	var pts := PackedVector2Array([r.position + Vector2(c, 0), Vector2(r.end.x - c, r.position.y), Vector2(r.end.x, r.position.y + c),
		Vector2(r.end.x, r.end.y - c), Vector2(r.end.x - c, r.end.y), Vector2(r.position.x + c, r.end.y), Vector2(r.position.x, r.end.y - c), Vector2(r.position.x, r.position.y + c)])
	draw_colored_polygon(pts, Color(0.01, 0.05, 0.1, 0.82))
	draw_polyline(pts + PackedVector2Array([pts[0]]), Color(col, 0.95), 2.5, true)

func _seg_bar(r: Rect2, v: float, col: Color, segs: int, blink := false) -> void:
	_dash_frame(Rect2(r.position - Vector2(3, 3), r.size + Vector2(6, 6)), Color(col, 0.6))
	var sw := r.size.x / segs
	for i in segs:
		var sr := Rect2(Vector2(r.position.x + i * sw + 1, r.position.y), Vector2(sw - 2, r.size.y))
		var fill := clampf(v * segs - i, 0.0, 1.0)
		draw_rect(sr, Color(0.1, 0.18, 0.25, 0.8))
		if fill > 0.0: draw_rect(Rect2(sr.position, Vector2(sr.size.x * fill, sr.size.y)), RED if blink else col)

## A console bar: its name over it, segmented fill inside a cut frame.
func _console_bar(r: Rect2, label: String, v: float, col: Color, segs: int, blink := false) -> void:
	_text(Vector2(r.position.x + 10, r.position.y - 4), label, 12, Color(WHITE, 0.92))
	_seg_bar(r.grow(-3.0), v, col, segs, blink)

## A round icon button by the radar (shield, repair, mech, super).
func _icon_btn(id: String, icon: String, col: Color, active := false, badge := "", cd := 0.0, glow := false) -> void:
	if not buttons.has(id): return
	var r: Rect2 = buttons[id]
	var c := r.get_center()
	var rr := r.size.x * 0.5
	var down := held.has(id)
	var hexp := PackedVector2Array()
	for k in 7: hexp.append(c + Vector2.from_angle(TAU * k / 6.0 + PI / 6.0) * rr)
	if glow: draw_circle(c, rr + 4.0 + 5.0 * (0.5 + 0.5 * sin(t * 6.0)), Color(col, 0.25))
	draw_colored_polygon(hexp.slice(0, 6), Color(col.darkened(0.5), 0.95) if (active or down) else Color(0.02, 0.08, 0.15, 0.92))
	draw_polyline(hexp, Color(col, 1.0), 2.5, true)
	_icon(icon, c, rr * 0.48, WHITE if (active or down or glow) else col.lightened(0.3))
	if cd > 0.0: draw_arc(c, rr - 4.0, -PI / 2, -PI / 2 + TAU * (1.0 - cd), 32, Color(WHITE, 0.8), 2.5, true)
	if badge != "":
		var bc := c + Vector2(rr * 0.72, -rr * 0.62)
		draw_circle(bc, 10, RED if badge == "0" else Color(0.02, 0.07, 0.14))
		draw_arc(bc, 10, 0, TAU, 20, Color(col, 0.9), 1.5, true)
		_text(bc + Vector2(-10, 5), badge, 12, WHITE, HORIZONTAL_ALIGNMENT_CENTER, 20)

func _dashboard() -> void:
	way_rect = Rect2()
	var g := dash_geo()
	var rc: Vector2 = g["rc"]
	var rad: float = g["rad"]
	var ro: float = g["ro"]
	var blink := fmod(t, 0.6) < 0.3
	var pulse := 0.5 + 0.5 * sin(t * 6.0)
	# the rings' backing
	draw_circle(rc, ro + 4.0, Color(0.01, 0.04, 0.09, 0.88))
	draw_arc(rc, ro + 4.0, 0, TAU, 96, Color(CYAN, 0.8), 2.0, true)
	draw_arc(rc, rad + 22.0, 0, TAU, 96, Color(CYAN, 0.4), 1.5, true)
	# outer ring: SHIELD over the top (left to right), POWER low left, SUPER low right (both fill upward from the bottom)
	var sh: float = clampf(GS.shield / maxf(GS.max_shield(), 1.0), 0.0, 1.0)
	var en: float = clampf(GS.energy / Data.ENERGY_MAX, 0.0, 1.0)
	var sup: float = clampf(GS.super_charge, 0.0, 1.0)
	var orr := ro - 8.0
	_ring_gauge(rc, orr, 12.0, PI + 0.06, TAU - 0.06, sh, Color(0.2, 0.7, 1.0), 16, sh < 0.2 and blink)
	_ring_gauge(rc, orr, 12.0, PI * 0.5 + 0.06, PI - 0.06, en, GREEN, 8)
	_ring_gauge(rc, orr, 12.0, PI * 0.5 - 0.06, 0.06, sup, ORANGE.lerp(WHITE, 0.45 * pulse) if sup >= 1.0 else ORANGE, 8)
	if sup >= 1.0: draw_arc(rc, orr, 0.06, PI * 0.5 - 0.06, 24, Color(ORANGE, 0.3 * pulse), 24.0, true)
	# inner ring: the hull. BODY on top, L WING and R WING low on each side
	var hu: float = clampf(GS.hull / maxf(GS.max_hull(), 1.0), 0.0, 1.0)
	var wl: float = clampf(GS.wing_l / maxf(GS.wing_max(), 1.0), 0.0, 1.0)
	var wr: float = clampf(GS.wing_r / maxf(GS.wing_max(), 1.0), 0.0, 1.0)
	var hr := rad + 13.0   # v7.8 (owner): the hull ring is yellow (orange, then red as it breaks)
	_ring_gauge(rc, hr, 10.0, -PI * 0.78, -PI * 0.22, hu, _ring_hull_col(hu), 10, hu < 0.25 and blink)
	_ring_gauge(rc, hr, 10.0, PI * 0.95, PI * 0.55, wl, _ring_hull_col(wl), 6, wl < 0.25 and blink)
	_ring_gauge(rc, hr, 10.0, PI * 0.05, PI * 0.45, wr, _ring_hull_col(wr), 6, wr < 0.25 and blink)
	# the radar (tap = map)
	draw_circle(rc, rad + 2.0, Color(0.01, 0.05, 0.1, 0.9))
	draw_arc(rc, rad + 2.0, 0, TAU, 64, Color(CYAN, 0.6), 1.5, true)
	_radar(rc, rad - 2.0, false)
	_text(rc + Vector2(-40, -hr + 20), "BODY", 10, Color(WHITE, 0.85), HORIZONTAL_ALIGNMENT_CENTER, 80)
	_text(rc + Vector2(-hr - 6, hr * 0.5), "L WING", 10, Color(WHITE, 0.85), HORIZONTAL_ALIGNMENT_CENTER, 50)
	_text(rc + Vector2(hr - 44, hr * 0.5), "R WING", 10, Color(WHITE, 0.85), HORIZONTAL_ALIGNMENT_CENTER, 50)
	# SPEED on top (tap = cockpit / chase view)
	var sr: Rect2 = g["speed"]
	var pts := PackedVector2Array([sr.position + Vector2(16, 0), Vector2(sr.end.x - 16, sr.position.y), sr.end - Vector2(0, 10), Vector2(sr.end.x - 10, sr.end.y),
		Vector2(sr.position.x + 10, sr.end.y), Vector2(sr.position.x, sr.end.y - 10), sr.position + Vector2(16, 0)])
	draw_colored_polygon(pts.slice(0, 6), Color(0.01, 0.06, 0.12, 0.92 if not held.has("view") else 0.6))
	draw_polyline(pts, Color(CYAN, 0.95), 2.5, true)
	_icon("view", sr.position + Vector2(24, sr.size.y * 0.5), 11.0, CYAN_HI)
	_text(Vector2(sr.position.x + 40, sr.position.y + 22), "%d m/s" % int(space.speed_now), 20, WHITE, HORIZONTAL_ALIGNMENT_CENTER, sr.size.x - 48)
	var mode := ""
	if space.warp_state == "on": mode = "WARP"
	elif space.warp_state == "charging": mode = "WARP CHARGING"
	elif space.engine_kill: mode = "DRIFT"
	elif space.braking: mode = "STOPPING"
	elif space.boosting: mode = "THRUST"
	if space.surface_mode and mode == "": mode = "ALT %d m" % int(space.altitude)
	_text(Vector2(sr.position.x + 40, sr.end.y - 6), mode if mode != "" else ("CHASE VIEW" if GS.view == "cockpit" else "COCKPIT VIEW"), 11, GOLD if mode != "" else CYAN_HI, HORIZONTAL_ALIGNMENT_CENTER, sr.size.x - 48)
	# the four square buttons that used to be round
	var sh_cd: float = space.shield_cd / Data.SHIELD_BOOST_COOLDOWN
	_corner("shield", "SHIELD REPAIR", "shield", Color(0.35, 0.7, 1.0), false, str(GS.shield_charges), sh_cd)
	_corner("repair", "HULL REPAIR", "repair", GOLD, false, str(GS.repairs), space.repair_cd / 1.5)
	_corner("form", "TRANSFORM", "form", GREEN, space.transform_t > 0.0, "", 0.0, space.warp_state != "off")
	var armed: bool = space.special_ready() != "" or space.special_state != "idle"
	_corner("special", "SUPER", "special", ORANGE, armed and pulse > 0.4, "", 0.0, false)
	_gps_strip(Rect2(S.x * 0.5 - 230, sr.position.y - 44, 460, 34))   # v1.5i

## Radar (Job S, v1.4p): the same GPS-style view as the navigation map, small. A grid, faceted blips, a north
## marker, and the course line when one is set. North-up or heading-up, angled or overhead (NavGrid's setting).
## A tap on a blip opens the map with that object's info card.
var radar_blips: Array = []        # [world position, screen position, kind] of what was drawn (hit-testing, tests)
var radar_pick := Vector3.INF      # the world position of the blip the last radar tap landed on (INF = none)
var radar_view := NavGrid.new()
var radar_stats := {}
var radar_north := Vector2.ZERO    # where the N marker was drawn
var radar_route := {}              # {"from", "to"} when a course is drawn on the radar

func radar_pick_at(p: Vector2) -> Vector3:
	var best := Vector3.INF
	var best_d: float = Data.RADAR_HIT_RADIUS
	for bl in radar_blips:
		var d := (bl[1] as Vector2).distance_to(p)
		if d < best_d:
			best_d = d
			best = bl[0]
	return best

func _radar(rc: Vector2, rr: float, label: bool) -> void:
	var pp: Vector3 = space.player.global_position
	# v1.4m: normal range near things; far from everything (out by the sun, say) the radar zooms out until the
	# station, the planets and the gates all fit, so you can see where you are
	var want_rng: float = Data.RADAR_RANGE
	if not space.surface_mode:
		var near := INF
		var far := 0.0
		for n: Node3D in [space.station, space.planet] + space.gates + space.extras:
			if not is_instance_valid(n): continue
			var dn := pp.distance_to(n.global_position)
			near = minf(near, dn)
			far = maxf(far, dn)
		if near > Data.RADAR_RANGE: want_rng = far * Data.RADAR_FIT
	var mwr: Dictionary = space.mission_waypoint()
	var mnode: Node3D = mwr.get("node") if not mwr.is_empty() and is_instance_valid(mwr.get("node")) else null
	if radar_overview > 0.0:   # v1.7o: just after launch with a job: zoomed out over the station, the bases and the target
		radar_overview -= get_process_delta_time()
		var far2 := 0.0
		for n2: Node3D in [space.station, mnode, space.nav_dest] + space.extras:
			if n2 != null and is_instance_valid(n2) and n2.global_position.y > -500000.0: far2 = maxf(far2, pp.distance_to(n2.global_position))
		if far2 > 0.0: want_rng = maxf(want_rng, far2 * Data.RADAR_FIT)
	radar_range = lerpf(radar_range, want_rng, clampf(get_process_delta_time() * Data.RADAR_ZOOM_SPEED, 0.0, 1.0))
	var rng := radar_range * (1.0 + GS.mod("radar")) * (1.0 - 0.6 * space.in_nebula * (1.0 - Data.BEACON_SENSOR_HELP * space.beacon_lit))
	var heading := Data.RADAR_HEADING_UP or NavGrid.orient == "heading"   # v6.9 (owner): the radar's arrow always points up
	var fwd3: Vector3 = -space.player.global_basis.z
	var anchor := rc + Vector2(0, rr * Data.RADAR_HEADING_ANCHOR) if heading else rc
	radar_view.major_px = 44.0
	radar_view.setup(anchor, Vector3(pp.x, 0, pp.z), rr / rng, fwd3 if heading else Vector3.ZERO, NavGrid.tilt == "angled", rr * Data.NAV_DEPTH)
	# the scope: a polygon disc, the grid cut to it, polygon range rings
	NavGrid.fill(self, NavGrid.poly(rc, rr, 16), Color(0.01, 0.05, 0.09, 0.55))
	radar_stats = radar_view.draw_grid(self, Rect2(rc - Vector2(rr, rr), Vector2(rr, rr) * 2.0), rr)
	var rim := NavGrid.poly(rc, rr, 16)
	draw_polyline(rim + PackedVector2Array([rim[0]]), Color(CYAN, 0.75), 2.0, true)
	var half := NavGrid.poly(anchor, rr * 0.5, 16)
	for i in 16:
		var seg := NavGrid.clip_circle(half[i], half[(i + 1) % 16], rc, rr)
		if not seg.is_empty(): draw_line(seg[0], seg[1], Color(CYAN, 0.3), 1.0)
	# the course line
	radar_route = {}
	var course: Node3D = space.autopilot if space.autopilot != null and is_instance_valid(space.autopilot) else (space.nav_dest if space.nav_dest != null and is_instance_valid(space.nav_dest) else null)   # v1.7o: the GPS too
	if course != null:
		var dest := radar_view.to_screen(course.global_position)
		var rseg := NavGrid.clip_circle(anchor, dest, rc, rr)
		if not rseg.is_empty():
			NavGrid.route(self, rseg[0], rseg[1], GREEN, t, dest.distance_to(rc) <= rr, 0.5)
			radar_route = {"from": rseg[0], "to": rseg[1]}
	var items: Array = []   # [position, colour, kind, node]
	for e in space.enemies: items.append([e["node"].global_position, RED if e["node"].get_meta("kind", "enemy") == "enemy" else GOLD, "ship", e["node"]])
	for tr in space.traffic: items.append([tr["node"].global_position, GREEN, "ship", tr["node"]])
	if space.station.get_meta("kind", "") == "station": items.append([space.station.global_position, GREEN, "station", null])
	if not space.surface_mode:
		items.append([space.planet.global_position, Color(0.5, 0.8, 1.0), "planet", null])
		for g in space.gates: items.append([g.global_position, GOLD, "gate", null])
		for x in space.extras:   # v1.7o: the other planets and stations always show (at the rim when far: their way)
			if not is_instance_valid(x): continue
			var big: bool = float(x.get_meta("radius", 0.0)) > 100.0
			items.append([x.global_position, Color(0.5, 0.8, 1.0) if big else GREEN, "planet" if big else "station", null])
		if radar_range > Data.RADAR_RANGE * 1.2 and space.sun_pos != Vector3.INF: items.append([space.sun_pos, Color(1.0, 0.9, 0.4), "star", null])
	if space.surface_mode:   # v1.8y (owner): on a planet the radar shows every base (at the rim when far: their way)
		for b in space.base_spots():
			if space.station.get_meta("kind", "") == "station" and (b["pos"] as Vector3).distance_to(space.station.global_position) < 200.0: continue
			items.append([b["pos"], GREEN, "station", null])
	if mnode != null: items.append([mnode.global_position, GOLD, "mission", null])   # v1.7o: the job's waypoint
	radar_blips.clear()
	for it in items:
		var v: Vector2 = radar_view.to_screen(it[0])
		var off := v - rc
		if off.length() > rr - 5.0: v = rc + off.normalized() * (rr - 5.0)
		match it[2]:
			"planet": NavGrid.sphere(self, v, 6.0, it[1], 12, false)
			"station": NavGrid.ring(self, v, 6.0, it[1], 8, 0.4, 0.2)
			"gate": NavGrid.ring(self, v, 6.0, it[1], 12, 0.3, 0.15, 0.85)
			"star": NavGrid.star(self, v, 3.5, it[1])
			"mission":   # a gold diamond, pulsing
				var ds := 7.0 + 1.5 * sin(t * 5.0)
				NavGrid.fill(self, PackedVector2Array([v + Vector2(0, -ds), v + Vector2(ds, 0), v + Vector2(0, ds), v + Vector2(-ds, 0)]), Color(GOLD, 0.95))
			_:
				var nf: Vector3 = -(it[3] as Node3D).global_basis.z if is_instance_valid(it[3]) else Vector3.FORWARD
				NavGrid.dart(self, v, 5.5, Vector2(nf.x, nf.z).rotated(radar_view.rot), it[1])
		radar_blips.append([it[0], v, it[2]])
	# you: the arrow. Heading-up: fixed, pointing up. North-up: it turns with the ship.
	var hullc := GREEN.lerp(RED, 1.0 - GS.hull / GS.max_hull())
	NavGrid.dart(self, anchor, 11.0, Vector2(fwd3.x, fwd3.z).rotated(radar_view.rot), hullc.lightened(0.2), true)
	# north marker on the rim: straight up in north-up, wherever true north is in heading-up
	var nd := Vector2(0, -1).rotated(radar_view.north_angle())
	radar_north = rc + nd * rr
	var np := Vector2(-nd.y, nd.x)
	NavGrid.fill(self, PackedVector2Array([radar_north + nd * 7.0, radar_north - nd * 3.0 + np * 5.0, radar_north - nd * 3.0 - np * 5.0]), Color(1.0, 0.45, 0.4))
	draw_string(font, radar_north + nd * 15.0 + Vector2(-4, 5), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, Data.ts(13), WHITE)
	_text(Vector2(rc.x - rr, rc.y + rr + (-2.0 if label else 2.0)), "RADAR %s" % _dist(rng), 10, Color(CYAN, 0.8), HORIZONTAL_ALIGNMENT_CENTER, rr * 2.0)

# ---------------------------------------------------------------- v1.5i GPS strip
var gps_drawn := {}   # what the strip showed last frame (tests): {name, dist, eta, k}

## Point A (you) and point B (the destination) on a blue line; your marker slides toward B as the distance closes
## (and back if you fly away), with the name, the distance and the ETA at your current effective speed.
func _gps_strip(rc: Rect2) -> void:
	gps_drawn = {}
	var n: Node3D = space.nav_dest
	if n == null or not is_instance_valid(n): return
	var d: float = space.distance_to(n)
	var full: float = maxf(space.nav_start, d)
	var k := clampf(1.0 - d / maxf(full, 1.0), 0.0, 1.0)
	var eta: float = space.nav_eta()
	_box(rc, Color(0.01, 0.05, 0.1, 0.82), Color(Data.GPS_ROUTE_COLOR, 0.9), 8, 2)
	var x0 := rc.position.x + 34.0
	var x1 := rc.end.x - 34.0
	var y := rc.position.y + 24.0
	var col: Color = Data.GPS_ROUTE_COLOR
	draw_line(Vector2(x0, y), Vector2(x1, y), Color(col, 0.35), 4.0)
	var xa := lerpf(x0, x1, k)
	draw_line(Vector2(xa, y), Vector2(x1, y), col, 4.0)   # the part still to fly
	draw_circle(Vector2(x1, y), 7.0, col)
	_text(Vector2(x1 + 10, y + 5), "B", 13, WHITE)
	var tri := PackedVector2Array([Vector2(xa + 9, y), Vector2(xa - 6, y - 7), Vector2(xa - 6, y + 7)])
	draw_colored_polygon(tri, WHITE)
	_text(Vector2(x0 - 24, y + 5), "A", 13, Color(1, 1, 1, 0.7))
	var eta_s := "--" if eta < 0.0 else ("%dm %02ds" % [int(eta) / 60, int(eta) % 60] if eta >= 60.0 else "%ds" % int(eta))
	var nst: int = space.nav_route.size()
	var lead := "GPS  %s" % n.name if nst <= 1 else "STOP 1/%d  %s" % [nst, n.name]
	var plan: Dictionary = space.nav_plan()
	if plan.get("via", "") == "lane":   # v1.5m: the fastest way is a trade lane: say so, and mark its mouth
		lead = ("RIDING THE LANE  ·  " if plan.get("riding", false) else "VIA TRADE LANE  ·  ") + lead
		if not plan.get("riding", false):
			var ep = _screen(plan["entry"])
			if ep != null:
				draw_arc(ep, 16.0, 0, TAU, 24, Color(0.55, 0.85, 1.0), 3.0)
				_text(ep + Vector2(20, 5), "LANE  %s" % _dist(space.player.global_position.distance_to(plan["entry"])), 12, Color(0.55, 0.85, 1.0))
	_text(Vector2(rc.position.x + 10, rc.position.y + 12), lead, 11, WHITE, HORIZONTAL_ALIGNMENT_LEFT, rc.size.x * 0.5)
	var right := "%s  ·  ETA %s" % [_dist(d), eta_s]
	var total := d
	if nst > 1:   # the whole route too
		total = float(space.route_lengths()[1])
		var te: float = total / maxf(space.eff_speed(), 1.0)
		right += "   ROUTE %s · %s" % [_dist(total), "%dm %02ds" % [int(te) / 60, int(te) % 60] if te >= 60.0 else "%ds" % int(te)]
	_text(Vector2(rc.position.x, rc.position.y + 12), right, 11, col, HORIZONTAL_ALIGNMENT_RIGHT, rc.size.x - 10)
	gps_drawn = {"name": str(n.name), "dist": d, "eta": eta, "k": k, "stops": nst, "total": total, "via": plan.get("via", "direct")}

# ---------------------------------------------------------------- v1.5g ship scan
var way_rect := Rect2()     # where the waypoint / target box was drawn (tap = scan)
var scan := {}              # the scan on screen ({} = none): space.scan_info() of scan_node
var scan_node: Node3D = null
var scan_t := 0.0           # > 0 while a scan is running

## Start a scan of the current target: in range, a ship, takes SCAN_TIME. Returns what to say.
func start_scan() -> String:
	var n: Node3D = space.target
	if n == null or not is_instance_valid(n): return "No target to scan."
	if space.scan_info(n).is_empty(): return "%s is not a ship." % n.name
	if space.distance_to(n) > Data.SCAN_RANGE: return "Too far to scan: get within %s." % _dist(Data.SCAN_RANGE)
	scan_node = n
	scan = {}
	scan_t = Data.SCAN_TIME
	Sfx.play("tractor", -10.0)
	return "Scanning %s..." % n.name

func close_scan() -> void:
	scan = {}
	scan_node = null
	scan_t = 0.0

func scan_rect() -> Rect2:
	return Rect2(S.x * 0.5 - 250, 132, 500, 64 + 30 * maxi(1, (scan.get("lines", []) as Array).size()))

func _tick_scan(dt: float) -> void:
	if scan_node == null: return
	if not is_instance_valid(scan_node) or space.target != scan_node:
		close_scan()
		return
	if scan_t > 0.0:
		scan_t -= dt
		if scan_t <= 0.0:
			scan = space.scan_info(scan_node)
			Sfx.play("pickup", -10.0)
	elif not scan.is_empty() and int(t * 2.0) != int((t - dt) * 2.0):
		scan = space.scan_info(scan_node)   # live hull / weapons while it is open

func _draw_scan() -> void:
	if scan_node == null or not is_instance_valid(scan_node): return
	var sp = _screen(scan_node.global_position)
	if scan_t > 0.0:   # scanning: a sweeping bracket on the ship and a progress bar
		var k := 1.0 - scan_t / Data.SCAN_TIME
		if sp != null:
			var r := 40.0 + 10.0 * sin(t * 12.0)
			draw_arc(sp, r, -PI * 0.5, -PI * 0.5 + TAU * k, 40, CYAN_HI, 3.0)
			_text(sp + Vector2(-40, -r - 10), "SCANNING %d%%" % int(k * 100.0), 13, CYAN_HI)
		return
	if scan.is_empty(): return
	var rc := scan_rect()
	var col: Color = RED if scan.get("hostile", false) else CYAN_HI
	_box(rc, Color(0.02, 0.06, 0.1, 0.9), col, 10, 2)
	_text(rc.position + Vector2(16, 28), str(scan["title"]), 18, WHITE, HORIZONTAL_ALIGNMENT_LEFT, rc.size.x - 60)
	_text(rc.position + Vector2(16, 50), str(scan["sub"]), 13, col)
	_text(Vector2(rc.end.x - 30, rc.position.y + 26), "X", 16, Color(1, 1, 1, 0.7))
	var y := rc.position.y + 80
	for ln in scan["lines"]:
		_text(Vector2(rc.position.x + 16, y), str(ln[0]), 12, GOLD)
		_text(Vector2(rc.position.x + 110, y), str(ln[1]), 13, WHITE, HORIZONTAL_ALIGNMENT_LEFT, rc.size.x - 126)
		y += 30
	if sp != null: draw_arc(sp, 34.0, 0, TAU, 32, Color(col, 0.8), 2.0)

## Waypoint box: autopilot destination, else the current target.
func _way_box(way_r: Rect2) -> void:
	_box(way_r, PANEL, EDGE, 10, 2)
	var wp: Node3D = space.autopilot if space.autopilot != null else space.target
	var mission := false   # v1.5a: nothing picked: the box shows the mission waypoint
	if not (wp and is_instance_valid(wp)):
		var mwb: Dictionary = space.mission_waypoint()
		if not mwb.is_empty():
			wp = mwb["node"]
			mission = true
	var dcol := GOLD
	if wp and is_instance_valid(wp):
		if wp.get_meta("kind", "") == "enemy": dcol = RED
		var dia := way_r.position + Vector2(20, 24)
		draw_colored_polygon(PackedVector2Array([dia + Vector2(0, -9), dia + Vector2(9, 0), dia + Vector2(0, 9), dia + Vector2(-9, 0)]), dcol)
		_text(way_r.position + Vector2(36, 22), "MISSION" if mission else ("WAYPOINT" if space.autopilot != null else "TARGET"), 12, CYAN_HI)
		_text(way_r.position + Vector2(36, 44), _dist(space.distance_to(wp)), 20, WHITE)
		_text(way_r.position + Vector2(12, 62), wp.name, 11, dcol, HORIZONTAL_ALIGNMENT_LEFT, way_r.size.x - 20)
		var th: float = space.target_health()
		if wp == space.target and th >= 0.0:
			var ts: float = space.target_shield()
			var bw := way_r.size.x - 24
			if ts >= 0.0:
				draw_rect(Rect2(way_r.position + Vector2(12, 64), Vector2(bw, 3)), Color(0, 0, 0, 0.6))
				draw_rect(Rect2(way_r.position + Vector2(12, 64), Vector2(bw * ts, 3)), CYAN_HI)
			draw_rect(Rect2(way_r.position + Vector2(12, 68), Vector2(bw, 4)), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(way_r.position + Vector2(12, 68), Vector2(bw * th, 4)), _hull_col(th))
	else:
		_text(way_r.position + Vector2(12, 34), "NO WAYPOINT", 13, Color(1, 1, 1, 0.6))
	var sens := "NORMAL"
	var scol := GREEN
	if space.in_nebula > 0.0:
		sens = "DEGRADED"
		scol = GOLD
	elif space.hostiles_near(900.0) > 0:
		sens = "%d HOSTILE" % space.hostiles_near(900.0)
		scol = RED
	_text(way_r.position + Vector2(12, 82), "SCAN  " + sens, 12, scol)
	if space.target != null and is_instance_valid(space.target) and not space.scan_info(space.target).is_empty():
		_text(way_r.position + Vector2(12, -6), "TAP = SCAN", 10, CYAN_HI, HORIZONTAL_ALIGNMENT_RIGHT, way_r.size.x - 24)   # (over the box: clear of TARGET)

# ---------------------------------------------------------------- comms: side screens + console
func _comms() -> void:
	if console_open: _roster()
	for side in ["l", "r"]: _side(side)   # callers draw over / beside the console panels

## One holo screen sliding in from its side: name strip, portrait, and the line on a white see-through panel under it.
func _side(side: String) -> void:
	var d: Dictionary = slots[side]
	if d.is_empty(): return
	var r := side_rect(side)
	var e := ease(float(d["anim"]), 0.4)
	r.position.x += (1.0 - e) * (r.size.x + 24.0) * (-1.0 if side == "l" else 1.0)
	var accent := RED if d["hostile"] else CYAN_HI
	var a := 0.55 + 0.45 * e
	_box(r, Color(0.02, 0.07, 0.14, 0.5 * a), Color(accent, 0.9 * a), 8, 2)
	# name strip
	var head := Rect2(r.position, Vector2(r.size.x, 26))
	draw_rect(head, Color(accent.darkened(0.35), 0.85 * a))
	var parts := (d["from"] as String).split(" — ", true, 1)
	var nm := parts[0].to_upper()
	var fs := 15
	var nw := r.size.x - (44 if d["mode"] == "talk" else 12)
	while fs > 10 and font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > nw: fs -= 1
	_text(head.position + Vector2(6, 18), nm, fs, WHITE)
	if d["mode"] == "talk" and buttons.has("hangup"):
		var hb: Rect2 = buttons["hangup"]
		hb.position.x += (1.0 - e) * (r.size.x + 24.0) * (-1.0 if side == "l" else 1.0)
		draw_rect(hb, Color(RED, 0.9))
		_text(hb.position + Vector2(0, 16), "END", 12, WHITE, HORIZONTAL_ALIGNMENT_CENTER, hb.size.x)
	# portrait
	var pr := Rect2(r.position + Vector2(6, 30), Vector2(r.size.x - 12, r.size.x - 12))
	pr.size.y = minf(pr.size.y, r.size.y - 30 - 70)
	var clip := str(d.get("video", "")) != ""
	if clip: pr.size.y = r.size.y - 36   # v1.7s (owner): a clip is the whole call: it fills the screen, no typed line under it
	var tex: Texture2D = _face_tex(d["face"], d["expr"]) if d["face"] != "" else null
	var talk: float = Sfx.talking if side == _last else 0.0
	if str(d.get("video", "")) != "" and vid != null and vid.get_video_texture() != null and vid.get_video_texture().get_width() > 0:
		tex = vid.get_video_texture()   # (the clip, last frame held when it ends)
		talk = 0.0
	if tex:
		var src := Rect2(Vector2.ZERO, tex.get_size())
		var asp := pr.size.x / pr.size.y
		if asp > 1.0: src = Rect2(0, src.size.y * (1.0 - 1.0 / asp) * 0.3, src.size.x, src.size.y / asp)
		var tasp: float = src.size.x / src.size.y
		if tasp < asp: src = Rect2(0, src.size.y * 0.04, src.size.x, src.size.x / asp)   # a tall clip: keep the head and shoulders
		draw_texture_rect_region(tex, Rect2(pr.position + Vector2(0, -2.0 * talk), pr.size), src, Color(1, 1, 1, a).lerp(Color(1.12, 1.12, 1.12, a), talk))
	else:
		draw_rect(pr, Color(0.02, 0.1, 0.2, 0.8 * a))
		var cc := pr.get_center()
		for i in 15:
			var hgt := 6.0 + 26.0 * absf(sin(t * 7.0 + i * 0.9)) * (0.35 + 0.65 * Sfx.talking)
			var x := cc.x - 42 + i * 6
			draw_line(Vector2(x, cc.y - hgt * 0.5), Vector2(x, cc.y + hgt * 0.5), accent, 3)
	for k in int(pr.size.y / 4.0):   # holo scanlines
		draw_line(Vector2(pr.position.x, pr.position.y + k * 4), Vector2(pr.end.x, pr.position.y + k * 4), Color(0, 0.1, 0.2, 0.12), 1)
	var sy := fmod(t * 60.0, pr.size.y)
	draw_line(Vector2(pr.position.x, pr.position.y + sy), Vector2(pr.end.x, pr.position.y + sy), Color(accent, 0.2), 3)
	draw_rect(pr, Color(accent, 0.7 * a), false, 1.5)
	if e < 1.0:   # digital materialise: bright bands sweep while it slides in
		for k in 6: draw_rect(Rect2(r.position.x, r.position.y + fmod(k * 53.0 + t * 900.0, r.size.y), r.size.x, 3), Color(accent, 0.5 * (1.0 - e)))
	if clip: return
	if d["mode"] == "pick":   # v1.8q: a picked contact: CALL under the face
		var cb := Rect2(r.position.x + 5, r.end.y - 63, r.size.x - 10, 58)
		var okc: bool = d.get("ok", true)
		var cc2 := GREEN if okc else Color(0.55, 0.6, 0.66)
		_box(cb, Color(cc2.darkened(0.5), 0.92 * a) if not held.has("call_pick") else Color(cc2, 0.6), Color(cc2, a), 10, 2)
		_text(Vector2(cb.position.x, cb.position.y + (30 if okc else 24)), "CALL" if okc else "OUT OF RANGE", 22 if okc else 13, WHITE, HORIZONTAL_ALIGNMENT_CENTER, cb.size.x)
		if okc: _text(Vector2(cb.position.x, cb.position.y + 48), "TAP TO CALL", 10, Color(cc2.lightened(0.4), a), HORIZONTAL_ALIGNMENT_CENTER, cb.size.x)
		elif str(d.get("sub", "")) != "": _text(Vector2(cb.position.x, cb.position.y + 44), str(d["sub"]), 10, Color(1, 1, 1, 0.7 * a), HORIZONTAL_ALIGNMENT_CENTER, cb.size.x)
		return
	# the line, on white see-through glass under the portrait
	var tr := Rect2(Vector2(r.position.x + 5, pr.end.y + 5), Vector2(r.size.x - 10, r.end.y - pr.end.y - 10))
	draw_rect(tr, Color(1, 1, 1, 0.7 * a))
	draw_rect(tr, Color(accent, 0.8 * a), false, 1.5)
	var tag := ("HOSTILE" if d["hostile"] else "FRIENDLY") + (" · LIVE" if d["mode"] == "talk" else "")
	draw_string(font, tr.position + Vector2(5, 12), tag, HORIZONTAL_ALIGNMENT_LEFT, tr.size.x - 10, 9, Color(accent.darkened(0.45), a))
	draw_multiline_string(font, tr.position + Vector2(5, 26), d["line"], HORIZONTAL_ALIGNMENT_LEFT, tr.size.x - 10, 13, maxi(1, int((tr.size.y - 16) / 15.0)), Color(0.03, 0.07, 0.13, a))

func _dist(d: float) -> String:
	return "%.1f km" % (d / 1000.0) if d >= 1000.0 else "%d m" % int(d)

## Comms console (LOG, v1.8q): tap a name and the picture comes up beside the list with CALL under it.
## Comms console (LOG): contacts on the left (only people in this star system pick up), the chat log on the right,
## TYPE and VOICE along the bottom.
func _roster() -> void:
	if console_view == "chat":
		_chat_panel()
		return
	var r := contacts_rect()
	# ---- left edge (v1.8r): who you can call. Faces flush left, names beside them; tap a row and the picture comes up on the right.
	draw_rect(r, Color(0.02, 0.07, 0.14, 0.9))
	draw_line(Vector2(r.end.x, r.position.y), r.end, CYAN_HI, 2)
	_text(r.position + Vector2(10, 22), "CALL LIST", 15, WHITE)
	var cl := call_list()
	if buttons.has("met_up"):
		_pill("met_up", "UP", false, CYAN)
		_pill("met_down", "DOWN", false, CYAN)
	var rh: float = Data.COMMS_ROW_H
	# the first row is whoever CALL used to reach: your target, or control / the guide
	var hr := Rect2(r.position.x, r.position.y + 32, r.size.x - 6, rh - 4)
	var hsel := pick == "hail"
	draw_rect(hr, Color(GREEN, 0.3) if hsel or held.has("met_hail") else Color(0.05, 0.13, 0.23, 1.0))
	draw_rect(hr, Color(GREEN, 1.0 if hsel else 0.7), false, 2.0 if hsel else 1.0)
	_text(Vector2(hr.position.x + 10, hr.position.y + 18), "TARGET / CONTROL", 14, WHITE)
	_text(Vector2(hr.position.x + 10, hr.position.y + 34), "TAP TO SELECT", 10, Color(GREEN, 0.95))
	if cl.is_empty():
		draw_multiline_string(font, Vector2(r.position.x + 10, hr.end.y + 22), "Nobody yet. Friendly people you meet appear here.", HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 20, 12, 3, Color(1, 1, 1, 0.7))
	for k in mini(cl.size() - contact_scroll, contact_rows() - 1):
		var br := Rect2(r.position.x, r.position.y + 32 + (k + 1) * rh, r.size.x - 6, rh - 4)
		var id: String = cl[k + contact_scroll]
		var c: Dictionary = Data.CHARACTERS[id]
		var ok := in_range(id)
		var m: String = GS.mood.get(id, "neutral")
		var mc: Color = {"friendly": GREEN, "neutral": CYAN_HI, "enraged": RED}[m]
		if not ok: mc = Color(0.55, 0.6, 0.66)
		var down := held.has("met_%d" % k)
		draw_rect(br, Color(mc, 0.25) if down else Color(0.05, 0.13, 0.23, 1.0 if ok else 0.6))
		draw_rect(br, Color(mc, 0.7 if ok else 0.35), false, 1.0)
		if pick == id: draw_rect(br, Color(mc, 1.0), false, 2.5)   # the one whose picture is up
		var fs := br.size.y
		var fr := Rect2(br.position.x, br.position.y, fs, fs)   # face against the screen edge
		var ftex: Texture2D = _face_tex(c.get("face", ""), "normal") if c.get("face", "") != "" else null
		if ftex: draw_texture_rect(ftex, fr, false, Color(1, 1, 1, 1.0 if ok else 0.4))
		else: draw_circle(fr.get_center(), fs * 0.4, Color(c["color"], 0.9))
		var tw := br.size.x - fs - 12
		_text(Vector2(br.position.x + fs + 8, br.position.y + 18), c["name"], 14, WHITE if ok else Color(1, 1, 1, 0.5), HORIZONTAL_ALIGNMENT_LEFT, tw)
		var sub: String = "TAP TO SELECT" if ok else "OUT OF RANGE · %s" % Data.SYSTEMS[c["system"]]["name"].to_upper()
		_text(Vector2(br.position.x + fs + 8, br.position.y + 34), sub, 10, Color(mc, 0.95) if ok else Color(1, 1, 1, 0.45), HORIZONTAL_ALIGNMENT_LEFT, tw)

## v1.8s (owner: less on the screen): the text screen of a call: the message log with TYPE / HOLD TO TALK / VOICE, on the
## left in place of the call list, with CLOSE. It comes up when you press CALL (or tap a caller's screen).
func _chat_panel() -> void:
	var lg := msglog_rect()
	# ---- right edge (v1.8r): the message log, newest at the top; TYPE and VOICE under it
	draw_rect(lg, Color(0.02, 0.07, 0.14, 0.9))
	draw_line(Vector2(lg.end.x, lg.position.y), lg.end, CYAN_HI, 2)
	_text(lg.position + Vector2(10, 22), "MESSAGES", 15, WHITE)
	if buttons.has("chat_close"): _pill("chat_close", "CLOSE", false, CYAN)
	var lr := Rect2(lg.position.x + 6, lg.position.y + 32, lg.size.x - 12, lg.size.y - 32 - 50)
	draw_rect(lr, Color(1, 1, 1, 0.08))
	var y := lr.position.y + 16
	for line in history:
		if y > lr.end.y - 6: break
		var mine := (line as String).begins_with("YOU:")
		var lines := maxi(1, int(ceil(font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x / (lr.size.x - 12))))
		var room := maxi(1, int((lr.end.y - y) / 15.0) + 1)
		draw_multiline_string(font, Vector2(lr.position.x + 6, y), line, HORIZONTAL_ALIGNMENT_LEFT, lr.size.x - 12, 12, mini(4, room), GOLD if mine else Color(0.85, 0.92, 1.0))
		y += 15.0 * mini(lines, 4) + 5.0
	if roster_t > 0.95 and not roster_closing:
		_pill("type", "TYPE", _typer.visible, CYAN)
		_pill("talk", "LISTENING" if listening else "HOLD TO TALK", listening, GREEN if listening else CYAN, heard_text.left(18) if listening and heard_text != "" else "")
		_pill("voice", "VOICE", false, CYAN, "REPLAY")   # v1.9a: one voice option (clone, else device voice): this replays the line
	if _typer.visible:
		_typer.size = Vector2(minf(420.0, S.x - lg.end.x - side_rect("r").size.x - 32), 40)
		_typer.position = Vector2(lg.end.x + 8, lg.end.y - 44)

## TYPE: open the message box (the phone keyboard comes up).
# ---------------------------------------------------------------- v1.5j hold-to-talk
var listening := false
var heard_text := ""
var _listen_wait := 0.0     # after release: waiting for the browser's last words (seconds left)
var speech_override := ""   # tests: pretend the browser heard this ("" = use the browser)

## Can this device turn speech into text? (Web only, and only where the browser has speech recognition.)
func speech_supported() -> bool:
	if speech_override != "": return true
	if not OS.has_feature("web"): return false
	return bool(JavaScriptBridge.eval("!!(window.__hlSR && window.__hlSR.supported)", true))

func talk_press() -> void:
	roster_idle = 0.0
	if not speech_supported():
		flash_message("Voice input isn't available on this device or browser: type instead.")
		start_typing()
		return
	listening = true
	heard_text = ""
	_listen_wait = 0.0
	Sfx.stop_voice()   # nobody talks over you
	Sfx.play("comm_open", -10.0)
	if speech_override == "" and OS.has_feature("web"): JavaScriptBridge.eval("window.__hlListenStart && window.__hlListenStart()", true)

func talk_release() -> void:
	if not listening: return
	listening = false
	if speech_override == "" and OS.has_feature("web"): JavaScriptBridge.eval("window.__hlListenStop && window.__hlListenStop()", true)
	_listen_wait = Data.TALK_FINISH_WAIT

## Every frame while listening or just after: read what the browser heard; when it is done, hand the words to the
## same place typed text goes (the character's brain answers, and the voice provider speaks the answer).
func _tick_talk(dt: float) -> void:
	if not listening and _listen_wait <= 0.0: return
	var st := "listening"
	if speech_override != "":
		heard_text = speech_override
		st = "done" if not listening else "listening"
	elif OS.has_feature("web"):
		heard_text = str(JavaScriptBridge.eval("(window.__hlSR && window.__hlSR.text) || ''", true))
		st = str(JavaScriptBridge.eval("(window.__hlSR && window.__hlSR.state) || 'error'", true))
	if listening: return
	_listen_wait -= dt
	if st == "error" and heard_text == "":
		_listen_wait = 0.0
		flash_message("Didn't catch that: type instead.")
		start_typing()
		return
	if st == "done" or _listen_wait <= 0.0:
		_listen_wait = 0.0
		var said := heard_text.strip_edges()
		heard_text = ""
		if said == "":
			flash_message("Didn't catch that: hold TALK and speak, or type.")
			return
		_log("You: %s" % said)
		typed.emit(said)

func start_typing() -> void:
	roster_idle = 0.0
	_typer.visible = true
	_typer.grab_focus()
