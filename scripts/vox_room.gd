class_name VoxRoom
extends Node3D
## v12.30 (owner: "a mini game is better than the panorama ... everything in that station is gonna be designed to be
## collapsible, destroyable"; Game Maker's Toolkit's destruction video): one station room built from 1 m blocks.
##  - Shots chip blocks (each material has its own toughness); a blast takes out a ball of them.
##  - Anything no longer joined to the room's frame (the floor and the outer shell) breaks off as a real falling chunk
##    (Teardown style): shoot out the pillars under a catwalk and it comes down.
##  - The CUTTER slices a thin line through metal; cut round a section and it drops away (Hardspace: Shipbreaker).
##  - Fuel tanks blow up and set off the blocks round them (a chain).
##  - Hits leave scorched crater marks on the walls (decals).
## Graybox for now: flat colours per material.

const CELL := 1.0
const CHUNK := 8
enum M { AIR, FRAME, WALL, PILLAR, CRATE, CONSOLE, PIPE, TANK, GLASS, FLOOR }
const HP := {M.FRAME: 255, M.WALL: 14, M.PILLAR: 10, M.CRATE: 3, M.CONSOLE: 4, M.PIPE: 5, M.TANK: 2, M.GLASS: 1, M.FLOOR: 18}
const COL := {M.FRAME: Color(0.34, 0.35, 0.38), M.WALL: Color(0.55, 0.57, 0.6), M.PILLAR: Color(0.62, 0.6, 0.55), M.CRATE: Color(0.62, 0.45, 0.25),
	M.CONSOLE: Color(0.2, 0.32, 0.42), M.PIPE: Color(0.5, 0.4, 0.32), M.TANK: Color(0.85, 0.3, 0.15), M.GLASS: Color(0.55, 0.85, 1.0), M.FLOOR: Color(0.42, 0.43, 0.46)}

var sx := 0
var sy := 0
var sz := 0
var mat := PackedByteArray()
var hp := PackedByteArray()
var scar := PackedByteArray()   # cells broken here: the blocks round them get jagged edges
var _dirty := {}
var _chunks := {}          # chunk key -> [MeshInstance3D, StaticBody3D]
var _mat: StandardMaterial3D
var debris: Array = []     # [{body, life}]
var decals: Array = []
var _scorch: Texture2D
var broken := 0            # (tests)
var collapsed := 0         # blocks that came down as chunks (tests)
var cut_cells := 0
signal blast(at: Vector3, radius: float)   # a fuel tank went up (the game hurts whoever is near)

func setup(w: int, h: int, d: int) -> void:
	sx = w
	sy = h
	sz = d
	mat.resize(w * h * d)
	mat.fill(M.AIR)
	hp.resize(w * h * d)
	scar.resize(w * h * d)
	scar.fill(0)
	_mat = StandardMaterial3D.new()
	_mat.vertex_color_use_as_albedo = true
	_mat.roughness = 0.9
	_scorch = _make_scorch()

func idx(x: int, y: int, z: int) -> int:
	return (y * sz + z) * sx + x

func inb(x: int, y: int, z: int) -> bool:
	return x >= 0 and y >= 0 and z >= 0 and x < sx and y < sy and z < sz

func get_m(x: int, y: int, z: int) -> int:
	return mat[idx(x, y, z)] if inb(x, y, z) else M.FRAME

func set_m(x: int, y: int, z: int, m: int) -> void:
	if not inb(x, y, z): return
	var i := idx(x, y, z)
	mat[i] = m
	hp[i] = HP.get(m, 1)
	_dirty[_ck(x, y, z)] = true

func box(a: Vector3i, b: Vector3i, m: int) -> void:   # fill [a, b] inclusive
	for y in range(mini(a.y, b.y), maxi(a.y, b.y) + 1):
		for z in range(mini(a.z, b.z), maxi(a.z, b.z) + 1):
			for x in range(mini(a.x, b.x), maxi(a.x, b.x) + 1): set_m(x, y, z, m)

func solid_at(p: Vector3) -> bool:
	var c := cell_of(p)
	return get_m(c.x, c.y, c.z) != M.AIR

func cell_of(p: Vector3) -> Vector3i:
	return Vector3i(floori(p.x / CELL), floori(p.y / CELL), floori(p.z / CELL))

func _ck(x: int, y: int, z: int) -> Vector3i:
	return Vector3i(x / CHUNK, y / CHUNK, z / CHUNK)

