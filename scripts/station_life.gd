class_name StationLife
extends Node3D
## v12.48 (owner: "all the assets to get destroyed when you're in the station ... shoot a table in the middle and both
## pieces fall"; "the wall paint ... shoot the wall or blow up a wall and it shows a big cut-out, sheetrock";
## "regular people ducking for cover ... civilians or other faction characters"):
## inside a deck (station breakout, battleship, facility):
##  - PROPS: tables, crates, consoles. Each is one mesh; shot enough it swaps to a few ready-cut chunks that tumble
##    with simple physics (gravity, bounce on the deck, spin), settle, and fade out after a while. Props stop shots
##    (both ways: cover), and you can't walk through them.
##  - MARKS: bullet holes on walls and floor, a blown-out patch (broken drywall, the studs behind, scorch) where a
##    missile hits a wall, a glowing cut where the sword hits one. Flat pictures on the wall (cheap); the oldest go.
##  - PEOPLE (the station breakout): crew walking about. Shooting near them, the alert, or a blast and they run for
##    the nearest table / crate (the side away from you) and crouch there, hands over heads; hit, they go down.
##    In the quiet start, a scream brings the guards in that room on you.

const GRAV := 70.0              # m/s2 at the deck's (mech) scale
const CHUNK_LIFE := 9.0         # s a broken piece stays before it sinks away
const MAX_CHUNKS := 40
const MAX_MARKS := 60
const PROP_HP := {"table": 14.0, "crate": 22.0, "console": 16.0, "wall": 40.0, "door": 30.0, "ammo_case": 18.0}
## v12.68 (owner: "crates, walls, doors and the ammo case pre-cut into chunks along panel seams and line cuts; on a
## hit chunks break off or are sliced away"): these come apart a chunk at a time (the one nearest the hit); the
## sword slices off everything on the far side of its cut; the ammo case goes up when it breaks
const CHIP_KINDS := ["crate", "wall", "door", "ammo_case"]
const AMMO_BLAST := 46.0
const CIV_H := 12.5             # m: the crew at the pilot's (mech-sized) scale
const CIV_WALK := 16.0
const CIV_RUN := 42.0
const CIV_PER_ROOM := 2
const CIV_MAX := 14
const PANIC_R := 160.0          # m: a shot or hit this close sends people for cover

var sp: Node                    # the space scene
var props: Array = []           # {node, aabb, hp, kind, room, broken}
var chunks: Array = []          # {node, vel, spin, life, half}
var marks: Array = []
var civs: Array = []            # {node, pivot, inst, ap, skel, state, goal, t, room, cover, calm}
var broken := 0                 # (tests)
var ammo_blasts := 0            # (tests)
var downed := 0
var _rng := RandomNumberGenerator.new()
var _mat: StandardMaterial3D
var _glow: StandardMaterial3D
var _tex := {}
var _mark_mats := {}

func setup(space: Node, faction: String, civilians: bool, tint: Color) -> void:
	sp = space
	_rng.seed = hash(faction + str(Boarding.INFO.get("name", "")))
	_mats()
	var body := Color(0.62, 0.64, 0.68).lerp(tint, 0.18)
	_fill(body)
	if civilians: _add_people(faction)

## v12.68: just the materials (a test bench: props placed by hand, no deck)
func setup_bare(space: Node) -> void:
	sp = space
	_mats()

func _mats() -> void:
	_mat = StandardMaterial3D.new()
	_mat.vertex_color_use_as_albedo = true
	_mat.roughness = 0.75
	_mat.metallic = 0.2
	_glow = StandardMaterial3D.new()
	_glow.albedo_color = Color(0.3, 0.9, 1.0)
	_glow.emission_enabled = true
	_glow.emission = Color(0.3, 0.9, 1.0)
	_glow.emission_energy_multiplier = 1.6

func _fill(body: Color) -> void:
	for k in Boarding.ROOMS:
		var R: Dictionary = Boarding.ROOMS[k]
		if str(R.get("label", "")) == "CORRIDOR" or bool(R.get("hex", false)): continue
		var r: Array = R["r"]
		var area := (float(r[1]) - float(r[0])) * (float(r[3]) - float(r[2]))
		var n := clampi(int(area / 9000.0), 3, 8)
		if str(k) == "reactor" and Boarding.KIND != "hub": n = 0   # (a battleship's reactor hall stays clear)
		for i in n:
			var p := _free_spot(str(k), 40.0)
			if p == Vector3.INF: continue
			var kind: String = ["table", "table", "crate", "crate", "console", "wall", "door", "ammo_case"][_rng.randi() % 8]   # (v12.68: + walls, doors, ammo cases)
			_add_prop(kind, p, _rng.randf() * TAU, body, str(k))

