extends Control
## Galaxy map: a panoramic view THROUGH the travel network, in Homelancer's white + blues blueprint style.
## You stand at the heart of the network and look around: drag left/right (a little up/down) to pan, tap a system to
## see it, EXPAND to open its blueprint (planets, stations, gates, spaceways). Pure data: nothing loads.

signal closed

const BG := Color(0.965, 0.978, 0.992)
const PALE := Color(0.81, 0.89, 0.96)
const SKY := Color(0.56, 0.76, 0.92)
const MID := Color(0.24, 0.56, 0.82)
const DEEP := Color(0.12, 0.37, 0.66)
const NAVY := Color(0.05, 0.18, 0.35)
const SHADES := [PALE, SKY, MID, DEEP, NAVY]
# v3.1: the system view on the dark chart
const SV_INK := Color(0.92, 0.96, 1.0)
const SV_LINE := Color(0.4, 0.8, 1.0)
const SV_SUB := Color(0.55, 0.8, 1.0)
const SV_ORBIT := Color(0.4, 0.6, 0.9, 0.35)
const FOV_H := 1.9   # radians across the screen
const FOV_V := 1.05

var font: Font = ThemeDB.fallback_font
var yaw := 0.0
var pitch := 0.0
var current := "solara"
var selected := ""
var expanded := ""
var viewer := Vector3(-10, 0, -20)
var t := 0.0
var _drag_from := Vector2.INF
var _drag_moved := 0.0
var _hits := {}
var boxes := 0   # v1.9e (tests): system boxes drawn in the last frame
var _btns := {}
var focus := ""      # the front system nearest the centre of view: outlined and named as you pan past it
var focus_t := 0.0   # 0..1 fade-in of that outline
var flat := true     # v1.4m: the map opens as the flat 11 x 11 chart with fog of war; "3D VIEW" shows the old look-around
var backdrop: Texture2D = null   # v1.5q: the old network picture was removed (owner)
const FOCUS_DIST := 70.0   # only systems this close count as "in front" (the far ones are just stars)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

func open(system_id: String) -> void:
	current = system_id
	selected = system_id
	expanded = ""
	fz = 1.0
	fpan = Vector2.ZERO
	var net := Galaxy.network()
	var d: Vector3 = (net["systems"][current]["pos"] as Vector3) - viewer
	yaw = atan2(d.x, -d.z)   # face your own system
	pitch = 0.0
	visible = true

func _process(dt: float) -> void:
	if not visible: return
	t += dt
	if _drag_from == Vector2.INF and expanded == "": yaw += dt * 0.015   # slow drift, like a sensor sweep
	var f := focus_of(get_viewport_rect().size, yaw, pitch, viewer)
	if f != focus:
		focus = f
		focus_t = 0.0
	focus_t = minf(1.0, focus_t + dt * 3.0)
	queue_redraw()

## The system in front that is nearest the middle of the screen ("" if none is near the middle).
static func focus_of(S: Vector2, yaw: float, pitch: float, viewer: Vector3) -> String:
	var best := ""
	var bd := S.x * 0.16
	var sys: Dictionary = Galaxy.network()["systems"]
	for id in sys:
		var d: Vector3 = (sys[id]["pos"] as Vector3) - viewer
		if d.length() > FOCUS_DIST: continue
		var dx := wrapf(atan2(d.x, -d.z) - yaw, -PI, PI)
		var el := asin(clampf(d.y / maxf(d.length(), 0.001), -1, 1))
		var p := Vector2(dx / FOV_H * S.x, -(el - pitch) / FOV_V * S.y)
		if p.length() < bd:
			bd = p.length()
			best = id
	return best

## v10.6 (owner: "the galaxy map should let me zoom in and out by pinching"): two fingers pinch the chart (phone),
## a trackpad pinch or the mouse wheel too (desktop); the zoom centres on the fingers.
var _touches := {}
var _pinch_d := 0.0
func _pinch(e: InputEvent) -> bool:
	if not flat or expanded != "": return false
	if e is InputEventMagnifyGesture:
		_zoom(e.factor, e.position); return true
	if e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		_zoom(1.15 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15, e.position); return true
	if e is InputEventScreenTouch:
		if e.pressed: _touches[e.index] = e.position
		else: _touches.erase(e.index)
		_pinch_d = 0.0
		if _touches.size() >= 2:
			var ks := _touches.keys(); _pinch_d = (_touches[ks[0]] as Vector2).distance_to(_touches[ks[1]])
			_drag_from = Vector2.INF   # (two fingers: no tap, no drag)
			_drag_moved = 99.0
			return true
		return false
	if e is InputEventScreenDrag and _touches.size() >= 2:
		_touches[e.index] = e.position
		var ks := _touches.keys()
		var a: Vector2 = _touches[ks[0]]; var b: Vector2 = _touches[ks[1]]
		var d := a.distance_to(b)
		if _pinch_d > 1.0 and d > 1.0: _zoom(d / _pinch_d, (a + b) * 0.5)
		_pinch_d = d
		return true
	return false

func _gui_input(e: InputEvent) -> void:
	if _pinch(e):
		accept_event()
		return
	var pos := Vector2.INF
	var pressed := false
	var released := false
	if e is InputEventScreenTouch:
		pos = e.position
		pressed = e.pressed
		released = not e.pressed
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		pos = e.position
		pressed = e.pressed
		released = not e.pressed
	elif e is InputEventScreenDrag or e is InputEventMouseMotion:
		if _drag_from != Vector2.INF and expanded == "" and flat:   # v1.9e: drag the chart about when zoomed in
			_drag_moved += (e.relative as Vector2).length()
			fpan = _clamp_pan(fpan + (e.relative as Vector2))
		elif _drag_from != Vector2.INF and expanded == "":
			var rel: Vector2 = e.relative
			_drag_moved += rel.length()
			yaw -= rel.x / get_viewport_rect().size.x * FOV_H
			pitch = clampf(pitch + rel.y / get_viewport_rect().size.y * FOV_V, -0.35, 0.35)
		accept_event()
		return
	else:
		return
	accept_event()
	if pressed:
		_drag_from = pos
		_drag_moved = 0.0
		return
	if released:
		_drag_from = Vector2.INF
		if _drag_moved > 12.0: return
		tap(pos)

