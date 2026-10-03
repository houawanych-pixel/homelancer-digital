class_name Rooms
extends Control
## Station interiors as panorama rooms (owner + Grok design notes, Oct 2).
## A room is ONE long picture: the front view and the back view side by side, with a blended bridge at each join
## (tools/rooms/make_strip.py builds it from a 16:9 image with front on top, back on the bottom). You look around by dragging: it scrolls left and right forever
## (seamless wrap) and tilts only a little up and down. No floor or ceiling beyond the picture.
## A LOOK stick (bottom right) turns the view; the marker nearest the middle lights up GREEN and a green button
## appears: one tap uses it. Signs, doors and people are HOTSPOTS: you can also tap one directly. A door zooms into it, swaps the picture while zoomed, and zooms out
## in the next room (the zoom hides the swap). Only the current room's picture is in memory.
## Pictures live in the "rooms" content pack (assets/rooms/<id>.jpg).

signal action(act: String)   # "screen:<hub screen>", "launch", "map", "inspect"; rooms and talk are handled here

const CYAN := Color(0.4, 0.86, 1.0)
const GOLD := Color(1.0, 0.82, 0.4)
const GREEN := Color(0.25, 0.92, 0.45)   # "ready": the same green as the docking prompt
const STICK_R := 74.0
const STICK_TURN := 0.16      # strip lengths per second at full stick: a full turn takes about 6 s
const STICK_TILT := 1.6       # tilt units per second at full stick (the tilt range is small)
const FOCUS_HALF := 0.17      # a marker within this share of the screen width from the middle is "in view"
const OVERSCAN := 1.14        # the picture is this much taller than the screen: that is the tilt you get
const ZOOM_IN := 0.42         # seconds to zoom into a door
const ZOOM_OUT := 0.38

## Which room you arrive in when you dock, by station id.
const STATIONS := {"liberty_hub": "main_hub"}

