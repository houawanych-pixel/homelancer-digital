class_name Wildlife
extends Node3D
## v12.28 (owner: "how do the animals work? ... the sheep or the deer", alien versions): wildlife on a planet's grass.
## Like Minecraft's animals they are not blocks: small shaped models with a simple brain (wander, graze, bolt from the
## mech), that appear on grass round the player and go when you are far away, so they cost little. Three kinds:
##   strider - a six-legged deer with branching antlers: grazes in small herds, bolts fast when you come near
##   grazer  - a fluffy round grazer with glowing spots and long drooping feelers: drifts slowly, only shuffles off
##   hopper  - a small long-eared hopper that lives in the flowers: hops about, scatters when you come near
## The bodies are lofted from rings (curved, tapered shapes), legs on hip pivots swing as they walk.

var space: Node   # the SpaceSystem (for the ground height and the player)
var animals: Array = []   # [{kind, node, legs: [Node3D], head: Node3D, vel, target, state, t, phase, home}]
var _spawn_t := 0.0
var _rng := RandomNumberGenerator.new()
var fled := 0   # (tests)

func _ready() -> void:
	name = "Wildlife"
	_rng.randomize()

## Every frame on the surface: spawn near the player on grass, run the brains, drop the far ones.
func tick(dt: float, player_pos: Vector3, kind_of_ground: String) -> void:
	var cfg: Dictionary = Data.WILDLIFE_BIOMES.get(kind_of_ground, {})
	_spawn_t -= dt
	if _spawn_t <= 0.0:
		_spawn_t = 0.7
		for i in range(animals.size() - 1, -1, -1):   # gone when far away
			var a: Dictionary = animals[i]
			var ap: Vector3 = (a["node"] as Node3D).global_position if is_instance_valid(a["node"]) else Vector3.INF
			if ap == Vector3.INF or Vector2(ap.x - player_pos.x, ap.z - player_pos.z).length() > Data.WILDLIFE_DESPAWN:   # (across the ground: flying high doesn't clear them)
				if is_instance_valid(a["node"]): (a["node"] as Node).queue_free()
				animals.remove_at(i)
		if not cfg.is_empty() and animals.size() < int(cfg.get("max", 0)):
			_spawn_group(player_pos, cfg)
	for a in animals: _think(a, dt, player_pos)

func _spawn_group(pp: Vector3, cfg: Dictionary) -> void:
	var kinds: Dictionary = cfg["kinds"]
	var roll := _rng.randf()
	var kind := ""
	for k in kinds:
		roll -= float(kinds[k])
		if roll <= 0.0:
			kind = k
			break
	if kind == "": return
	var spec: Dictionary = Data.WILDLIFE[kind]
	# somewhere on grass between the near and far rings round the player, not in front of the mech's nose
	for tries in 20:
		var ang := _rng.randf() * TAU
		var d := _rng.randf_range(Data.WILDLIFE_SPAWN[0], Data.WILDLIFE_SPAWN[1])
		var c := pp + Vector3(cos(ang), 0, sin(ang)) * d
		var f: BlockField = space._block_field_at(c.x, c.z)
		if f == null or not f.grass_at(c.x, c.z, kind == "hopper"): continue
		var herd := _rng.randi_range(int(spec["herd"][0]), int(spec["herd"][1]))
		for i in herd:
			var p := c + Vector3(_rng.randf_range(-12, 12), 0, _rng.randf_range(-12, 12))
			_add(kind, p)
		return

