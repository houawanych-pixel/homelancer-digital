class_name PilotGear
extends RefCounted
## v12.75 (owner's spec: "DYNAMIC PILOT EQUIPMENT CAMERA SYSTEM"): the pilot's gear as real 3D pieces on his skeleton.
## Each item is built from drawn outlines (curved, chamfered armour plates; lathed shells and nozzles) in the item's
## colours, and hung on its bone with a BoneAttachment3D, so it moves with him (walking, aiming). Slots:
##   helmet  -> Head (over the eyes)            upper -> Spine02 (chest, back plates) + both Upperarms (shoulder pads)
##   lower   -> Thighs, Calves (knees, shins)   booster -> Spine02 (on the back)      tactical -> Waist / Spine02
## A Tripo model for an item (AssetRegistry "gear" kind, same id) can replace the drawn one later.
## A body with no skeleton (Judy until she is rigged) gets the pieces placed by her height instead.

const SLOTS := ["helmet", "upper", "lower", "booster", "tactical"]
const REF_EYE := 1.62   # m: eye height of the 1.8 m figure the pieces are drawn for

# ---------------------------------------------------------------- shapes
## a curved armour plate: `outline` (m, in X/Y, facing -Z), `thick`, edges bent back by `bend` (z += bend * x^2),
## the front face `chamfer` smaller (a bevelled edge)
static func plate(outline: PackedVector2Array, thick: float, bend: float, chamfer: float, m: Material) -> MeshInstance3D:
	var c := Vector2.ZERO
	for p in outline: c += p
	c /= float(outline.size())
	var front := PackedVector2Array()
	for p in outline: front.append(c + (p - c) * (1.0 - chamfer))
	var tri := Geometry2D.triangulate_polygon(outline)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var zb := func(p: Vector2) -> float: return bend * p.x * p.x
	for i in range(0, tri.size(), 3):   # the front (-Z) and the back
		for k in [0, 2, 1]:
			var q: Vector2 = front[tri[i + k]]
			st.add_vertex(Vector3(q.x, q.y, zb.call(q) - thick))
		for k2 in [0, 1, 2]:
			var q2: Vector2 = outline[tri[i + k2]]
			st.add_vertex(Vector3(q2.x, q2.y, zb.call(q2)))
	var n := outline.size()
	for i in n:   # the bevelled sides
		var a: Vector2 = outline[i]
		var b: Vector2 = outline[(i + 1) % n]
		var fa: Vector2 = front[i]
		var fb: Vector2 = front[(i + 1) % n]
		var A := Vector3(a.x, a.y, zb.call(a))
		var B := Vector3(b.x, b.y, zb.call(b))
		var FA := Vector3(fa.x, fa.y, zb.call(fa) - thick)
		var FB := Vector3(fb.x, fb.y, zb.call(fb) - thick)
		for v in [A, FA, FB, A, FB, B]: st.add_vertex(v)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

## a lathed shell: `prof` [[radius, y], ...] turned round Y from angle a0 to a1 (0 = +Z, PI = the front, -Z)
static func lathe(prof: Array, a0: float, a1: float, segs: int, m: Material, both := true) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in prof.size() - 1:
		for k in segs:
			var t0 := a0 + (a1 - a0) * float(k) / segs
			var t1 := a0 + (a1 - a0) * float(k + 1) / segs
			var p0: Array = prof[i]
			var p1: Array = prof[i + 1]
			var v := [Vector3(sin(t0) * p0[0], p0[1], cos(t0) * p0[0]), Vector3(sin(t1) * p0[0], p0[1], cos(t1) * p0[0]),
				Vector3(sin(t1) * p1[0], p1[1], cos(t1) * p1[0]), Vector3(sin(t0) * p1[0], p1[1], cos(t0) * p1[0])]
			for q in [0, 2, 1, 0, 3, 2]: st.add_vertex(v[q])
			if both:
				for q2 in [0, 1, 2, 0, 2, 3]: st.add_vertex(v[q2])
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

static func mat(col: Color, glow := false, metal := 0.55) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = metal
	m.roughness = 0.38
	if glow:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = 2.2
	if col.a < 1.0: m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m

