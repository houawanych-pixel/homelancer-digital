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

func _gui_input(e: InputEvent) -> void:
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
		if _drag_from != Vector2.INF and expanded == "":
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

# ---------------------------------------------------------------- drawing
func _draw() -> void:
	var S := get_viewport_rect().size
	_hits.clear()
	_btns.clear()
	if flat: _draw_flat(S)
	else:
		draw_network(self, S, yaw, pitch, t, viewer, current, selected, _hits, true, focus, focus_t, backdrop)
		_title(S)
	var mb := Rect2(Vector2(S.x - 300, 16), Vector2(140, 48))
	if expanded == "":
		_btns["mode"] = mb
		_button(mb, "3D VIEW" if flat else "FLAT MAP")
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
static func flat_grid(S: Vector2) -> Array:
	var org := Vector2(378.0, 96.0)
	var cell := Vector2((S.x - org.x - 24.0) / 11.0, (S.y - org.y - 44.0) / 11.0)
	return [org, cell]

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
	draw_rect(Rect2(Vector2.ZERO, S), Data.MAP_FOG)
	var g := flat_grid(S)
	var org: Vector2 = g[0]
	var cell: Vector2 = g[1]
	var net := Galaxy.network()
	var sys: Dictionary = net["systems"]
	var at := {}
	var state := {}
	var tile_of := {}
	for tl in GalaxyData.TILES:
		at[tl[0]] = flat_pos(S, tl[3], tl[4])
		state[tl[0]] = fog_state(tl[0])
		tile_of[Vector2i(tl[3], tl[4])] = tl[0]
	# the grid, with the tiles you know lit in their faction's colour
	for c in 11:
		for r in 11:
			var rc := Rect2(org + Vector2(c * cell.x, r * cell.y), cell).grow(-1.5)
			var id: String = tile_of.get(Vector2i(c, r), "")
			var st: String = state.get(id, "fog")
			if st == "seen":
				var fc: Color = SystemBuilder.FACTIONS[sys[id]["faction"]][3]
				draw_rect(rc, Color(fc, 0.2))
				draw_rect(rc, Color(fc, 0.55), false, 1.5)
			elif st == "rumor":
				draw_rect(rc, Color(0.5, 0.6, 0.7, 0.07))
				draw_rect(rc, Color(0.5, 0.6, 0.7, 0.3), false, 1.0)
			else:
				draw_rect(rc, Color(1, 1, 1, 0.012))
				draw_rect(rc, Color(0.4, 0.5, 0.6, 0.08), false, 1.0)
	for c in 11: draw_string(font, org + Vector2(c * cell.x, -8.0), "ABCDEFGHIJK"[c], HORIZONTAL_ALIGNMENT_CENTER, cell.x, 14, Color(0.6, 0.75, 0.9, 0.8))
	for r in 11: draw_string(font, org + Vector2(-26.0, r * cell.y + cell.y * 0.5 + 5.0), str(r + 1), HORIZONTAL_ALIGNMENT_CENTER, 22.0, 14, Color(0.6, 0.75, 0.9, 0.8))
	# gates: a line shows when you have been to at least one end of it
	for l in net["links"]:
		var sa: String = state[l[0]]
		var sb: String = state[l[1]]
		if sa != "seen" and sb != "seen": continue
		var lc := link_color(l[2])
		var both: bool = sa == "seen" and sb == "seen"
		if l[2] == "jump_gate": draw_line(at[l[0]], at[l[1]], Color(lc, 0.9 if both else 0.4), 2.5 if both else 1.5, true)
		else: _dashed(self, at[l[0]], at[l[1]], Color(lc, 0.9 if both else 0.4), 2.5 if both else 1.5, 8.0 if l[2] == "warp_gate" else 4.0)
	# systems
	for id in at:
		var st2: String = state[id]
		if st2 == "fog": continue
		var p: Vector2 = at[id]
		var s: Dictionary = sys[id]
		if st2 == "seen":
			var fc2: Color = SystemBuilder.FACTIONS[s["faction"]][3]
			draw_circle(p, 9.0, fc2)
			draw_arc(p, 9.0, 0, TAU, 24, Color.WHITE, 1.5, true)
			draw_string(font, p + Vector2(-cell.x * 0.5, 26.0), s["name"], HORIZONTAL_ALIGNMENT_CENTER, cell.x, 13, Color.WHITE)
		else:
			draw_arc(p, 8.0, 0, TAU, 20, Color(0.7, 0.8, 0.9, 0.7), 1.5, true)
			draw_string(font, p + Vector2(-10, 6), "?", HORIZONTAL_ALIGNMENT_CENTER, 20, 15, Color(0.7, 0.8, 0.9, 0.8))
		if id == current:
			draw_arc(p, 15.0 + 2.5 * sin(t * 3.0), 0, TAU, 32, Color(1.0, 0.85, 0.4), 2.5, true)
			draw_string(font, p + Vector2(-cell.x * 0.5, -18.0), "YOU", HORIZONTAL_ALIGNMENT_CENTER, cell.x, 13, Color(1.0, 0.85, 0.4))
		if id == selected:
			for cn in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var q: Vector2 = p + cn * 17.0
				draw_line(q, q - Vector2(cn.x * 8, 0), Color.WHITE, 2.0)
				draw_line(q, q - Vector2(0, cn.y * 8), Color.WHITE, 2.0)
		_hits[id] = p
	# heading and key
	draw_string(font, Vector2(24, 40), "GALAXY MAP", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color.WHITE)
	var known := 0
	for id2 in state:
		if state[id2] == "seen": known += 1
	draw_string(font, Vector2(24, 64), "%d of %d systems charted  ·  tap a system" % [known, state.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.7, 0.85, 1.0))
	var ky := S.y - 16.0
	var kx := org.x
	for kd in [["jump_gate", "Jump gate"], ["warp_gate", "Warp gate"], ["rift_gate", "Rift gate"]]:
		if kd[0] == "jump_gate": draw_line(Vector2(kx, ky - 5), Vector2(kx + 34, ky - 5), link_color(kd[0]), 2.5)
		else: _dashed(self, Vector2(kx, ky - 5), Vector2(kx + 34, ky - 5), link_color(kd[0]), 2.5, 8.0 if kd[0] == "warp_gate" else 4.0)
		draw_string(font, Vector2(kx + 42, ky), kd[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.85, 0.92, 1.0))
		kx += 150.0
	draw_arc(Vector2(kx + 8, ky - 5), 7.0, 0, TAU, 16, Color(0.7, 0.8, 0.9, 0.7), 1.5)
	draw_string(font, Vector2(kx + 22, ky), "? = not charted yet", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.85, 0.92, 1.0))

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
			if labels: ci.draw_string(f, p + Vector2(-60, r + 28), "YOU ARE HERE", HORIZONTAL_ALIGNMENT_CENTER, 120, 12, NAVY)
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
				ci.draw_string(f, p + Vector2(-110, -gr - 12), (s["name"] as String).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 220, 18, Color(NAVY, focus_k))
				ci.draw_string(f, p + Vector2(-110, gr + 20), "%s · %s" % [s["faction"], "CHARTED" if s["discovered"] else "UNCHARTED"], HORIZONTAL_ALIGNMENT_CENTER, 220, 11, Color(DEEP, focus_k))
		elif labels and (id == selected or id == current or s["playable"]):
			ci.draw_string(f, p + Vector2(r + 6, 5), s["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 13 if s["playable"] else 11, NAVY if s["discovered"] else MID)
		if hits != null: hits[id] = p
	if labels:
		for c in Galaxy.CLUSTERS:
			var d2: Vector3 = (c[2] as Vector3) - viewer
			var dx2 := wrapf(atan2(d2.x, -d2.z) - yaw, -PI, PI)
			var el2 := asin(clampf(d2.y / maxf(d2.length(), 0.001), -1, 1))
			var cp := Vector2(S.x * 0.5 + dx2 / FOV_H * S.x, S.y * 0.5 - (el2 - pitch) / FOV_V * S.y - 70)
			if cp.x > 0 and cp.x < S.x: ci.draw_string(f, cp - Vector2(100, 0), (c[0] as String).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 200, 13, Color(DEEP, 0.55))

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

func _button(r: Rect2, label: String) -> void:
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

func _info(S: Vector2) -> void:
	var s: Dictionary = Galaxy.network()["systems"][selected]
	var r := Rect2(Vector2(24, 86), Vector2(330, 196))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.94)
	sb.border_color = DEEP
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	draw_style_box(sb, r)
	if flat and fog_state(selected) != "seen":   # fog of war: an unknown contact tells you only where it is
		_text(r.position + Vector2(16, 32), "UNCHARTED SYSTEM", 22, NAVY)
		_text(r.position + Vector2(16, 58), "Tile %s" % s.get("tile", "?"), 15, MID)
		_text(r.position + Vector2(16, 86), "A gate from a system you know", 15, NAVY)
		_text(r.position + Vector2(16, 108), "leads here. Fly there to chart it.", 15, NAVY)
		return
	_text(r.position + Vector2(16, 32), (s["name"] as String).to_upper(), 22, NAVY)
	_text(r.position + Vector2(16, 54), "%s · tile %s" % [s["faction"], s.get("tile", "?")], 15, MID)
	_text(r.position + Vector2(16, 78), "%s star · %d planets · %d stations" % [s["star"], s["planets"], s["stations"]], 15, NAVY)
	var kinds := {"warp_gate": 0, "jump_gate": 0, "rift_gate": 0}
	for l in Galaxy.links_of(selected): kinds[l[2]] += 1
	_text(r.position + Vector2(16, 100), "Gates: %d jump · %d warp · %d rift" % [kinds["jump_gate"], kinds["warp_gate"], kinds["rift_gate"]], 15, NAVY)
	var status := "FLYABLE" if s["playable"] else ("SURVEYED — no route yet" if s["discovered"] else "UNCHARTED")
	_text(r.position + Vector2(16, 124), status, 14, DEEP if s["playable"] else MID)
	var eb := Rect2(r.position + Vector2(16, 140), Vector2(140, 44))
	_btns["expand"] = eb
	_button(eb, "EXPAND")

## Blueprint of one system: star, orbits, bodies, warp gate, spaceways as dashed highways between bodies.
func _system_view(S: Vector2, id: String) -> void:
	var r := Rect2(Vector2(S.x * 0.12, 80), Vector2(S.x * 0.76, S.y - 120))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.97)
	sb.border_color = DEEP
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	draw_style_box(sb, r)
	var s: Dictionary = Galaxy.network()["systems"][id]
	_text(r.position + Vector2(20, 34), "%s SYSTEM" % (s["name"] as String).to_upper(), 22, NAVY)
	_text(r.position + Vector2(20, 56), "Blueprint · %s" % ("charted" if s["playable"] else "long-range survey"), 13, MID)
	var bodies := Galaxy.bodies(id)
	var c := r.get_center() + Vector2(0, 20)
	var far := 1.0
	for b in bodies: far = maxf(far, Vector2(b["pos"].x, b["pos"].z).length())
	var k := minf(r.size.x, r.size.y - 90) * 0.42 / far
	draw_circle(c, 9, Color(1.0, 0.82, 0.4))
	draw_arc(c, 13, 0, TAU, 24, DEEP, 1.5)
	var at := {}
	for b in bodies:
		var p: Vector2 = c + Vector2(b["pos"].x, b["pos"].z) * k
		at[b["key"]] = p
		draw_arc(c, c.distance_to(p), 0, TAU, 64, Color(PALE, 0.9), 1.0)
	for sw in Galaxy.SPACEWAYS.get(id, []):
		if at.has(sw[1]) and at.has(sw[2]):
			_dashed(self, at[sw[1]], at[sw[2]], DEEP, 3.0, 7.0)
			var mid: Vector2 = (at[sw[1]] + at[sw[2]]) * 0.5
			_text(mid + Vector2(-80, -8), sw[0], 12, DEEP, HORIZONTAL_ALIGNMENT_CENTER, 160)
	for b in bodies:
		var p: Vector2 = at[b["key"]]
		match b["kind"]:
			"planet": draw_circle(p, 10, MID)
			"station": draw_rect(Rect2(p - Vector2(7, 7), Vector2(14, 14)), DEEP)
			"warp gate":
				draw_arc(p, 11, 0, TAU, 24, NAVY, 3.0)
		_text(p + Vector2(14, 5), "%s (%s)" % [b["name"], b["kind"]], 12, NAVY)
	var links := Galaxy.links_of(id)
	var y := r.end.y - 18.0 - 16.0 * mini(links.size(), 4)
	_text(Vector2(r.position.x + 20, y - 4), "ROUTES OUT", 12, MID)
	for i in mini(links.size(), 4):
		var l: Array = links[i]
		var other: String = l[1] if l[0] == id else l[0]
		_text(Vector2(r.position.x + 20, y + 14 + i * 16), "%s → %s" % [(l[2] as String).replace("_", " "), Galaxy.network()["systems"][other]["name"]], 12, NAVY)
