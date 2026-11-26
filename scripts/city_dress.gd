extends RefCounted
class_name CityDress
## v13.354 (owner's picture of the capital's crossing: cherry trees in blossom along the pavements, tall street lamps
## with purple banners, lit bollards at the kerbs): the street dressing. Every block gets its own few multimeshes
## (one draw each, culled with the block, gone past Data.DRESS_FAR), so thousands of them cost phones little.
## - street lamps along every pavement facing a road (a slim white post, an arm, a glowing head); every other one
##   carries a hanging purple faction banner with a lit edge;
## - lit bollards along the kerb;
## - cherry trees in blossom on the pavements where there's no glass canopy overhead (the outskirts, the towns).
## Corners are kept clear (the footbridges' escalators run there).

const PARTS := ["post", "head", "banner", "bollard", "trunk", "bloom", "bloom2"]

static func points(pid: String, tile: int, r: Vector2i) -> Dictionary:
	var out := {"lamp": [], "bollard": [], "tree": []}   # [Vector2 position, Vector2 facing the road]
	var plan := CityPlan.block(pid, tile, r)
	var cr := CityPlan.rect(pid, tile)
	var S: float = Data.BLOCK_REGION
	var org := Vector2(-Surface.EDGE, -Surface.EDGE) + Vector2(cr.position) * S
	var bo := org + Vector2(r - cr.position) * S
	var pv: float = Data.CITY_PAVEMENT * Data.BLOCK_MIN
	var canopy: bool = Data.CITY_FOOTBRIDGES and not CityPlan.is_outskirt(pid, tile, r) and not CityPlan.is_town(pid, tile)
	for lr in plan.get("lots", []):
		var lot: Rect2i = lr
		var x0 := bo.x + lot.position.x * Data.BLOCK_MIN
		var z0 := bo.y + lot.position.y * Data.BLOCK_MIN
		var x1 := bo.x + lot.end.x * Data.BLOCK_MIN
		var z1 := bo.y + lot.end.y * Data.BLOCK_MIN
		for ed in [[Vector2(x0, z0), Vector2(x1, z0), Vector2(0, 1)], [Vector2(x0, z1), Vector2(x1, z1), Vector2(0, -1)], [Vector2(x0, z0), Vector2(x0, z1), Vector2(1, 0)], [Vector2(x1, z0), Vector2(x1, z1), Vector2(-1, 0)]]:
			var p0: Vector2 = ed[0]
			var p1: Vector2 = ed[1]
			var inn: Vector2 = ed[2]   # toward the lot (the road is the other way)
			var L := p0.distance_to(p1)
			var keep: float = Data.DRESS_CORNER
			if L < keep * 2.0 + 10.0: continue
			var dir := (p1 - p0) / L
			var u := keep
			var k := 0
			while u <= L - keep:
				var at := p0 + dir * u
				out["lamp"].append([at + inn * pv * 0.16, -inn, k % 2 == 0])
				if not canopy: out["tree"].append([at + dir * Data.DRESS_EVERY * 0.5 + inn * pv * 0.55, -inn])
				u += Data.DRESS_EVERY
				k += 1
			var b := keep
			while b <= L - keep:
				out["bollard"].append([p0 + dir * b + inn * 0.6, -inn])
				b += Data.DRESS_BOLLARD_EVERY
	return out