## u, v: where the hotspot sits on the picture (u 0..1 across the whole strip: 0..0.5 front view, 0.5..1 back view;
## v 0 top .. 1 bottom). act: "room:<id>" | "screen:<hub screen>" | "launch" | "map" | "inspect" | "say:<text>" | "talk:<character>"
const ROOMS := {
	"main_hub": {"name": "UNITY STATION · MAIN HUB H-01", "face": 0.25, "spots": [
		{"u": 0.045, "v": 0.50, "label": "STARBORN CAFÉ", "sub": "Unity Bar H-08", "act": "room:bar"},
		{"u": 0.170, "v": 0.47, "label": "SHIP DEALER", "sub": "H-02", "act": "screen:ships"},
		{"u": 0.250, "v": 0.70, "label": "SERVICE DESK", "sub": "Repair and resupply", "act": "screen:repair"},
		{"u": 0.333, "v": 0.47, "label": "SHIP DEALER", "sub": "H-02", "act": "screen:ships"},
		{"u": 0.434, "v": 0.27, "label": "QUARTERS", "sub": "Apartment A-721", "act": "room:apartment"},
		{"u": 0.539, "v": 0.32, "label": "MISSION CENTER", "sub": "H-04", "act": "room:mission"},
		{"u": 0.600, "v": 0.60, "label": "TRADE MARKET", "sub": "H-05 · up the stairs", "act": "room:market"},
		{"u": 0.742, "v": 0.17, "label": "DOCKING BAY", "sub": "H-06 · launch", "act": "room:docking"},
		{"u": 0.885, "v": 0.60, "label": "HANGAR", "sub": "H-01 · your ship", "act": "room:hangar"},
		{"u": 0.949, "v": 0.28, "label": "EQUIPMENT", "sub": "H-05", "act": "screen:equipment"},
	]},
	"docking": {"name": "UNITY STATION · DOCKING BAY H-06", "face": 0.21, "spots": [
		{"u": 0.210, "v": 0.50, "label": "LAUNCH", "sub": "Take your ship out", "act": "launch"},
		{"u": 0.960, "v": 0.66, "label": "NAVIGATION", "sub": "System map", "act": "map"},
		{"u": 0.751, "v": 0.72, "label": "MAIN HUB", "sub": "H-01", "act": "room:main_hub"},
		{"u": 0.633, "v": 0.60, "label": "DECK CREW", "sub": "Talk", "act": "say:Bay's clear, pilot. Your ship is fuelled and on the rail whenever you want her."},
	]},
	"mission": {"name": "UNITY STATION · MISSION CENTER H-03", "face": 0.25, "spots": [
		{"u": 0.172, "v": 0.50, "label": "CONTRACTS", "sub": "Bounty · escort · trade", "act": "say:No contracts are posted yet. Check back soon, pilot."},
		{"u": 0.250, "v": 0.72, "label": "CMDR. VALE", "sub": "Talk", "act": "talk:vale"},
		{"u": 0.724, "v": 0.36, "label": "GALAXY MAP", "sub": "Navigation", "act": "map"},
		{"u": 0.750, "v": 0.88, "label": "MAIN HUB", "sub": "H-01", "act": "room:main_hub"},
	]},
	"market": {"name": "UNITY STATION · TRADE MARKET H-05", "face": 0.25, "spots": [
		{"u": 0.466, "v": 0.42, "label": "WEAPONS & DEFENSE", "sub": "Equipment dealer", "act": "screen:equipment"},
		{"u": 0.250, "v": 0.72, "label": "TRADERS", "sub": "Talk", "act": "say:Cargo trading opens soon. For now the weapons stall is the one doing business."},
		{"u": 0.712, "v": 0.26, "label": "EQUIPMENT", "sub": "H-04", "act": "screen:equipment"},
		{"u": 0.750, "v": 0.70, "label": "MAIN HUB", "sub": "H-01", "act": "room:main_hub"},
		{"u": 0.790, "v": 0.26, "label": "DOCKING BAY", "sub": "H-06", "act": "room:docking"},
	]},
	"bar": {"name": "UNITY STATION · UNITY BAR H-08", "face": 0.25, "spots": [
		{"u": 0.250, "v": 0.62, "label": "BARTENDER", "sub": "Talk", "act": "say:What'll it be? Word is the raiders in the belt answer to someone called Shade."},
		{"u": 0.443, "v": 0.50, "label": "LIVE MUSIC", "sub": "Listen", "act": "say:The band plays on. Different worlds, same sky."},
		{"u": 0.750, "v": 0.72, "label": "MAIN HUB", "sub": "H-01", "act": "room:main_hub"},
	]},
	"hangar": {"name": "UNITY STATION · HANGAR H-01", "face": 0.25, "spots": [
		{"u": 0.251, "v": 0.52, "label": "YOUR SHIP", "sub": "Inspect", "act": "inspect"},
		{"u": 0.419, "v": 0.38, "label": "MAINTENANCE", "sub": "Repair and resupply", "act": "screen:repair"},
		{"u": 0.531, "v": 0.27, "label": "CUSTOMIZATION", "sub": "Weapons and gear", "act": "screen:equipment"},
		{"u": 0.966, "v": 0.27, "label": "REPAIRS", "sub": "Back in the fight", "act": "screen:repair"},
		{"u": 0.750, "v": 0.56, "label": "MAIN HUB", "sub": "Through the door", "act": "room:main_hub"},
	]},
	"apartment": {"name": "UNITY STATION · APARTMENT A-721", "face": 0.30, "spots": [
		{"u": 0.049, "v": 0.45, "label": "DOOR", "sub": "Main Hub", "act": "room:main_hub"},
		{"u": 0.575, "v": 0.78, "label": "BED", "sub": "Rest", "act": "say:You rest a while. The station hums around you."},
		{"u": 0.826, "v": 0.45, "label": "STATION MAP", "sub": "Navigation", "act": "map"},
	]},
}

var room := ""
var tex: Texture2D
var pan := 0.25          # u at the middle of the screen
var tilt := 0.0          # -1 (look up) .. 1 (look down)
var zoom := 1.0
var fade := 0.0
var busy := false
var caption := ""        # what someone just said
var caption_who := ""
var caption_t := 0.0
var font: Font = ThemeDB.fallback_font
var _t := 0.0
var _drag := false
var _moved := 0.0
var _vel := 0.0
var _zoom_at := Vector2.ZERO
var look := Vector2.ZERO   # the look stick, -1..1 (x turns, y tilts)
var focus := -1            # the marker in the middle of the view (green = ready), -1 = none
var _stick_on := false

