extends Control
## Navigation screen (Job S, v1.4p): a GPS-style map of the current system.
##  - holographic grid that keeps going as you zoom (pinch, wheel, + / -), drag to pan
##  - NORTH-UP (angled GPS view or flat overhead) or HEADING-UP (you are the arrow, the map turns round you)
##  - tap anything to identify it: glowing brackets and an info card with its picture; then SET COURSE
##  - a set course is drawn as a thick glowing route with a pulsing pin
## The projection, grid and shapes live in NavGrid (shared with the HUD radar).

signal closed
signal course_set(node: Node3D)
signal galaxy_requested

const CYAN := Color(0.4, 0.86, 1.0)
const GOLD := Color(1.0, 0.82, 0.4)
const GREEN := Color(0.45, 1.0, 0.6)
const RED := Color(1.0, 0.36, 0.3)
const PLANET := Color(0.42, 0.72, 1.0)
const PANEL := Color(0.02, 0.06, 0.1, 0.94)

var space: SpaceSystem = null # null while docked (map built from data only)
var font: Font = ThemeDB.fallback_font
var selected := ""            # "" | "point" | an object key: "station", "planet", "gate", "gate1".., "planet1".., "station1".., "belt", "nebula", "star", "enemy0".., "traffic0"..
var hits := {}                # key -> screen position (this frame's projection, so it follows any rotation)
var objs := {}                # key -> {type, name, pos, col, r, data, node}
var btn_close := Rect2()
var btn_course := Rect2()
var btn_galaxy := Rect2()
var btn_orient := Rect2()
var btn_tilt := Rect2()
var btn_zoom_in := Rect2()
var btn_zoom_out := Rect2()
var btn_fit := Rect2()
var btn_card_x := Rect2()
var card_rect := Rect2()
var compass_pos := Vector2.ZERO
var map_rect := Rect2()
var scale_k := 1.0            # pixels per metre right now
var center := Vector3.ZERO    # world point at the middle of the fitted system
var way_pos := Vector3.INF    # a custom waypoint picked by tapping empty space on the map
var view := NavGrid.new()
var zoom := 1.0
var pan := Vector3.ZERO       # north-up only: how far the view has been dragged (world metres)
var grid_stats := {}          # what the grid drew last frame (tests)
var route := {}               # the drawn course: {"from", "to", "dist", "eta", "name"} (screen points), {} when none
var t := 0.0
var _press := {}              # pointer index -> [start, last, moved]
var _pinch := 0.0
var _last_press_frame := -1
var _last_press_pos := Vector2.INF
var clip: Control
var canvas: Control
var over: Control

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	if not NavGrid._loaded: NavGrid.load_prefs()
	clip = Control.new()   # the map window: everything the canvas draws is cut off at its edge
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(clip)
	canvas = Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.draw.connect(_draw_map)
	clip.add_child(canvas)
	over = Control.new()   # panels, buttons and the info card, on top of the map
	over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	over.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	over.draw.connect(_draw_over)
	add_child(over)

func open(sp: SpaceSystem) -> void:
	space = sp
	selected = ""
	zoom = 1.0
	pan = Vector3.ZERO
	_press.clear()
	visible = true
	_layout()
	queue_redraw()

func _process(dt: float) -> void:
	if not visible: return
	t += dt
	queue_redraw()
	canvas.queue_redraw()
	over.queue_redraw()

# ---------------------------------------------------------------- view state
func heading_up() -> bool:
	return NavGrid.orient == "heading" and space != null and is_instance_valid(space.player)

func toggle_orient() -> void:
	NavGrid.toggle_orient()
	pan = Vector3.ZERO
	_layout()

func toggle_tilt() -> void:
	NavGrid.toggle_tilt()
	_layout()

func zoom_by(f: float) -> void:
	zoom = clampf(zoom * f, Data.NAV_ZOOM[0], Data.NAV_ZOOM[1])
	_layout()

func fit() -> void:
	zoom = 1.0
	pan = Vector3.ZERO
	_layout()

# ---------------------------------------------------------------- input (mouse and touch share one path)
func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		accept_event()
		if map_rect.has_point(e.position): zoom_by(Data.NAV_ZOOM_STEP if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / Data.NAV_ZOOM_STEP)
		return
	var idx := -1
	var pos := Vector2.ZERO
	var down := false
	var up := false
	var motion := false
	if e is InputEventScreenTouch:
		idx = e.index
		pos = e.position
		down = e.pressed
		up = not e.pressed
	elif e is InputEventScreenDrag:
		idx = e.index
		pos = e.position
		motion = true
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		idx = 99
		pos = e.position
		down = e.pressed
		up = not e.pressed
	elif e is InputEventMouseMotion and _press.has(99):
		idx = 99
		pos = e.position
		motion = true
	else: return
	accept_event()
	if down:
		# a mouse click arrives twice when touch emulation is on (as a click and as a touch): take it once
		if Engine.get_process_frames() == _last_press_frame and pos.distance_to(_last_press_pos) < 2.0: return
		_last_press_frame = Engine.get_process_frames()
		_last_press_pos = pos
		_press[idx] = [pos, pos, false]
		if _press.size() == 2: _pinch = _spread()
	elif motion and _press.has(idx):
		var pr: Array = _press[idx]
		if _press.size() >= 2:   # pinch to zoom
			pr[1] = pos
			pr[2] = true
			var sp := _spread()
			if _pinch > 10.0 and sp > 10.0: zoom_by(sp / _pinch)
			_pinch = sp
		else:
			if (pr[0] as Vector2).distance_to(pos) > Data.NAV_TAP_SLOP: pr[2] = true
			if pr[2] and map_rect.has_point(pr[0]) and not heading_up():   # drag the map
				var w0 := view.to_world((pr[1] as Vector2) - map_rect.position)
				var w1 := view.to_world(pos - map_rect.position)
				pan += w0 - w1
				_layout()
			pr[1] = pos
	elif up and _press.has(idx):
		var pr2: Array = _press[idx]
		_press.erase(idx)
		if not pr2[2] and _press.is_empty(): tap(pos)

func _spread() -> float:
	var v := _press.values()
	return ((v[0][1] as Vector2).distance_to(v[1][1])) if v.size() >= 2 else 0.0