# ---------------------------------------------------------------- props
## a spot in room k, `pad` m clear of the walls, of the doors' middle lines, the room's middle pillar, the start,
## the console and the other props
func _free_spot(k: String, pad: float) -> Vector3:
	var R: Dictionary = Boarding.ROOMS[k]
	var r: Array = R["r"]
	var poly := Boarding.outline(k)
	var c := Vector2((float(r[0]) + float(r[1])) * 0.5, (float(r[2]) + float(r[3])) * 0.5)
	var pillar := minf(float(r[1]) - float(r[0]), float(r[3]) - float(r[2])) * 0.5 * 0.28 + 18.0 if str(R.get("shape", "")) == "ring" else 0.0
	for tries in 14:
		var q := Vector2(_rng.randf_range(float(r[0]) + pad, float(r[1]) - pad), _rng.randf_range(float(r[2]) + pad, float(r[3]) - pad))
		if not poly.is_empty() and not Geometry2D.is_point_in_polygon(q, poly): continue
		if pillar > 0.0 and q.distance_to(c) < pillar: continue
		if absf(q.x - c.x) < 22.0 or absf(q.y - c.y) < 22.0: continue   # (keep the cross through the doors clear)
		if q.distance_to(Vector2(Boarding.START_AT.x, Boarding.START_AT.z)) < 45.0: continue
		var con: Vector3 = sp.board.get("console", Vector3.INF) if sp != null else Vector3.INF
		if con != Vector3.INF and q.distance_to(Vector2(con.x, con.z)) < 50.0: continue
		var ok := true
		for pr in props:
			var pc: Vector3 = (pr["aabb"] as AABB).get_center()
			if q.distance_to(Vector2(pc.x, pc.z)) < 28.0:
				ok = false
				break
		if ok: return Vector3(q.x, Boarding.floor_of(k, q.x, q.y), q.y)
	return Vector3.INF

## the parts of each prop: [centre, size, colour k (x the body colour; < 0 = the glowing screen), tilt (deg about x)],
## and how they split into chunks (lists of part indices)
static func shape(kind: String) -> Dictionary:
	match kind:
		"table":
			return {"parts": [[Vector3(-3.5, 5.2, 0), Vector3(7, 0.8, 7.5), 1.0, 0.0], [Vector3(3.5, 5.2, 0), Vector3(7, 0.8, 7.5), 1.0, 0.0],
				[Vector3(-6, 2.4, -3), Vector3(0.9, 4.8, 0.9), 0.55, 0.0], [Vector3(-6, 2.4, 3), Vector3(0.9, 4.8, 0.9), 0.55, 0.0],
				[Vector3(6, 2.4, -3), Vector3(0.9, 4.8, 0.9), 0.55, 0.0], [Vector3(6, 2.4, 3), Vector3(0.9, 4.8, 0.9), 0.55, 0.0],
				[Vector3(-3.5, 5.65, 0), Vector3(5.6, 0.12, 5.2), -1.0, 0.0]],
				"split": [[0, 2, 3, 6], [1, 4, 5]]}
		"crate":
			return {"parts": [[Vector3(-1.8, 3.5, -1.8), Vector3(3.6, 7, 3.6), 0.85, 0.0], [Vector3(1.8, 3.5, -1.8), Vector3(3.6, 7, 3.6), 0.75, 0.0],
				[Vector3(-1.8, 3.5, 1.8), Vector3(3.6, 7, 3.6), 0.75, 0.0], [Vector3(1.8, 3.5, 1.8), Vector3(3.6, 7, 3.6), 0.85, 0.0],
				[Vector3(0, 7.2, 0), Vector3(7.6, 0.6, 7.6), 0.45, 0.0], [Vector3(0, 3.5, 3.65), Vector3(7.4, 1.0, 0.3), -1.0, 0.0]],
				"split": [[0, 4], [1], [2, 5], [3]]}
		"wall":   # a free-standing wall: 3 x 2 panels with seams between, in a frame
			var wp: Array = []
			var spl: Array = []
			for r in 2:
				for c in 3:
					wp.append([Vector3((c - 1) * 4.8, 2.6 + r * 4.8, 0), Vector3(4.6, 4.6, 1.2), 0.9 if (r + c) % 2 == 0 else 0.8, 0.0])
					spl.append([wp.size() - 1])
			wp.append([Vector3(-7.4, 5.0, 0), Vector3(0.6, 10.0, 1.6), 0.5, 0.0])
			wp.append([Vector3(7.4, 5.0, 0), Vector3(0.6, 10.0, 1.6), 0.5, 0.0])
			spl.append([6, 7])
			return {"parts": wp, "split": spl}
		"door":   # a door in its frame: two leaves, two panels each, a lit strip (frame last)
			return {"parts": [[Vector3(-2.4, 2.6, 0), Vector3(4.6, 5.0, 0.8), 0.85, 0.0], [Vector3(-2.4, 7.7, 0), Vector3(4.6, 5.0, 0.8), 0.8, 0.0],
				[Vector3(2.4, 2.6, 0), Vector3(4.6, 5.0, 0.8), 0.85, 0.0], [Vector3(2.4, 7.7, 0), Vector3(4.6, 5.0, 0.8), 0.8, 0.0],
				[Vector3(0, 5.2, 0.45), Vector3(0.3, 10.0, 0.1), -1.0, 0.0],
				[Vector3(-5.2, 5.4, 0), Vector3(0.8, 10.8, 1.4), 0.45, 0.0], [Vector3(5.2, 5.4, 0), Vector3(0.8, 10.8, 1.4), 0.45, 0.0], [Vector3(0, 10.6, 0), Vector3(11.2, 0.8, 1.4), 0.45, 0.0]],
				"split": [[0], [1], [2, 4], [3], [5, 6, 7]]}
		"ammo_case":   # a long case: body, lid, two straps, the glowing warning panel
			return {"parts": [[Vector3(-2.2, 1.6, 0), Vector3(4.3, 3.2, 3.6), 0.55, 0.0], [Vector3(2.2, 1.6, 0), Vector3(4.3, 3.2, 3.6), 0.6, 0.0],
				[Vector3(0, 3.45, 0), Vector3(8.8, 0.5, 3.8), 0.4, 0.0], [Vector3(-2.2, 1.6, 1.85), Vector3(0.5, 3.0, 0.1), 0.3, 0.0], [Vector3(2.2, 1.6, 1.85), Vector3(0.5, 3.0, 0.1), 0.3, 0.0],
				[Vector3(0, 1.8, 1.86), Vector3(1.8, 1.0, 0.05), -1.0, 0.0]],
				"split": [[0, 3], [1, 4, 5], [2]], "explosive": true}
		_:   # console
			return {"parts": [[Vector3(0, 2.6, 0), Vector3(7, 5.2, 3.4), 0.6, 0.0], [Vector3(0, 6.0, 0.4), Vector3(7, 0.6, 3.8), 0.9, -28.0],
				[Vector3(0, 6.35, 0.45), Vector3(6.2, 0.1, 3.0), -1.0, -28.0]],
				"split": [[0], [1, 2]]}