## The strip is [front | bridge | back | bridge] (tools/rooms/make_strip.py). Marker positions are written against the
## two views (0..0.5 front, 0.5..1 back); this turns one into a position along the real strip.
const VIEW_W := 1672.0
const BRIDGE := 160.0
static func strip_u(u: float) -> float:
	var x := u * 2.0 * VIEW_W if u < 0.5 else VIEW_W + BRIDGE + (u - 0.5) * 2.0 * VIEW_W
	return x / (2.0 * VIEW_W + 2.0 * BRIDGE)

static func start_room(station_id: String) -> String:
	return STATIONS.get(station_id, "")

static func available(station_id: String) -> bool:
	return STATIONS.has(station_id) and Packs.is_ready("rooms")

static func path(id: String) -> String: return "res://assets/rooms/%s.jpg" % id

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

## Show a room straight away (no zoom), looking the way that room's "face" says.
func open(id: String) -> void:
	room = id
	tex = load(path(id))   # the previous room's picture is dropped here: only one is ever loaded
	pan = strip_u(float(ROOMS[id]["face"]))
	tilt = 0.0
	zoom = 1.0
	fade = 0.0
	caption = ""
	visible = true
	queue_redraw()

## Go through a door: zoom into it, swap the picture while zoomed in, zoom back out in the new room.
func go(id: String, at: Vector2) -> void:
	if busy or not ROOMS.has(id): return
	busy = true
	_zoom_at = at
	caption = ""
	var tw := create_tween()
	tw.tween_property(self, "zoom", 2.6, ZOOM_IN).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.parallel().tween_property(self, "fade", 1.0, ZOOM_IN).set_ease(Tween.EASE_IN)
	await tw.finished
	open(id)
	zoom = 1.5
	fade = 1.0
	_zoom_at = size * 0.5
	var tw2 := create_tween()
	tw2.tween_property(self, "zoom", 1.0, ZOOM_OUT).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw2.parallel().tween_property(self, "fade", 0.0, ZOOM_OUT)
	await tw2.finished
	busy = false

func _scale() -> float:
	return size.y * OVERSCAN / float(tex.get_height())

## Screen position of a point on the picture (the copy nearest the middle of the screen).
func spot_pos(u: float, v: float) -> Vector2:
	var sc := _scale()
	var w := tex.get_width() * sc
	var du := fposmod(strip_u(u) - pan + 0.5, 1.0) - 0.5
	var extra := size.y * (OVERSCAN - 1.0)
	return Vector2(size.x * 0.5 + du * w, v * tex.get_height() * sc - extra * (0.5 + 0.5 * tilt))

func _process(dt: float) -> void:
	if not visible: return
	_t += dt
	if look != Vector2.ZERO and not busy and tex != null:   # the look stick: big left-right sweep, gentle up-down
		pan = fposmod(pan + look.x * STICK_TURN * dt, 1.0)
		tilt = clampf(tilt + look.y * STICK_TILT * dt, -1.0, 1.0)
		_vel = 0.0
	focus = _find_focus()
	if not _drag and absf(_vel) > 0.0001:   # a flick keeps turning for a moment
		pan = fposmod(pan + _vel * dt, 1.0)
		_vel = lerpf(_vel, 0.0, clampf(dt * 4.0, 0.0, 1.0))
	if caption_t > 0.0:
		caption_t -= dt
		if caption_t <= 0.0: caption = ""
	queue_redraw()

## Where the look stick sits (bottom right, like the aim stick in flight) and the green GO button (bottom middle).
func stick_center() -> Vector2: return Vector2(size.x - STICK_R - 46.0, size.y - STICK_R - 46.0)
func go_rect() -> Rect2: return Rect2(size.x * 0.5 - 190.0, size.y - 104.0, 380.0, 62.0)