## One tap / click at a screen point. Buttons first, then the info card, then objects, then empty space.
func tap(p: Vector2) -> void:
	_layout()
	if btn_galaxy.has_point(p):
		galaxy_requested.emit()
		return
	if btn_close.has_point(p):
		visible = false
		closed.emit()
		return
	if btn_course.has_point(p):
		if selected != "" and space != null and space.controls: set_course()
		return
	if selected == "" and space != null:   # v1.5i GPS: the route panel and the destination rows
		for k in route_btns:
			if (route_btns[k] as Rect2).has_point(p):
				var parts: PackedStringArray = str(k).split("_")
				var i := int(parts[1]) if parts.size() > 1 else -1
				match parts[0]:
					"up": space.move_stop(i, -1)
					"down": space.move_stop(i, 1)
					"x": space.remove_stop(i)
					"clear": space.clear_route()
					"go":
						gps_note = space.route_go()
						visible = false
						closed.emit()   # back to flying: the autopilot takes it from here
					"stop": armed = -1 if armed == i else i
				if parts[0] != "stop": armed = -1
				return
		for k in add_btns:
			if (add_btns[k] as Rect2).has_point(p):
				gps_note = add_waypoint(k)
				return
		for k in dest_rows:
			if (dest_rows[k] as Rect2).has_point(p):
				if armed >= 0:
					var n := _dest_node(k)
					space.replace_stop(armed, n)
					gps_note = "Stop %d is now %s." % [armed + 1, n.name] if n != null else ""
					armed = -1
				else: set_destination(k)
				return
	if btn_orient.has_point(p):
		if space != null: toggle_orient()
		return
	if btn_tilt.has_point(p):
		toggle_tilt()
		return
	if btn_zoom_in.has_point(p):
		zoom_by(Data.NAV_ZOOM_STEP)
		return
	if btn_zoom_out.has_point(p):
		zoom_by(1.0 / Data.NAV_ZOOM_STEP)
		return
	if btn_fit.has_point(p):
		fit()
		return
	if selected != "" and btn_card_x.has_point(p):
		selected = ""
		return
	if selected != "" and card_rect.has_point(p): return   # reading the card
	var key := pick(p)
	if key != "":
		selected = key
		return
	if selected != "":   # a tap outside closes the card
		selected = ""
		return
	if map_rect.has_point(p) and space != null:   # empty space: drop your own waypoint there
		var w := view.to_world(p - map_rect.position)
		way_pos = Vector3(w.x, space.player.global_position.y, w.z)
		selected = "point"

## The object under a screen point ("" = none). Uses this frame's projected positions, so it works in any rotation.
func pick(p: Vector2) -> String:
	if not map_rect.has_point(p): return ""
	var best := ""
	var best_d: float = Data.NAV_HIT_RADIUS
	for k in hits:
		var d := (hits[k] as Vector2).distance_to(p)
		var reach: float = maxf(Data.NAV_HIT_RADIUS, float(objs[k].get("px", 0.0)))
		if d < reach and (best == "" or d < best_d):
			best = k
			best_d = d
	return best

func select(key: String) -> void:
	_layout()
	if objs.has(key): selected = key

## Select whatever is nearest this world position (a tap on a radar blip opens the map on that object).
func select_near(world: Vector3) -> String:
	_layout()
	var best := ""
	var best_d := INF
	for key in objs:
		var d := Vector2(objs[key]["pos"].x - world.x, objs[key]["pos"].z - world.z).length()
		if d < best_d:
			best = key
			best_d = d
	if best != "": selected = best
	return best

## SET COURSE: fly to the selected place or waypoint on autopilot.
func set_course() -> void:
	var n: Node3D = null
	if selected == "point": n = space.waypoint_at(way_pos)
	else:
		n = _node(selected)
		if n == null and objs.has(selected):   # a zone with no node of its own (belt, nebula): fly to its middle
			var op: Vector3 = objs[selected]["pos"]
			n = space.waypoint_at(Vector3(op.x, space.player.global_position.y if selected != "star" else op.y, op.z))
			n.name = str(objs[selected]["name"]).validate_node_name()
	visible = false
	course_set.emit(n)

## v1.5i GPS: the known places of this system, nearest first: [{key, name, kind, dist}]. Ships are left out (they
## move); the mission waypoint comes first when there is one. Only what the map already shows (nothing hidden).
func dest_list() -> Array:
	var out: Array = []
	if space == null or not is_instance_valid(space.player): return out
	var pp: Vector3 = space.player.global_position
	var mw: Dictionary = space.mission_waypoint()
	if not mw.is_empty() and is_instance_valid(mw["node"]):
		out.append({"key": "mission", "name": "MISSION: %s" % mw["title"], "kind": "Mission", "dist": pp.distance_to((mw["node"] as Node3D).global_position)})
	var rest: Array = []
	for k in objs:
		var o: Dictionary = objs[k]
		if o.get("ship", false) or k == "star": continue
		var kind: String = {"planet": "Planet", "station": "Station", "gate": "Gate", "belt": "Asteroid field", "nebula": "Nebula", "beacon": "Beacon"}.get(str(o["type"]), str(o["type"]).capitalize())
		if o["type"] == "gate": kind = "%s Gate > %s" % [str(o["data"].get("gkind", "jump")).capitalize(), Data.SYSTEMS[o["data"]["to"]]["name"]]
		rest.append({"key": k, "name": str(o["name"]), "kind": kind, "dist": pp.distance_to(o["pos"])})
	rest.sort_custom(func(a, b): return a["dist"] < b["dist"])
	return out + rest

## The node a list entry stands for (a zone or point gets a GPS marker of its own).
func _dest_node(key: String) -> Node3D:
	if key == "mission":
		var mw: Dictionary = space.mission_waypoint()
		return mw["node"] if not mw.is_empty() else null
	var n: Node3D = _node(key)
	if n == null and objs.has(key):
		var op: Vector3 = objs[key]["pos"]
		n = space.nav_marker(Vector3(op.x, space.player.global_position.y, op.z), str(objs[key]["name"]))
	return n

## Make a list entry the GPS destination (the route becomes just this stop) without flying it.
func set_destination(key: String) -> void:
	if space == null: return
	var n := _dest_node(key)
	if n != null:
		space.gps_mission = (n == space.mission_waypoint().get("node"))   # v1.7o: picking the job keeps it following
		space.set_destination(n)
		armed = -1

## ADD WAYPOINT: the entry becomes the next stop of the route.
func add_waypoint(key: String) -> String:
	if space == null: return ""
	var n := _dest_node(key)
	var said: String = space.add_stop(n)
	if n != null and not (n in space.nav_route) and n.get_meta("gps_marker", false): n.queue_free()
	return said

var armed := -1   # a stop picked for replacing: the next list entry tapped takes its place (-1 = none)
var route_btns := {}   # "up_i" / "down_i" / "x_i" / "stop_i" / "clear" -> Rect2
var add_btns := {}     # key -> Rect2 of the row's ADD (+) button
var gps_note := ""     # the last thing the route panel said