## one mesh from a list of parts (body colour by vertex; the screen on a second, glowing surface), centred on `at`
func _mesh(kind: String, idx: Array, body: Color, at: Vector3) -> ArrayMesh:
	var sh := shape(kind)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var gl := SurfaceTool.new()
	gl.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any_glow := false
	for i in idx:
		var p: Array = sh["parts"][i]
		var k := float(p[2])
		var t := (st if k >= 0.0 else gl)
		if k < 0.0: any_glow = true
		var col := body * (k if k >= 0.0 else 1.0)
		col.a = 1.0
		_box(t, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(float(p[3]))), (p[0] as Vector3) - at), p[1], col)
	st.generate_normals()
	var m := st.commit()
	m.surface_set_material(0, _mat)
	if any_glow:
		gl.generate_normals()
		gl.commit(m)
		m.surface_set_material(1, _glow)
	return m

static func _box(st: SurfaceTool, xf: Transform3D, size: Vector3, col: Color) -> void:
	var h := size * 0.5
	var c := [Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z),
		Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]
	var faces := [[0, 3, 2, 1], [4, 5, 6, 7], [0, 4, 7, 3], [1, 2, 6, 5], [3, 7, 6, 2], [0, 1, 5, 4]]
	for f in faces:
		for tri in [[f[0], f[1], f[2]], [f[0], f[2], f[3]]]:
			for v in tri:
				st.set_color(col)
				st.add_vertex(xf * (c[v] as Vector3))

func _add_prop(kind: String, at: Vector3, yaw: float, body: Color, room: String) -> void:
	var sh := shape(kind)
	var all: Array = []
	for i in (sh["parts"] as Array).size(): all.append(i)
	var mi := MeshInstance3D.new()
	mi.name = "Prop_%s" % kind
	mi.mesh = _mesh(kind, all, body, Vector3.ZERO)
	add_child(mi)
	mi.global_position = at
	mi.rotation.y = yaw
	var bb := mi.global_transform * mi.mesh.get_aabb()
	var left: Array = []
	for g in (sh["split"] as Array).size(): left.append(g)
	props.append({"node": mi, "aabb": bb, "hp": float(PROP_HP[kind]), "kind": kind, "room": room, "broken": false, "body": body, "yaw": yaw, "at": at,
		"left": left, "chip_hp": float(PROP_HP[kind]) / maxf(1.0, float(left.size()))})

## the nearest intact prop along from -> to: [t 0..1, prop] (t = 1 when none)
func seg_prop(from: Vector3, to: Vector3) -> Array:
	var best := 1.0
	var bp = null
	var L := from.distance_to(to)
	if L < 0.001: return [1.0, null]
	for p in props:
		if p["broken"]: continue
		var bb: AABB = p["aabb"]
		var hp = bb.intersects_segment(from, to)
		if hp != null:
			var t := from.distance_to(hp) / L
			if t < best:
				best = t
				bp = p
	return [best, bp]

func damage_prop(p: Dictionary, dmg: float, at: Vector3, dir: Vector3) -> void:
	if p["broken"]: return
	p["hp"] = float(p["hp"]) - dmg
	sp._spark(at, Color(1, 0.85, 0.55), 2.5, 0.2)
	noise(at, PANIC_R * 0.7)
	if str(p["kind"]) in CHIP_KINDS and float(p["hp"]) > 0.0:   # v12.68: a chunk comes off for every share of damage
		while (p["left"] as Array).size() > 1 and float(p["hp"]) < float(p["chip_hp"]) * float((p["left"] as Array).size() - 1):
			chip_prop(p, at, dir)
		return
	if float(p["hp"]) <= 0.0: break_prop(p, dir)