static func _pts(a: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in a: out.append(Vector2(float(p[0]), float(p[1])))
	return out

static func _mirror(a: Array) -> Array:   # a half outline (x >= 0, top to bottom) made whole
	var out: Array = a.duplicate()
	for i in range(a.size() - 1, -1, -1):
		if absf(float(a[i][0])) > 0.0001: out.append([-float(a[i][0]), float(a[i][1])])
	return out

# ---------------------------------------------------------------- the items' pieces
## [[anchor, Node3D (drawn in m round the anchor, facing -Z, Y up)], ...]
## anchors: eyes, chest, back, shoulder_l / _r, thigh_l / _r, knee_l / _r, shin_l / _r, waist, hip_l / _r
static func pieces(slot: String, pd: Dictionary) -> Array:
	var col: Color = pd.get("col", Color(0.85, 0.87, 0.9))
	var acc: Color = pd.get("acc", Color(0.25, 0.6, 1.0))
	var look := str(pd.get("look", "none"))
	var M := mat(col)
	var A := mat(acc, true)
	var D := mat(Color(0.12, 0.13, 0.15), false, 0.7)
	var out: Array = []
	match slot:
		"helmet":
			if look == "none": return out
			var shell := Node3D.new()
			var prof := [[0.0, 0.175], [0.07, 0.165], [0.112, 0.13], [0.132, 0.07], [0.134, 0.01], [0.126, -0.05], [0.108, -0.1]]
			var open := 0.75 if look == "flight" else (0.35 if look == "visor" else 0.0)   # (half the face opening, radians)
			if open > 0.0:
				shell.add_child(lathe(prof, PI + open, PI * 3.0 - open, 28, M))
				var vis := lathe([[0.138, 0.06], [0.142, 0.0], [0.13, -0.05]], PI - open - 0.05, PI + open + 0.05, 12, mat(Color(acc, 0.55), true))
				shell.add_child(vis)   # the glass visor over the face
			else:
				shell.add_child(lathe(prof, 0.0, TAU, 32, M))
				var slit := plate(_pts([[-0.09, 0.012], [0.09, 0.012], [0.07, -0.012], [-0.07, -0.012]]), 0.01, 2.0, 0.1, A)
				slit.position = Vector3(0, 0.0, -0.132)
				shell.add_child(slit)
				var ridge := plate(_pts([[-0.02, 0.0], [0.02, 0.0], [0.012, -0.24], [-0.012, -0.24]]), 0.03, 0.0, 0.2, D)
				ridge.rotation.x = -PI * 0.5
				ridge.position = Vector3(0, 0.168, -0.11)
				shell.add_child(ridge)
			for sx in [-1.0, 1.0]:   # the ear pods
				var pod := lathe([[0.0, 0.035], [0.035, 0.03], [0.042, 0.0], [0.035, -0.03], [0.0, -0.035]], 0.0, TAU, 14, D)
				pod.rotation.z = PI * 0.5
				pod.position = Vector3(sx * 0.135, -0.01, 0.0)
				shell.add_child(pod)
				var lamp := lathe([[0.0, 0.012], [0.016, 0.0], [0.0, -0.012]], 0.0, TAU, 10, A)
				lamp.rotation.z = PI * 0.5
				lamp.position = Vector3(sx * 0.17, -0.01, 0.0)
				shell.add_child(lamp)
			shell.scale = Vector3(1.2, 1.0, 1.2)   # (over the hair, not inside it)
			shell.position = Vector3(0, -0.005, 0.01)
			out.append(["eyes", shell])
		"upper":
			if look == "none": return out
			var big := look == "armor"
			var chest := plate(_pts(_mirror([[0.0, 0.17], [0.15, 0.15], [0.18, 0.05], [0.15, -0.1], [0.07, -0.18], [0.0, -0.2]] if big else [[0.0, 0.12], [0.11, 0.1], [0.13, 0.0], [0.08, -0.12], [0.0, -0.14]])), 0.05 if big else 0.03, 2.6, 0.12, M)
			chest.scale = Vector3.ONE * 1.2
			out.append(["chest", chest])
			var core := plate(_pts(_mirror([[0.0, 0.05], [0.04, 0.03], [0.04, -0.03], [0.0, -0.05]])), 0.02, 0.0, 0.2, A)
			core.position = Vector3(0, 0.0, -0.05 if big else -0.03)
			chest.add_child(core)
			if big:
				var back := plate(_pts(_mirror([[0.0, 0.16], [0.16, 0.14], [0.17, -0.06], [0.06, -0.16], [0.0, -0.17]])), 0.04, -2.4, 0.1, M)
				back.rotation.y = PI
				out.append(["back", back])
			for side in ["l", "r"]:
				var sx := -1.0 if side == "l" else 1.0
				var pad := lathe([[0.0, 0.08 if big else 0.05], [0.07 if big else 0.05, 0.06 if big else 0.04], [0.105 if big else 0.075, 0.0], [0.1 if big else 0.07, -0.05]], 0.0, TAU, 20, M)
				pad.scale = Vector3(1.35, 1.25, 1.5)
				var trim := lathe([[0.108 if big else 0.078, 0.004], [0.108 if big else 0.078, -0.012]], 0.0, TAU, 20, A)
				pad.add_child(trim)
				pad.position = Vector3(sx * 0.02, 0.02, 0.0)
				out.append(["shoulder_" + side, pad])
			if look == "harness":   # crossed straps over the chest
				for sx2 in [-1.0, 1.0]:
					var strap := plate(_pts([[-0.018, 0.2], [0.018, 0.2], [0.018, -0.22], [-0.018, -0.22]]), 0.012, 0.0, 0.1, D)
					strap.rotation.z = sx2 * 0.42
					strap.position = Vector3(0, 0, -0.035)
					chest.add_child(strap)
		"lower":
			if look == "none": return out
			var big2 := look == "armor"
			for side in ["l", "r"]:
				var knee := plate(_pts(_mirror([[0.0, 0.07], [0.055, 0.05], [0.065, -0.01], [0.04, -0.06], [0.0, -0.075]])), 0.045, 6.0, 0.18, M)
				var kl := plate(_pts(_mirror([[0.0, 0.015], [0.03, 0.01], [0.03, -0.01], [0.0, -0.015]])), 0.012, 0.0, 0.2, A)
				kl.position = Vector3(0, 0.0, -0.045)
				knee.add_child(kl)
				out.append(["knee_" + side, knee])
				var shin := plate(_pts(_mirror([[0.0, 0.17], [0.05, 0.16], [0.06, 0.0], [0.05, -0.17], [0.0, -0.19]] if big2 else [[0.0, 0.12], [0.042, 0.11], [0.048, 0.0], [0.04, -0.12], [0.0, -0.13]])), 0.03, 8.0, 0.12, M)
				out.append(["shin_" + side, shin])
				if big2:
					var thigh := plate(_pts(_mirror([[0.0, 0.15], [0.07, 0.13], [0.075, -0.05], [0.05, -0.14], [0.0, -0.15]])), 0.035, 5.0, 0.12, M)
					out.append(["thigh_" + side, thigh])
		"booster":
			var big3 := look == "jump"
			var pack := plate(_pts(_mirror([[0.0, 0.2 if big3 else 0.16], [0.12 if big3 else 0.1, 0.18 if big3 else 0.14], [0.14 if big3 else 0.11, -0.05], [0.1, -0.17 if big3 else -0.13], [0.0, -0.19 if big3 else -0.15]])), 0.12 if big3 else 0.09, -1.6, 0.1, M)
			pack.rotation.y = PI   # (it faces back)
			var noz_n := 4 if big3 else 2
			for i in noz_n:
				var nx := (float(i) - (noz_n - 1) * 0.5) * 0.075
				var noz := lathe([[0.022, 0.0], [0.03, -0.03], [0.04, -0.07], [0.037, -0.075]], 0.0, TAU, 14, D)
				noz.position = Vector3(nx, -0.17 if big3 else -0.13, -0.06)
				pack.add_child(noz)
				var fire := lathe([[0.03, -0.07], [0.0, -0.075]], 0.0, TAU, 12, A)
				noz.add_child(fire)
			if big3:   # the fins
				for sx3 in [-1.0, 1.0]:
					var fin := plate(_pts([[0.0, 0.08], [0.1, 0.02], [0.1, -0.02], [0.0, -0.06]]), 0.015, 0.0, 0.1, M)
					fin.rotation.y = PI * 0.5 * sx3
					fin.position = Vector3(sx3 * 0.14, 0.04, -0.06)
					pack.add_child(fin)
			var strip := plate(_pts([[-0.06, 0.012], [0.06, 0.012], [0.06, -0.012], [-0.06, -0.012]]), 0.008, 0.0, 0.1, A)
			strip.position = Vector3(0, 0.06, -0.12 if big3 else -0.095)
			pack.add_child(strip)
			out.append(["back", pack])
		"tactical":
			for side in ["l", "r"]:
				var sx4 := -1.0 if side == "l" else 1.0
				var pouch := plate(_pts(_mirror([[0.0, 0.045], [0.04, 0.04], [0.045, -0.04], [0.0, -0.045]])), 0.045, 4.0, 0.15, D)
				pouch.rotation.y = sx4 * 0.9
				out.append(["hip_" + side, pouch])
				var flap := plate(_pts(_mirror([[0.0, 0.012], [0.042, 0.012], [0.04, -0.012], [0.0, -0.012]])), 0.01, 4.0, 0.1, M)
				flap.position = Vector3(0, 0.035, -0.045)
				pouch.add_child(flap)
			if look == "medkit":
				var kit := plate(_pts(_mirror([[0.0, 0.05], [0.06, 0.045], [0.06, -0.045], [0.0, -0.05]])), 0.05, 2.0, 0.12, mat(Color(0.92, 0.92, 0.9)))
				var cross := plate(_pts([[-0.012, 0.03], [0.012, 0.03], [0.012, 0.012], [0.03, 0.012], [0.03, -0.012], [0.012, -0.012], [0.012, -0.03], [-0.012, -0.03], [-0.012, -0.012], [-0.03, -0.012], [-0.03, 0.012], [-0.012, 0.012]]), 0.008, 0.0, 0.05, mat(Color(0.85, 0.1, 0.1), true))
				cross.position = Vector3(0, 0, -0.052)
				kit.add_child(cross)
				out.append(["waist", kit])
			elif look == "shield":
				var em := lathe([[0.0, 0.02], [0.04, 0.015], [0.05, 0.0], [0.04, -0.015], [0.0, -0.02]], 0.0, TAU, 18, D)
				em.rotation.x = PI * 0.5
				var core2 := lathe([[0.0, 0.025], [0.028, 0.0], [0.0, -0.025]], 0.0, TAU, 14, A)
				core2.rotation.x = PI * 0.5
				core2.position = Vector3(0, -0.012, 0)
				em.add_child(core2)
				em.position = Vector3(0.08, 0.05, 0.0)
				out.append(["chest_front", em])
			elif look == "grenades":
				var band := Node3D.new()
				for i in 4:
					var g := lathe([[0.0, 0.035], [0.022, 0.028], [0.026, 0.0], [0.022, -0.028], [0.0, -0.035]], 0.0, TAU, 12, mat(Color(0.3, 0.38, 0.22)))
					g.position = Vector3(-0.09 + i * 0.06, 0.08 - i * 0.055, 0.0)
					var pin := lathe([[0.006, 0.045], [0.006, 0.03]], 0.0, TAU, 6, A)
					g.add_child(pin)
					band.add_child(g)
				out.append(["chest_front", band])
	return out

# ---------------------------------------------------------------- putting them on
static func skel_of(model: Node) -> Skeleton3D:
	var s := model.find_children("*", "Skeleton3D", true, false)
	return s[0] if not s.is_empty() else null

## remove the old pieces and hang the loadout's on the pilot (keeps everything else he has)
static func apply(model: Node3D, lo: Dictionary) -> void:
	for n in model.find_children("Gear_*", "", true, false): n.free()
	var sk := skel_of(model)
	var body: Node3D = model.get_child(0) if model.get_child_count() > 0 else model
	var fr := _frame(model, sk, body)
	for slot in SLOTS:
		var pid := str((lo.get("parts", {}) as Dictionary).get(slot, ""))
		var pd := Loadout.part("pilot", slot, pid)
		if pd.is_empty(): continue
		var k := 0
		for pc in pieces(slot, pd):
			var anc := str(pc[0])
			var node: Node3D = pc[1]
			node.name = "Gear_%s_%d" % [slot, k]
			node.set_meta("gear", pid)
			k += 1
			_hang(model, sk, body, fr, anc, node)

## where the anchors are, in skeleton space (or the body's, with no skeleton), and the body's axes there
static func _frame(model: Node3D, sk: Skeleton3D, body: Node3D) -> Dictionary:
	var f := {}
	if sk != null:
		sk.force_update_all_bone_transforms()
		var rel: Transform3D = PilotRig._rel(sk, body)
		var ib := rel.basis.inverse()
		f["right"] = (ib * Vector3.RIGHT).normalized()
		f["up"] = (ib * Vector3.UP).normalized()
		f["back"] = (ib * Vector3.BACK).normalized()
		var bp := func(n: String) -> Vector3:
			var i := sk.find_bone(n)
			return sk.get_bone_global_pose(i).origin if i >= 0 else Vector3.ZERO
		var eye: Vector3 = (bp.call("L_Eye") + bp.call("R_Eye")) * 0.5
		var foot: Vector3 = (bp.call("L_Foot") + bp.call("R_Foot")) * 0.5
		var s: float = maxf(0.01, (eye - foot).dot(f["up"])) / (REF_EYE - 0.08)   # (the foot bone is at the ankle)
		f["s"] = s
		var up: Vector3 = f["up"]
		var bk: Vector3 = f["back"]
		var rt: Vector3 = f["right"]
		var sp: Vector3 = bp.call("Spine02")
		f["at"] = {"eyes": [eye + bk * 0.035 * s, "Head"], "chest": [sp + up * 0.03 * s - bk * 0.14 * s, "Spine02"], "chest_front": [sp - bk * 0.19 * s, "Spine02"],
			"back": [sp + up * 0.0 * s + bk * 0.16 * s, "Spine02"], "waist": [bp.call("Waist") - bk * 0.12 * s + rt * 0.0, "Waist"]}
		for side in ["l", "r"]:
			var P := "L_" if side == "l" else "R_"
			var sx := -1.0 if side == "l" else 1.0
			var ua: Vector3 = bp.call(P + "Upperarm")
			f["at"]["shoulder_" + side] = [ua + up * 0.075 * s + rt * sx * 0.03 * s, P + "Upperarm"]
			var th: Vector3 = bp.call(P + "Thigh")
			var ca: Vector3 = bp.call(P + "Calf")
			var ft: Vector3 = bp.call(P + "Foot")
			f["at"]["thigh_" + side] = [th.lerp(ca, 0.5) - bk * 0.075 * s, P + "Thigh"]
			f["at"]["knee_" + side] = [ca - bk * 0.06 * s, P + "Calf"]
			f["at"]["shin_" + side] = [ca.lerp(ft, 0.5) - bk * 0.05 * s, P + "Calf"]
			f["at"]["hip_" + side] = [bp.call("Waist") + rt * sx * 0.16 * s - up * 0.04 * s, "Waist"]
			var hd_: Vector3 = bp.call(P + "Hand")
			f["at"]["hand_" + side] = [hd_ if hd_ != Vector3.ZERO else bp.call(P + "Forearm"), P + "Hand"]
			f["at"]["foot_" + side] = [ft - bk * 0.06 * s - up * 0.02 * s, P + "Foot"]
	else:   # no skeleton: by the body's height (body space)
		var bb := PilotRig._aabb(body)
		var h := bb.size.y
		var s2 := h / 1.8
		f["right"] = Vector3.RIGHT
		f["up"] = Vector3.UP
		f["back"] = Vector3.BACK
		f["s"] = s2
		var c := bb.get_center()
		var y0 := bb.position.y
		var at := func(x: float, y: float, z: float) -> Array: return [Vector3(c.x + x * s2, y0 + y * s2, c.z + z * s2), ""]
		f["at"] = {"eyes": at.call(0.0, 1.62, 0.02), "chest": at.call(0.0, 1.3, -0.1), "chest_front": at.call(0.0, 1.3, -0.14), "back": at.call(0.0, 1.3, 0.13),
			"waist": at.call(0.0, 1.0, -0.11)}
		for side in ["l", "r"]:
			var sx2 := -1.0 if side == "l" else 1.0
			f["at"]["shoulder_" + side] = at.call(sx2 * 0.19, 1.47, 0.0)
			f["at"]["thigh_" + side] = at.call(sx2 * 0.1, 0.72, -0.07)
			f["at"]["knee_" + side] = at.call(sx2 * 0.1, 0.5, -0.06)
			f["at"]["shin_" + side] = at.call(sx2 * 0.1, 0.3, -0.05)
			f["at"]["hip_" + side] = at.call(sx2 * 0.16, 0.98, 0.0)
			f["at"]["hand_" + side] = at.call(sx2 * 0.3, 0.82, 0.0)
			f["at"]["foot_" + side] = at.call(sx2 * 0.1, 0.08, -0.06)
	return f

static func _hang(model: Node3D, sk: Skeleton3D, body: Node3D, f: Dictionary, anc: String, node: Node3D) -> void:
	var a: Array = f["at"].get(anc, [])
	if a.is_empty(): return
	var s: float = f["s"]
	var basis := Basis(f["right"] * s, f["up"] * s, f["back"] * s)
	var want := Transform3D(basis, a[0]) * node.transform
	if sk != null and str(a[1]) != "" and sk.find_bone(str(a[1])) >= 0:
		var att := sk.get_node_or_null("GearAt_" + str(a[1])) as BoneAttachment3D
		if att == null:
			att = BoneAttachment3D.new()
			att.name = "GearAt_" + str(a[1])
			att.bone_name = str(a[1])
			sk.add_child(att)
		var bgp: Transform3D = sk.get_bone_global_pose(sk.find_bone(str(a[1])))
		att.transform = bgp   # (a new attachment only follows its bone from the next pose update: put it there now)
		att.add_child(node)
		node.transform = bgp.affine_inverse() * want
	else:
		body.add_child(node)
		node.transform = want

## v12.75: an anchor's place in the model's own space (the hip holster for the sidearm, ...)
static func anchor_local(model: Node3D, anc: String) -> Vector3:
	var sk := skel_of(model)
	var body: Node3D = model.get_child(0) if model.get_child_count() > 0 else model
	var f := _frame(model, sk, body)
	var a: Array = f["at"].get(anc, [])
	if a.is_empty(): return Vector3.INF
	return (PilotRig._rel(sk, model) * (a[0] as Vector3)) if sk != null else PilotRig._rel(body, model) * (a[0] as Vector3)

## where the camera should look for a slot (world space), and from which side ("front" / "back")
static func focus(model: Node3D, slot: String) -> Array:
	var sk := skel_of(model)
	var body: Node3D = model.get_child(0) if model.get_child_count() > 0 else model
	var f := _frame(model, sk, body)
	var key: String = {"helmet": "eyes", "upper": "chest", "lower": "shin_r", "booster": "back", "tactical": "waist", "sidearm": "hip_r"}.get(slot, "chest")
	var p: Vector3 = f["at"].get(key, [Vector3.ZERO, ""])[0]
	if slot == "lower": p = (f["at"]["knee_l"][0] + f["at"]["knee_r"][0]) * 0.5
	if slot == "gloves": p = f["at"].get("hand_l", [p])[0]          # v13.08 (owner): the camera goes to the gloves (the free hand: the right one holds the gun)
	if slot == "boots": p = (f["at"]["foot_l"][0] + f["at"]["foot_r"][0]) * 0.5   # ... and to the boots
	var world: Vector3 = (sk.global_transform * p) if sk != null else body.global_transform * p
	return [world, "back" if slot == "booster" else "front"]