## Map keys: "station", "planet", "gate" (the first gate), "gate1", "gate2" ... (the system's other gates).
func _gate_index(key: String) -> int: return 0 if key == "gate" else int(key.substr(4))
func _node(key: String) -> Node3D:
	if space == null: return null
	if key == "station": return space.station
	if key == "planet": return space.planet
	if key.begins_with("gate"): return space.gates[mini(_gate_index(key), space.gates.size() - 1)]
	if objs.has(key) and objs[key].get("node") != null and is_instance_valid(objs[key]["node"]): return objs[key]["node"]
	return null
func _data(key: String) -> Dictionary:
	var sys: Dictionary = Data.SYSTEMS[GS.system_id]
	if key == "station" or key == "planet": return sys[key]
	if key.begins_with("gate"): return sys["gates"][mini(_gate_index(key), sys["gates"].size() - 1)]
	return objs[key].get("data", {}) if objs.has(key) else {}

## Pick a spot on the map as a waypoint (used by the route test, same as a tap).
func pick_point(world: Vector3) -> void:
	way_pos = world
	selected = "point"

func _w2m(p: Vector3) -> Vector2:
	return view.to_screen(p) + map_rect.position

func _txt(ci: CanvasItem, p: Vector2, s_txt: String, s := 16, c := Color.WHITE, align := HORIZONTAL_ALIGNMENT_LEFT, w := -1.0) -> void:
	if s < Data.TEXT_BUMP_BELOW: s = maxi(Data.TEXT_MIN, s + Data.TEXT_BUMP)   # v1.4m: small print is a little bigger
	s = Data.ts(s)   # v1.7p: bigger for phones
	ci.draw_string_outline(font, p, s_txt, align, w, s, 4, Color(0, 0, 0, 0.8))
	ci.draw_string(font, p, s_txt, align, w, s, c)

# ---------------------------------------------------------------- what is on the map
## Everything that can be shown and tapped, from the system data plus (in flight) the live contacts.
func _collect() -> void:
	objs.clear()
	var sys: Dictionary = Data.SYSTEMS[GS.system_id]
	var st: Dictionary = sys["station"]
	objs["station"] = {"type": "station", "name": st["name"], "pos": st["pos"], "col": GREEN, "r": 60.0, "data": st, "main": true}
	var pl: Dictionary = sys["planet"]
	objs["planet"] = {"type": "planet", "name": pl["name"], "pos": pl["pos"], "col": PLANET, "r": float(pl["radius"]), "data": pl, "main": true}
	for gi in sys["gates"].size():
		var gd: Dictionary = sys["gates"][gi]
		objs["gate" if gi == 0 else "gate%d" % gi] = {"type": "gate", "name": gd["name"], "pos": gd["pos"], "col": GOLD, "r": 70.0, "data": gd}
	var k := 1
	for xd: Dictionary in sys.get("more_planets", []):
		objs["planet%d" % k] = {"type": "planet", "name": xd["name"], "pos": xd["pos"], "col": PLANET.darkened(0.12), "r": float(xd["radius"]), "data": xd, "node": _extra_at(xd["pos"])}
		k += 1
	k = 1
	for xd: Dictionary in sys.get("more_stations", []):
		objs["station%d" % k] = {"type": "station", "name": xd["name"], "pos": xd["pos"], "col": GREEN.darkened(0.15), "r": 45.0, "data": xd, "node": _extra_at(xd["pos"])}
		k += 1
	var belt: Dictionary = sys["asteroids"]
	objs["belt"] = {"type": "belt", "name": belt["name"], "pos": belt["center"], "col": Color(0.82, 0.72, 0.56), "r": float(belt["radius"]), "data": belt}
	var neb: Dictionary = sys["nebula"]
	objs["nebula"] = {"type": "nebula", "name": neb["name"] + " nebula", "pos": neb["center"], "col": neb["color"], "r": float(neb["radius"]), "data": neb}
	var star_pos: Vector3 = space.sun_pos if space != null and space.sun_pos != Vector3.INF else -(sys.get("sun_dir", Vector3(0, -0.3, 1)) as Vector3).normalized() * Data.SUN_DIST
	objs["star"] = {"type": "star", "name": "%s's Star" % sys["name"], "pos": star_pos, "col": sys.get("star", Color(1.0, 0.9, 0.5)), "r": 900.0, "data": {}}
	if space != null and is_instance_valid(space.player):
		var i := 0
		for e in space.enemies:
			if is_instance_valid(e["node"]):
				objs["enemy%d" % i] = {"type": "enemy", "name": e["def"].get("name", "Hostile"), "pos": (e["node"] as Node3D).global_position, "col": RED if (e["node"] as Node3D).get_meta("kind", "enemy") == "enemy" else GOLD, "r": 8.0, "data": e["def"], "node": e["node"], "ship": true}
			i += 1
		i = 0
		for tr in space.traffic:
			if is_instance_valid(tr["node"]):
				objs["traffic%d" % i] = {"type": "traffic", "name": str((tr["node"] as Node3D).name), "pos": (tr["node"] as Node3D).global_position, "col": GREEN, "r": 8.0, "data": {}, "node": tr["node"], "ship": true}
			i += 1

func _extra_at(p: Vector3) -> Node3D:
	if space == null: return null
	for x: Node3D in space.extras:
		if is_instance_valid(x) and x.global_position.distance_to(p) < 5.0: return x
	return null