## A ray through the blocks (Amanatides-Woo). {hit, cell, normal, point, dist} or {} if nothing in range.
func ray(o: Vector3, dir: Vector3, maxd: float) -> Dictionary:
	dir = dir.normalized()
	var c := cell_of(o)
	var step := Vector3i(signi(int(signf(dir.x))), signi(int(signf(dir.y))), signi(int(signf(dir.z))))
	var tmax := Vector3.INF
	var tdel := Vector3.INF
	for a in 3:
		if dir[a] != 0.0:
			var nb := (float(c[a]) + (1.0 if dir[a] > 0.0 else 0.0)) * CELL
			tmax[a] = (nb - o[a]) / dir[a]
			tdel[a] = CELL / absf(dir[a])
	var t := 0.0
	var nrm := Vector3.ZERO
	while t <= maxd:
		if not inb(c.x, c.y, c.z):
			if c.y < 0 or c.y >= sy or c.x < -1 or c.z < -1 or c.x > sx or c.z > sz: return {}
		elif mat[idx(c.x, c.y, c.z)] != M.AIR:
			return {"cell": c, "normal": nrm, "point": o + dir * t, "dist": t}
		var a2 := 0
		if tmax.y < tmax[a2]: a2 = 1
		if tmax.z < tmax[a2]: a2 = 2
		t = tmax[a2]
		tmax[a2] += tdel[a2]
		c[a2] += step[a2]
		nrm = Vector3.ZERO
		nrm[a2] = -float(step[a2])
	return {}

## Damage one block; true if it broke. Fuel tanks blow up.
func hit_cell(c: Vector3i, dmg: int) -> bool:
	if not inb(c.x, c.y, c.z): return false
	var i := idx(c.x, c.y, c.z)
	var m := mat[i]
	if m == M.AIR or m == M.FRAME: return false
	if hp[i] > dmg:
		hp[i] -= dmg
		return false
	mat[i] = M.AIR
	scar[i] = 1
	broken += 1
	_dirty[_ck(c.x, c.y, c.z)] = true
	for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		var q: Vector3i = c + d
		if inb(q.x, q.y, q.z): _dirty[_ck(q.x, q.y, q.z)] = true
	if m == M.TANK: call_deferred("explode", Vector3(c) * CELL + Vector3.ONE * 0.5, 3.5, 30)
	_check_queue.append(c)
	return true

var _check_queue: Array = []

## A blast: every block in the ball takes damage (more near the middle); a crater mark on what's left.
func explode(at: Vector3, radius: float, dmg: int) -> void:
	var r := int(ceil(radius))
	var c0 := cell_of(at)
	for y in range(-r, r + 1):
		for z in range(-r, r + 1):
			for x in range(-r, r + 1):
				var d := Vector3(x, y, z).length()
				if d > radius: continue
				hit_cell(c0 + Vector3i(x, y, z), int(dmg * (1.0 - d / (radius + 0.5))) + 1)
	blast.emit(at, radius)
	_fx_burst(at, radius)

## Every frame: check what came loose, redraw changed chunks, age the debris.
func tick(dt: float) -> void:
	if not _check_queue.is_empty():
		var q := _check_queue.duplicate()
		_check_queue.clear()
		_detach_loose(q)
	var n := 0
	for k in _dirty.keys():
		_build_chunk(k)
		_dirty.erase(k)
		n += 1
		if n >= 6: break
	for i in range(debris.size() - 1, -1, -1):
		debris[i]["life"] = float(debris[i]["life"]) - dt
		if float(debris[i]["life"]) <= 0.0:
			(debris[i]["body"] as Node).queue_free()
			debris.remove_at(i)

func rebuild_all() -> void:
	for y in range(0, sy, CHUNK):
		for z in range(0, sz, CHUNK):
			for x in range(0, sx, CHUNK): _build_chunk(_ck(x, y, z))
	_dirty.clear()

## Teardown-style: from each block next to a removed one, flood out; a group that never reaches the frame is loose
## and falls as one rigid chunk.
func _detach_loose(around: Array) -> void:
	var seen := {}
	for c in around:
		for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
			var s: Vector3i = c + d
			if not inb(s.x, s.y, s.z) or mat[idx(s.x, s.y, s.z)] == M.AIR or seen.has(s): continue
			var group: Array = []
			var stack: Array = [s]
			var gset := {s: true}
			var anchored := false
			while not stack.is_empty() and group.size() < 2500:
				var p: Vector3i = stack.pop_back()
				group.append(p)
				var pm := mat[idx(p.x, p.y, p.z)]
				if pm == M.FRAME or pm == M.FLOOR and p.y == 0:
					anchored = true
					break
				for d2 in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
					var q: Vector3i = p + d2
					if not inb(q.x, q.y, q.z) or gset.has(q) or mat[idx(q.x, q.y, q.z)] == M.AIR: continue
					gset[q] = true
					stack.append(q)
			for g in gset: seen[g] = true
			if anchored or group.size() >= 2500: continue
			_make_debris(gset.keys())