func _add(kind: String, p: Vector3) -> void:
	var spec: Dictionary = Data.WILDLIFE[kind]
	var root := Node3D.new()
	root.name = "Animal_" + kind
	add_child(root)
	var parts := _build(kind, root)
	var s: float = float(spec["size"]) * _rng.randf_range(0.85, 1.15)
	root.scale = Vector3.ONE * s
	p.y = space._ground(p.x, p.z)
	root.global_position = p
	root.rotation.y = _rng.randf() * TAU
	if Data.WILDLIFE_SHADOWLESS: for mi in root.find_children("*", "MeshInstance3D", true, false): (mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	animals.append({"kind": kind, "node": root, "legs": parts["legs"], "head": parts["head"], "vel": Vector3.ZERO, "target": p, "state": "graze",
		"t": _rng.randf_range(1.0, 4.0), "phase": _rng.randf() * TAU, "hop": 0.0, "spec": spec})

## The brain: graze (head down, now and then a step), wander to a spot near by, flee from the player.
func _think(a: Dictionary, dt: float, pp: Vector3) -> void:
	var node: Node3D = a["node"]
	if not is_instance_valid(node): return
	var spec: Dictionary = a["spec"]
	var pos := node.global_position
	var away := Vector3(pos.x - pp.x, 0, pos.z - pp.z)
	var dist := away.length()
	a["t"] = float(a["t"]) - dt
	if dist < float(spec["flee"]) and a["state"] != "flee":
		a["state"] = "flee"
		a["t"] = _rng.randf_range(2.5, 4.0)
		fled += 1
	var speed := 0.0
	var dir := Vector3.ZERO
	match a["state"]:
		"graze":
			if float(a["t"]) <= 0.0:
				a["state"] = "wander"
				a["t"] = _rng.randf_range(2.0, 5.0)
				a["target"] = pos + Vector3(_rng.randf_range(-30, 30), 0, _rng.randf_range(-30, 30))
		"wander":
			var to: Vector3 = (a["target"] as Vector3) - pos
			to.y = 0.0
			if to.length() < 3.0 or float(a["t"]) <= 0.0:
				a["state"] = "graze"
				a["t"] = _rng.randf_range(2.0, 6.0)
			else:
				dir = to.normalized()
				speed = float(spec["walk"])
		"flee":
			dir = away.normalized() if dist > 0.1 else Vector3.FORWARD
			speed = float(spec["run"])
			if float(a["t"]) <= 0.0 and dist > float(spec["flee"]) * 1.4:
				a["state"] = "graze"
				a["t"] = _rng.randf_range(1.0, 3.0)
	var v: Vector3 = a["vel"]
	v = v.lerp(dir * speed, minf(1.0, dt * 3.0))
	a["vel"] = v
	var np := pos + v * dt
	var gy: float = space._ground(np.x, np.z)
	if gy > pos.y + 6.0:   # a wall: turn back
		a["vel"] = -v * 0.5
		a["target"] = pos - v
		np = pos
		gy = pos.y
	# hoppers bound along; the rest keep to the ground
	var hopping: bool = a["kind"] == "hopper" and v.length() > 0.5
	if hopping:
		a["hop"] = fmod(float(a["hop"]) + dt * 3.2, 1.0)
		gy += sin(float(a["hop"]) * PI) * float(spec["size"]) * 1.6
	np.y = lerpf(pos.y, gy, minf(1.0, dt * 10.0)) if not hopping else gy
	node.global_position = np
	if v.length() > 0.3:
		var want := atan2(v.x, v.z)   # (the models face +z)
		node.rotation.y = lerp_angle(node.rotation.y, want, minf(1.0, dt * 6.0))
	# the legs swing with the speed; the head dips to graze
	a["phase"] = float(a["phase"]) + dt * (2.0 + v.length() * 0.9)
	var swing := clampf(v.length() / maxf(1.0, float(spec["run"])), 0.0, 1.0) * 0.9 + 0.05
	var legs: Array = a["legs"]
	for i in legs.size():
		var lg: Node3D = legs[i]
		var off := PI * float(i % 2) + (PI * 0.66 * float(i / 2) if legs.size() == 6 else 0.0)   # (six legs: a tripod gait)
		lg.rotation.x = sin(float(a["phase"]) * 2.0 + off) * swing
	var head: Node3D = a["head"]
	if head != null:
		var dip := 0.5 if a["state"] == "graze" else 0.0
		head.rotation.x = lerpf(head.rotation.x, dip + sin(float(a["phase"]) * 0.7) * 0.08, minf(1.0, dt * 3.0))

# ---------------------------------------------------------------- the models (custom shapes, not boxes)
## A smooth body lofted along z through rings [z, y, rx, ry, colour]; closed at both ends.
static func _loft(rings: Array, seg := 10) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array = []
	for r in rings:
		var ring: Array = []
		for i in seg:
			var a := TAU * i / seg
			ring.append(Vector3(cos(a) * float(r[2]), float(r[1]) + sin(a) * float(r[3]), float(r[0])))
		pts.append(ring)
	for j in rings.size() - 1:
		var ca: Color = rings[j][4]
		var cb: Color = rings[j + 1][4]
		for i in seg:
			var a0: Vector3 = pts[j][i]
			var a1: Vector3 = pts[j][(i + 1) % seg]
			var b0: Vector3 = pts[j + 1][i]
			var b1: Vector3 = pts[j + 1][(i + 1) % seg]
			for v in [[a0, ca], [b0, cb], [b1, cb], [a0, ca], [b1, cb], [a1, ca]]:
				st.set_color(v[1])
				st.add_vertex(v[0])
	for e in [0, rings.size() - 1]:   # caps
		var cc := Vector3(0, float(rings[e][1]), float(rings[e][0]))
		for i in seg:
			var p0: Vector3 = pts[e][i]
			var p1: Vector3 = pts[e][(i + 1) % seg]
			for v in ([cc, p1, p0] if e == 0 else [cc, p0, p1]):
				st.set_color(rings[e][4])
				st.add_vertex(v)
	st.generate_normals()
	return st.commit()

## A tapered limb hanging down from its pivot (length, width at the top, at the bottom), with a joint bend.
static func _limb(length: float, w0: float, w1: float, col: Color, bend := 0.15) -> ArrayMesh:
	return _loft([[0.0, 0.0, w0, w0, col], [bend * length, -length * 0.5, (w0 + w1) * 0.55, (w0 + w1) * 0.55, col], [0.0, -length, w1, w1, col.darkened(0.3)]], 6)

static var _mat_cache := {}
static func _mat(glow := false) -> StandardMaterial3D:
	var key := "g" if glow else "n"
	if _mat_cache.has(key): return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.85
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if glow:
		m.emission_enabled = true
		m.emission = Color(0.3, 1.0, 0.9)
		m.emission_energy_multiplier = 1.4
	_mat_cache[key] = m
	return m

func _piece(parent: Node3D, mesh: ArrayMesh, at: Vector3, glow := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(glow)
	mi.position = at
	parent.add_child(mi)
	return mi

## Each model is about 1 unit long / tall before the animal's own size scales it.
func _build(kind: String, root: Node3D) -> Dictionary:
	var legs: Array = []
	var head := Node3D.new()
	match kind:
		"strider":   # the six-legged deer: a long lean body, a raised neck, a slim head with branching antlers
			var hide := Color(0.62, 0.45, 0.3)
			var belly := Color(0.85, 0.78, 0.62)
			var stripe := Color(0.25, 0.55, 0.6)
			_piece(root, _loft([[-0.55, 0.62, 0.05, 0.05, hide], [-0.45, 0.66, 0.13, 0.15, stripe], [-0.1, 0.68, 0.17, 0.18, hide], [0.2, 0.7, 0.16, 0.17, stripe], [0.45, 0.74, 0.12, 0.14, hide], [0.5, 0.78, 0.06, 0.06, belly]]), Vector3.ZERO)
			head.position = Vector3(0, 0.78, 0.48)
			root.add_child(head)
			_piece(head, _loft([[0.0, 0.0, 0.07, 0.07, hide], [0.08, 0.2, 0.06, 0.06, hide], [0.14, 0.34, 0.05, 0.05, hide]], 8), Vector3.ZERO)   # the neck, up and forward
			_piece(head, _loft([[0.08, 0.36, 0.06, 0.07, hide], [0.2, 0.38, 0.06, 0.06, hide], [0.32, 0.35, 0.03, 0.035, belly]], 8), Vector3.ZERO)   # the head
			for sd in [-1.0, 1.0]:   # antlers: a stem forking in two, then two again
				var base := Vector3(0.035 * sd, 0.42, 0.12)
				var a1 := base + Vector3(0.06 * sd, 0.16, -0.04)
				for tip in [a1 + Vector3(0.08 * sd, 0.1, 0.03), a1 + Vector3(0.0, 0.14, -0.06), a1 + Vector3(0.1 * sd, 0.02, -0.08)]:
					_piece(head, _stick(a1, tip, 0.012, Color(0.9, 0.95, 1.0)), Vector3.ZERO, true)
				_piece(head, _stick(base, a1, 0.018, Color(0.85, 0.9, 0.95)), Vector3.ZERO)
			for i in 6:   # six slender legs, three a side
				var z := 0.38 - 0.36 * float(i / 2)
				var pv := Node3D.new()
				pv.position = Vector3(0.12 * (1.0 if i % 2 == 0 else -1.0), 0.62, z)
				root.add_child(pv)
				_piece(pv, _limb(0.62, 0.045, 0.02, hide, 0.12), Vector3.ZERO)
				legs.append(pv)
		"grazer":   # round and fluffy, glowing spots, long drooping feelers, four stubby legs
			var fur := Color(0.62, 0.7, 0.92)
			var fur2 := Color(0.78, 0.84, 1.0)
			var rings: Array = []
			for i in 9:   # a lumpy round body
				var t := float(i) / 8.0
				var r := sin(t * PI) * 0.46 * (1.0 + 0.08 * sin(t * 23.0)) + 0.02
				rings.append([-0.45 + t * 0.9, 0.5, r, r * 0.85, fur if i % 2 == 0 else fur2])
			_piece(root, _loft(rings, 12), Vector3.ZERO)
			for k in 7:   # glowing spots on its back
				var a := float(k) * 2.4
				var spot := _loft([[-0.04, 0.0, 0.0, 0.0, Color(0.4, 1.0, 0.9)], [0.0, 0.0, 0.05, 0.05, Color(0.4, 1.0, 0.9)], [0.04, 0.0, 0.0, 0.0, Color(0.4, 1.0, 0.9)]], 6)
				_piece(root, spot, Vector3(sin(a) * 0.28, 0.82 + 0.05 * cos(a * 1.3), -0.3 + 0.1 * k), true)
			head.position = Vector3(0, 0.6, 0.42)
			root.add_child(head)
			_piece(head, _loft([[0.0, 0.0, 0.14, 0.12, fur2], [0.12, -0.02, 0.12, 0.1, fur2], [0.2, -0.05, 0.05, 0.04, Color(0.3, 0.3, 0.45)]], 10), Vector3.ZERO)
			for sd in [-1.0, 1.0]:   # feelers, drooping, with glowing tips
				var p0 := Vector3(0.06 * sd, 0.1, 0.08)
				var p1 := p0 + Vector3(0.12 * sd, 0.16, 0.04)
				var p2 := p1 + Vector3(0.1 * sd, -0.06, 0.1)
				_piece(head, _stick(p0, p1, 0.015, fur), Vector3.ZERO)
				_piece(head, _stick(p1, p2, 0.012, Color(0.4, 1.0, 0.9)), Vector3.ZERO, true)
			for i in 4:
				var pv := Node3D.new()
				pv.position = Vector3(0.22 * (1.0 if i % 2 == 0 else -1.0), 0.22, 0.2 if i < 2 else -0.2)
				root.add_child(pv)
				_piece(pv, _limb(0.22, 0.07, 0.06, fur.darkened(0.2), 0.05), Vector3.ZERO)
				legs.append(pv)
		"hopper":   # small, a teardrop body, big hind legs, long ears
			var coat := Color(0.85, 0.55, 0.75)
			var pale := Color(1.0, 0.9, 0.95)
			_piece(root, _loft([[-0.32, 0.38, 0.06, 0.06, coat], [-0.2, 0.42, 0.2, 0.22, coat], [0.05, 0.46, 0.18, 0.2, pale], [0.22, 0.52, 0.1, 0.11, coat]], 10), Vector3.ZERO)
			head.position = Vector3(0, 0.56, 0.24)
			root.add_child(head)
			_piece(head, _loft([[-0.04, 0.0, 0.1, 0.1, coat], [0.08, 0.02, 0.09, 0.09, coat], [0.16, -0.01, 0.03, 0.03, pale]], 10), Vector3.ZERO)
			for sd in [-1.0, 1.0]:   # tall ears, tips glowing
				_piece(head, _loft([[0.0, 0.0, 0.03, 0.015, coat], [0.0, 0.2, 0.045, 0.015, coat], [-0.03, 0.42, 0.01, 0.01, Color(1.0, 0.5, 0.9)]], 6), Vector3(0.05 * sd, 0.06, 0.0)).rotation.z = -0.25 * sd
			for i in 4:
				var hind := i >= 2
				var pv := Node3D.new()
				pv.position = Vector3(0.1 * (1.0 if i % 2 == 0 else -1.0), 0.36 if hind else 0.34, -0.18 if hind else 0.16)
				root.add_child(pv)
				_piece(pv, _limb(0.34 if hind else 0.3, 0.08 if hind else 0.035, 0.03, coat.darkened(0.15), 0.3 if hind else 0.05), Vector3.ZERO)
				legs.append(pv)
	return {"legs": legs, "head": head}

## A thin tapered stick from a to b (antlers, feelers).
static func _stick(a: Vector3, b: Vector3, w: float, col: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var d := (b - a).normalized()
	var s1 := d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized()
	var s2 := d.cross(s1).normalized()
	for i in 5:
		var a0 := TAU * i / 5.0
		var a1 := TAU * (i + 1) / 5.0
		var o0 := (s1 * cos(a0) + s2 * sin(a0))
		var o1 := (s1 * cos(a1) + s2 * sin(a1))
		for v in [a + o0 * w, a + o1 * w, b + o1 * w * 0.3, a + o0 * w, b + o1 * w * 0.3, b + o0 * w * 0.3]:
			st.set_color(col)
			st.add_vertex(v)
	st.generate_normals()
	return st.commit()