## What the info card says about an object: {"name", "type", "lines": [...], "picture": Texture2D or null,
## "fallback": the type picture was used, "region": part of the picture to show, "distance": metres or -1}
func info(key: String) -> Dictionary:
	if key == "point":
		var d0 := space.player.global_position.distance_to(way_pos) if space != null and is_instance_valid(space.player) else -1.0
		return {"name": "Custom waypoint", "type": "Waypoint", "lines": ["A point you picked on the map."], "picture": null, "fallback": true, "region": Rect2(), "distance": d0, "col": GOLD}
	if not objs.has(key): return {}
	var o: Dictionary = objs[key]
	var d: Dictionary = o["data"]
	var sys: Dictionary = Data.SYSTEMS[GS.system_id]
	var out := {"name": o["name"], "type": "", "lines": [], "picture": null, "fallback": false, "region": Rect2(), "distance": -1.0, "col": o["col"]}
	var own := ""
	var pic_type: String = o["type"]
	match o["type"]:
		"planet":
			out["type"] = "Planet" + ("  ·  %s" % str(d["palette"]).capitalize() if d.has("palette") else "")
			own = NavGrid.planet_picture(d)
			if d.has("desc"): out["lines"].append(d["desc"])
			out["lines"].append("Dockable: land at the surface port." if key == "planet" else "Fly down into its atmosphere to enter.")
		"station":
			out["type"] = "Station"
			own = "res://assets/nav/station_wheel.jpg" if d.get("model", "") == "wheel_station" else ""
			var fac: String = d.get("faction", sys.get("faction", ""))
			if fac != "": out["lines"].append("Faction: %s" % fac)
			out["faction"] = fac
			var sv: Array = d.get("services", [] if d.get("placeholder", false) else Data.NAV_STATION_SERVICES)
			out["services"] = sv
			out["lines"].append("Services: %s" % ("  ·  ".join(sv) if not sv.is_empty() else "none yet (landmark)"))
			if d.has("desc"): out["lines"].append(d["desc"])
		"gate":
			out["type"] = "Jump Gate"
			var dest: String = Data.SYSTEMS[d["to"]]["name"]
			out["destination"] = dest
			out["name"] = "%s > %s" % [o["name"], dest]
			out["lines"].append("Destination: %s%s" % [dest, "" if d["to"] in GS.discovered else "  (uncharted)"])
			out["lines"].append("Fly to it and press DOCK to jump.")
		"belt":
			out["type"] = "Asteroid Belt"
			out["lines"].append("%d rocks, about %d m across. Mind your hull." % [int(d.get("count", 0)), int(o["r"] * 2.0)])
		"nebula":
			out["type"] = "Nebula"
			out["lines"].append("Radar range drops inside it.")
		"star":
			out["type"] = "Star"
			out["lines"].append("Too hot to approach: shields and repairs fail close in.")
		"enemy":
			out["type"] = "Ship  ·  Hostile"
			out["lines"].append("Hull %d  ·  Shield %d" % [int(d.get("hull", 0)), int(d.get("shield", 0))])
		"traffic":
			out["type"] = "Ship  ·  Civilian"
			out["lines"].append("Local traffic on its route.")
	var pic := NavGrid.picture(own, pic_type)
	out["picture"] = pic[0]
	out["fallback"] = pic[1]
	if pic[0] != null:
		var ts: Vector2 = (pic[0] as Texture2D).get_size()
		out["region"] = Rect2(ts.x * 0.5 - ts.y * 0.6667, 0, ts.y * 1.3333, ts.y) if ts.x > ts.y * 1.5 else Rect2(Vector2.ZERO, ts)   # world maps are 2:1: show the middle
	if space != null and is_instance_valid(space.player):
		var n := _node(key)
		out["distance"] = space.distance_to(n) if n != null else space.player.global_position.distance_to(o["pos"])
	return out

# ---------------------------------------------------------------- layout and projection
func _layout() -> void:
	var S := get_viewport_rect().size
	map_rect = Rect2(36, 100, S.x * 0.64, S.y - 130)
	var sys: Dictionary = Data.SYSTEMS[GS.system_id]
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
	if space != null and is_instance_valid(space.player):   # v1.5e: in flight the map is centred on YOU, zoomed out until the whole system fits round you
		var pp0: Vector3 = space.player.global_position
		center = Vector3(pp0.x, 0, pp0.z)
		var reach := 0.0
		for p in pts: reach = maxf(reach, maxf(absf(p.x - pp0.x), absf(p.z - pp0.z)))
		span = Vector2(reach, reach) * 2.0 + Vector2(1200, 1200)
	var fit_k := minf(map_rect.size.x / span.x, map_rect.size.y / span.y)
	var angled := NavGrid.tilt == "angled"
	var depth: float = map_rect.size.y * 0.5 * Data.NAV_DEPTH
	if heading_up():
		scale_k = map_rect.size.x / Data.NAV_HEADING_SPAN * zoom
		var pp: Vector3 = space.player.global_position
		view.setup(Vector2(map_rect.size.x * 0.5, map_rect.size.y * Data.NAV_HEADING_ANCHOR), Vector3(pp.x, 0, pp.z), scale_k, -space.player.global_basis.z, angled, depth)
	else:
		scale_k = fit_k * zoom * (0.94 if angled else 1.0)
		view.setup(map_rect.size * 0.5, center + pan, scale_k, Vector3.ZERO, angled, depth)
	clip.position = map_rect.position
	clip.size = map_rect.size
	canvas.position = Vector2.ZERO
	canvas.size = map_rect.size
	_collect()
	hits.clear()
	for key in objs:
		var o: Dictionary = objs[key]
		hits[key] = _w2m(o["pos"])
		o["px"] = _px(o)
	# the right column
	var sm := Rect2(map_rect.end.x + 20, 100, S.x - map_rect.end.x - 56, 250)
	var bh := 58.0
	btn_close = Rect2(sm.position.x + sm.size.x * 0.5 + 5, S.y - 30 - bh, sm.size.x * 0.5 - 5, bh)
	btn_galaxy = Rect2(sm.position.x, S.y - 30 - bh, sm.size.x * 0.5 - 5, bh)
	btn_course = Rect2(sm.position.x, btn_close.position.y - 10 - bh, sm.size.x, bh)
	card_rect = Rect2(sm.position.x, 100, sm.size.x, btn_course.position.y - 12 - 100)
	btn_card_x = Rect2(card_rect.end.x - 50, card_rect.position.y + 6, 44, 44)
	# view buttons along the bottom of the map
	var y := map_rect.end.y - 56.0
	var x := map_rect.position.x + 10.0
	btn_orient = Rect2(x, y, 168, 46)
	btn_tilt = Rect2(x + 176, y, 150, 46)
	btn_zoom_out = Rect2(map_rect.end.x - 10 - 46 * 3 - 16, y, 46, 46)
	btn_zoom_in = Rect2(map_rect.end.x - 10 - 46 * 2 - 8, y, 46, 46)
	btn_fit = Rect2(map_rect.end.x - 10 - 46, y, 46, 46)
	compass_pos = Vector2(map_rect.end.x - 46, map_rect.position.y + 58)

## How big an object is drawn (pixels): its true size, but never smaller than a readable token.
func _px(o: Dictionary) -> float:
	var s := view.persp(o["pos"])
	match o["type"]:
		"planet": return clampf(float(o["r"]) * scale_k * s, 12.0 if o.get("main", false) else 9.0, 220.0)
		"star": return clampf(float(o["r"]) * scale_k * s, 16.0, 120.0)
		"station": return clampf(float(o["r"]) * scale_k * s, 15.0 if o.get("main", false) else 11.0, 90.0)
		"gate": return clampf(float(o["r"]) * scale_k * s, 14.0, 90.0)
		"belt", "nebula": return maxf(float(o["r"]) * scale_k * s, 14.0)
	return 9.0