## The marker nearest the middle of the view, if it is close enough to count as "in view".
func _find_focus() -> int:
	if tex == null or busy: return -1
	var best := -1
	var bd := size.x * FOCUS_HALF
	var spots: Array = ROOMS[room]["spots"]
	for i in spots.size():
		var d := absf(spot_pos(spots[i]["u"], spots[i]["v"]).x - size.x * 0.5)
		if d < bd:
			bd = d
			best = i
	return best

func _gui_input(e: InputEvent) -> void:
	if busy or tex == null: return
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			if e.position.distance_to(stick_center()) < STICK_R * 1.5:   # thumb on the look stick
				_stick_on = true
				look = ((e.position - stick_center()) / STICK_R).limit_length(1.0)
				return
			_drag = true
			_moved = 0.0
			_vel = 0.0
		else:
			if _stick_on:
				_stick_on = false
				look = Vector2.ZERO
				return
			_drag = false
			if _moved < 14.0: tap(e.position)
	elif e is InputEventMouseMotion and _stick_on:
		look = ((e.position - stick_center()) / STICK_R).limit_length(1.0)
	elif e is InputEventMouseMotion and _drag:
		drag(e.relative)
		_moved += e.relative.length()

## Look around: sideways scrolls the picture (wraps forever), up/down tilts a little.
func drag(rel: Vector2) -> void:
	var w := tex.get_width() * _scale()
	var du := -rel.x / w
	pan = fposmod(pan + du, 1.0)
	_vel = du * 30.0
	tilt = clampf(tilt - rel.y / (size.y * 0.25), -1.0, 1.0)

## Tap: the nearest hotspot within reach.
func tap(p: Vector2) -> void:
	if focus >= 0 and go_rect().has_point(p):   # the green button: use whatever is in view
		use(focus)
		return
	var best := -1
	var bd := 78.0
	var spots: Array = ROOMS[room]["spots"]
	for i in spots.size():
		var d := spot_pos(spots[i]["u"], spots[i]["v"]).distance_to(p)
		if d < bd:
			bd = d
			best = i
	if best >= 0: use(best)

func use(i: int) -> void:
	var sp: Dictionary = ROOMS[room]["spots"][i]
	var act: String = sp["act"]
	Sfx.play("click")
	if act.begins_with("room:"): go(act.substr(5), spot_pos(sp["u"], sp["v"]))
	elif act.begins_with("say:"): say(sp["label"], act.substr(4))
	elif act.begins_with("talk:"):
		var id := act.substr(5)
		var line: String = Brain.reply(id, "hello", {"system": GS.system_id, "hostiles": 0})
		if line.begins_with("[") and line.find("]") > 0: line = line.substr(line.find("]") + 1)
		say(Data.CHARACTERS[id]["name"], line)
	else: action.emit(act)

func say(who: String, line: String) -> void:
	caption_who = who
	caption = line
	caption_t = 7.0

