extends Control
## Navigation screen: top-down map of the current system plus the known star map (Solara <-> Vega).

signal closed
signal course_set(node: Node3D)
signal galaxy_requested

const CYAN := Color(0.4, 0.86, 1.0)
const GOLD := Color(1.0, 0.82, 0.4)
const GREEN := Color(0.45, 1.0, 0.6)
const RED := Color(1.0, 0.36, 0.3)

var space: SpaceSystem = null # null while docked (map built from data only)
var font: Font = ThemeDB.fallback_font
var selected := "" # "station" | "planet" | "gate"
var hits := {}
var btn_close := Rect2()
var btn_course := Rect2()
var btn_galaxy := Rect2()
var map_rect := Rect2()
var scale_k := 1.0
var center := Vector3.ZERO
var way_pos := Vector3.INF   # a custom waypoint picked by tapping empty space on the map

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

func open(sp: SpaceSystem) -> void:
	space = sp
	selected = ""
	visible = true
	queue_redraw()

func _process(_dt: float) -> void:
	if visible: queue_redraw()

func _gui_input(e: InputEvent) -> void:
	var p := Vector2.ZERO
	if e is InputEventScreenTouch and e.pressed: p = e.position
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT: p = e.position
	else: return
	accept_event()
	if btn_galaxy.has_point(p):
		galaxy_requested.emit()
		return
	if btn_close.has_point(p):
		visible = false
		closed.emit()
		return
	if btn_course.has_point(p) and selected != "" and space != null and space.controls:
		set_course()
		return
	for k in hits:
		if (hits[k] as Vector2).distance_to(p) < 44.0:
			selected = k
			return
	if map_rect.has_point(p) and space != null:   # empty space: drop your own waypoint there
		var rel := (p - map_rect.get_center()) / scale_k
		way_pos = Vector3(center.x + rel.x, space.player.global_position.y, center.z + rel.y)
		selected = "point"

## SET COURSE: fly to the selected place or waypoint on autopilot.
func set_course() -> void:
	var n: Node3D = space.waypoint_at(way_pos) if selected == "point" else _node(selected)
	visible = false
	course_set.emit(n)

## Map keys: "station", "planet", "gate" (the first gate), "gate1", "gate2" ... (the system's other gates).
func _gate_index(key: String) -> int: return 0 if key == "gate" else int(key.substr(4))
func _node(key: String) -> Node3D:
	if key == "station": return space.station
	if key == "planet": return space.planet
	return space.gates[mini(_gate_index(key), space.gates.size() - 1)]
func _data(key: String) -> Dictionary:
	var sys: Dictionary = Data.SYSTEMS[GS.system_id]
	if key == "station" or key == "planet": return sys[key]
	return sys["gates"][mini(_gate_index(key), sys["gates"].size() - 1)]

## Pick a spot on the map as a waypoint (used by the route test, same as a tap).
func pick_point(world: Vector3) -> void:
	way_pos = world
	selected = "point"

func _w2m(p: Vector3) -> Vector2:
	var rel := Vector2(p.x - center.x, p.z - center.z) * scale_k
	return map_rect.get_center() + rel

func _txt(p: Vector2, t: String, s := 16, c := Color.WHITE, align := HORIZONTAL_ALIGNMENT_LEFT, w := -1.0) -> void:
	if s < Data.TEXT_BUMP_BELOW: s = maxi(Data.TEXT_MIN, s + Data.TEXT_BUMP)   # v1.4m: small print is a little bigger
	draw_string_outline(font, p, t, align, w, s, 4, Color(0, 0, 0, 0.8))
	draw_string(font, p, t, align, w, s, c)

