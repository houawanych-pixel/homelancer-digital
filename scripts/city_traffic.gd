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
var _lanes: Array = []    # [from (tile-local x, z), to] one way each
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

func tick(dt: float) -> void:
	if _lanes.is_empty(): return
	var pp: Vector3 = space.player.global_position
	var near := _near_city(pp)
	for p in pool:
		if p["state"] == "off": continue
		var nd: Node3D = p["node"]
		if not near or Vector2(nd.position.x - pp.x, nd.position.z - pp.z).length() > Data.TRAFFIC_RANGE + 120.0:
			_off(p)
			continue
		if bool(p.get("parked", false)): continue
		p["t"] = float(p["t"]) + float(p["speed"]) * dt
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
	nd.position = Vector3(at.x, _g + Data.TRAFFIC_HOVER + bob, at.y)

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
