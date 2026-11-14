class_name ShipMap3D
extends SubViewport
## v13.129 (owner: "not just a top down map: rotate it, zoom in and out, know where you're at in the ship; the rooms you
## have been through fog of war style; every section its own object; the locked doors in their colour (yellow, red);
## the floor red or blue, mechs or pilots; and the elevation of rooms on the same floor"). A small 3D model of the
## deck you are on, drawn in its own world: every room, hall and doorway a slab at its own height (ramps tilted), red
## for mech space, blue for pilot space, yellow lifts. Places you have been are solid; the rest is a faint ghost. Card
## doors show in their colour once you have seen them. You are the white arrow, the next place to go the gold one.
## Drag turns it, pinch / wheel zooms (hud.gd feeds yaw, pitch and zoom).

const COL := {"mech": Color(0.95, 0.22, 0.2), "pilot": Color(0.25, 0.55, 1.0), "lift": Color(1.0, 0.85, 0.15)}
const FOG := Color(0.55, 0.65, 0.8)
const SLAB := 3.0
var cam: Camera3D
var world_root: Node3D
var slabs := {}          # room key -> MeshInstance3D
var door_nodes: Array = []   # [MeshInstance3D, door dict]
var you: MeshInstance3D
var goal: MeshInstance3D
var center := Vector3.ZERO
var radius := 500.0
var _seen_n := -1
var adj := {}            # room key -> [neighbour keys] (rooms whose rects touch: walkable joins)
var route_root: Node3D
var _route_key := ""
var lit := {}            # v13.138: the rooms Evee lights up (yellow) on the way to her waypoint
var _state := ""
var plan_mi: MeshInstance3D
var plan_decks := {}     # deck name -> its plan picture (the next deck's plan when you go up or down)
var _route_t := 0.0