func _make_debris(cells: Array) -> void:
	var lo := Vector3i(99999, 99999, 99999)
	var hi := Vector3i(-99999, -99999, -99999)
	var mats := {}
	for c in cells:
		lo = Vector3i(mini(lo.x, c.x), mini(lo.y, c.y), mini(lo.z, c.z))
		hi = Vector3i(maxi(hi.x, c.x), maxi(hi.y, c.y), maxi(hi.z, c.z))
		mats[c] = mat[idx(c.x, c.y, c.z)]
	for c in cells:
		mat[idx(c.x, c.y, c.z)] = M.AIR
		scar[idx(c.x, c.y, c.z)] = 1
		_dirty[_ck(c.x, c.y, c.z)] = true
		for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
			var q: Vector3i = c + d
			if inb(q.x, q.y, q.z): _dirty[_ck(q.x, q.y, q.z)] = true
	collapsed += cells.size()
	var centre := (Vector3(lo) + Vector3(hi) + Vector3.ONE) * 0.5 * CELL
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for c in cells:
		for f in 6:
			var nb: Vector3i = c + FACE_DIR[f]
			if mats.has(nb): continue
			_face(st, Vector3(c) * CELL - centre, f, (COL.get(mats[c], Color.GRAY) as Color).darkened(0.08), centre, mats[c] != M.FRAME and mats[c] != M.FLOOR)
	var body := RigidBody3D.new()
	body.mass = maxf(1.0, cells.size() * 0.5)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _mat
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = (Vector3(hi - lo) + Vector3.ONE) * CELL * 0.92
	cs.shape = bs
	body.add_child(cs)
	add_child(body)
	body.global_position = global_position + centre
	body.angular_velocity = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.6
	debris.append({"body": body, "life": 9.0, "cells": cells.size()})

const FACE_DIR := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
const FACE_SHADE := [0.86, 0.86, 1.0, 0.6, 0.93, 0.93]

## Owner: Red Faction look, "not so blocky". Walls stay clean flat panels until something breaks: then every block corner
## next to a broken cell is nudged by a fixed amount worked out from where it is, so the blocks still meet with no gaps
## but the torn edge reads as jagged shards, not a cube hole. Falling chunks are jagged all over.
const SHARD := 0.2

func _scarred(p: Vector3) -> bool:
	var cx := int(round(p.x / CELL))
	var cy := int(round(p.y / CELL))
	var cz := int(round(p.z / CELL))
	for y in [cy - 1, cy]:
		for z in [cz - 1, cz]:
			for x in [cx - 1, cx]:
				if inb(x, y, z) and scar[idx(x, y, z)] != 0: return true
	return false

func _jit(p: Vector3, always := false) -> Vector3:
	if not always and not _scarred(p): return Vector3.ZERO
	var h := int(round(p.x * 4.0)) * 73856093 ^ int(round(p.y * 4.0)) * 19349663 ^ int(round(p.z * 4.0)) * 83492791
	var a := float(h & 1023) / 1023.0 - 0.5
	var b := float((h >> 10) & 1023) / 1023.0 - 0.5
	var c := float((h >> 20) & 1023) / 1023.0 - 0.5
	return Vector3(a, b, c) * SHARD * 2.0

func _face(st: SurfaceTool, o: Vector3, f: int, col: Color, jo := Vector3.ZERO, rough := true) -> void:
	var s := CELL
	var v: Array
	match f:
		0: v = [Vector3(s, 0, 0), Vector3(s, s, 0), Vector3(s, s, s), Vector3(s, 0, s)]
		1: v = [Vector3(0, 0, s), Vector3(0, s, s), Vector3(0, s, 0), Vector3(0, 0, 0)]
		2: v = [Vector3(0, s, 0), Vector3(0, s, s), Vector3(s, s, s), Vector3(s, s, 0)]
		3: v = [Vector3(0, 0, s), Vector3(0, 0, 0), Vector3(s, 0, 0), Vector3(s, 0, s)]
		4: v = [Vector3(s, 0, s), Vector3(s, s, s), Vector3(0, s, s), Vector3(0, 0, s)]
		_: v = [Vector3(0, 0, 0), Vector3(0, s, 0), Vector3(s, s, 0), Vector3(s, 0, 0)]
	var c2 := Color(col.r * FACE_SHADE[f], col.g * FACE_SHADE[f], col.b * FACE_SHADE[f])
	var p: Array = []
	for k in 4:
		var q: Vector3 = o + v[k]
		p.append(q + _jit(q + jo, jo != Vector3.ZERO) if rough else q)
	for tri in [[0, 1, 2], [0, 2, 3]]:
		var n: Vector3 = (p[tri[2]] - p[tri[0]]).cross(p[tri[1]] - p[tri[0]]).normalized()
		if n.dot(Vector3(FACE_DIR[f])) < 0.0: n = -n
		for k in tri:
			st.set_color(c2)
			st.set_normal(n)
			st.add_vertex(p[k])