func _draw() -> void:
	var S := get_viewport_rect().size
	_layout()
	draw_rect(Rect2(Vector2.ZERO, S), Color(0.01, 0.03, 0.06, 0.96))
	var sys: Dictionary = Data.SYSTEMS[GS.system_id]
	_txt(self, Vector2(36, 50), "NAVIGATION — %s SYSTEM" % sys["name"].to_upper(), 30, CYAN)
	_txt(self, Vector2(38, 78), "Tap anything to identify it, then SET COURSE to fly there on autopilot." if space != null and space.controls else "Plan your route. Launch to fly it.", 16, Color(0.85, 0.9, 0.95))
	draw_rect(map_rect, Color(0.012, 0.045, 0.08))

# ---------------------------------------------------------------- the map itself (clipped to the map window)
func _draw_map() -> void:
	var ci := canvas
	var sys: Dictionary = Data.SYSTEMS[GS.system_id]
	var local := Rect2(Vector2.ZERO, map_rect.size)
	var through: Array = []
	for key in objs:
		if objs[key]["type"] in ["planet", "station", "gate", "star"]: through.append(objs[key]["pos"])
	grid_stats = view.draw_grid(ci, local, 0.0, through, true, font)
	# orbit paths: a polygon circle through each planet, round the middle of the system
	for key in objs:
		var o: Dictionary = objs[key]
		if o["type"] != "planet": continue
		var rad := Vector2(o["pos"].x, o["pos"].z).length()
		if rad > 50.0: ci.draw_polyline(view.plane_ring(Vector3.ZERO, rad, Data.NAV_SIDES["orbit"]), Color(PLANET, 0.22), 1.5)
	# zones lying on the grid
	var neb: Dictionary = objs["nebula"]
	var np := PackedVector2Array()
	for i in 14:
		var a := TAU * i / 14.0
		var rr: float = float(neb["r"]) * (0.78 + 0.22 * sin(i * 2.3 + 1.0))
		np.append(view.to_screen(neb["pos"] + Vector3(cos(a) * rr, 0, sin(a) * rr)))
	NavGrid.cloud(ci, np, view.to_screen(neb["pos"]), neb["col"])
	_txt(ci, view.to_screen(neb["pos"]) + Vector2(-90, 5), neb["name"], 14, (neb["col"] as Color).lightened(0.45), HORIZONTAL_ALIGNMENT_CENTER, 180)
	var belt: Dictionary = objs["belt"]
	var bc := view.to_screen(belt["pos"])
	ci.draw_polyline(view.plane_ring(belt["pos"], belt["r"], Data.NAV_SIDES["ring"]), Color(belt["col"], 0.8), 2.0)
	ci.draw_polyline(view.plane_ring(belt["pos"], float(belt["r"]) * 0.55, Data.NAV_SIDES["ring"]), Color(belt["col"], 0.3), 1.0)
	for i in 26:
		var a2 := i * 2.4
		var rp: Vector3 = belt["pos"] + Vector3(cos(a2), 0, sin(a2)) * float(belt["r"]) * (0.25 + 0.75 * fmod(i * 0.37, 1.0))
		NavGrid.rock(ci, view.to_screen(rp), clampf(float(belt["r"]) * scale_k * 0.09, 3.0, 14.0) * (0.7 + 0.5 * fmod(i * 0.61, 1.0)), belt["col"], i)
	_txt(ci, bc + Vector2(-90, float(belt["px"]) * 0.8 + 20), belt["name"], 14, (belt["col"] as Color).lightened(0.2), HORIZONTAL_ALIGNMENT_CENTER, 180)
	# patrol areas
	for p in sys["patrols"]:
		ci.draw_polyline(view.plane_ring(p, 150.0, 12), Color(RED, 0.4), 1.5)
	# the course: under the bodies, over the grid
	route = {}
	var dest_n: Node3D = null
	if space != null and is_instance_valid(space.player):
		if space.nav_dest != null and is_instance_valid(space.nav_dest): dest_n = space.nav_dest   # v1.5i: the GPS destination
		elif space.autopilot != null and is_instance_valid(space.autopilot): dest_n = space.autopilot
	if dest_n != null:
		var a3 := view.to_screen(space.player.global_position)
		var b3 := view.to_screen(dest_n.global_position)
		var dist: float = space.distance_to(dest_n)
		route = {"from": a3 + map_rect.position, "to": b3 + map_rect.position, "dist": dist, "eta": space.nav_eta() if dest_n == space.nav_dest else dist / maxf(space.eff_speed(), 1.0), "name": str(dest_n.name)}
		var plan: Dictionary = space.nav_plan() if dest_n == space.nav_dest else {}
		if plan.get("via", "") == "lane" and not plan.get("riding", false):   # v1.5m: fastest by trade lane: fly to its mouth, ride it, fly on
			var e3 := view.to_screen(plan["entry"])
			var x3 := view.to_screen(plan["exit"])
			NavGrid.route(ci, a3, e3, Data.GPS_ROUTE_COLOR, t)
			ci.draw_line(e3, x3, Color(0.55, 0.85, 1.0), 6.0)
			NavGrid.route(ci, x3, b3, Data.GPS_ROUTE_COLOR, t)
			ci.draw_circle(e3, 7.0, Color(0.55, 0.85, 1.0))
			_txt(ci, (e3 + x3) * 0.5 + Vector2(10, 14), "TRADE LANE", 13, Color(0.55, 0.85, 1.0))
			route["via"] = "lane"
		else:
			NavGrid.route(ci, a3, b3, Data.GPS_ROUTE_COLOR, t)
			route["via"] = "direct"
		_txt(ci, a3 + Vector2(-26, -14), "A", 15, Color.WHITE)
		_txt(ci, (a3 + b3) * 0.5 + Vector2(12, -8), "%s  ·  ETA %s" % [_dist(dist), _eta(route["eta"])], 16, Color.WHITE)
		# v1.5i stage 2: the later stops, joined in order; numbered (the last is B)
		var stops: Array = space.nav_route if dest_n == space.nav_dest else [dest_n]
		var prev := b3
		for i in stops.size():
			var sp := view.to_screen((stops[i] as Node3D).global_position)
			if i > 0: NavGrid.route(ci, prev, sp, Color(Data.GPS_ROUTE_COLOR, 0.75), t)
			ci.draw_circle(sp, 10.0, Data.GPS_ROUTE_COLOR)
			if i == stops.size() - 1: ci.draw_arc(sp, 16.0 + 3.0 * sin(t * 4.0), 0, TAU, 24, Color(Data.GPS_ROUTE_COLOR, 0.7), 2.0)
			_txt(ci, sp + Vector2(-5, 5), str(i + 1) if stops.size() > 1 else "B", 13, Color.WHITE)
			prev = sp
		route["stops"] = stops.size()
	# bodies, far ones first so near ones overlap them in the angled view
	var order: Array = objs.keys()
	order.sort_custom(func(a4, b4): return (hits[a4] as Vector2).y < (hits[b4] as Vector2).y)
	for key in order:
		var o2: Dictionary = objs[key]
		var c := view.to_screen(o2["pos"])
		var r: float = o2["px"]
		if not local.grow(r * 2.0 + 160.0).has_point(c): continue   # outside the map window
		match o2["type"]:
			"planet": NavGrid.sphere(ci, c, r, o2["col"], Data.NAV_SIDES["planet"])
			"star": NavGrid.star(ci, c, r, o2["col"])
			"station": NavGrid.station(ci, c, r, o2["col"])
			"gate": NavGrid.gate(ci, c, r, o2["col"])
			"enemy", "traffic":
				var nd: Node3D = o2["node"]
				var f: Vector3 = -nd.global_basis.z
				NavGrid.dart(ci, c, 8.0, Vector2(f.x, f.z).rotated(view.rot), o2["col"])
		if o2["type"] in ["planet", "station", "gate", "star"]:
			var main_obj: bool = o2.get("main", false) or o2["type"] == "gate"
			var label: String = o2["name"]
			if o2["type"] == "gate": label = "%s > %s" % [o2["name"], Data.SYSTEMS[o2["data"]["to"]]["name"]]
			_txt(ci, c + Vector2(r + 8, 6), label, 16 if main_obj else 13, o2["col"] if main_obj else Color(o2["col"], 0.85))
	if selected == "point" and way_pos != Vector3.INF:
		var wp := view.to_screen(way_pos)
		NavGrid.fill(ci, PackedVector2Array([wp + Vector2(0, -12), wp + Vector2(12, 0), wp + Vector2(0, 12), wp + Vector2(-12, 0)]), GOLD)
		NavGrid.brackets(ci, wp, 20.0, Color.WHITE, 0.5 + 0.5 * sin(t * 5.0))
		_txt(ci, wp + Vector2(26, 6), "WAYPOINT", 15, GOLD)
	elif selected != "" and objs.has(selected):
		NavGrid.brackets(ci, view.to_screen(objs[selected]["pos"]), maxf(18.0, float(objs[selected]["px"]) + 8.0), Color(0.75, 0.95, 1.0), 0.5 + 0.5 * sin(t * 5.0))
	# v1.5e: the mission waypoint (gold diamond, as on the HUD)
	if space != null and is_instance_valid(space.player):
		var mw: Dictionary = space.mission_waypoint()
		if not mw.is_empty() and is_instance_valid(mw["node"]):
			var mp := view.to_screen((mw["node"] as Node3D).global_position)
			NavGrid.fill(ci, PackedVector2Array([mp + Vector2(0, -11), mp + Vector2(11, 0), mp + Vector2(0, 11), mp + Vector2(-11, 0)]), GOLD)
			ci.draw_polyline(PackedVector2Array([mp + Vector2(0, -16), mp + Vector2(16, 0), mp + Vector2(0, 16), mp + Vector2(-16, 0), mp + Vector2(0, -16)]), Color(GOLD, 0.5 + 0.5 * sin(t * 4.0)), 2.0)
			_txt(ci, mp + Vector2(22, -10), "MISSION", 14, GOLD)
	# you
	if space != null and is_instance_valid(space.player):
		var pp := view.to_screen(space.player.global_position)
		var fw: Vector3 = -space.player.global_basis.z
		var dir := Vector2(fw.x, fw.z).rotated(view.rot)
		for rr2 in [400.0, 1200.0]:   # range rings
			ci.draw_polyline(view.plane_ring(space.player.global_position, rr2, Data.NAV_SIDES["ring"]), Color(1, 1, 1, 0.16), 1.0)
		NavGrid.fill(ci, NavGrid.poly(pp, 22.0, 12), Color(1, 1, 1, 0.1))
		NavGrid.dart(ci, pp, 17.0, dir, Color.WHITE, true)
		var readout := "YOU  ·  %d m/s" % int(space.speed_now)
		if not route.is_empty(): readout += "  ·  ETA %s" % _eta(route["eta"])
		_txt(ci, pp + Vector2(22, 18), readout, 13, Color.WHITE)
	ci.draw_rect(local, Color(CYAN, 0.45), false, 2.0)