func setup(rooms: Dictionary, doors: Array, plan_tex: Texture2D = null, pm: Dictionary = {}, decks: Dictionary = {}) -> void:
	plan_decks = decks
	own_world_3d = true
	transparent_bg = true
	size = Vector2i(720, 720)
	msaa_3d = Viewport.MSAA_2X
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	world_root = Node3D.new()
	add_child(world_root)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1, 1, 1)
	e.ambient_light_energy = 1.0
	env.environment = e
	world_root.add_child(env)
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	# v13.136 (owner: "use the overhead map as well, laid on the 3D"): the ship's deck plan picture under the model,
	# the rooms' slabs standing on it (plan px -> world: (px - ax) * scale, (py - cy) * scale)
	if plan_tex != null and not pm.is_empty():
		var sc := float(pm["scale"])
		var pw := float(pm["w"]) * sc
		var ph := float(pm["h"]) * sc
		var pl := MeshInstance3D.new()
		var plm := PlaneMesh.new()
		plm.size = Vector2(pw, ph)
		pl.mesh = plm
		var mm := StandardMaterial3D.new()
		mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mm.albedo_texture = plan_tex
		mm.albedo_color = Color(1, 1, 1, 0.55)   # v13.141: dimmer, so the room cubes read on it
		mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mm.cull_mode = BaseMaterial3D.CULL_DISABLED
		pl.material_override = mm
		pl.position = Vector3((float(pm["w"]) * 0.5 - float(pm["ax"])) * sc, -SLAB * 2.0, (float(pm["h"]) * 0.5 - float(pm["cy"])) * sc)
		pl.name = "PlanPicture"
		world_root.add_child(pl)
		plan_mi = pl
		plan_decks["MAIN DECK"] = plan_tex
	for k in rooms:
		var R: Dictionary = rooms[k]
		var r: Array = R["r"]
		var y0 := float(R["y"][0])
		var y1 := float(R["y"][1])
		var sx := float(r[1]) - float(r[0])
		var sz := float(r[3]) - float(r[2])
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var flat := absf(y1 - y0) < 0.5
		var run := sx if str(R.get("axis", "x")) == "x" else sz
		var slope := 0.0 if flat else atan2(y1 - y0, maxf(1.0, run))
		bm.size = Vector3(sx if flat or str(R.get("axis", "x")) != "x" else sqrt(sx * sx + (y1 - y0) * (y1 - y0)), SLAB,
			sz if flat or str(R.get("axis", "x")) == "x" else sqrt(sz * sz + (y1 - y0) * (y1 - y0)))
		mi.mesh = bm
		mi.position = Vector3((float(r[0]) + float(r[1])) * 0.5, (y0 + y1) * 0.5, (float(r[2]) + float(r[3])) * 0.5)
		if not flat:
			if str(R.get("axis", "x")) == "x": mi.rotation.z = slope
			else: mi.rotation.x = -slope
		mi.material_override = _mat(FOG, 0.10)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world_root.add_child(mi)
		slabs[k] = mi
		var kd := str(R.get("kind", "mech"))
		if not COL.has(kd): kd = "mech"
		mi.set_meta("col", COL[kd])
		# v13.138 (owner: "a clean look: little small cubes, a little transparent"): a room is one see-through cube as
		# tall as its ceiling (a quarter scale: mech rooms stand tall, pilot rooms low); halls and doorways a thin floor
		if not bool(R.get("flow", false)) and not bool(R.get("conn", false)):
			var wh := clampf(float(R.get("h", 50.0)) * 0.35, 6.0, 40.0)
			bm.size = Vector3(bm.size.x * 0.94, wh, bm.size.z * 0.94)
			mi.position.y += wh * 0.5
			mi.set_meta("cube", true)
			var ed := MeshInstance3D.new()   # v13.141: the cube's edges, so it reads as a box
			ed.name = "Edges"
			ed.mesh = _edges(bm.size)
			ed.material_override = _mat(COL[kd], 0.0)
			ed.visible = false
			mi.add_child(ed)
		lo = lo.min(Vector3(float(r[0]), minf(y0, y1), float(r[2])))
		hi = hi.max(Vector3(float(r[1]), maxf(y0, y1), float(r[3])))
	for d in doors:
		if int(d.get("key", 0)) <= 0 or not d.has("center"): continue
		var dm := MeshInstance3D.new()
		var db := BoxMesh.new()
		db.size = Vector3(26, 22, 26)
		dm.mesh = db
		dm.position = (d["center"] as Vector3) + Vector3(0, 11, 0)
		dm.material_override = _mat(ShipInterior.KEY_COL[int(d["key"])], 0.95)
		dm.visible = false
		world_root.add_child(dm)
		door_nodes.append([dm, d])
	you = MeshInstance3D.new()
	var prm := PrismMesh.new()
	prm.size = Vector3(60, 90, 12)
	you.mesh = prm
	you.material_override = _mat(Color(1, 1, 1), 1.0)
	world_root.add_child(you)
	goal = MeshInstance3D.new()
	var gm := SphereMesh.new()
	gm.radius = 26.0
	gm.height = 52.0
	goal.mesh = gm
	goal.material_override = _mat(Color(1.0, 0.82, 0.25), 1.0)
	goal.visible = false
	world_root.add_child(goal)
	for a in rooms: adj[a] = []
	var ks: Array = rooms.keys()
	for i in ks.size():
		for j in range(i + 1, ks.size()):
			if not Boarding.joint(ks[i], ks[j]).is_empty():
				adj[ks[i]].append(ks[j])
				adj[ks[j]].append(ks[i])
	route_root = Node3D.new()
	world_root.add_child(route_root)
	center = (lo + hi) * 0.5
	radius = maxf(200.0, (hi - lo).length() * 0.5)
	you.scale = Vector3.ONE * clampf(radius / 1500.0, 0.35, 1.2)   # v13.141 (owner: "arrow marker too big")
	goal.scale = Vector3.ONE * clampf(radius / 1500.0, 0.35, 1.2)
	for dn in door_nodes: (dn[0] as MeshInstance3D).scale = Vector3.ONE * clampf(radius / 900.0, 0.6, 3.0)
	cam = Camera3D.new()
	cam.fov = 40.0
	cam.near = 5.0
	cam.far = radius * 12.0
	world_root.add_child(cam)
	cam.current = true