## v12.68: the chunk nearest `at` breaks off (along its panel seam) and flies; the rest of the prop stays standing
var chipped := 0   # (tests)
func chip_prop(p: Dictionary, at: Vector3, dir: Vector3) -> void:
	var left: Array = p["left"]
	if left.size() <= 1:
		break_prop(p, dir)
		return
	var mi: MeshInstance3D = p["node"]
	var xf := mi.global_transform
	var sh := shape(str(p["kind"]))
	var best := -1
	var bd := INF
	for g in left:
		var c := _group_centre(sh, sh["split"][g])
		var d := (xf * c).distance_to(at)
		if d < bd:
			bd = d
			best = g
	left.erase(best)
	_fly_chunk(p, sh, sh["split"][best], xf, dir, 1.0)
	_rebuild(p, sh, xf)
	chipped += 1
	sp._spark(at, Color(1.0, 0.75, 0.35), 4.0, 0.3)
	Sfx.play("hull_hit", -12.0, 1.3)

## v12.68: the sword's cut: everything on the far side of the plane through `at` (normal `n`) is sliced away
func slice_prop(p: Dictionary, at: Vector3, n: Vector3) -> int:
	if p["broken"] or not (str(p["kind"]) in CHIP_KINDS): return 0
	var mi: MeshInstance3D = p["node"]
	var xf := mi.global_transform
	var sh := shape(str(p["kind"]))
	var cut: Array = []
	for g in p["left"]:
		if ((xf * _group_centre(sh, sh["split"][g])) - at).dot(n) > 0.0: cut.append(g)
	if cut.is_empty() or cut.size() == (p["left"] as Array).size():
		break_prop(p, n)
		return cut.size()
	for g in cut:
		(p["left"] as Array).erase(g)
		_fly_chunk(p, sh, sh["split"][g], xf, n, 1.4)
	_rebuild(p, sh, xf)
	chipped += cut.size()
	for k in 4: sp._spark(at + Vector3(randf_range(-3, 3), randf_range(0, 6), randf_range(-3, 3)), Color(1.0, 0.6, 0.25), 3.0, 0.35)
	return cut.size()

static func _group_centre(sh: Dictionary, grp: Array) -> Vector3:
	var c := Vector3.ZERO
	for i in grp: c += (sh["parts"][i][0] as Vector3)
	return c / maxf(1.0, float(grp.size()))

## what's left of a prop: its mesh from the chunks still on it, and a box that fits them (collision stays sane)
func _rebuild(p: Dictionary, sh: Dictionary, xf: Transform3D) -> void:
	var idx: Array = []
	for g in p["left"]: idx.append_array(sh["split"][g])
	var mi: MeshInstance3D = p["node"]
	mi.mesh = _mesh(str(p["kind"]), idx, p["body"], Vector3.ZERO)
	p["aabb"] = xf * mi.mesh.get_aabb()

func _fly_chunk(p: Dictionary, sh: Dictionary, grp: Array, xf: Transform3D, dir: Vector3, k: float) -> void:
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for i in grp:
		var pa: Array = sh["parts"][i]
		lo = lo.min((pa[0] as Vector3) - (pa[1] as Vector3) * 0.5)
		hi = hi.max((pa[0] as Vector3) + (pa[1] as Vector3) * 0.5)
	var c := (lo + hi) * 0.5
	var cm := MeshInstance3D.new()
	cm.name = "Chunk"
	cm.mesh = _mesh(str(p["kind"]), grp, p["body"], c)
	add_child(cm)
	cm.global_transform = Transform3D(xf.basis, xf * c)
	var push := dir.normalized()
	push.y = 0.0
	var v := push.normalized() * _rng.randf_range(14.0, 26.0) * k + Vector3(0, _rng.randf_range(10.0, 20.0), 0)
	chunks.append({"node": cm, "vel": v, "spin": Vector3(_rng.randf_range(-4, 4), _rng.randf_range(-3, 3), _rng.randf_range(-4, 4)), "life": CHUNK_LIFE, "half": (hi.y - lo.y) * 0.5, "rest": 0.0})
	while chunks.size() > MAX_CHUNKS:
		var old: Dictionary = chunks.pop_front()
		if is_instance_valid(old["node"]): (old["node"] as Node3D).queue_free()