func _draw() -> void:
	var S := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, S), Color(0.01, 0.03, 0.06, 0.96))
	var sys: Dictionary = Data.SYSTEMS[GS.system_id]
	_txt(Vector2(36, 50), "NAVIGATION — %s SYSTEM" % sys["name"].to_upper(), 30, CYAN)
	_txt(Vector2(38, 78), "Tap a destination, then SET COURSE to fly there on autopilot." if space != null and space.controls else "Plan your route. Launch to fly it.", 16, Color(0.85, 0.9, 0.95))
	map_rect = Rect2(36, 100, S.x * 0.64, S.y - 130)
	draw_rect(map_rect, Color(0.02, 0.06, 0.1))
	draw_rect(map_rect, Color(CYAN, 0.35), false, 2)
	for i in range(1, 8):
		var x := map_rect.position.x + map_rect.size.x * i / 8.0
		draw_line(Vector2(x, map_rect.position.y), Vector2(x, map_rect.end.y), Color(CYAN, 0.06))
	for i in range(1, 6):
		var y := map_rect.position.y + map_rect.size.y * i / 6.0
		draw_line(Vector2(map_rect.position.x, y), Vector2(map_rect.end.x, y), Color(CYAN, 0.06))
	# fit the system into the map
	var pts := [sys["station"]["pos"], sys["planet"]["pos"], sys["gate"]["pos"], sys["asteroids"]["center"], sys["nebula"]["center"]]
	for gd0 in sys["gates"]: pts.append(gd0["pos"])
	for xd0 in sys.get("more_planets", []): pts.append(xd0["pos"])
	var mn := Vector2(1e9, 1e9)
	var mx := Vector2(-1e9, -1e9)
	for p in pts:
		mn = Vector2(minf(mn.x, p.x), minf(mn.y, p.z))
		mx = Vector2(maxf(mx.x, p.x), maxf(mx.y, p.z))
	center = Vector3((mn.x + mx.x) * 0.5, 0, (mn.y + mx.y) * 0.5)
	var span := (mx - mn) + Vector2(1200, 1200)
	scale_k = minf(map_rect.size.x / span.x, map_rect.size.y / span.y)
	# zones
	var neb: Dictionary = sys["nebula"]
	draw_circle(_w2m(neb["center"]), neb["radius"] * scale_k, Color(neb["color"], 0.25))
	_txt(_w2m(neb["center"]) + Vector2(-80, 4), neb["name"] + " nebula", 14, Color(neb["color"].lightened(0.4), 1), HORIZONTAL_ALIGNMENT_CENTER, 160)
	var belt: Dictionary = sys["asteroids"]
	draw_arc(_w2m(belt["center"]), belt["radius"] * scale_k, 0, TAU, 40, Color(0.8, 0.7, 0.55, 0.7), 2.0)
	for i in 30:
		var a := i * 2.4
		draw_circle(_w2m(belt["center"]) + Vector2(cos(a), sin(a)) * belt["radius"] * scale_k * fmod(i * 0.37, 1.0), 2, Color(0.8, 0.7, 0.55))
	_txt(_w2m(belt["center"]) + Vector2(-80, belt["radius"] * scale_k + 18), belt["name"], 14, Color(0.9, 0.8, 0.65), HORIZONTAL_ALIGNMENT_CENTER, 160)
	# patrol areas
	for p in sys["patrols"]:
		draw_arc(_w2m(p), 150 * scale_k, 0, TAU, 24, Color(RED, 0.35), 1.5)
	# destinations
	hits.clear()
	var items := [["station", sys["station"]["pos"], GREEN, sys["station"]["name"] + " (station)"],
		["planet", sys["planet"]["pos"], Color(0.5, 0.8, 1.0), sys["planet"]["name"] + " (planet)"],
		["gate", sys["gate"]["pos"], GOLD, sys["gate"]["name"] + " > " + Data.SYSTEMS[sys["gate"]["to"]]["name"]]]
	for gi in range(1, sys["gates"].size()):
		var gd: Dictionary = sys["gates"][gi]
		items.append(["gate%d" % gi, gd["pos"], GOLD, gd["name"]])
	for it in items:
		var mp := _w2m(it[1])
		hits[it[0]] = mp
		var r := 14.0 if it[0] != "planet" else maxf(14.0, sys["planet"]["radius"] * scale_k)
		draw_circle(mp, r, Color(it[2], 0.85))
		if it[0] == selected: draw_arc(mp, r + 9, 0, TAU, 32, Color.WHITE, 3.0)
		_txt(mp + Vector2(r + 8, 6), it[3], 16, it[2])
	# the rest of the system: placeholder planets and stations (TARGET in flight selects them)
	for xd: Dictionary in sys.get("more_planets", []):
		var xp := _w2m(xd["pos"])
		draw_circle(xp, maxf(7.0, float(xd["radius"]) * scale_k), Color(0.5, 0.8, 1.0, 0.45))
		_txt(xp + Vector2(12, 5), xd["name"], 13, Color(0.5, 0.8, 1.0, 0.8))
	for xd: Dictionary in sys.get("more_stations", []):
		var xs := _w2m(xd["pos"])
		draw_rect(Rect2(xs - Vector2(5, 5), Vector2(10, 10)), Color(GREEN, 0.55))
		_txt(xs + Vector2(10, 5), xd["name"], 13, Color(GREEN, 0.8))
	if selected == "point" and way_pos != Vector3.INF:
		var wp := _w2m(way_pos)
		draw_colored_polygon(PackedVector2Array([wp + Vector2(0, -12), wp + Vector2(12, 0), wp + Vector2(0, 12), wp + Vector2(-12, 0)]), GOLD)
		draw_arc(wp, 20, 0, TAU, 32, Color.WHITE, 2.0)
		_txt(wp + Vector2(18, 6), "WAYPOINT", 15, GOLD)
	# live objects
	if space != null and is_instance_valid(space.player):
		for e in space.enemies:
			draw_circle(_w2m(e["node"].global_position), 4, RED)
		var pp: Vector2 = _w2m(space.player.global_position)
		var f: Vector3 = -space.player.global_basis.z
		var dir := Vector2(f.x, f.z).normalized()
		var perp := Vector2(-dir.y, dir.x)
		draw_colored_polygon(PackedVector2Array([pp + dir * 14, pp - dir * 8 + perp * 8, pp - dir * 8 - perp * 8]), Color.WHITE)
		_txt(pp + Vector2(12, -10), "YOU", 13, Color.WHITE)
	# star map panel
	var sm := Rect2(map_rect.end.x + 20, 100, S.x - map_rect.end.x - 56, 250)
	draw_rect(sm, Color(0.02, 0.06, 0.1))
	draw_rect(sm, Color(CYAN, 0.35), false, 2)
	_txt(sm.position + Vector2(14, 28), "KNOWN SPACE", 16, CYAN)
	if GS.system_id in ["solara", "vega"] and not ("veranthos" in GS.discovered):
		var a2 := sm.position + Vector2(sm.size.x * 0.28, sm.size.y * 0.6)
		var b2 := sm.position + Vector2(sm.size.x * 0.75, sm.size.y * 0.45)
		var vega_known := "vega" in GS.discovered
		draw_line(a2, b2, Color(GOLD, 0.8 if vega_known else 0.25), 3.0)
		for s in [["solara", a2], ["vega", b2]]:
			var known: bool = s[0] in GS.discovered
			var here: bool = s[0] == GS.system_id
			draw_circle(s[1], 16, Color(Data.SYSTEMS[s[0]]["star"], 1.0 if known else 0.3))
			if here: draw_arc(s[1], 24, 0, TAU, 32, Color.WHITE, 2.0)
			_txt(s[1] + Vector2(-60, 44), Data.SYSTEMS[s[0]]["name"] if known else "Uncharted", 16, Color.WHITE if known else Color(1, 1, 1, 0.4), HORIZONTAL_ALIGNMENT_CENTER, 120)
		_txt(sm.position + Vector2(14, sm.size.y - 14), "Aquila Gate <> Solara Gate" if vega_known else "Jump through the Aquila Gate to chart the next system.", 13, Color(0.85, 0.9, 0.95))
	else:
		# once you are out in the galaxy: this system's tile and where each of its gates leads
		_txt(sm.position + Vector2(14, 52), "%s  ·  tile %s  ·  %s" % [sys["name"], sys.get("tile", "?"), sys.get("faction", "")], 15, Color.WHITE)
		var gy := 78.0
		for gd in sys["gates"]:
			var known2: bool = gd["to"] in GS.discovered
			_txt(sm.position + Vector2(14, gy), "%s > %s" % [str(gd.get("gkind", "jump")).to_upper(), Data.SYSTEMS[gd["to"]]["name"] + ("" if known2 else "  (uncharted)")], 14, GOLD if known2 else Color(1, 1, 1, 0.6))
			gy += 22.0
		_txt(sm.position + Vector2(14, sm.size.y - 14), "%d of %d systems charted. GALAXY shows the whole map." % [GS.discovered.size(), Data.SYSTEMS.size()], 13, Color(0.85, 0.9, 0.95))
	# selection panel + buttons
	var sel := Rect2(sm.position.x, sm.end.y + 16, sm.size.x, 150)
	draw_rect(sel, Color(0.02, 0.06, 0.1))
	draw_rect(sel, Color(CYAN, 0.35), false, 2)
	if selected == "":
		_txt(sel.position + Vector2(14, 34), "No destination selected.", 16, Color(1, 1, 1, 0.7))
		_txt(sel.position + Vector2(14, 60), "Tap a place, or tap empty space for a waypoint.", 13, Color(1, 1, 1, 0.55))
	elif selected == "point":
		_txt(sel.position + Vector2(14, 34), "Custom waypoint", 20, GOLD)
		if space != null and is_instance_valid(space.player):
			_txt(sel.position + Vector2(14, 60), "Distance %.1f km" % (space.player.global_position.distance_to(way_pos) / 1000.0), 15, CYAN)
	else:
		var d: Dictionary = _data(selected)
		_txt(sel.position + Vector2(14, 34), d["name"], 20, GOLD)
		var line := "Dockable %s" % ("station" if selected == "station" else "planet") if not selected.begins_with("gate") else "%s gate to %s" % [str(d.get("gkind", "warp")).capitalize() if d.has("gkind") and (d["id"] as String).contains("_gate_") else "Warp", Data.SYSTEMS[d["to"]]["name"]]
		_txt(sel.position + Vector2(14, 60), line, 15, Color(0.85, 0.9, 0.95))
		if space != null and is_instance_valid(space.player):
			var n: Node3D = _node(selected)
			_txt(sel.position + Vector2(14, 84), "Distance %.1f km" % (space.distance_to(n) / 1000.0), 15, CYAN)
	btn_course = Rect2(sel.position.x, sel.end.y + 14, sel.size.x, 62)
	btn_galaxy = Rect2(sel.position.x, btn_course.end.y + 12, sel.size.x * 0.5 - 5, 62)
	btn_close = Rect2(sel.position.x + sel.size.x * 0.5 + 5, btn_course.end.y + 12, sel.size.x * 0.5 - 5, 62)
	var can := selected != "" and space != null and space.controls
	_btn(btn_course, "SET COURSE", can, GREEN)
	_btn(btn_galaxy, "GALAXY", true, CYAN)
	_btn(btn_close, "CLOSE", true, CYAN)

func _btn(r: Rect2, label: String, enabled: bool, col: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col, 0.28 if enabled else 0.06)
	sb.border_color = Color(col, 0.9 if enabled else 0.25)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	draw_style_box(sb, r)
	_txt(r.position + Vector2(0, r.size.y * 0.5 + 8), label, 21, Color(1, 1, 1, 1.0 if enabled else 0.35), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