## Handle a tap (also used by tests).
func tap(pos: Vector2) -> void:
	for b in _btns:
		if (_btns[b] as Rect2).has_point(pos):
			press(b)
			return
	if expanded != "": return
	var best := ""
	var bd := 38.0
	for id in _hits:
		var d: float = (_hits[id] as Vector2).distance_to(pos)
		if d < bd:
			bd = d
			best = id
	if best != "": selected = best

func press(b: String) -> void:
	match b:
		"close":
			if expanded != "": expanded = ""
			else:
				visible = false
				closed.emit()
		"expand": if selected != "": expanded = selected
		"mode": flat = not flat
		"zoom_in": _zoom(Data.MAP_ZOOM_STEP)
		"zoom_out": _zoom(1.0 / Data.MAP_ZOOM_STEP)

## v1.9e: zoom the chart about the middle of the screen, kept on screen.
func _zoom(k: float, at := Vector2.INF) -> void:
	var S := get_viewport_rect().size
	var c := Vector2((378.0 + S.x) * 0.5, (96.0 + S.y) * 0.5) if at == Vector2.INF else at
	var nz := clampf(fz * k, 1.0, Data.MAP_ZOOM_MAX)
	var org := Vector2(378.0, 96.0) + fpan
	fpan = _clamp_pan(c - (c - org) * (nz / fz) - Vector2(378.0, 96.0))
	fz = nz

func _clamp_pan(p: Vector2) -> Vector2:
	var S := get_viewport_rect().size
	var full := Vector2(S.x - 378.0 - 24.0, S.y - 96.0 - 44.0) * fz
	var room := Vector2(S.x - 378.0 - 24.0, S.y - 96.0 - 44.0)
	return Vector2(clampf(p.x, -(full.x - room.x) - 300.0, 0.0), clampf(p.y, -(full.y - room.y), 0.0))

# ---------------------------------------------------------------- drawing
func _draw() -> void:
	var S := get_viewport_rect().size
	_hits.clear()
	_btns.clear()
	boxes = 0
	if flat: _draw_flat(S)
	else:
		draw_network(self, S, yaw, pitch, t, viewer, current, selected, _hits, true, focus, focus_t, backdrop)
		_title(S)
	var mb := Rect2(Vector2(S.x - 300, 16), Vector2(140, 48))
	if expanded == "":
		_btns["mode"] = mb
		_button(mb, "3D VIEW" if flat else "FLAT MAP")
		if flat:   # v1.9e: zoom in to read the boxes
			_btns["zoom_out"] = Rect2(Vector2(S.x - 440, 16), Vector2(60, 48))
			_button(_btns["zoom_out"], "-")
			_btns["zoom_in"] = Rect2(Vector2(S.x - 372, 16), Vector2(60, 48))
			_button(_btns["zoom_in"], "+")
	if selected != "" and expanded == "": _info(S)
	if expanded != "": _system_view(S, expanded)
	var cb := Rect2(Vector2(S.x - 150, 16), Vector2(130, 48))
	_btns["close"] = cb
	_button(cb, "BACK" if expanded != "" else "CLOSE")

# ---------------------------------------------------------------- v1.4m: the flat chart with fog of war
## What the pilot knows of a system: "seen" (been there), "rumor" (a gate from a system you have seen leads there:
## shown as an unknown contact), or "fog" (nothing shown at all).
static func fog_state(id: String) -> String:
	if id in GS.discovered: return "seen"
	for l in Galaxy.links_of(id):
		var other: String = l[1] if l[0] == id else l[0]
		if other in GS.discovered: return "rumor"
	return "fog"

## The rectangle of the chart and the size of one tile (11 columns A-K, 11 rows 1-11, as on the owner's map).
static var fz := 1.0             # v1.9e: chart zoom (+ / - buttons)
static var fpan := Vector2.ZERO  # v1.9e: chart pan (drag the chart)
static func flat_grid(S: Vector2) -> Array:
	var org := Vector2(378.0, 96.0)
	var cell := Vector2((S.x - org.x - 24.0) / 11.0, (S.y - org.y - 44.0) / 11.0) * fz
	return [org + fpan, cell]

## v1.9e: what a charted system's box says: [planet count, [[station name, has the owner's 3D model]]].
static func box_info(id: String) -> Array:
	if not Data.SYSTEMS.has(id): return [0, []]
	var sy: Dictionary = Data.SYSTEMS[id]
	var st: Array = [[str(sy["station"]["name"]), Data.is_st3d(sy["station"].get("model", ""))]]
	for b in sy.get("more_stations", []): st.append([str(b["name"]), Data.is_st3d(b.get("model", ""))])
	return [1 + (sy.get("more_planets", []) as Array).size(), st]

static func flat_pos(S: Vector2, col: int, row: int) -> Vector2:
	var g := flat_grid(S)
	return (g[0] as Vector2) + Vector2((col + 0.5) * (g[1] as Vector2).x, (row + 0.5) * (g[1] as Vector2).y)

static func link_color(kind: String) -> Color:
	match kind:
		"warp_gate": return Color(0.4, 0.7, 1.0)
		"rift_gate": return Color(0.8, 0.45, 1.0)
	return Color(0.4, 0.95, 0.55)