## it breaks: the whole prop goes, its chunks fly off away from the hit and up, tumbling
func break_prop(p: Dictionary, dir: Vector3) -> void:
	if p["broken"]: return
	p["broken"] = true
	broken += 1
	var mi: MeshInstance3D = p["node"]
	var xf := mi.global_transform
	mi.queue_free()
	var sh := shape(str(p["kind"]))
	var gl: Array = p.get("left", [])
	for gi in (sh["split"] as Array).size():
		if not gl.is_empty() and not (gi in gl): continue   # (v12.68: the chunks already gone)
		var grp: Array = sh["split"][gi]
		var c := Vector3.ZERO
		var lo := Vector3(INF, INF, INF)
		var hi := -lo
		for i in grp:
			var pa: Array = sh["parts"][i]
			c += pa[0]
			lo = Vector3(minf(lo.x, (pa[0] as Vector3).x - (pa[1] as Vector3).x * 0.5), minf(lo.y, (pa[0] as Vector3).y - (pa[1] as Vector3).y * 0.5), minf(lo.z, (pa[0] as Vector3).z - (pa[1] as Vector3).z * 0.5))
			hi = Vector3(maxf(hi.x, (pa[0] as Vector3).x + (pa[1] as Vector3).x * 0.5), maxf(hi.y, (pa[0] as Vector3).y + (pa[1] as Vector3).y * 0.5), maxf(hi.z, (pa[0] as Vector3).z + (pa[1] as Vector3).z * 0.5))
		c = (lo + hi) * 0.5
		var cm := MeshInstance3D.new()
		cm.name = "Chunk"
		cm.mesh = _mesh(str(p["kind"]), grp, p["body"], c)
		add_child(cm)
		cm.global_transform = Transform3D(xf.basis, xf * c)
		var out := (xf * c - xf.origin)
		out.y = 0.0
		var push := (dir.normalized() * 0.6 + out.normalized() * 0.8) if out.length() > 0.1 else dir.normalized()
		push.y = 0.0
		var v := push.normalized() * _rng.randf_range(14.0, 26.0) + Vector3(0, _rng.randf_range(12.0, 24.0), 0)
		chunks.append({"node": cm, "vel": v, "spin": Vector3(_rng.randf_range(-4, 4), _rng.randf_range(-3, 3), _rng.randf_range(-4, 4)), "life": CHUNK_LIFE, "half": (hi.y - lo.y) * 0.5, "rest": 0.0})
	while chunks.size() > MAX_CHUNKS:
		var old: Dictionary = chunks.pop_front()
		if is_instance_valid(old["node"]): (old["node"] as Node3D).queue_free()
	Sfx.play("explosion", -14.0, 1.6)
	noise(xf.origin, PANIC_R * 1.5)
	if bool(sh.get("explosive", false)):   # v12.68: the ammo case goes up and takes what's near with it
		ammo_blasts += 1
		sp._explode(xf.origin + Vector3(0, 3, 0), 18.0)
		for k in 8: sp._spark(xf.origin + Vector3(_rng.randf_range(-6, 6), _rng.randf_range(1, 8), _rng.randf_range(-6, 6)), Color(1.0, 0.7, 0.3), 4.0, 0.5)
		call_deferred("explosion", xf.origin, AMMO_BLAST)
		if sp.player != null and sp.player.global_position.distance_to(xf.origin) < AMMO_BLAST: sp._player_hit(12.0, xf.origin)

func _update_chunks(dt: float) -> void:
	for c in chunks:
		var n: Node3D = c["node"]
		if not is_instance_valid(n): continue
		c["life"] = float(c["life"]) - dt
		if float(c["rest"]) < 0.6:
			c["vel"] = (c["vel"] as Vector3) + Vector3(0, -GRAV * dt, 0)
			n.global_position += (c["vel"] as Vector3) * dt
			var sv: Vector3 = c["spin"]
			if sv.length() > 0.01: n.rotate(sv.normalized(), sv.length() * dt)
			var fl := Boarding.floor_at(n.global_position)
			if n.global_position.y - float(c["half"]) < fl:   # on the deck: bounce, slide, settle
				n.global_position.y = fl + float(c["half"])
				var v: Vector3 = c["vel"]
				c["vel"] = Vector3(v.x * 0.55, absf(v.y) * 0.3, v.z * 0.55)
				c["spin"] = sv * 0.55
				if (c["vel"] as Vector3).length() < 4.0: c["rest"] = float(c["rest"]) + dt * 4.0
			var q := Boarding.keep_in(n.global_position, 4.0)   # (not out through a wall)
			if Vector2(q.x - n.global_position.x, q.z - n.global_position.z).length() > 0.5:
				n.global_position = Vector3(q.x, n.global_position.y, q.z)
				c["vel"] = Vector3(-(c["vel"] as Vector3).x * 0.3, (c["vel"] as Vector3).y, -(c["vel"] as Vector3).z * 0.3)
		if float(c["life"]) < 1.5: n.global_position.y -= dt * 3.0   # (sinks away at the end)
		if float(c["life"]) <= 0.0: n.queue_free()
	chunks = chunks.filter(func(c): return float(c["life"]) > 0.0 and is_instance_valid(c["node"]))

## keep a body (the player) out of the props: returns the pushed-out position
func push_out(p: Vector3, r: float) -> Vector3:
	for pr in props:
		if pr["broken"]: continue
		var bb: AABB = (pr["aabb"] as AABB).grow(r)
		if p.y > bb.end.y + 6.0: continue
		if p.x > bb.position.x and p.x < bb.end.x and p.z > bb.position.z and p.z < bb.end.z:
			var dx0 := p.x - bb.position.x
			var dx1 := bb.end.x - p.x
			var dz0 := p.z - bb.position.z
			var dz1 := bb.end.z - p.z
			var m := minf(minf(dx0, dx1), minf(dz0, dz1))
			if m == dx0: p.x = bb.position.x
			elif m == dx1: p.x = bb.end.x
			elif m == dz0: p.z = bb.position.z
			else: p.z = bb.end.z
	return p

## a blast: props near it break, people near it panic
func explosion(at: Vector3, radius: float) -> void:
	for p in props:
		if p["broken"]: continue
		var c: Vector3 = (p["aabb"] as AABB).get_center()
		var d := c.distance_to(at)
		if d < radius: break_prop(p, (c - at) if d > 0.5 else Vector3.RIGHT)
	noise(at, maxf(PANIC_R, radius * 2.0))