func _draw() -> void:
	if tex == null: return
	var S := size
	var sc := _scale()
	var w := tex.get_width() * sc
	var h := tex.get_height() * sc
	var extra := S.y * (OVERSCAN - 1.0)
	var y := -extra * (0.5 + 0.5 * tilt)
	if zoom != 1.0: draw_set_transform(_zoom_at * (1.0 - zoom), 0.0, Vector2(zoom, zoom))
	var x0 := fposmod(S.x * 0.5 - pan * w, w) - w   # the first copy starts at or left of the screen edge
	var x := x0
	while x < S.x:
		draw_texture_rect(tex, Rect2(x, y, w, h), false)
		x += w
	# hotspots
	var pulse := 0.5 + 0.5 * sin(_t * 3.0)
	var spots: Array = ROOMS[room]["spots"]
	for i in spots.size():
		var sp: Dictionary = spots[i]
		var p := spot_pos(sp["u"], sp["v"])
		if p.x < -160.0 or p.x > S.x + 160.0: continue
		var door: bool = (sp["act"] as String).begins_with("room:") or sp["act"] == "launch"
		var lit := i == focus   # in the middle of the view: lights up green = ready to use
		var col := GREEN if lit else (GOLD if door else CYAN)
		if lit:
			draw_circle(p, 30.0 + 6.0 * pulse, Color(GREEN, 0.16))
			draw_arc(p, 30.0 + 6.0 * pulse, 0.0, TAU, 36, Color(GREEN, 0.9), 3.5)
		draw_circle(p, 12.0 if lit else 9.0, Color(col, 0.95))
		draw_arc(p, 17.0 + 5.0 * pulse, 0.0, TAU, 28, Color(col, 0.75 - 0.4 * pulse), 2.5)
		var tw := maxf(font.get_string_size(sp["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x, font.get_string_size(sp["sub"], HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x) + 20.0
		var r := Rect2(p.x - tw * 0.5, p.y + 26.0, tw, 42.0)
		draw_rect(r, Color(0.02, 0.12, 0.06, 0.86) if lit else Color(0.02, 0.05, 0.1, 0.78))
		draw_rect(r, Color(col, 0.95 if lit else 0.8), false, 2.5 if lit else 1.5)
		draw_string(font, r.position + Vector2(10, 18), sp["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
		draw_string(font, r.position + Vector2(10, 35), sp["sub"], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
	if zoom != 1.0: draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# room name, credits, hint
	draw_rect(Rect2(0, 0, S.x, 54), Color(0, 0, 0, 0.5))
	draw_string(font, Vector2(24, 35), ROOMS[room]["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)
	draw_string(font, Vector2(S.x - 324, 35), "CREDITS  %d cr" % GS.credits, HORIZONTAL_ALIGNMENT_RIGHT, 300, 20, GOLD)
	draw_string(font, Vector2(0, S.y - 16), "Stick or drag to look around  ·  green = ready, tap it", HORIZONTAL_ALIGNMENT_CENTER, S.x, 14, Color(1, 1, 1, 0.65))
	# the green button: whatever is in the middle of the view, one tap
	if focus >= 0 and not busy:
		var g := go_rect()
		var fs: Dictionary = spots[focus]
		draw_rect(g, Color(0.05, 0.36, 0.16, 0.92))
		draw_rect(g, Color(GREEN, 0.75 + 0.25 * pulse), false, 3.0)
		draw_string(font, Vector2(g.position.x, g.position.y + 27), fs["label"], HORIZONTAL_ALIGNMENT_CENTER, g.size.x, 20, Color.WHITE)
		draw_string(font, Vector2(g.position.x, g.position.y + 49), "TAP  ·  " + str(fs["sub"]), HORIZONTAL_ALIGNMENT_CENTER, g.size.x, 13, GREEN)
	# the look stick (same look as the aim stick in flight)
	var sc2 := stick_center()
	draw_circle(sc2, STICK_R + 8.0, Color(0.0, 0.05, 0.1, 0.35))
	draw_circle(sc2, STICK_R, Color(0.02, 0.1, 0.2, 0.62 if _stick_on else 0.5))
	draw_arc(sc2, STICK_R, 0.0, TAU, 40, Color(CYAN, 0.5), 2.0)
	draw_circle(sc2 + look * STICK_R * 0.62, STICK_R * 0.34, Color(0.62, 0.8, 0.97, 0.95 if _stick_on else 0.85))
	draw_string(font, Vector2(sc2.x - STICK_R, sc2.y - STICK_R - 14.0), "LOOK", HORIZONTAL_ALIGNMENT_CENTER, STICK_R * 2.0, 13, Color(1, 1, 1, 0.7))
	if caption != "":
		var cr := Rect2(S.x * 0.14, S.y - 216.0, S.x * 0.68, 96.0)
		draw_rect(cr, Color(0.02, 0.05, 0.1, 0.86))
		draw_rect(cr, Color(CYAN, 0.8), false, 2.0)
		draw_string(font, cr.position + Vector2(18, 28), caption_who, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, CYAN)
		draw_multiline_string(font, cr.position + Vector2(18, 54), caption, HORIZONTAL_ALIGNMENT_LEFT, cr.size.x - 36.0, 18, 2, Color.WHITE)
	if fade > 0.0: draw_rect(Rect2(Vector2.ZERO, S), Color(0, 0, 0, fade))
