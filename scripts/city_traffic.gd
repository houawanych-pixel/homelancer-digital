class_name CityTraffic
extends Node3D
## v13.282 (owner: "hover traffic: simple stand-ins for cars, buses and trucks, staying low along the streets"): the
## traffic of a city tile. Like the people (CityLife), a fixed pool reused round you: each vehicle hovers a little
## over the street and drives one lane of an avenue or an alley straight across the city, keeping right, then is
## taken back and comes again on another lane near you. Every vehicle is a few slabs: a body, a glass cabin (a bus has
## a long one, a truck a cab and a box), a glowing hover strip under it, headlights in front and tail lights behind.
## Sized for the 3.8 m people.

var space: Node
var planet_id := ""
var tile := -1
var pool: Array = []      # {node, kind, state: "off" | "drive", from, to, t, len, speed, base_y}
var made := 0             # (tests) vehicles sent out so far
var _lanes: Array = []    # [from (tile-local x, z), to, (v13.323: height over the street; none = on the street)] one way each
var sky_lanes := 0        # (checks) lanes up on the skyways
## v13.324 (owner: "traffic lights, futuristic: a set of circles, green bars for green and red, and cars stop and go"):
## a light at every avenue crossing; the avenues along x and along z take turns (green, amber, then the other way).
var _ave_x: Array = []    # [x, half width] of the avenues that run along z
var _ave_z: Array = []    # [z, half width] of the avenues that run along x
var light_t := 0.0        # the lights' clock (s)
var lights: Array = []    # the light posts (Node3D)
var stops := 0            # (checks) times a car held at a red light
var _lamp_x: StandardMaterial3D   # the lamps that the traffic along x sees
var _lamp_z: StandardMaterial3D
var _spawn_t := 0.0
var _rng := RandomNumberGenerator.new()
var _g := 0.0

func setup(sp: Node, pid: String, t: int) -> void:
	space = sp
	planet_id = pid
	tile = t
	name = "CityTraffic"
	_rng.seed = hash(pid + str(t) + "|traffic")
	_g = CityPlan.ground(pid, t)
	_build_lanes()
	_build_pool()
	_build_lights()

## The lanes: every avenue between and round the blocks and every alley through them, two lanes each way, keeping right.
func _build_lanes() -> void:
	var cr := CityPlan.rect(planet_id, tile)
	if cr.size == Vector2i.ZERO: return
	var S: float = Data.BLOCK_REGION
	var org := Vector2(-Surface.EDGE, -Surface.EDGE) + Vector2(cr.position) * S
	var size := Vector2(cr.size) * S
	var av: float = Data.CITY_AVENUE * Data.BLOCK_MIN
	var lw: float = Data.TRAFFIC_LANE_W
	# the road middles across one axis: outer avenues (a half avenue just inside the edge), inner ones on the block
	# lines, an alley through each block's middle
	var mids := func(n_blocks: int) -> Array:
		var out: Array = [[av * 0.5, 1.0]]
		for b in n_blocks:
			out.append([b * S + S * 0.5, 1.0])   # the alley
			if b > 0: out.append([b * S, 2.0])  # an avenue between two blocks
		out.append([n_blocks * S - av * 0.5, 1.0])
		return out
	for m in mids.call(cr.size.y):   # lanes along x
		var z: float = org.y + float(m[0])
		for k in int(m[1]):
			var off := lw * (0.5 + k)
			_lanes.append([Vector2(org.x, z + off), Vector2(org.x + size.x, z + off)])   # eastbound keeps right (south side)
			_lanes.append([Vector2(org.x + size.x, z - off), Vector2(org.x, z - off)])
	for m in mids.call(cr.size.x):   # lanes along z
		var x: float = org.x + float(m[0])
		for k in int(m[1]):
			var off := lw * (0.5 + k)
			_lanes.append([Vector2(x - off, org.y), Vector2(x - off, org.y + size.y)])
			_lanes.append([Vector2(x + off, org.y + size.y), Vector2(x + off, org.y)])
	# v13.323 (owner: "we should have a track on the top to have cars running through there too"): the skyways over the
	# inner avenues (the same lines CityTowers.city_links draws), two lanes each way on each deck
	if not CityPlan.is_town(planet_id, tile) and Data.CITY_TOWERS:
		for ax in 2:
			for kk in range(1, (cr.size.x if ax == 0 else cr.size.y)):
				var line: float = (org.x if ax == 0 else org.y) + kk * S
				var levels: Array = [Data.SKYWAY_Y] if kk > 1 else [Data.SKYWAY_Y, Data.SKYWAY_Y2]
				for ly in levels:
					var yy: float = float(ly) + Data.TRAFFIC_HOVER
					for k in 2:
						var off := lw * (0.5 + k)
						if ax == 0:   # a skyway along z
							_lanes.append([Vector2(line - off, org.y), Vector2(line - off, org.y + size.y), yy])
							_lanes.append([Vector2(line + off, org.y + size.y), Vector2(line + off, org.y), yy])
						else:
							_lanes.append([Vector2(org.x, line + off), Vector2(org.x + size.x, line + off), yy])
							_lanes.append([Vector2(org.x + size.x, line - off), Vector2(org.x, line - off), yy])
	sky_lanes = _lanes.filter(func(l): return l.size() > 2).size()
	# v13.324: the avenue lines (where the lights stand): [coordinate, half the road's width] on each axis
	var lines := func(n_blocks: int, o: float) -> Array:
		var out: Array = [[o + av * 0.5, av * 0.5]]
		for b in range(1, n_blocks): out.append([o + b * S, av])
		out.append([o + n_blocks * S - av * 0.5, av * 0.5])
		return out
	_ave_x = lines.call(cr.size.x, org.x)   # x of the avenues that run along z
	_ave_z = lines.call(cr.size.y, org.y)   # z of the avenues that run along x