static func _dist(d: float) -> String:
	return "%.1f km" % (d / 1000.0) if d >= 1000.0 else "%d m" % int(d)

static func _eta(sec: float) -> String:
	var s := int(sec)
	return "%d:%02d" % [s / 60, s % 60]

# ---------------------------------------------------------------- panels, buttons and the info card (over the map)
func _draw_over() -> void:
	var ci := over
	var S := get_viewport_rect().size
	var sys: Dictionary = Data.SYSTEMS[GS.system_id]
	# compass: always there, always points at true north
	NavGrid.compass(ci, compass_pos, 26.0, view.north_angle(), font)
	_txt(ci, map_rect.position + Vector2(12, 24), ("HEADING-UP" if heading_up() else "NORTH-UP") + ("  ·  ANGLED" if NavGrid.tilt == "angled" else "  ·  OVERHEAD") + "  ·  grid %s" % _dist(float(grid_stats.get("spacing", 0.0))), 13, Color(CYAN.lightened(0.3), 0.9))
	_btn(ci, btn_orient, "HEADING-UP" if not heading_up() else "NORTH-UP", space != null, CYAN, 16)
	_btn(ci, btn_tilt, "OVERHEAD" if NavGrid.tilt == "angled" else "ANGLED", true, CYAN, 16)
	_btn(ci, btn_zoom_out, "−", zoom > Data.NAV_ZOOM[0] + 0.001, CYAN, 26)
	_btn(ci, btn_zoom_in, "+", zoom < Data.NAV_ZOOM[1] - 0.001, CYAN, 26)
	_btn(ci, btn_fit, "FIT", true, CYAN, 14)
	if selected == "":
		var sm := Rect2(card_rect.position, Vector2(card_rect.size.x, minf(250.0, card_rect.size.y * 0.62)))
		ci.draw_rect(sm, PANEL)
		ci.draw_rect(sm, Color(CYAN, 0.35), false, 2)
		if space != null and is_instance_valid(space.player):   # v1.5i GPS: tap a place to make it the destination
			_dest_panel(ci, Rect2(card_rect.position, card_rect.size))
			var can0 := false
			_btn(ci, btn_course, "SET COURSE", can0, GREEN)
			_btn(ci, btn_galaxy, "GALAXY", true, CYAN)
			_btn(ci, btn_close, "CLOSE", true, CYAN)
			return
		_txt(ci, sm.position + Vector2(14, 28), "KNOWN SPACE", 16, CYAN)
		_txt(ci, sm.position + Vector2(14, 52), "%s  ·  tile %s  ·  %s" % [sys["name"], sys.get("tile", "?"), sys.get("faction", "")], 15, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, sm.size.x - 28)
		var gy := 78.0
		for gd in sys["gates"]:
			if gy > sm.size.y - 40: break
			var known2: bool = gd["to"] in GS.discovered
			_txt(ci, sm.position + Vector2(14, gy), "%s > %s" % [gd["name"], Data.SYSTEMS[gd["to"]]["name"] + ("" if known2 else "  (uncharted)")], 14, GOLD if known2 else Color(1, 1, 1, 0.6), HORIZONTAL_ALIGNMENT_LEFT, sm.size.x - 28)
			gy += 22.0
		_txt(ci, sm.position + Vector2(14, sm.size.y - 14), "%d of %d systems charted." % [GS.discovered.size(), Data.SYSTEMS.size()], 13, Color(0.85, 0.9, 0.95), HORIZONTAL_ALIGNMENT_LEFT, sm.size.x - 28)
		var hint := Rect2(sm.position.x, sm.end.y + 12, sm.size.x, card_rect.end.y - sm.end.y - 12)
		ci.draw_rect(hint, PANEL)
		ci.draw_rect(hint, Color(CYAN, 0.35), false, 2)
		_txt(ci, hint.position + Vector2(14, 30), "No destination selected.", 16, Color(1, 1, 1, 0.75))
		ci.draw_multiline_string(font, hint.position + Vector2(14, 54), "Tap a planet, station, gate or ship to see what it is. Tap empty space for a waypoint. Pinch or use + and − to zoom.", HORIZONTAL_ALIGNMENT_LEFT, hint.size.x - 28, 14, 4, Color(1, 1, 1, 0.6))
	else:
		_card(ci)
	var can := selected != "" and space != null and space.controls
	_btn(ci, btn_course, "SET COURSE", can, GREEN)
	_btn(ci, btn_galaxy, "GALAXY", true, CYAN)
	_btn(ci, btn_close, "CLOSE", true, CYAN)