## The galaxy as it is on the owner's 11 x 11 map: every system in its tile, every gate as a line between tiles.
## Fog of war: you see the systems you have been to, the next ones along their gates as unknown contacts, and
## nothing else.
func _draw_flat(S: Vector2) -> void:
	# v3.1 (owner's concept art): deep space with the galaxy glowing behind the chart, systems as lit orbs in their
	# faction's colour, glowing gate lanes, name tags, and a standing key.
	draw_rect(Rect2(Vector2.ZERO, S), Data.MAP_FOG)
	var g := flat_grid(S)
	var org: Vector2 = g[0]
	var cell: Vector2 = g[1]
	var chart := Rect2(org, cell * 11.0)
	var gt := galaxy_tex()
	var gs := maxf(chart.size.x, chart.size.y) * 1.15
	draw_texture_rect(gt, Rect2(chart.get_center() - Vector2(gs, gs) * 0.5, Vector2(gs, gs)), false, Color(1, 1, 1, 0.6))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 160:   # far stars (fixed, they move with the chart)
		var sp := Vector2(rng.randf() * S.x, rng.randf() * S.y) + fpan * 0.3
		draw_circle(Vector2(fposmod(sp.x, S.x), fposmod(sp.y, S.y)), rng.randf_range(0.6, 1.6), Color(1, 1, 1, rng.randf_range(0.15, 0.6) * (0.75 + 0.25 * sin(t * 1.5 + i))))
	var net := Galaxy.network()
	var sys: Dictionary = net["systems"]
	var at := {}
	var state := {}
	var tile_of := {}
	for tl in GalaxyData.TILES:
		at[tl[0]] = flat_pos(S, tl[3], tl[4])
		state[tl[0]] = fog_state(tl[0])
		tile_of[Vector2i(tl[3], tl[4])] = tl[0]
	# the grid: faint lines, and a soft glow of the faction's colour on the tiles you know
	for c in 12: draw_line(org + Vector2(c * cell.x, 0), org + Vector2(c * cell.x, cell.y * 11.0), Color(0.45, 0.7, 1.0, 0.09), 1.0)
	for r in 12: draw_line(org + Vector2(0, r * cell.y), org + Vector2(cell.x * 11.0, r * cell.y), Color(0.45, 0.7, 1.0, 0.09), 1.0)
	for c in 11:
		for r in 11:
			var id: String = tile_of.get(Vector2i(c, r), "")
			if state.get(id, "fog") == "seen":
				var rc := Rect2(org + Vector2(c * cell.x, r * cell.y), cell).grow(-2.0)
				var fc: Color = SystemBuilder.FACTIONS[sys[id]["faction"]][3]
				draw_rect(rc, Color(fc, 0.08))
				draw_rect(rc, Color(fc, 0.3), false, 1.0)
	for c in 11: draw_string(font, org + Vector2(c * cell.x, -8.0), "ABCDEFGHIJK"[c], HORIZONTAL_ALIGNMENT_CENTER, cell.x, Data.ts(13), Color(0.6, 0.78, 1.0, 0.7))
	for r in 11: draw_string(font, org + Vector2(-26.0, r * cell.y + cell.y * 0.5 + 5.0), str(r + 1), HORIZONTAL_ALIGNMENT_CENTER, 22.0, Data.ts(13), Color(0.6, 0.78, 1.0, 0.7))
	# gates: a glowing lane shows when you have been to at least one end of it
	for l in net["links"]:
		var sa: String = state[l[0]]
		var sb: String = state[l[1]]
		if sa != "seen" and sb != "seen": continue
		var lc := link_color(l[2])
		var both: bool = sa == "seen" and sb == "seen"
		var a0: Vector2 = at[l[0]]
		var b0: Vector2 = at[l[1]]
		if l[2] == "jump_gate":
			draw_line(a0, b0, Color(lc, 0.14 if both else 0.06), 9.0, true)
			draw_line(a0, b0, Color(lc, 0.95 if both else 0.45), 2.5 if both else 1.5, true)
		else:
			draw_line(a0, b0, Color(lc, 0.1 if both else 0.05), 8.0, true)
			_dashed(self, a0, b0, Color(lc, 0.95 if both else 0.45), 2.5 if both else 1.5, 8.0 if l[2] == "warp_gate" else 4.0)
	# systems
	for id in at:
		var st2: String = state[id]
		if st2 == "fog": continue
		var p: Vector2 = at[id]
		var s: Dictionary = sys[id]
		if st2 == "seen" and cell.x >= Data.MAP_ORRERY_DETAIL:   # v10.6 (owner: pinch in to see the star and its planets)
			boxes += 1
			var stp: Vector2 = _orrery(id, p, cell)
			if id == current:
				_you_pulse(stp)   # (zoomed in: YOU sits at the main station, not on the star)
				_hits[id] = p
				continue
		elif st2 == "seen" and cell.x >= Data.MAP_BOX_DETAIL:   # v1.9e: zoomed in: the system's box, like the owner's document
			var fc3: Color = SystemBuilder.FACTIONS[s["faction"]][3]
			boxes += 1
			var bi := box_info(id)
			var tl0 := p - cell * 0.5 + Vector2(6, 4)
			var fs := clampi(int(cell.x / 10.0), 10, 18)
			var w := cell.x - 12.0
			draw_rect(Rect2(p - cell * 0.5, cell).grow(-2.0), Color(0.01, 0.03, 0.07, 0.75))
			draw_string(font, tl0 + Vector2(0, fs + 4), s["name"], HORIZONTAL_ALIGNMENT_LEFT, w, fs + 2, Color.WHITE)
			draw_string(font, tl0 + Vector2(0, fs * 2 + 8), "%s · %s" % [s.get("tile", ""), s["faction"]], HORIZONTAL_ALIGNMENT_LEFT, w, fs - 2, fc3.lightened(0.3))
			draw_string(font, tl0 + Vector2(0, fs * 3 + 12), "%d planet%s · %d station%s" % [bi[0], "" if bi[0] == 1 else "s", (bi[1] as Array).size(), "" if (bi[1] as Array).size() == 1 else "s"], HORIZONTAL_ALIGNMENT_LEFT, w, fs - 1, Color(0.9, 0.95, 1.0))
			var ly := tl0.y + fs * 4 + 16.0
			for sn: Array in bi[1]:
				if ly > p.y + cell.y * 0.5 - 6.0: break
				draw_string(font, Vector2(tl0.x, ly), ("* " if sn[1] else "· ") + str(sn[0]), HORIZONTAL_ALIGNMENT_LEFT, w, fs - 2, Color(1.0, 0.72, 0.3) if sn[1] else Color(0.72, 0.8, 0.9))
				ly += fs + 2.0
			draw_circle(p + Vector2(cell.x * 0.5 - 12.0, -cell.y * 0.5 + 12.0), 5.0, fc3)
			draw_arc(p + Vector2(cell.x * 0.5 - 12.0, -cell.y * 0.5 + 12.0), 8.0, 0, TAU, 20, stand_color(str(s["faction"])), 2.0, true)
		elif st2 == "seen":
			var fc2: Color = SystemBuilder.FACTIONS[s["faction"]][3]
			_orb(p, fc2, 1.0)
			draw_arc(p, 12.0, 0, TAU, 28, stand_color(str(s["faction"])), 2.0, true)
			_tag(p + Vector2(0, 30.0), str(s["name"]).to_upper(), fc2)
		else:
			draw_circle(p, 11.0, Color(0.5, 0.62, 0.78, 0.12))
			draw_arc(p, 9.0, 0, TAU, 20, Color(0.7, 0.8, 0.92, 0.7), 1.5, true)
			draw_string(font, p + Vector2(-10, 6), "?", HORIZONTAL_ALIGNMENT_CENTER, 20, Data.ts(13), Color(0.85, 0.92, 1.0, 0.85))
		if id == current: _you_pulse(p)
		if id == selected:
			for cn in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var q: Vector2 = p + cn * 20.0
				draw_line(q, q - Vector2(cn.x * 9, 0), Color.WHITE, 2.0)
				draw_line(q, q - Vector2(0, cn.y * 9), Color.WHITE, 2.0)
		_hits[id] = p
	# v10.6 (owner: "it needs to pulse to tell you what system you're at"): in an unknown area (not on the charts) you
	# still get the pulse, on its tile
	if not sys.has(current) and Data.SYSTEMS.has(current):
		var tl2: String = str(Data.SYSTEMS[current].get("tile", ""))
		if tl2.length() >= 2:
			var cc := "ABCDEFGHIJK".find(tl2[0]); var rr := int(tl2.substr(1)) - 1
			if cc >= 0 and rr >= 0:
				var yp: Vector2 = flat_pos(S, cc, rr)
				draw_circle(yp, 7.0, Color(1.0, 0.85, 0.4))
				_you_pulse(yp)
				_tag(yp + Vector2(0, 30.0), str(Data.SYSTEMS[current]["name"]).to_upper(), Color(0.85, 0.9, 1.0))
				_hits[current] = yp
	# heading and keys
	draw_string(font, Vector2(24, 40), "GALAXY MAP", HORIZONTAL_ALIGNMENT_LEFT, -1, Data.ts(26), Color.WHITE)
	var known := 0
	for id2 in state:
		if state[id2] == "seen": known += 1
	draw_string(font, Vector2(24, 66), "EXPLORE · TRAVEL · DISCOVER  —  %d of %d systems charted" % [known, state.size()], HORIZONTAL_ALIGNMENT_LEFT, 330.0 + 24.0 + 400.0, Data.ts(13), Color(0.55, 0.8, 1.0))
	# standing key (who will shoot at you), under the buttons
	var kr := Rect2(Vector2(24, S.y - 44 - 26 * STAND_KEY.size()), Vector2(170, 4 + 26 * STAND_KEY.size()))
	draw_style_box(_glass_box(), kr)
	var yk := kr.position.y + 22.0
	for k in STAND_KEY:
		draw_circle(Vector2(kr.position.x + 18, yk - 5), 6.0, k[1])
		draw_string(font, Vector2(kr.position.x + 32, yk), k[0], HORIZONTAL_ALIGNMENT_LEFT, -1, Data.ts(13), Color(0.85, 0.92, 1.0))
		yk += 26.0
	var ky := S.y - 16.0
	var kx := org.x
	for kd in [["jump_gate", "Jump gate"], ["warp_gate", "Warp gate"], ["rift_gate", "Rift gate"]]:
		if kd[0] == "jump_gate": draw_line(Vector2(kx, ky - 5), Vector2(kx + 34, ky - 5), link_color(kd[0]), 2.5)
		else: _dashed(self, Vector2(kx, ky - 5), Vector2(kx + 34, ky - 5), link_color(kd[0]), 2.5, 8.0 if kd[0] == "warp_gate" else 4.0)
		draw_string(font, Vector2(kx + 42, ky), kd[1], HORIZONTAL_ALIGNMENT_LEFT, -1, Data.ts(14), Color(0.85, 0.92, 1.0))
		kx += 150.0
	draw_arc(Vector2(kx + 8, ky - 5), 7.0, 0, TAU, 16, Color(0.7, 0.8, 0.9, 0.7), 1.5)
	draw_string(font, Vector2(kx + 22, ky), "? = not charted yet   * = 3D station", HORIZONTAL_ALIGNMENT_LEFT, -1, Data.ts(14), Color(0.85, 0.92, 1.0))