func _build_pool() -> void:
	var kinds: Array = []
	for k in Data.TRAFFIC_MIX:
		for q in int(Data.TRAFFIC_MIX[k]): kinds.append(k)
	for i in Data.TRAFFIC_POOL:
		var kind: String = kinds[i % kinds.size()]
		var nd := _vehicle(kind, i)
		nd.visible = false
		add_child(nd)
		pool.append({"node": nd, "kind": kind, "state": "off", "from": Vector2.ZERO, "to": Vector2.ZERO, "t": 0.0, "len": 1.0, "speed": 0.0, "phase": _rng.randf() * TAU})

static var _mats := {}
static func _mat(key: String, col: Color, glow := 0.0, glass := false) -> StandardMaterial3D:
	if _mats.has(key): return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.08 if glass else 0.35
	m.metallic = 0.7 if not glass else 0.2
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = glow
	_mats[key] = m
	return m

func _box(parent: Node3D, size: Vector3, at: Vector3, mat: Material, nm := "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = at
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if nm != "": mi.name = nm
	parent.add_child(mi)
	return mi

## A vehicle of a kind, facing -Z, its underside at y = 0 (it hovers TRAFFIC_HOVER over the street).
## v13.292 (owner: "cut these shapes out and use the top view as placeholders"): the owner's vehicle sheets, cut out of
## the green: each vehicle is its top-view outline pulled up into a body, the top view laid on its roof and the side
## view on its sides (see-through where the picture is), so from above it is the drawing and from the street it has
## the right shape and colours. assets/vehicles: <id>_top.webp, <id>_side.webp, vehicles.json (outline, sizes, kind).
static var _art: Dictionary = {}
static func art() -> Dictionary:
	if _art.is_empty() and FileAccess.file_exists("res://assets/vehicles/vehicles.json"):
		var j = JSON.parse_string(FileAccess.get_file_as_string("res://assets/vehicles/vehicles.json"))
		if j is Dictionary: _art = j
	return _art

## Which drawn vehicle plays a kind of traffic (the i-th of its list).
static func model_for(kind: String, i: int) -> String:
	var opts: Array = (Data.TRAFFIC_MODELS.get(kind, []) as Array).filter(func(m): return art().has(m))
	return str(opts[i % opts.size()]) if not opts.is_empty() else ""

static var _art_mats := {}
func _art_mat(path: String) -> StandardMaterial3D:
	if _art_mats.has(path): return _art_mats[path]
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(path)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.45
	m.metallic = 0.25
	m.emission_enabled = true   # (the drawings' neon and lights read in the shade)
	m.emission_texture = m.albedo_texture
	m.emission_energy_multiplier = 0.35
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_art_mats[path] = m
	return m

## The drawn vehicle: length ln (m) along -Z (its nose), width and height from its pictures.
func _art_vehicle(root: Node3D, id: String, ln: float) -> Vector3:
	var d: Dictionary = art()[id]
	var tw: Vector2 = Vector2(d["top"][0], d["top"][1])
	var sw: Vector2 = Vector2(d["side"][0], d["side"][1])
	var w := ln * tw.y / tw.x
	var hgt := ln * sw.y / sw.x
	var roof := hgt * Data.VEHICLE_ROOF_AT
	var pts: Array = d["outline"]
	var st := SurfaceTool.new()   # the sides: the side view wrapped round the outline
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var np := pts.size()
	var p3 := func(q: Array, y: float) -> Vector3: return Vector3((0.5 - float(q[1])) * w, y, (float(q[0]) - 0.5) * ln)
	for k in np:
		var a: Array = pts[k]
		var b: Array = pts[(k + 1) % np]
		var A0: Vector3 = p3.call(a, 0.0)
		var B0: Vector3 = p3.call(b, 0.0)
		var A1: Vector3 = p3.call(a, hgt)
		var B1: Vector3 = p3.call(b, hgt)
		var nrm := (B0 - A0).cross(Vector3.UP).normalized()
		for v in [[A0, Vector2(float(a[0]), 1.0)], [B0, Vector2(float(b[0]), 1.0)], [B1, Vector2(float(b[0]), 0.0)], [A0, Vector2(float(a[0]), 1.0)], [B1, Vector2(float(b[0]), 0.0)], [A1, Vector2(float(a[0]), 0.0)]]:
			st.set_normal(nrm)
			st.set_uv(v[1])
			st.add_vertex(v[0])
	var sides := MeshInstance3D.new()
	sides.name = "Sides"
	sides.mesh = st.commit()
	sides.material_override = _art_mat("res://assets/vehicles/%s_side.webp" % id)
	sides.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(sides)
	var top := MeshInstance3D.new()   # the roof: the top view, at the roof line
	top.name = "Roof"
	var qm := QuadMesh.new()
	qm.size = Vector2(w, ln)
	qm.orientation = PlaneMesh.FACE_Y
	top.mesh = qm
	top.material_override = _art_mat("res://assets/vehicles/%s_top.webp" % id)
	top.position = Vector3(0, roof, 0)
	top.rotation.y = -PI * 0.5   # (the picture's nose is at its left: turn it to point down -Z)
	top.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(top)
	return Vector3(w, hgt, ln)

func _vehicle(kind: String, i: int, model := "") -> Node3D:
	var root := Node3D.new()
	root.name = "%s%d" % [kind.capitalize(), i]
	var mid := model if model != "" and art().has(model) else model_for(kind, i)
	if mid != "":
		var dims2 := _art_vehicle(root, mid, (Data.TRAFFIC_SIZE[kind] as Vector3).z)
		var hov := _mat("hover", Data.CITY_TRIM, 2.2)
		_box(root, Vector3(dims2.x * 0.7, 0.2, dims2.z * 0.75), Vector3(0, 0.05, 0), hov, "Hover")
		var lamp2 := OmniLight3D.new()
		lamp2.light_color = Data.CITY_TRIM
		lamp2.light_energy = 0.8
		lamp2.omni_range = dims2.x * 1.6
		lamp2.position = Vector3(0, -0.6, 0)
		lamp2.shadow_enabled = false
		root.add_child(lamp2)
		root.set_meta("kind", kind)
		root.set_meta("model", mid)
		return root
	var dims: Vector3 = Data.TRAFFIC_SIZE[kind]   # width, height, length
	var w := dims.x
	var hgt := dims.y
	var ln := dims.z
	var pal: Array = Data.TRAFFIC_COLORS
	var col: Color = pal[(i * 7 + hash(kind)) % pal.size()]
	var body := _mat("body%d" % ((i * 7 + hash(kind)) % pal.size()), col)
	var glass := _mat("glass", Color(0.08, 0.14, 0.2), 0.0, true)
	var hover := _mat("hover", Data.CITY_TRIM, 2.2)
	var head := _mat("head", Color(1.0, 0.97, 0.85), 2.5)
	var tail := _mat("tail", Color(1.0, 0.12, 0.1), 2.0)
	match kind:
		"bus":
			_box(root, Vector3(w, hgt * 0.62, ln), Vector3(0, hgt * 0.31, 0), body)
			_box(root, Vector3(w * 0.96, hgt * 0.32, ln * 0.94), Vector3(0, hgt * 0.78, 0), glass)
			_box(root, Vector3(w * 0.9, hgt * 0.06, ln * 0.9), Vector3(0, hgt * 0.97, 0), body)
		"truck":
			_box(root, Vector3(w, hgt * 0.5, ln * 0.3), Vector3(0, hgt * 0.25, -ln * 0.35), body)
			_box(root, Vector3(w * 0.94, hgt * 0.3, ln * 0.22), Vector3(0, hgt * 0.62, -ln * 0.37), glass)
			_box(root, Vector3(w * 1.02, hgt, ln * 0.66), Vector3(0, hgt * 0.5, ln * 0.17), _mat("cargo%d" % (i % 3), [Color(0.75, 0.76, 0.78), Color(0.55, 0.42, 0.25), Color(0.3, 0.33, 0.36)][i % 3]))
		_:   # car: a low wedge of slabs
			_box(root, Vector3(w, hgt * 0.45, ln), Vector3(0, hgt * 0.225, 0), body)
			_box(root, Vector3(w * 0.86, hgt * 0.4, ln * 0.5), Vector3(0, hgt * 0.65, ln * 0.06), glass)
			_box(root, Vector3(w * 0.9, hgt * 0.08, ln * 0.18), Vector3(0, hgt * 0.5, -ln * 0.4), body)   # (a hood fin)
	_box(root, Vector3(w * 0.8, 0.25, ln * 0.85), Vector3(0, -0.15, 0), hover, "Hover")
	for sx in [-1.0, 1.0]:
		_box(root, Vector3(w * 0.18, hgt * 0.08, 0.2), Vector3(sx * w * 0.32, hgt * 0.3, -ln * 0.5 - 0.1), head)
		_box(root, Vector3(w * 0.2, hgt * 0.08, 0.2), Vector3(sx * w * 0.32, hgt * 0.3, ln * 0.5 + 0.1), tail)
	var lamp := OmniLight3D.new()   # (the hover glow on the street under it)
	lamp.light_color = Data.CITY_TRIM
	lamp.light_energy = 0.8
	lamp.omni_range = w * 1.6
	lamp.position = Vector3(0, -0.6, 0)
	lamp.shadow_enabled = false
	root.add_child(lamp)
	root.set_meta("kind", kind)
	return root

## "go", "amber" or "stop" for the traffic running along x (along_x) or along z.
func light(along_x: bool) -> String:
	var G: float = Data.TRAFFIC_LIGHT_GREEN
	var A: float = Data.TRAFFIC_LIGHT_AMBER
	var ph := fposmod(light_t, (G + A) * 2.0)
	if not along_x: ph = fposmod(ph + G + A, (G + A) * 2.0)
	return "go" if ph < G else ("amber" if ph < G + A else "stop")

func _build_lights() -> void:
	if _ave_x.is_empty(): return
	_lamp_x = StandardMaterial3D.new()
	_lamp_z = StandardMaterial3D.new()
	for m in [_lamp_x, _lamp_z]:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var frame := _mat("tl_frame", Color(0.1, 0.12, 0.16))
	var trim := _mat("tl_trim", Data.CITY_TRIM, 1.5)
	# v13.328 (owner: "New Terra black screen ... WebGL context lost"): the lights were ~23 nodes each (1,500 meshes,
	# 1 M triangles on a big city) and phones ran out of GPU memory. Now every part goes into one merged mesh per
	# material (4 meshes for all the lights), with low-segment shapes. Same look; the lamps still change colour.
	var cyl := func(r_top: float, r_bot: float, h: float, segs: int) -> CylinderMesh:
		var c := CylinderMesh.new()
		c.top_radius = r_top
		c.bottom_radius = r_bot
		c.height = h
		c.radial_segments = segs
		c.rings = 1
		return c
	var pole: CylinderMesh = cyl.call(0.35, 0.45, Data.TRAFFIC_LIGHT_H, 8)
	var disc: CylinderMesh = cyl.call(1.6, 1.6, 0.4, 16)   # the head: a round dark frame ...
	var dot: CylinderMesh = cyl.call(0.28, 0.28, 0.5, 8)   # ... a ring of round lamps ...
	var bar_z := BoxMesh.new()       # ... and a glowing bar under it (laid along its face: one for each way the head turns)
	bar_z.size = Vector3(2.4, 0.5, 0.4)
	var bar_x := BoxMesh.new()
	bar_x.size = Vector3(0.4, 0.5, 2.4)
	var st := {}
	for k in ["frame", "trim", "x", "z"]:
		var t := SurfaceTool.new()
		t.begin(Mesh.PRIMITIVE_TRIANGLES)
		st[k] = t
	for ax in _ave_x:
		for az in _ave_z:
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					var post := Node3D.new()
					post.name = "TrafficLight"
					post.position = Vector3(float(ax[0]) + sx * (float(ax[1]) + 3.0), _g, float(az[0]) + sz * (float(az[1]) + 3.0))
					add_child(post)
					lights.append(post)
					var pxf := Transform3D(Basis.IDENTITY, post.position)
					(st["frame"] as SurfaceTool).append_from(pole, 0, pxf * Transform3D(Basis.IDENTITY, Vector3(0, Data.TRAFFIC_LIGHT_H * 0.5, 0)))
					for face_x in [true, false]:   # one head for each way through the crossing
						var hp := Vector3(0, Data.TRAFFIC_LIGHT_H - 1.0, 0) + (Vector3(-sx * 1.2, 0, 0) if face_x else Vector3(0, 0, -sz * 1.2))
						var hb := Basis.from_euler(Vector3(PI * 0.5, 0.0, 0.0) if not face_x else Vector3(0.0, 0.0, PI * 0.5))   # its face toward the traffic
						var hxf := pxf * Transform3D(hb, hp)
						var lk := "x" if face_x else "z"
						(st["frame"] as SurfaceTool).append_from(disc, 0, hxf)
						for k in 8:
							var a := TAU * k / 8.0
							(st[lk] as SurfaceTool).append_from(dot, 0, hxf * Transform3D(Basis.IDENTITY, Vector3(cos(a) * 1.05, 0.0, sin(a) * 1.05)))
						(st["trim"] as SurfaceTool).append_from(dot, 0, hxf)
						(st[lk] as SurfaceTool).append_from(bar_x if face_x else bar_z, 0, hxf * Transform3D(Basis.IDENTITY, Vector3(-2.2, 0.0, 0.0) if face_x else Vector3(0.0, 0.0, 2.2)))
	for pr in [["frame", frame], ["trim", trim], ["x", _lamp_x], ["z", _lamp_z]]:
		var mi := MeshInstance3D.new()
		mi.name = "Lights_" + str(pr[0])
		mi.mesh = (st[pr[0]] as SurfaceTool).commit()
		mi.material_override = pr[1]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	_show_lights()

func _show_lights() -> void:
	if _lamp_x == null: return
	for pr in [[_lamp_x, light(true)], [_lamp_z, light(false)]]:
		(pr[0] as StandardMaterial3D).albedo_color = {"go": Color(0.25, 1.0, 0.45), "amber": Color(1.0, 0.75, 0.2), "stop": Color(1.0, 0.2, 0.2)}[pr[1]] * 1.6

## Where along its lane a street car must stop before the next avenue crossing (INF: none ahead).
func _next_stop(p: Dictionary) -> float:
	var a: Vector2 = p["from"]
	var b: Vector2 = p["to"]
	var d := (b - a).normalized()
	var along_x := absf(d.x) > absf(d.y)
	var best := INF
	for ln in (_ave_x if along_x else _ave_z):
		var c: float = float(ln[0])
		var hw: float = float(ln[1])
		var edge := c - signf(d.x if along_x else d.y) * (hw + Data.TRAFFIC_STOP_GAP)   # the stop line before the crossing
		var t := (edge - (a.x if along_x else a.y)) * signf(d.x if along_x else d.y)
		if t >= float(p["t"]) - 0.5 and t < best: best = t
	return best

func tick(dt: float) -> void:
	if _lanes.is_empty(): return
	light_t += dt
	_show_lights()
	var pp: Vector3 = space.player.global_position
	var near := _near_city(pp)
	for p in pool:
		if p["state"] == "off": continue
		var nd: Node3D = p["node"]
		if not near or Vector2(nd.position.x - pp.x, nd.position.z - pp.z).length() > Data.TRAFFIC_RANGE + 120.0:
			_off(p)
			continue
		if bool(p.get("parked", false)): continue
		var step := float(p["speed"]) * dt
		if float(p.get("up", 0.0)) <= 0.0:   # v13.324: on the street: the lights, and the car in front
			var limit := INF
			var ts := _next_stop(p)
			var d0 := ((p["to"] as Vector2) - (p["from"] as Vector2)).normalized()
			if ts < INF and light(absf(d0.x) > absf(d0.y)) != "go" and ts - float(p["t"]) < Data.TRAFFIC_LIGHT_SEE:
				limit = ts
			var me: Vector3 = space.player.global_position   # v13.325: and for you, standing in its lane
			var a0: Vector2 = p["from"]
			var rel := Vector2(me.x, me.z) - a0
			var t_me := rel.dot(d0)
			var side := absf(rel.x * d0.y - rel.y * d0.x)
			if side < Data.TRAFFIC_LANE_W * 0.5 + 2.0 and t_me > float(p["t"]) and t_me - float(p["t"]) < Data.TRAFFIC_LIGHT_SEE and me.y < _g + 12.0:
				limit = minf(limit, t_me - Data.TRAFFIC_YIELD)
			for q in pool:   # keep a gap to the car ahead on the same lane
				if q == p or q["state"] == "off" or q.get("lane", -1) != p.get("lane", -2): continue
				var dt2 := float(q["t"]) - float(p["t"])
				if dt2 > 0.0 and dt2 < Data.TRAFFIC_LIGHT_SEE: limit = minf(limit, float(q["t"]) - Data.TRAFFIC_CAR_GAP)
			if float(p["t"]) + step > limit:
				if not bool(p.get("held", false)) and limit == ts: stops += 1
				p["held"] = true
				step = maxf(0.0, limit - float(p["t"]))
			else: p["held"] = false
		p["t"] = float(p["t"]) + step
		if float(p["t"]) >= float(p["len"]):
			_off(p)
			continue
		_place(p, dt)
	if not near: return
	_spawn_t -= dt
	if _spawn_t > 0.0: return
	_spawn_t = Data.TRAFFIC_SPAWN_EVERY
	for p in pool:
		if p["state"] == "off":
			_spawn(p, pp)
			break

func _near_city(pp: Vector3) -> bool:
	if pp.y > _g + Data.TRAFFIC_ALT: return false
	var cr := CityPlan.rect(planet_id, tile)
	var org := Vector2(-Surface.EDGE, -Surface.EDGE) + Vector2(cr.position) * Data.BLOCK_REGION
	var rr := Rect2(org, Vector2(cr.size) * Data.BLOCK_REGION).grow(Data.TRAFFIC_RANGE * 0.5)
	return rr.has_point(Vector2(pp.x, pp.z))

func _off(p: Dictionary) -> void:
	p["state"] = "off"
	p["parked"] = false
	(p["node"] as Node3D).visible = false

## On a lane that passes near you, at a point within range (most start a little behind you or ahead, never on top).
func _spawn(p: Dictionary, pp: Vector3) -> void:
	var me := Vector2(pp.x, pp.z)
	var order: Array = range(_lanes.size())
	order.shuffle()
	for li in order:
		var a: Vector2 = _lanes[li][0]
		var b: Vector2 = _lanes[li][1]
		var ab := b - a
		var L := ab.length()
		var t_me := clampf((me - a).dot(ab / L), 0.0, L)
		var closest := a + ab / L * t_me
		if closest.distance_to(me) > Data.TRAFFIC_RANGE * 0.8: continue
		var t0 := t_me + _rng.randf_range(-Data.TRAFFIC_RANGE * 0.8, Data.TRAFFIC_RANGE * 0.6)
		if absf(t0 - t_me) < 40.0 and closest.distance_to(me) < 15.0: t0 = t_me - 120.0   # (never pops up right on you)
		t0 = clampf(t0, 0.0, L - 1.0)
		var busy := false
		for q in pool:   # keep a gap to anything already on this lane
			if q["state"] != "off" and q.get("lane", -1) == li and absf(float(q["t"]) - t0) < 40.0: busy = true
		if busy: continue
		var kind: String = p["kind"]
		var spd: Vector2 = Data.TRAFFIC_SPEED[kind]
		p["lane"] = li
		p["up"] = float(_lanes[li][2]) if (_lanes[li] as Array).size() > 2 else 0.0
		p["from"] = a
		p["to"] = b
		p["len"] = L
		p["t"] = t0
		p["speed"] = _rng.randf_range(spd.x, spd.y)
		p["state"] = "drive"
		p["parked"] = false
		var nd: Node3D = p["node"]
		nd.visible = true
		nd.rotation.y = atan2(-ab.x, -ab.y)
		_place(p, 0.0)
		made += 1
		return

func _place(p: Dictionary, _dt: float) -> void:
	var nd: Node3D = p["node"]
	var a: Vector2 = p["from"]
	var b: Vector2 = p["to"]
	var at := a.lerp(b, float(p["t"]) / float(p["len"]))
	var bob := sin(Time.get_ticks_msec() * 0.002 + float(p["phase"])) * 0.25
	nd.position = Vector3(at.x, _g + (float(p.get("up", 0.0)) if float(p.get("up", 0.0)) > 0.0 else Data.TRAFFIC_HOVER) + bob, at.y)

## v13.283 (owner: "stealing cars"): take a vehicle out of the traffic (or off the kerb where someone left it): it
## is yours now (the caller hangs it on the player). A fresh one takes its place in the pool.
var parked: Array = []    # vehicles left on the street by you: [Node3D]
var _fresh := 1000
func take(q: Dictionary) -> Node3D:
	var nd: Node3D = q["node"]
	if bool(q.get("kerb", false)):
		parked.erase(nd)
		return nd
	for p in pool:
		if p["node"] == nd:
			var nn := _vehicle(str(p["kind"]), _fresh)
			_fresh += 1
			nn.visible = false
			add_child(nn)
			p["node"] = nn
			p["state"] = "off"
			p["parked"] = false
			break
	return nd

## v13.285: a vehicle of a kind (out of the garage).
func make_vehicle(kind: String, model := "") -> Node3D:
	_fresh += 1
	return _vehicle(kind, _fresh, model)

## A vehicle you got out of: it stays where you left it, hovering, and you can take it again.
func leave(nd: Node3D) -> void:
	if nd.get_parent() != null: nd.get_parent().remove_child(nd)
	add_child(nd)
	parked.append(nd)
	while parked.size() > Data.TRAFFIC_PARKED_MAX:
		var old: Node3D = parked.pop_front()
		if is_instance_valid(old): old.queue_free()

func active() -> int:
	return pool.filter(func(p): return p["state"] != "off").size()

## The vehicle nearest a point (within reach), for getting in: its pool entry, or {}.
func nearest(p: Vector3, reach: float) -> Dictionary:
	var best: Dictionary = {}
	var bd := reach
	for q in pool:
		if q["state"] == "off": continue
		var d := (q["node"] as Node3D).global_position.distance_to(p)
		if d < bd:
			bd = d
			best = q
	for nd in parked:
		if not is_instance_valid(nd): continue
		var d2 := (nd as Node3D).global_position.distance_to(p)
		if d2 < bd:
			bd = d2
			best = {"node": nd, "kind": str(nd.get_meta("kind", "car")), "kerb": true}
	return best