var dest_rows := {}   # key -> Rect2 (screen) of the destination list rows drawn last frame

func _dest_panel(ci: CanvasItem, rc: Rect2) -> void:
	dest_rows = {}
	route_btns = {}
	add_btns = {}
	ci.draw_rect(rc, PANEL)
	ci.draw_rect(rc, Color(CYAN, 0.35), false, 2)
	var col: Color = Data.GPS_ROUTE_COLOR
	var y := rc.position.y + 26.0
	# ---- the route: stops in order, with up / down / remove; tap a stop's name to replace it
	var stops: Array = space.nav_route
	if not stops.is_empty():
		var lens: Array = space.route_lengths()
		var spd: float = maxf(space.eff_speed(), 1.0)
		_txt(ci, Vector2(rc.position.x + 14, y), "ROUTE  ·  %s  ·  ETA %s" % [_dist(lens[1]), _eta(lens[1] / spd)], 14, col, HORIZONTAL_ALIGNMENT_LEFT, rc.size.x - 180)
		var cb := Rect2(rc.end.x - 78, y - 18, 66, 24)
		ci.draw_rect(cb, Color(1, 1, 1, 0.08))
		_txt(ci, cb.position + Vector2(0, 17), "CLEAR", 12, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, cb.size.x)
		route_btns["clear"] = cb
		var gb := Rect2(rc.end.x - 150, y - 18, 66, 24)   # v1.5m: fly the whole route on autopilot
		ci.draw_rect(gb, Color(0.15, 0.6, 0.3, 0.85) if not space.nav_go else Color(0.15, 0.6, 0.3, 0.4))
		_txt(ci, gb.position + Vector2(0, 17), "GO", 13, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, gb.size.x)
		route_btns["go"] = gb
		var pl: Dictionary = space.nav_plan()
		if pl.get("via", "") == "lane":
			_txt(ci, Vector2(rc.position.x + 14, y + 16), "Fastest: by trade lane %s" % pl["lane_name"], 11, Color(0.55, 0.85, 1.0), HORIZONTAL_ALIGNMENT_LEFT, rc.size.x - 28)
			y += 20.0
		y += 10.0
		for i in stops.size():
			var n: Node3D = stops[i]
			var sr := Rect2(rc.position.x + 8, y, rc.size.x - 16, 30)
			ci.draw_rect(sr, Color(GOLD, 0.25) if armed == i else (Color(col, 0.22) if i == 0 else Color(1, 1, 1, 0.05)))
			var leg: float = space.distance_to(n) if i == 0 else (stops[i - 1] as Node3D).global_position.distance_to(n.global_position)
			_txt(ci, sr.position + Vector2(8, 20), "%d. %s" % [i + 1, n.name], 13, GOLD if armed == i else Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, sr.size.x - 170)
			_txt(ci, sr.position + Vector2(sr.size.x - 168, 20), _dist(leg), 12, CYAN, HORIZONTAL_ALIGNMENT_RIGHT, 64)
			route_btns["stop_%d" % i] = Rect2(sr.position, Vector2(sr.size.x - 100, sr.size.y))
			var bx := sr.end.x - 96.0
			for b in ["up", "down", "x"]:
				var br := Rect2(bx, sr.position.y + 2, 30, 26)
				ci.draw_rect(br, Color(1, 1, 1, 0.1))
				var c := br.get_center()
				if b == "up": ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -6), c + Vector2(7, 5), c + Vector2(-7, 5)]), Color.WHITE)
				elif b == "down": ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, 6), c + Vector2(7, -5), c + Vector2(-7, -5)]), Color.WHITE)
				else:
					ci.draw_line(c + Vector2(-6, -6), c + Vector2(6, 6), Color(1, 0.6, 0.55), 2.5)
					ci.draw_line(c + Vector2(-6, 6), c + Vector2(6, -6), Color(1, 0.6, 0.55), 2.5)
				route_btns["%s_%d" % [b, i]] = br
				bx += 32.0
			y += 33.0
		if armed >= 0: _txt(ci, Vector2(rc.position.x + 14, y + 14), "Tap a place below to put it at stop %d." % (armed + 1), 12, GOLD)
		elif gps_note != "": _txt(ci, Vector2(rc.position.x + 14, y + 14), gps_note, 12, Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_LEFT, rc.size.x - 28)
		y += 22.0
	# ---- the places: tap = go there (the route becomes this one stop); + = ADD WAYPOINT
	_txt(ci, Vector2(rc.position.x + 14, y + 16), "GPS  ·  DESTINATIONS", 15, CYAN)
	_txt(ci, Vector2(rc.position.x + 14, y + 16), "+ = ADD WAYPOINT", 11, Color(1, 1, 1, 0.6), HORIZONTAL_ALIGNMENT_RIGHT, rc.size.x - 28)
	y += 26.0
	var rows: Array = dest_list()
	var cur: Node3D = space.nav_dest if space.nav_dest != null and is_instance_valid(space.nav_dest) else null
	for i in rows.size():
		if y + 36.0 > rc.end.y - 4.0: break
		var r: Dictionary = rows[i]
		var rr := Rect2(rc.position.x + 8, y, rc.size.x - 16, 34)
		var mine: bool = cur != null and (str(cur.name) == str(r["name"]).validate_node_name() or str(cur.name) == r["name"] or (r["key"] != "mission" and _node(str(r["key"])) == cur))
		ci.draw_rect(rr, Color(col, 0.28) if mine else Color(1, 1, 1, 0.04))
		_txt(ci, rr.position + Vector2(8, 15), str(r["name"]), 13, GOLD if r["key"] == "mission" else Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, rr.size.x - 130)
		_txt(ci, rr.position + Vector2(8, 29), str(r["kind"]), 10, Color(0.75, 0.85, 0.95), HORIZONTAL_ALIGNMENT_LEFT, rr.size.x - 130)
		_txt(ci, rr.position + Vector2(rr.size.x - 122, 22), _dist(float(r["dist"])), 13, CYAN, HORIZONTAL_ALIGNMENT_RIGHT, 80)
		var ab := Rect2(rr.end.x - 36, rr.position.y + 3, 32, 28)
		ci.draw_rect(ab, Color(col, 0.35))
		_txt(ci, ab.position + Vector2(0, 21), "+", 18, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, ab.size.x)
		add_btns[str(r["key"])] = Rect2(ab.position + position, ab.size)
		dest_rows[str(r["key"])] = Rect2(rr.position + position, Vector2(rr.size.x - 40, rr.size.y))
		y += 37.0