func _build_chunk(k: Vector3i) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	var any := false
	for y in range(k.y * CHUNK, mini(sy, (k.y + 1) * CHUNK)):
		for z in range(k.z * CHUNK, mini(sz, (k.z + 1) * CHUNK)):
			for x in range(k.x * CHUNK, mini(sx, (k.x + 1) * CHUNK)):
				var m := mat[idx(x, y, z)]
				if m == M.AIR: continue
				var base: Color = COL.get(m, Color.GRAY)
				var jit := 0.94 + 0.06 * float((x * 7 + y * 13 + z * 5) % 5) / 4.0   # (a little variation block to block)
				var col := Color(base.r * jit, base.g * jit, base.b * jit)
				if hp[idx(x, y, z)] < int(HP.get(m, 1)): col = col.darkened(0.35 * (1.0 - float(hp[idx(x, y, z)]) / float(HP.get(m, 1))))   # (cracked: darker)
				for f in 6:
					var q: Vector3i = Vector3i(x, y, z) + FACE_DIR[f]
					if inb(q.x, q.y, q.z) and mat[idx(q.x, q.y, q.z)] != M.AIR: continue
					if not inb(q.x, q.y, q.z) and (q.y < 0): continue
					_face(st, Vector3(x, y, z) * CELL, f, col, Vector3.ZERO, m != M.FRAME and m != M.FLOOR)
					any = true
	var pair: Array = _chunks.get(k, [])
	if pair.is_empty():
		var mi := MeshInstance3D.new()
		mi.material_override = _mat
		add_child(mi)
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		sb.add_child(cs)
		add_child(sb)
		pair = [mi, sb, cs]
		_chunks[k] = pair
	if any:
		var mesh := st.commit()
		(pair[0] as MeshInstance3D).mesh = mesh
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(mesh.get_faces())
		(pair[2] as CollisionShape3D).shape = shape
	else:
		(pair[0] as MeshInstance3D).mesh = null
		(pair[2] as CollisionShape3D).shape = null

## A scorched crater mark where a shot or blast hit (oldest go first).
func mark(at: Vector3, normal: Vector3, size: float) -> void:
	var d := Decal.new()
	d.texture_albedo = _scorch
	d.size = Vector3(size, 0.6, size)
	d.cull_mask = 1
	add_child(d)
	d.global_position = at
	var up := normal if normal != Vector3.ZERO else Vector3.UP
	var side := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	d.global_basis = Basis(side, up, side.cross(up)).orthonormalized()
	decals.append(d)
	if decals.size() > 70: (decals.pop_front() as Node).queue_free()

func _make_scorch() -> Texture2D:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for y in 64:
		for x in 64:
			var d := Vector2(x - 31.5, y - 31.5).length() / 32.0
			var n := rng.randf() * 0.25
			var a := clampf(1.0 - d - n * d, 0.0, 1.0)
			var core := clampf(1.0 - d * 2.5, 0.0, 1.0)
			img.set_pixel(x, y, Color(0.08 + core * 0.5, 0.06 + core * 0.25, 0.05, a * 0.9))
	return ImageTexture.create_from_image(img)

func _fx_burst(at: Vector3, radius: float) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 40
	p.lifetime = 0.8
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = radius * 3.0
	p.initial_velocity_max = radius * 7.0
	p.gravity = Vector3(0, -12, 0)
	var sm := SphereMesh.new()
	sm.radius = 0.15
	sm.height = 0.3
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.6, 0.2)
	sm.material = m
	p.mesh = sm
	add_child(p)
	p.global_position = at
	p.emitting = true
	get_tree().create_timer(1.5).timeout.connect(p.queue_free)
	var fl := OmniLight3D.new()
	fl.light_color = Color(1.0, 0.6, 0.3)
	fl.light_energy = 6.0
	fl.omni_range = radius * 4.0
	add_child(fl)
	fl.global_position = at
	var tw := create_tween()
	tw.tween_property(fl, "light_energy", 0.0, 0.5)
	tw.tween_callback(fl.queue_free)