# ---------------------------------------------------------------- marks on the walls
## a mark on a wall / the deck at `at`, facing `normal`: "hole" (a shot), "blast" (a missile: broken drywall, the
## studs behind, scorch), "cut" (the sword: a glowing gash along `along`)
func mark(at: Vector3, normal: Vector3, kind: String, along := Vector3.ZERO) -> void:
	if normal.length() < 0.5: return
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	var sz := {"hole": Vector2(4.5, 4.5), "blast": Vector2(34, 30), "cut": Vector2(30, 3.2)}.get(kind, Vector2(4, 4)) as Vector2
	if kind == "hole": sz *= _rng.randf_range(0.8, 1.25)
	qm.size = sz
	q.mesh = qm
	q.material_override = _mark_mat(kind)
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	q.name = "Mark_%s" % kind
	add_child(q)
	var n := normal.normalized()
	var up := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.9 else Vector3.FORWARD
	q.global_transform = Transform3D(Basis.looking_at(-n, up), at + n * (0.12 + 0.01 * float(marks.size() % 8)))
	if kind == "cut" and along.length() > 0.1:
		var a := along - n * along.dot(n)
		if a.length() > 0.1: q.rotate(n, (q.global_basis.x).signed_angle_to(a.normalized(), n))
	else:
		q.rotate(n, _rng.randf() * TAU)
	marks.append(q)
	while marks.size() > MAX_MARKS:
		var old: Node3D = marks.pop_front()
		if is_instance_valid(old): old.queue_free()

func _mark_mat(kind: String) -> StandardMaterial3D:
	if _mark_mats.has(kind): return _mark_mats[kind]
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = _mark_tex(kind)
	m.roughness = 0.9
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if kind == "cut":
		m.emission_enabled = true
		m.emission_texture = m.albedo_texture
		m.emission = Color(1, 1, 1)
		m.emission_energy_multiplier = 1.2
	_mark_mats[kind] = m
	return m