func _edges(sz: Vector3) -> ArrayMesh:
	var h := sz * 0.5
	var v := PackedVector3Array()
	for a in [-1.0, 1.0]:
		for b in [-1.0, 1.0]:
			v.append_array([Vector3(-h.x, a * h.y, b * h.z), Vector3(h.x, a * h.y, b * h.z)])
			v.append_array([Vector3(a * h.x, -h.y, b * h.z), Vector3(a * h.x, h.y, b * h.z)])
			v.append_array([Vector3(a * h.x, b * h.y, -h.z), Vector3(a * h.x, b * h.y, h.z)])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arr)
	return m

func _mat(c: Color, a: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(c, a)
	if a < 0.99: m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	return m

## Every frame the map is open. seen: room keys you have stood in.
func refresh(seen: Dictionary, deck_y: float, ppos: Vector3, pfwd: Vector3, goal_at, yaw: float, pitch: float, zoom: float, on_foot := false) -> void:
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var st := "%d|%s|%d" % [seen.size(), str(on_foot), lit.hash()]
	if st != _state:
		_state = st
		for k in slabs:
			var mi: MeshInstance3D = slabs[k]
			var col: Color = mi.get_meta("col")
			var mine: bool = (col == COL["pilot"]) == on_foot or col == COL["lift"]   # (on foot: the pilot rooms; in the mech: the mech's)
			var a: float
			if not mi.has_meta("cube"): a = 0.18 if seen.has(k) else 0.05   # (halls: a thin floor)
			elif seen.has(k): a = 0.62 if mine else 0.38   # v13.141 (owner: "a cube shape for the rooms that I was in"): the rooms you were in stand out
			else: a = 0.04 if mine else 0.02
			var c := col if mine or seen.has(k) else FOG
			if lit.has(k):
				c = Color(1.0, 0.85, 0.2)
				a = 0.62
			(mi.material_override as StandardMaterial3D).albedo_color = Color(c, a)
			var ed := mi.get_node_or_null("Edges") as MeshInstance3D
			if ed:
				ed.visible = seen.has(k) or lit.has(k)
				(ed.material_override as StandardMaterial3D).albedo_color = Color(c.lightened(0.3), 0.95)
		for dn in door_nodes:
			var d: Dictionary = dn[1]
			var near := false
			for rk in d.get("rooms", []): near = near or seen.has(str(rk))
			(dn[0] as MeshInstance3D).visible = near
	var dk := Boarding.deck_name(deck_y)   # the plan of the deck you are on
	if plan_mi != null and plan_decks.has(dk) and (plan_mi.material_override as StandardMaterial3D).albedo_texture != plan_decks[dk]:
		(plan_mi.material_override as StandardMaterial3D).albedo_texture = plan_decks[dk]
	if plan_mi != null: plan_mi.position.y = deck_y - SLAB * 2.0
	for k in slabs:   # only this deck (the others would hide it)
		var mi: MeshInstance3D = slabs[k]
		mi.visible = absf(mi.position.y - deck_y) < 60.0
	you.position = ppos + Vector3(0, 60, 0)
	var f := Vector2(pfwd.x, pfwd.z)
	you.rotation = Vector3(-PI / 2, 0, 0)
	if f.length() > 0.01: you.rotation.y = atan2(-f.x, -f.y)
	if goal_at != null:
		goal.visible = true
		goal.position = (goal_at as Vector3) + Vector3(0, 40, 0)
	else: goal.visible = false
	var dist := radius * 2.6 / maxf(0.5, zoom)
	var look := center.lerp(ppos, clampf((zoom - 1.0) / 2.0, 0.0, 1.0))   # zoomed in, it closes on you
	look.y = deck_y
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	cam.position = look + dir * dist
	cam.look_at(look, Vector3.UP)

## The way, room by room (shortest by room centres), from p to q.
func _path(p: Vector3, q: Vector3) -> PackedVector3Array:
	var a := Boarding.room_at(p, 6.0)
	var b := Boarding.room_at(q, 6.0)
	var out := PackedVector3Array([p])
	if a == "" or b == "" or a == b:
		out.append(q)
		return out
	var cen := func(k: String) -> Vector3:
		var r: Array = Boarding.ROOMS[k]["r"]
		var x := (float(r[0]) + float(r[1])) * 0.5
		var z := (float(r[2]) + float(r[3])) * 0.5
		return Vector3(x, Boarding.floor_of(k, x, z), z)
	var dist := {a: 0.0}
	var prev := {}
	var open := [a]
	while not open.is_empty():
		var bi := 0
		for i in open.size():
			if float(dist[open[i]]) < float(dist[open[bi]]): bi = i
		var u: String = open[bi]
		open.remove_at(bi)
		if u == b: break
		for v in adj.get(u, []):
			var nd := float(dist[u]) + (cen.call(u) as Vector3).distance_to(cen.call(v))
			if not dist.has(v) or nd < float(dist[v]):
				dist[v] = nd
				prev[v] = u
				if not open.has(v): open.append(v)
	if not prev.has(b):
		out.append(q)
		return out
	var chain: Array = []
	var c: String = b
	while c != a:
		chain.push_front(c)
		c = prev[c]
	for k in chain:
		if k != b: out.append(cen.call(k))
	out.append(q)
	return out

## v13.129 (owner: "plot the movement: point A to B to C to D ... to the objective"): the job's steps in order,
## lettered A, B, C ..., joined by the way through the ship (a gold line).
func set_route(from: Vector3, steps: Array) -> void:
	var key := "%d|%d" % [steps.size(), int(Boarding.room_at(from, 6.0).hash())]
	_route_t -= get_process_delta_time()
	if key == _route_key and _route_t > 0.0: return
	_route_key = key
	_route_t = 0.5
	for c in route_root.get_children(): c.queue_free()
	var w := clampf(radius / 140.0, 4.0, 30.0)
	var at := from
	var lit2 := {}
	for i in steps.size():
		var st: Dictionary = steps[i]
		var pts := _path(at, st["at"])
		for q in pts:   # v13.138 (owner: "ask Evee lights up the cubes in yellow"): the rooms on her way, lit yellow
			var rk := Boarding.room_at(q, 6.0)
			if rk != "": lit2[rk] = true
		for j in range(pts.size() - 1):   # (and the halls between them)
			for t in [0.25, 0.5, 0.75]:
				var rk2 := Boarding.room_at((pts[j] as Vector3).lerp(pts[j + 1], t), 6.0)
				if rk2 != "": lit2[rk2] = true
		var lb := Label3D.new()
		lb.text = "%s  %s" % [char(65 + i), str(st["label"])]
		lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lb.no_depth_test = true
		lb.font_size = 96
		lb.outline_size = 18
		lb.pixel_size = radius / 2600.0
		lb.modulate = st.get("col", Color(1, 1, 1))
		route_root.add_child(lb)
		lb.position = (st["at"] as Vector3) + Vector3(0, radius * 0.06, 0)
		var dot := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = w * 1.8
		sm.height = w * 3.6
		dot.mesh = sm
		dot.material_override = _mat(st.get("col", Color(1, 1, 1)), 1.0)
		route_root.add_child(dot)
		dot.position = (st["at"] as Vector3) + Vector3(0, 10, 0)
		at = st["at"]
	lit = lit2

func pause() -> void:
	render_target_update_mode = SubViewport.UPDATE_DISABLED