# ---------------------------------------------------------------- v3.1: the dark chart's pieces
const STAND_KEY := [["Friendly", Color(0.4, 0.95, 0.55)], ["Cautious", Color(1.0, 0.85, 0.3)], ["Hostile", Color(1.0, 0.35, 0.28)], ["Enemy", Color(0.62, 0.64, 0.68)]]

## The ring round a system: where you stand with the faction that holds it (the key's four colours).
static func stand_color(f: String) -> Color:
	match Factions.band(f):
		"purple", "blue", "green": return STAND_KEY[0][1]
		"yellow": return STAND_KEY[1][1]
		"orange", "red": return STAND_KEY[2][1]
	return STAND_KEY[3][1]

## A lit orb: soft halo, coloured body, bright core.
func _orb(p: Vector2, col: Color, k: float) -> void:
	draw_circle(p, 17.0 * k + 2.0, Color(col, 0.1))
	draw_circle(p, 11.0 * k + 1.5, Color(col, 0.25))
	draw_circle(p, 7.5 * k + 1.0, col)
	draw_circle(p, 3.5 * k + 0.5, col.lerp(Color.WHITE, 0.75))

## A name tag: a dark pill with a coloured edge, centred on p.
func _tag(p: Vector2, s: String, col: Color) -> void:
	var fs := Data.ts(12)
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 16.0
	var r := Rect2(p - Vector2(w * 0.5, fs * 0.5 + 4.0), Vector2(w, fs + 8.0))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.05, 0.1, 0.85)
	sb.border_color = Color(col, 0.9)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	draw_style_box(sb, r)
	draw_string(font, Vector2(r.position.x + 8.0, r.end.y - 6.0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)

func _glass_box(lit := false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.06, 0.12, 0.9) if not lit else Color(0.05, 0.25, 0.42, 0.95)
	sb.border_color = Color(0.35, 0.75, 1.0, 0.8) if not lit else Color(0.5, 0.9, 1.0)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	return sb

## The spiral galaxy behind the chart: made once, in code (no picture to download).
static var _galaxy: Texture2D = null
static func galaxy_tex() -> Texture2D:
	if _galaxy != null: return _galaxy
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var hues := [Color(0.35, 0.55, 1.0), Color(0.75, 0.4, 1.0), Color(1.0, 0.45, 0.4), Color(1.0, 0.75, 0.35), Color(0.35, 1.0, 0.6), Color(0.3, 0.85, 1.0)]
	for y in n:
		for x in n:
			var d := Vector2(x - n * 0.5, y - n * 0.5) / (n * 0.5)
			var r := d.length()
			if r > 1.0: continue
			var a := atan2(d.y, d.x)
			var arm := 0.5 + 0.5 * cos(2.0 * (a - 4.2 * log(r + 0.06)))   # two arms winding out
			arm = pow(arm, 1.7)
			var fall := exp(-r * 1.9)
			var core := exp(-r * r * 40.0)
			var hk := fposmod(a / TAU + r * 0.55, 1.0) * hues.size()
			var hc: Color = (hues[int(hk) % hues.size()] as Color).lerp(hues[(int(hk) + 1) % hues.size()], hk - floorf(hk))
			var c := hc * (arm * fall * 0.9 + fall * 0.12) + Color(1.0, 0.85, 0.55) * core * 1.4
			var al := clampf(arm * fall * 0.85 + fall * 0.15 + core, 0.0, 1.0) * (1.0 - smoothstep(0.75, 1.0, r))
			img.set_pixel(x, y, Color(minf(c.r, 1.0), minf(c.g, 1.0), minf(c.b, 1.0), al))
	_galaxy = ImageTexture.create_from_image(img)
	return _galaxy

## The network drawing, shared with the title screen. hits (optional) receives screen positions of systems.
static func draw_network(ci: CanvasItem, S: Vector2, yaw: float, pitch: float, t: float, viewer: Vector3, current := "", selected := "", hits = null, labels := true, focus := "", focus_k := 1.0, back: Texture2D = null) -> void:
	var f: Font = ThemeDB.fallback_font
	ci.draw_rect(Rect2(Vector2.ZERO, S), BG)
	if back:   # the owner's network picture as a far, slow layer (moves at a third of the pan speed)
		var bh := S.y * 1.15
		var bw := back.get_width() * bh / back.get_height()
		var x0 := -fposmod(yaw / FOV_H * S.x * 0.33, bw)
		var y0 := (S.y - bh) * 0.5 + pitch / FOV_V * S.y * 0.33
		while x0 < S.x:
			ci.draw_texture_rect(back, Rect2(x0, y0, bw, bh), false, Color(1, 1, 1, 0.35))
			x0 += bw
	# faint blueprint grid: horizon and meridians
	var hy := S.y * 0.5 + pitch / FOV_V * S.y
	ci.draw_line(Vector2(0, hy), Vector2(S.x, hy), Color(PALE, 0.9), 1.0)
	for k in 24:
		var az := k * TAU / 24.0
		var x := S.x * 0.5 + wrapf(az - yaw, -PI, PI) / FOV_H * S.x
		if x > -10 and x < S.x + 10: ci.draw_line(Vector2(x, 0), Vector2(x, S.y), Color(PALE, 0.5), 1.0)
	var net := Galaxy.network()
	var sys: Dictionary = net["systems"]
	var proj := {}
	for id in sys:
		var d: Vector3 = (sys[id]["pos"] as Vector3) - viewer
		var dist := d.length()
		var az := atan2(d.x, -d.z)
		var el := asin(clampf(d.y / maxf(dist, 0.001), -1, 1))
		var dx := wrapf(az - yaw, -PI, PI)
		var p := Vector2(S.x * 0.5 + dx / FOV_H * S.x, S.y * 0.5 - (el - pitch) / FOV_V * S.y)
		proj[id] = [p, dist, dx]
	# connections
	for l in net["links"]:
		var a: Array = proj[l[0]]
		var b: Array = proj[l[1]]
		if absf(float(a[2]) - float(b[2])) > PI * 0.9: continue   # would wrap round the back
		var pa: Vector2 = a[0]
		var pb: Vector2 = b[0]
		if (pa.x < -200 and pb.x < -200) or (pa.x > S.x + 200 and pb.x > S.x + 200): continue
		match l[2]:
			"jump_gate": ci.draw_line(pa, pb, Color(MID, 0.75), 1.6, true)
			"warp_gate": _dashed(ci, pa, pb, Color(SKY, 0.95), 2.0, 9.0)
			"rift_gate": _dashed(ci, pa, pb, Color(NAVY, 0.8), 3.0, 4.0)
	# systems
	for id in proj:
		var p: Vector2 = proj[id][0]
		if p.x < -20 or p.x > S.x + 20 or p.y < -20 or p.y > S.y + 20: continue
		var s: Dictionary = sys[id]
		var r := clampf(260.0 / maxf(float(proj[id][1]), 1.0), 3.0, 11.0)
		var col: Color = SHADES[int(s["shade"])]
		if s["discovered"]: ci.draw_circle(p, r, col)
		else: ci.draw_arc(p, r, 0, TAU, 20, col, 1.6, true)
		if s["playable"]: ci.draw_arc(p, r + 4, 0, TAU, 24, DEEP, 2.0, true)
		if id == current:
			ci.draw_arc(p, r + 10 + 2.0 * sin(t * 3.0), 0, TAU, 32, NAVY, 2.0, true)
			if labels: ci.draw_string(f, p + Vector2(-60, r + 28), "YOU ARE HERE", HORIZONTAL_ALIGNMENT_CENTER, 120, Data.ts(12), NAVY)
		if id == selected:
			for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var q: Vector2 = p + c * (r + 8)
				ci.draw_line(q, q - Vector2(c.x * 7, 0), NAVY, 2.0)
				ci.draw_line(q, q - Vector2(0, c.y * 7), NAVY, 2.0)
		if id == focus and focus_k > 0.0:   # comes into the middle: lights up with a stroke and shows its name
			var gr := r + 14.0 + 4.0 * (1.0 - focus_k)
			ci.draw_arc(p, gr, 0, TAU, 40, Color(SKY, 0.55 * focus_k), 6.0, true)
			ci.draw_arc(p, gr, 0, TAU, 40, Color(DEEP, focus_k), 2.0, true)
			if labels:
				ci.draw_string(f, p + Vector2(-110, -gr - 12), (s["name"] as String).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 220, Data.ts(18), Color(NAVY, focus_k))
				ci.draw_string(f, p + Vector2(-110, gr + 20), "%s · %s" % [s["faction"], "CHARTED" if s["discovered"] else "UNCHARTED"], HORIZONTAL_ALIGNMENT_CENTER, 220, Data.ts(11), Color(DEEP, focus_k))
		elif labels and (id == selected or id == current or s["playable"]):
			ci.draw_string(f, p + Vector2(r + 6, 5), s["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, Data.ts(13 if s["playable"] else 11), NAVY if s["discovered"] else MID)
		if hits != null: hits[id] = p
	if labels:
		for c in Galaxy.CLUSTERS:
			var d2: Vector3 = (c[2] as Vector3) - viewer
			var dx2 := wrapf(atan2(d2.x, -d2.z) - yaw, -PI, PI)
			var el2 := asin(clampf(d2.y / maxf(d2.length(), 0.001), -1, 1))
			var cp := Vector2(S.x * 0.5 + dx2 / FOV_H * S.x, S.y * 0.5 - (el2 - pitch) / FOV_V * S.y - 70)
			if cp.x > 0 and cp.x < S.x: ci.draw_string(f, cp - Vector2(100, 0), (c[0] as String).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 200, Data.ts(13), Color(DEEP, 0.55))

static func _dashed(ci: CanvasItem, a: Vector2, b: Vector2, col: Color, w: float, dash: float) -> void:
	var l := a.distance_to(b)
	if l < 1.0: return
	var dir := (b - a) / l
	var s := 0.0
	while s < l:
		ci.draw_line(a + dir * s, a + dir * minf(s + dash, l), col, w, true)
		s += dash * 2.0

func _text(p: Vector2, s: String, size := 15, col := NAVY, align := HORIZONTAL_ALIGNMENT_LEFT, w := -1.0) -> void:
	draw_string(font, p, s, align, w, size, col)

func _button(r: Rect2, label: String, lit := false) -> void:
	if flat or expanded != "":   # v3.1: dark glass, like the hub
		draw_style_box(_glass_box(lit), r)
		_text(r.position + Vector2(0, r.size.y * 0.5 + 7), label, Data.ts(15), Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.WHITE
	sb.border_color = DEEP
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	draw_style_box(sb, r)
	_text(r.position + Vector2(0, r.size.y * 0.5 + 6), label, 16, DEEP, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)

func _title(S: Vector2) -> void:
	_text(Vector2(24, 40), "GALAXY NAVIGATION", 24, NAVY)
	_text(Vector2(24, 62), "Drag to look around · tap a system · EXPAND for its chart", 13, MID)
	var ly := S.y - 22.0
	draw_line(Vector2(24, ly), Vector2(60, ly), Color(MID, 0.75), 1.6)
	_text(Vector2(66, ly + 5), "Jump gate", 12, NAVY)
	_dashed(self, Vector2(150, ly), Vector2(186, ly), SKY, 2.0, 9.0)
	_text(Vector2(192, ly + 5), "Warp gate (hidden)", 12, NAVY)
	_dashed(self, Vector2(330, ly), Vector2(366, ly), NAVY, 3.0, 4.0)
	_text(Vector2(372, ly + 5), "Rift gate", 12, NAVY)
	draw_arc(Vector2(462, ly), 6, 0, TAU, 16, DEEP, 2.0)
	_text(Vector2(474, ly + 5), "Flyable now", 12, NAVY)
	var n: int = Galaxy.network()["systems"].size()
	_text(Vector2(S.x - 340, ly + 5), "%d systems · %d links · map data only" % [n, Galaxy.network()["links"].size()], 12, MID, HORIZONTAL_ALIGNMENT_RIGHT, 320)

## v10.6: zoomed right in, a charted system's tile shows the system itself, laid out as it really is (its 1,000 km
## square shrunk into the tile): the star glowing, each planet on its orbit round the star, the stations and gates.
func _orrery(id: String, p: Vector2, cell: Vector2) -> Vector2:
	var d: Dictionary = Data.SYSTEMS[id]
	var r := Rect2(p - cell * 0.5, cell).grow(-2.0)
	draw_rect(r, Color(0.01, 0.02, 0.05, 0.88))
	var fc: Color = SystemBuilder.FACTIONS[d.get("faction", "Neutral")][3] if SystemBuilder.FACTIONS.has(d.get("faction", "Neutral")) else Color(0.6, 0.7, 0.9)
	draw_rect(r, Color(fc, 0.5), false, 1.5)
	var E: float = Data.SPACE_EDGE
	var to2 := func(v: Vector3) -> Vector2: return p + Vector2(clampf(v.x / E, -1.0, 1.0), clampf(v.z / E, -1.0, 1.0)) * (cell * 0.46)
	var sun: Vector3 = SystemBuilder.sun_pos_of(d)
	var sp: Vector2 = to2.call(sun)
	var sun_in := absf(sun.x) < E and absf(sun.z) < E
	var bodies: Array = [[d["planet"]["pos"], float(d["planet"].get("radius", 1000.0)), d["planet"].get("name", "")]]
	for x in d.get("more_planets", []): bodies.append([x["pos"], float(x.get("radius", 600.0)), x.get("name", "")])
	if sun_in:
		for b in bodies: draw_arc(sp, (to2.call(b[0]) as Vector2).distance_to(sp), 0, TAU, 64, Color(0.55, 0.75, 1.0, 0.22), 1.0, true)
		for k in 3: draw_circle(sp, cell.x * (0.05 - k * 0.012) + 1.0 * sin(t * 2.0), Color(1.0, 0.85, 0.5, 0.25 + k * 0.3))
	else:   # the star is far off this square: its light comes from that side
		var dir := (sp - p).normalized()
		draw_circle(p + dir * cell.x * 0.44, cell.x * 0.03, Color(1.0, 0.85, 0.5, 0.9))
	var fs := clampi(int(cell.x / 22.0), 10, 15)
	for b in bodies:
		var bp: Vector2 = to2.call(b[0])
		draw_circle(bp, clampf(float(b[1]) / 4000.0, 3.0, 9.0) * cell.x / 300.0 + 2.0, Color(0.45, 0.75, 1.0))
		if b[2] != "": draw_string(font, bp + Vector2(6, -4), str(b[2]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.75, 0.88, 1.0, 0.9))
	var sts: Array = [d["station"]] + (d.get("more_stations", []) as Array)
	for st in sts:
		var q: Vector2 = to2.call(st["pos"])
		draw_rect(Rect2(q - Vector2(3, 3), Vector2(6, 6)), Color(0.4, 1.0, 0.6))
	for g in d.get("gates", []):
		draw_arc(to2.call(g["pos"]), 4.0, 0, TAU, 12, link_color(str(g.get("gkind", "jump")) + "_gate"), 1.5, true)
	draw_string(font, r.position + Vector2(6, fs + 4), str(d["name"]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 12, fs + 2, Color.WHITE)
	return to2.call(d["station"]["pos"])

## v10.6: where you are: rings pulsing out from the system (a sonar ping) and a YOU tag, easy to find at a glance.
func _you_pulse(p: Vector2) -> void:
	var gold := Color(1.0, 0.85, 0.4)
	for k in 3:
		var ph := fposmod(t * 0.8 + k / 3.0, 1.0)
		draw_arc(p, 14.0 + ph * 38.0, 0, TAU, 40, Color(gold, (1.0 - ph) * 0.85), 3.0 - ph * 2.0, true)
	draw_arc(p, 18.0 + 2.5 * sin(t * 3.0), 0, TAU, 32, gold, 2.5, true)
	_tag(p + Vector2(0, -28.0), "YOU", gold)

func _info(S: Vector2) -> void:
	if not Galaxy.network()["systems"].has(selected):   # v10.6 (owner phone shot: the card printed raw data): an unknown area
		_info_unknown(S)
		return
	var s: Dictionary = Galaxy.network()["systems"][selected]
	if not flat:
		_info_blueprint(S, s)
		return
	# v3.1: SELECTED SYSTEM card (dark glass), the faction's colour along its top edge
	var r := Rect2(Vector2(24, 86), Vector2(330, 222))
	draw_style_box(_glass_box(), r)
	var W := Color.WHITE
	var SUB := Color(0.55, 0.8, 1.0)
	_text(r.position + Vector2(16, 26), "SELECTED SYSTEM", Data.ts(12), SUB)
	if fog_state(selected) != "seen":   # fog of war: an unknown contact tells you only where it is
		_text(r.position + Vector2(16, 58), "UNCHARTED", Data.ts(20), W)
		_text(r.position + Vector2(16, 84), "Tile %s" % s.get("tile", "?"), Data.ts(14), SUB)
		_text(r.position + Vector2(16, 116), "A gate from a system you know", Data.ts(14), W)
		_text(r.position + Vector2(16, 140), "leads here. Fly there to chart it.", Data.ts(14), W)
		return
	var fc: Color = SystemBuilder.FACTIONS[s["faction"]][3]
	draw_rect(Rect2(r.position + Vector2(2, 2), Vector2(r.size.x - 4, 4)), fc)
	_orb(r.position + Vector2(r.size.x - 34, 46), fc, 1.0)
	draw_arc(r.position + Vector2(r.size.x - 34, 46), 12.0, 0, TAU, 28, stand_color(str(s["faction"])), 2.0, true)
	_text(r.position + Vector2(16, 58), (s["name"] as String).to_upper(), Data.ts(20), W)
	var band := Factions.band(str(s["faction"]))
	_text(r.position + Vector2(16, 84), "%s · %s · tile %s" % [s["faction"], Data.REP_INFO[band]["name"], s.get("tile", "?")], Data.ts(13), stand_color(str(s["faction"])))
	_text(r.position + Vector2(16, 110), "%s star · %d planets · %d stations" % [s["star"], s["planets"], s["stations"]], Data.ts(13), W)
	var kinds := {"warp_gate": 0, "jump_gate": 0, "rift_gate": 0}
	for l in Galaxy.links_of(selected): kinds[l[2]] += 1
	_text(r.position + Vector2(16, 134), "Gates: %d jump · %d warp · %d rift" % [kinds["jump_gate"], kinds["warp_gate"], kinds["rift_gate"]], Data.ts(13), W)
	var bi2 := box_info(selected)   # v1.9e: the station names (your 3D stations starred)
	var yy := r.position.y + 158.0
	for sn2: Array in (bi2[1] as Array).slice(0, 2):
		_text(Vector2(r.position.x + 16, yy), ("* " if sn2[1] else "· ") + str(sn2[0]), Data.ts(13), Color(1.0, 0.72, 0.3) if sn2[1] else SUB)
		yy += 20.0
	var eb := Rect2(Vector2(r.position.x, r.end.y + 10), Vector2(r.size.x, 54))
	_btns["expand"] = eb
	_button(eb, "OPEN SYSTEM  »", true)

## v10.6: you are in (or picked) one of the unknown areas, which are not on the charts: a plain card, no raw data.
func _info_unknown(S: Vector2) -> void:
	var r := Rect2(Vector2(24, 86), Vector2(330, 222))
	draw_style_box(_glass_box(), r)
	var d: Dictionary = Data.SYSTEMS.get(selected, {})
	_text(r.position + Vector2(16, 26), "SELECTED SYSTEM", Data.ts(12), Color(0.55, 0.8, 1.0))
	_text(r.position + Vector2(16, 58), str(d.get("name", "Unknown area")).to_upper(), Data.ts(20), Color.WHITE)
	_text(r.position + Vector2(16, 84), "Unknown area · tile %s" % str(d.get("tile", "?")), Data.ts(13), Color(0.75, 0.8, 0.9))
	_text(r.position + Vector2(16, 110), "Off the charts: no gates on the map.", Data.ts(13), Color.WHITE)
	var bi2 := box_info(selected)
	var yy := r.position.y + 140.0
	for sn2: Array in (bi2[1] as Array).slice(0, 2):
		_text(Vector2(r.position.x + 16, yy), "· " + str(sn2[0]), Data.ts(13), Color(0.55, 0.8, 1.0))
		yy += 20.0
	if Data.SYSTEMS.has(selected):
		var eb := Rect2(Vector2(r.position.x, r.end.y + 10), Vector2(r.size.x, 54))
		_btns["expand"] = eb
		_button(eb, "OPEN SYSTEM  »", true)

func _info_blueprint(S: Vector2, s: Dictionary) -> void:
	var r := Rect2(Vector2(24, 86), Vector2(330, 196))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.94)
	sb.border_color = DEEP
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	draw_style_box(sb, r)
	_text(r.position + Vector2(16, 32), (s["name"] as String).to_upper(), 22, NAVY)
	_text(r.position + Vector2(16, 54), "%s · tile %s" % [s["faction"], s.get("tile", "?")], 15, MID)
	_text(r.position + Vector2(16, 78), "%s star · %d planets · %d stations" % [s["star"], s["planets"], s["stations"]], 15, NAVY)
	var status := "FLYABLE" if s["playable"] else ("SURVEYED — no route yet" if s["discovered"] else "UNCHARTED")
	_text(r.position + Vector2(16, 124), status, 14, DEEP if s["playable"] else MID)
	var eb := Rect2(r.position + Vector2(16, 140), Vector2(140, 44))
	_btns["expand"] = eb
	_button(eb, "EXPAND")

## Blueprint of one system: star, orbits, bodies, warp gate, spaceways as dashed highways between bodies.
func _system_view(S: Vector2, id: String) -> void:
	var r := Rect2(Vector2(S.x * 0.12, 80), Vector2(S.x * 0.76, S.y - 120))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.05, 0.1, 0.96)
	sb.border_color = Color(0.35, 0.75, 1.0, 0.8)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	draw_style_box(sb, r)
	var s: Dictionary = Galaxy.network()["systems"][id]
	_text(r.position + Vector2(20, 34), "%s SYSTEM" % (s["name"] as String).to_upper(), 22, SV_INK)
	_text(r.position + Vector2(20, 56), "Blueprint · %s" % ("charted" if s["playable"] else "long-range survey"), 13, SV_SUB)
	var bodies := Galaxy.bodies(id)
	var c := r.get_center() + Vector2(0, 20)
	var far := 1.0
	for b in bodies: far = maxf(far, Vector2(b["pos"].x, b["pos"].z).length())
	var k := minf(r.size.x, r.size.y - 90) * 0.42 / far
	draw_circle(c, 9, Color(1.0, 0.82, 0.4))
	draw_arc(c, 13, 0, TAU, 24, SV_LINE, 1.5)
	var at := {}
	for b in bodies:
		var p: Vector2 = c + Vector2(b["pos"].x, b["pos"].z) * k
		at[b["key"]] = p
		draw_arc(c, c.distance_to(p), 0, TAU, 64, Color(SV_ORBIT, 0.9), 1.0)
	for sw in Galaxy.SPACEWAYS.get(id, []):
		if at.has(sw[1]) and at.has(sw[2]):
			_dashed(self, at[sw[1]], at[sw[2]], SV_LINE, 3.0, 7.0)
			var mid: Vector2 = (at[sw[1]] + at[sw[2]]) * 0.5
			_text(mid + Vector2(-80, -8), sw[0], 12, SV_LINE, HORIZONTAL_ALIGNMENT_CENTER, 160)
	for b in bodies:
		var p: Vector2 = at[b["key"]]
		match b["kind"]:
			"planet": draw_circle(p, 10, SV_SUB)
			"station": draw_rect(Rect2(p - Vector2(7, 7), Vector2(14, 14)), SV_LINE)
			"warp gate":
				draw_arc(p, 11, 0, TAU, 24, SV_INK, 3.0)
		_text(p + Vector2(14, 5), "%s (%s)" % [b["name"], b["kind"]], 12, SV_INK)
	var links := Galaxy.links_of(id)
	var y := r.end.y - 18.0 - 16.0 * mini(links.size(), 4)
	_text(Vector2(r.position.x + 20, y - 4), "ROUTES OUT", 12, SV_SUB)
	for i in mini(links.size(), 4):
		var l: Array = links[i]
		var other: String = l[1] if l[0] == id else l[0]
		_text(Vector2(r.position.x + 20, y + 14 + i * 16), "%s → %s" % [(l[2] as String).replace("_", " "), Galaxy.network()["systems"][other]["name"]], 12, SV_INK)