## the pictures, drawn once in code
func _mark_tex(kind: String) -> ImageTexture:
	var S := 64 if kind == "hole" else 256
	var H := S if kind != "cut" else 32
	var img := Image.create(S, H, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	var bumps: Array = []   # the broken edge's lumps
	for i in 14: bumps.append([rng.randf() * TAU, rng.randf_range(0.03, 0.09), rng.randf_range(2.0, 7.0)])
	for y in H:
		for x in S:
			var u := (x + 0.5) / S - 0.5
			var v := (y + 0.5) / H - 0.5
			var col := Color(0, 0, 0, 0)
			match kind:
				"hole":
					var r := Vector2(u, v).length()
					var ang := atan2(v, u)
					var crack := absf(sin(ang * 5.0 + 1.3)) > 0.97 and r < 0.42
					if r < 0.13: col = Color(0.02, 0.02, 0.02, 1)
					elif r < 0.19: col = Color(0.3, 0.27, 0.24, 1)
					elif crack: col = Color(0.08, 0.08, 0.08, 0.85)
					elif r < 0.5: col = Color(0.05, 0.04, 0.03, (0.5 - r) / 0.31 * 0.75)
				"blast":
					var r2 := Vector2(u, v).length()
					var ang2 := atan2(v, u)
					var edge := 0.3
					for b in bumps: edge += float(b[1]) * sin(ang2 * float(b[2]) + float(b[0]))
					if r2 < edge:   # the cavity: studs, a cross-brace, a pipe, darkness
						var stud := fposmod(u * 4.0 + 0.5, 1.0) < 0.16
						var brace := absf(v - 0.06) < 0.025
						var pipe := absf(v + 0.12) < 0.018
						col = Color(0.05, 0.05, 0.06, 1)
						if stud: col = Color(0.45, 0.47, 0.5, 1).darkened(clampf((edge - r2) * 1.5, 0.0, 0.6))
						if brace: col = Color(0.36, 0.38, 0.4, 1)
						if pipe: col = Color(0.55, 0.32, 0.12, 1)
					elif r2 < edge + 0.035:   # the broken drywall lip
						col = Color(0.86, 0.84, 0.8, 1).darkened(rng.randf() * 0.25)
					elif r2 < 0.5:   # scorch
						col = Color(0.04, 0.03, 0.03, clampf((0.5 - r2) / (0.5 - edge) * 0.9, 0.0, 0.9))
				"cut":
					var d := absf(v) / 0.5
					var taper := clampf(1.0 - absf(u) * 2.0, 0.0, 1.0)
					var w := 0.35 * sqrt(taper)
					if d < w * 0.35: col = Color(1.0, 0.75, 0.35, 1)
					elif d < w: col = Color(0.08, 0.05, 0.04, 1)
					elif d < w + 0.25: col = Color(0.05, 0.04, 0.03, 0.5 * taper)
			img.set_pixel(x, y, col)
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_tex[kind] = t
	return t

# ---------------------------------------------------------------- people
func _add_people(faction: String) -> void:
	var paths: Array = []
	if faction.to_lower().begins_with("orion") and Packs.is_ready("crowd3d_orion"):
		for nm in ["HL_Orion_09_DragonWomanTechnician", "HL_Orion_12_FemaleMedic", "HL_Orion_13_MaleMedic", "HL_Orion_11_VioletMechTechnician", "HL_Orion_16_SilverPonytailOfficer", "HL_Orion_04_LavenderElfOfficer", "HL_Orion_17_VioletMissionSpecialist"]:
			paths.append("res://assets/crowd3d_orion/%s_Rigged.glb" % nm)
	if Packs.is_ready("crowd3d"):
		for nm in ["phenom_isara", "phenom_thalen", "phenom_vyrela", "phenom_xerathion"]: paths.append("res://assets/crowd3d/%s.glb" % nm)
	paths = paths.filter(func(p): return ResourceLoader.exists(p))
	if paths.is_empty(): return
	var cache := {}
	for k in Boarding.ROOMS:
		var R: Dictionary = Boarding.ROOMS[k]
		if str(R.get("label", "")) == "CORRIDOR" or bool(R.get("hex", false)) or str(k) in ["lbay", "sbay"]: continue
		for i in CIV_PER_ROOM:
			if civs.size() >= CIV_MAX: return
			var p := _free_spot(str(k), 30.0)
			if p == Vector3.INF: continue
			var path: String = paths[(civs.size() * 3 + i) % paths.size()]
			if not cache.has(path): cache[path] = load(path)
			_add_civ(cache[path], p, str(k))

func _add_civ(ps: PackedScene, at: Vector3, room: String) -> void:
	var node := Node3D.new()
	node.name = "Crew %d" % (civs.size() + 1)
	add_child(node)
	node.global_position = at
	var pivot := Node3D.new()   # (turned about the feet when they go down)
	node.add_child(pivot)
	var inst: Node3D = ps.instantiate()
	var bb := PilotRig._aabb(inst)
	var k := CIV_H * _rng.randf_range(0.92, 1.04) / maxf(0.01, bb.size.y)
	inst.scale = Vector3.ONE * k
	inst.position = Vector3(-bb.get_center().x * k, -bb.position.y * k, -bb.get_center().z * k)
	inst.rotation.y = PI / 2 if bb.size.z > bb.size.x * 1.3 else PI
	pivot.add_child(inst)
	var ap: AnimationPlayer = null
	for a in inst.find_children("*", "AnimationPlayer", true, false):
		ap = a
		for nm in ap.get_animation_list(): ap.get_animation(nm).loop_mode = Animation.LOOP_LINEAR
		break
	var skel: Skeleton3D = null
	for s in inst.find_children("*", "Skeleton3D", true, false):
		skel = s
		break
	var c := {"node": node, "pivot": pivot, "inst": inst, "ap": ap, "skel": skel, "state": "idle", "goal": at, "t": _rng.randf_range(0.5, 4.0),
		"room": room, "cover": null, "calm": 0.0, "drop": 0.0}
	civs.append(c)
	_clip(c, "Idle")

func _clip(c: Dictionary, nm: String, speed := 1.0) -> void:
	var ap: AnimationPlayer = c["ap"]
	if ap == null or not is_instance_valid(ap): return
	for a in ap.get_animation_list():
		if str(a).to_lower().ends_with(nm.to_lower()):
			if ap.current_animation != a or not ap.is_playing(): ap.play(a, 0.2)
			ap.speed_scale = speed
			return

## something loud at `at`: everyone near it (or in the room) runs for cover
func noise(at: Vector3, radius: float) -> void:
	for c in civs:
		if c["state"] == "down": continue
		if (c["node"] as Node3D).global_position.distance_to(at) < radius:
			c["calm"] = 0.0
			if c["state"] in ["idle", "walk"]: _panic(c)

## the nearest person a shot from -> to passes through: [t, civ] (t = 1 when none)
func seg_civ(from: Vector3, to: Vector3) -> Array:
	var L := from.distance_to(to)
	if L < 0.001: return [1.0, null]
	var best := 1.0
	var bc = null
	for c in civs:
		if c["state"] == "down": continue
		var n: Node3D = c["node"]
		var h := CIV_H * (0.45 if c["state"] == "cower" else 1.0)
		var a := n.global_position + Vector3(0, h * 0.25, 0)
		var b := n.global_position + Vector3(0, h * 0.85, 0)
		var pq := Geometry3D.get_closest_points_between_segments(from, to, a, b)
		if (pq[0] as Vector3).distance_to(pq[1]) < 2.6:
			var t := from.distance_to(pq[0]) / L
			if t < best:
				best = t
				bc = c
	return [best, bc]

func hit_civ(c: Dictionary) -> void:
	if c["state"] == "down": return
	c["state"] = "down"
	c["t"] = 0.0
	downed += 1
	var ap: AnimationPlayer = c["ap"]
	if ap != null and is_instance_valid(ap): ap.stop()
	noise((c["node"] as Node3D).global_position, PANIC_R * 1.5)
	if sp != null: sp.board_scream(str(c["room"]))

func _panic(c: Dictionary) -> void:
	var n: Node3D = c["node"]
	var threat: Vector3 = sp.player.global_position if sp != null and is_instance_valid(sp.player) else n.global_position + Vector3.FORWARD
	var best = null
	var bd := 240.0
	for p in props:
		if p["broken"] or str(p["room"]) != str(c["room"]): continue
		var pc: Vector3 = (p["aabb"] as AABB).get_center()
		var d := pc.distance_to(n.global_position)
		if d < bd:
			bd = d
			best = p
	_stand(c)
	if best != null:
		var bb: AABB = best["aabb"]
		var pc2 := bb.get_center()
		var away := pc2 - threat
		away.y = 0.0
		away = away.normalized() if away.length() > 0.1 else Vector3.RIGHT
		var g := pc2 + away * (maxf(bb.size.x, bb.size.z) * 0.5 + 6.0)
		c["goal"] = Vector3(g.x, Boarding.floor_at(g), g.z)
		c["cover"] = best
	else:   # nothing to hide behind: away from you, into a corner
		var away2 := n.global_position - threat
		away2.y = 0.0
		var g2 := Boarding.keep_in(n.global_position + away2.normalized() * 120.0, 20.0)
		c["goal"] = Vector3(g2.x, Boarding.floor_at(g2), g2.z)
		c["cover"] = null
	c["state"] = "run"

func _stand(c: Dictionary) -> void:
	var skel: Skeleton3D = c["skel"]
	if skel != null and is_instance_valid(skel): skel.reset_bone_poses()
	(c["inst"] as Node3D).position.y += float(c["drop"])
	c["drop"] = 0.0

## crouched behind cover, hands over the head (posed by bones: the models only have Walk / Idle)
func _cower(c: Dictionary) -> void:
	c["state"] = "cower"
	c["t"] = 0.0
	var ap: AnimationPlayer = c["ap"]
	if ap != null and is_instance_valid(ap): ap.stop()
	var skel: Skeleton3D = c["skel"]
	var body: Node3D = c["pivot"]
	if skel != null and is_instance_valid(skel):
		skel.reset_bone_poses()
		for sd in [["Left", -1.0], ["Right", 1.0]]:
			var s: String = sd[0]
			var x: float = sd[1]
			PilotRig.aim_bone(skel, body, s + "UpperLeg", s + "LowerLeg", Vector3(x * 0.15, -0.25, -1.0))
			PilotRig.aim_bone(skel, body, s + "LowerLeg", s + "Foot", Vector3(x * 0.05, -1.0, 0.45))
			PilotRig.aim_bone(skel, body, s + "UpperArm", s + "LowerArm", Vector3(x * 0.55, 0.55, -0.6))
			PilotRig.aim_bone(skel, body, s + "LowerArm", s + "Hand", Vector3(-x * 0.7, 0.55, 0.1))
		PilotRig.aim_bone(skel, body, "Spine", "Chest", Vector3(0, 0.75, -0.65))
	var drop := CIV_H * 0.36
	(c["inst"] as Node3D).position.y -= drop
	c["drop"] = drop

func _update_people(dt: float) -> void:
	if sp == null or not is_instance_valid(sp.player): return
	var pp: Vector3 = sp.player.global_position
	var alert: bool = str(sp.board.get("phase", "")) == "escape"
	var here := str(sp.board.get("room", ""))
	for c in civs:
		var n: Node3D = c["node"]
		var near := n.global_position.distance_to(pp) < 900.0
		n.visible = near
		var ap: AnimationPlayer = c["ap"]
		if ap != null and is_instance_valid(ap): ap.active = near
		match str(c["state"]):
			"down":
				var pv: Node3D = c["pivot"]
				pv.rotation.x = move_toward(pv.rotation.x, PI * 0.5, dt * 3.5)
				continue
			"idle":
				c["t"] = float(c["t"]) - dt
				if alert and here == str(c["room"]): _panic(c)
				elif float(c["t"]) <= 0.0:
					var q := _free_spot(str(c["room"]), 30.0)
					if q != Vector3.INF:
						c["goal"] = q
						c["state"] = "walk"
						_clip(c, "Walk", 1.0)
					else: c["t"] = 3.0
			"walk", "run":
				var run: bool = c["state"] == "run"
				if alert and here == str(c["room"]) and not run: _panic(c)
				var to: Vector3 = (c["goal"] as Vector3) - n.global_position
				to.y = 0.0
				if to.length() < 5.0:
					if run: _cower(c)
					else:
						c["state"] = "idle"
						c["t"] = _rng.randf_range(2.0, 6.0)
						_clip(c, "Idle")
				else:
					var spd := CIV_RUN if run else CIV_WALK
					if run: _clip(c, "Walk", 2.2)
					var step := to.normalized() * minf(spd * dt, to.length())
					var np := push_out(n.global_position + step, 3.0)
					n.global_position = Vector3(np.x, Boarding.floor_at(np), np.z)
					sp.face(n, to)
			"cower":
				c["calm"] = float(c["calm"]) + dt
				var cv = c["cover"]
				if cv != null and cv["broken"]:   # their cover went: run again
					_panic(c)
				elif float(c["calm"]) > (25.0 if alert else 12.0) and not (alert and here == str(c["room"])):
					_stand(c)
					c["state"] = "idle"
					c["t"] = _rng.randf_range(1.0, 3.0)
					_clip(c, "Idle")
				else:   # face away from the shooting
					var aw := n.global_position - pp
					aw.y = 0.0
					if aw.length() > 1.0: sp.face(n, -aw)

func update(dt: float) -> void:
	if not chunks.is_empty(): _update_chunks(dt)
	if not civs.is_empty(): _update_people(dt)