func _card(ci: CanvasItem) -> void:
	var inf := info(selected)
	if inf.is_empty():
		selected = ""
		return
	var r := card_rect
	var col: Color = inf["col"]
	ci.draw_rect(r, PANEL)
	ci.draw_rect(r, Color(col, 0.7), false, 2)
	var pw := r.size.x - 20.0
	var ph := minf(pw * 0.75, r.size.y * 0.5)
	var pr := Rect2(r.position + Vector2(10, 10), Vector2(pw, ph))
	ci.draw_rect(pr, Color(0.0, 0.02, 0.05))
	var tex: Texture2D = inf["picture"]
	if tex != null:
		var src: Rect2 = inf["region"]
		var want := pr.size.x / pr.size.y
		if src.size.x / src.size.y > want: src = Rect2(src.position.x + (src.size.x - src.size.y * want) * 0.5, src.position.y, src.size.y * want, src.size.y)
		else: src = Rect2(src.position.x, src.position.y + (src.size.y - src.size.x / want) * 0.5, src.size.x, src.size.x / want)
		ci.draw_texture_rect_region(tex, pr, src)
	else:   # no picture at all: a code-made token, never a broken image
		var c := pr.get_center()
		var pv := NavGrid.new()
		pv.setup(c, Vector3.ZERO, 1.0, Vector3.ZERO, false, 900.0)
		pv.draw_grid(ci, pr)
		var tp: String = objs[selected]["type"] if objs.has(selected) else "point"
		match tp:
			"planet": NavGrid.sphere(ci, c, ph * 0.3, col)
			"star": NavGrid.star(ci, c, ph * 0.2, col)
			"station": NavGrid.station(ci, c, ph * 0.3, col)
			"gate": NavGrid.gate(ci, c, ph * 0.3, col)
			"belt":
				for i in 7: NavGrid.rock(ci, c + Vector2(cos(i * 2.4), sin(i * 2.4) * 0.6) * ph * 0.28 * fmod(i * 0.37 + 0.3, 1.0), ph * 0.1, col, i)
			"nebula": NavGrid.cloud(ci, NavGrid.poly(c, ph * 0.34, 14), c, col)
			"point": NavGrid.route(ci, c + Vector2(-pw * 0.3, ph * 0.25), c + Vector2(0, ph * 0.15), GOLD, t)
			_: NavGrid.dart(ci, c, ph * 0.22, Vector2(0.4, -1), col, true)
	ci.draw_rect(pr, Color(col, 0.6), false, 1.5)
	_btn(ci, btn_card_x, "X", true, CYAN, 20)
	var y := pr.end.y + 30.0
	var nm: String = inf["name"]
	var fs := 22
	while fs > 14 and font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > r.size.x - 24: fs -= 1
	_txt(ci, Vector2(r.position.x + 12, y), nm, fs, GOLD)
	y += 24.0
	_txt(ci, Vector2(r.position.x + 12, y), str(inf["type"]).to_upper(), 14, col.lightened(0.3))
	if float(inf["distance"]) >= 0.0:
		_txt(ci, Vector2(r.position.x, y), _dist(inf["distance"]), 15, CYAN, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 12)
	y += 22.0
	for line: String in inf["lines"]:
		if y > r.end.y - 10: break
		var rows := maxi(1, int(ceil(font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x / (r.size.x - 24))))
		rows = mini(rows, maxi(1, int((r.end.y - y) / 18.0) + 1))
		ci.draw_multiline_string(font, Vector2(r.position.x + 12, y), line, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 24, 14, rows, Color(0.86, 0.91, 0.96))
		y += 18.0 * rows + 4.0

func _btn(ci: CanvasItem, r: Rect2, label: String, enabled: bool, col: Color, size := 21) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col.darkened(0.6), 0.9) if enabled else Color(0.03, 0.06, 0.1, 0.85)
	sb.border_color = Color(col, 0.9 if enabled else 0.25)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	ci.draw_style_box(sb, r)
	_txt(ci, r.position + Vector2(0, r.size.y * 0.5 + size * 0.36), label, size, Color(1, 1, 1, 1.0 if enabled else 0.35), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