## The dressing of one block: a Node3D of multimeshes.
static func build(pid: String, tile: int, r: Vector2i) -> Node3D:
	var root := Node3D.new()
	root.name = "Dress_%d_%d" % [r.x, r.y]
	var g := CityPlan.ground(pid, tile)
	var pts := points(pid, tile, r)
	var lamps: Array = pts["lamp"]
	var banners: Array = lamps.filter(func(l): return bool(l[2]))
	var trees: Array = pts["tree"]
	var bolls: Array = pts["bollard"]
	var LH: float = Data.DRESS_LAMP_H
	var face := func(fw: Vector2) -> Basis: return Basis(Vector3.UP, atan2(fw.x, fw.y))
	_mm(root, "post", _box(Vector3(0.45, LH, 0.45), Vector3(0, LH * 0.5, 0)), _mat(Data.TOWER_WHITE, 0.0), lamps.map(func(l): return Transform3D(face.call(l[1]), Vector3(l[0].x, g, l[0].y))))
	var head := _merge([[_box(Vector3(0.35, 0.35, 2.6), Vector3(0, LH - 0.3, 1.2)), Color.WHITE], [_box(Vector3(0.7, 0.3, 1.2), Vector3(0, LH - 0.55, 2.3)), Color.WHITE]])
	_mm(root, "head", head, _mat(Data.CITY_TRIM, 2.0), lamps.map(func(l): return Transform3D(face.call(l[1]), Vector3(l[0].x, g, l[0].y))))
	var ban := _merge([[_box(Vector3(0.12, 3.6, 1.5), Vector3(0.3, LH * 0.62, 0.9)), Color.WHITE]])
	_mm(root, "banner", ban, _mat(Data.DRESS_BANNER, 0.35), banners.map(func(l): return Transform3D(face.call(l[1]), Vector3(l[0].x, g, l[0].y))))
	_mm(root, "bollard", _box(Vector3(0.35, 1.1, 0.35), Vector3(0, 0.55, 0)), _mat(Data.CITY_TRIM, 1.2), bolls.map(func(l): return Transform3D(face.call(l[1]), Vector3(l[0].x, g, l[0].y))))
	if not trees.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = absi(hash("%s|%d|%s|trees" % [pid, tile, str(r)]))
		var xf: Array = []
		for t in trees:
			var s := rng.randf_range(0.8, 1.15)
			xf.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(t[0].x, g, t[0].y)))
		var TH: float = Data.DRESS_TREE_H
		_mm(root, "trunk", _cyl(0.3, 0.45, TH * 0.55, 6, Vector3(0, TH * 0.275, 0)), _mat(Data.DRESS_TRUNK, 0.0), xf)
		_mm(root, "bloom", _blob(Data.DRESS_TREE_R, Vector3(0, TH * 0.72, 0)), _mat(Data.DRESS_BLOOM, 0.15), xf)
		_mm(root, "bloom2", _blob(Data.DRESS_TREE_R * 0.7, Vector3(Data.DRESS_TREE_R * 0.55, TH * 0.6, 0.3)), _mat(Data.DRESS_BLOOM.lightened(0.15), 0.15), xf)
	return root

static func _mm(root: Node3D, nm: String, mesh: Mesh, mat: Material, xf: Array) -> void:
	if xf.is_empty(): return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xf.size()
	for i in xf.size(): mm.set_instance_transform(i, xf[i])
	var mi := MultiMeshInstance3D.new()
	mi.name = nm
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = Data.DRESS_FAR
	root.add_child(mi)

static var _mats := {}
static func _mat(c: Color, glow: float) -> StandardMaterial3D:
	var key := "%s|%.2f" % [c.to_html(), glow]
	if _mats.has(key): return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.6
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = glow
	_mats[key] = m
	return m

static func _box(size: Vector3, at: Vector3) -> ArrayMesh:
	var b := BoxMesh.new()
	b.size = size
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(b, 0, Transform3D(Basis.IDENTITY, at))
	return st.commit()

static func _cyl(rt: float, rb: float, h: float, segs: int, at: Vector3) -> ArrayMesh:
	var c := CylinderMesh.new()
	c.top_radius = rt
	c.bottom_radius = rb
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(c, 0, Transform3D(Basis.IDENTITY, at))
	return st.commit()

## A low round crown (a squashed sphere, few faces).
static func _blob(r: float, at: Vector3) -> ArrayMesh:
	var sp := SphereMesh.new()
	sp.radius = r
	sp.height = r * 1.5
	sp.radial_segments = 8
	sp.rings = 4
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(sp, 0, Transform3D(Basis.IDENTITY, at))
	return st.commit()

static func _merge(parts: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in parts: st.append_from(p[0] as Mesh, 0, Transform3D.IDENTITY)
	return st.commit()
