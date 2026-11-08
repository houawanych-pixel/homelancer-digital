class_name PilotRig
extends RefCounted
## v12.38: the owner's on-foot pilot (assets/pilot/hl_hova.glb, his Tripo model; it has a skeleton but no clips) with the
## mech's rifle in his hands. Used as the player's body in the station escape (inside the real flight / mech game).
## The arms are aimed at the rifle and the legs swing as he walks, all by code each frame.

const GLB := "res://assets/pilot/hl_hova.glb"
const RIFLE := "res://assets/pilot/pilot_rifle.glb"
const PACK := "pilot"

var root: Node3D
var body: Node3D
var skel: Skeleton3D
var lateral := Vector3.RIGHT
var _ph := 0.0
var _k := 0.0

static func ready() -> bool:
	if not Packs.is_ready(PACK):
		Packs.request(PACK)
		return false
	return ResourceLoader.exists(GLB)

## The body, `height` m tall, feet at y = -feet_below (the player's origin is its middle), looking down -Z.
func build(height: float, feet_below: float, glb := "", head_glb := "") -> Node3D:
	root = Node3D.new()
	root.name = "Pilot"
	body = Node3D.new()
	root.add_child(body)
	var path := glb if glb != "" and ResourceLoader.exists(glb) else GLB   # (v12.74: Hovick, or Judy from the gear store)
	var inst: Node3D = (load(path) as PackedScene).instantiate()
	var bb := _aabb(inst)
	var total := bb.size.y
	if head_glb != "" and ResourceLoader.exists(head_glb):   # v12.76 (owner: "head change"): a head on the suit's neck
		var head: Node3D = (load(head_glb) as PackedScene).instantiate()
		head.name = "Head"
		var hb := _aabb(head)
		var ov := 0.012 * bb.size.y   # (it sits a little into the collar, no gap)
		head.position = Vector3(bb.get_center().x, bb.end.y - ov, bb.get_center().z)
		inst.add_child(head)
		total = bb.size.y + maxf(0.0, hb.end.y) - ov   # (only what is above the neck adds height: hair may hang below it)
		bb = AABB(bb.position, Vector3(bb.size.x, total, bb.size.z))
	var k := height / maxf(0.01, total)
	inst.scale = Vector3.ONE * k
	inst.position = Vector3(-bb.get_center().x * k, -bb.position.y * k - feet_below, -bb.get_center().z * k)
	var side_on := bb.size.z > bb.size.x * 1.3
	inst.rotation.y = PI / 2 if side_on else PI
	lateral = Vector3(0, 0, 1) if side_on else Vector3(1, 0, 0)
	body.add_child(inst)
	for s in inst.find_children("*", "Skeleton3D", true, false):
		skel = s
		break
	if ResourceLoader.exists(RIFLE):
		var rifle: Node3D = (load(RIFLE) as PackedScene).instantiate()
		var rb := _aabb(rifle)
		var longest := maxf(rb.size.x, maxf(rb.size.y, rb.size.z))
		var rk := height * 0.53 / maxf(0.01, longest)
		var holder := Node3D.new()
		holder.name = "Rifle"
		body.add_child(holder)
		holder.position = Vector3(height * 0.11, height * 0.655 - feet_below, -height * 0.19)
		holder.add_child(rifle)
		rifle.scale = Vector3.ONE * rk
		rifle.position = -rb.get_center() * rk
		rifle.rotation.y = -PI / 2 if rb.size.x >= rb.size.z else PI
	return root

func pose(dt: float, speed: float, run_speed: float) -> void:
	if skel == null or not is_instance_valid(skel): return
	_k = move_toward(_k, clampf(speed / maxf(run_speed, 0.01), 0.0, 1.0), dt * 4.0)
	_ph += dt * (6.0 + speed * 0.12)
	var sw := sin(_ph) * 0.55 * _k
	for nm in ["L_Thigh", "R_Thigh", "L_Calf", "R_Calf", "L_Upperarm", "R_Upperarm", "L_Forearm", "R_Forearm"]:
		var i := skel.find_bone(nm)
		if i >= 0: skel.reset_bone_pose(i)
	_turn("L_Thigh", lateral, sw)
	_turn("R_Thigh", lateral, -sw)
	_turn("L_Calf", lateral, -maxf(0.0, -cos(_ph)) * 0.8 * _k)
	_turn("R_Calf", lateral, -maxf(0.0, cos(_ph)) * 0.8 * _k)
	# arms on the rifle: right hand on the grip, left under the barrel (body space: forward -Z, right +X)
	_aim("R_Upperarm", "R_Forearm", Vector3(0.05, -0.75, -0.65))
	_aim("R_Forearm", "R_Hand", Vector3(-0.25, 0.05, -1.0))
	_aim("L_Upperarm", "L_Forearm", Vector3(0.3, -0.6, -0.75))
	_aim("L_Forearm", "L_Hand", Vector3(0.45, 0.1, -1.0))

func _turn(name: String, axis: Vector3, a: float) -> void:
	var b := skel.find_bone(name)
	if b < 0: return
	var par := skel.get_bone_parent(b)
	var pg: Transform3D = skel.get_bone_global_pose(par) if par >= 0 else Transform3D.IDENTITY
	var gr: Transform3D = (skel.get_bone_global_rest(par) if par >= 0 else Transform3D.IDENTITY) * skel.get_bone_rest(b)
	skel.set_bone_pose_rotation(b, (pg.basis.inverse() * (Basis(axis.normalized(), a) * gr.basis)).get_rotation_quaternion())

func _aim(name: String, child: String, dir_body: Vector3) -> void:
	var b := skel.find_bone(name)
	var c := skel.find_bone(child)
	if b < 0 or c < 0: return
	var want: Vector3 = (_rel(skel, body).basis.inverse() * dir_body).normalized()   # (v12.70: works before he is in the scene too)
	var gp := skel.get_bone_global_pose(b)
	var cur := (skel.get_bone_global_pose(c).origin - gp.origin).normalized()
	if cur.length() < 0.5: return
	var nb := Basis(Quaternion(cur, want)) * gp.basis
	var par := skel.get_bone_parent(b)
	var pg: Basis = skel.get_bone_global_pose(par).basis if par >= 0 else Basis.IDENTITY
	skel.set_bone_pose_rotation(b, (pg.inverse() * nb).get_rotation_quaternion())

## v12.74: the suit's colour over the body (until each suit has its own model): a see-through coat
func tint(col: Color) -> void:
	for mi: MeshInstance3D in body.find_children("*", "MeshInstance3D", true, false):
		if col.a <= 0.0:
			mi.material_overlay = null
			continue
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(col, 0.42)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.metallic = 0.5
		m.roughness = 0.4
		mi.material_overlay = m

## v12.70: node `n`'s transform in `top`'s space (walks the parents; no scene tree needed)
static func _rel(n: Node, top: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var p: Node = n
	while p != null and p != top:
		if p is Node3D: xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf

## v12.70 (owner: "make the pilot hold the weapons correctly"): his arms in the aiming pose, and where his right palm
## is then, in the root's space (a gun's grip goes there). The palm: a little past the wrist, along the forearm.
func hand_point() -> Vector3:
	if skel == null or not is_instance_valid(skel): return Vector3.INF
	pose(0.0, 0.0, 1.0)
	skel.force_update_all_bone_transforms()
	var h := skel.find_bone("R_Hand")
	var f := skel.find_bone("R_Forearm")
	if h < 0: return Vector3.INF
	var to_root := _rel(skel, root)
	var hp: Vector3 = to_root * skel.get_bone_global_pose(h).origin
	if f >= 0: hp += (hp - to_root * skel.get_bone_global_pose(f).origin) * 0.3
	return hp

## v12.70: hold a loadout weapon (made by Loadout.weapon_mesh) instead of the rifle: its grip in his right palm,
## its muzzle forward. Returns false when there's no hand to put it in.
func hold(g: Node3D) -> bool:
	var hp := hand_point()
	if hp == Vector3.INF: return false
	var old := body.get_node_or_null("Rifle")
	if old != null: old.visible = false
	var held := body.get_node_or_null("Held")
	if held != null: held.free()
	g.name = "Held"
	body.add_child(g)
	var ms := g.get_node_or_null("MountSocket") as Node3D
	g.position = hp - (g.basis * ms.position if ms != null else Vector3.ZERO)
	return true

static func _aabb(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for c in n.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi.mesh == null: continue
		var xf := Transform3D.IDENTITY
		var p: Node = mi
		while p != null and p != n:
			if p is Node3D: xf = (p as Node3D).transform * xf
			p = p.get_parent()
		var b := xf * mi.mesh.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out if not first else AABB(Vector3(-0.3, 0, -0.2), Vector3(0.6, 1.8, 0.4))

## v12.48: point bone `name` (toward its child) along dir_body, given in `body`'s space (forward -Z, right +X).
## Shared with the station crew's crouch (StationLife).
static func aim_bone(skel: Skeleton3D, body: Node3D, name: String, child: String, dir_body: Vector3) -> void:
	var b := skel.find_bone(name)
	var c := skel.find_bone(child)
	if b < 0 or c < 0: return
	var want: Vector3 = (skel.global_transform.basis.inverse() * (body.global_transform.basis * dir_body)).normalized()
	var gp := skel.get_bone_global_pose(b)
	var cur := (skel.get_bone_global_pose(c).origin - gp.origin).normalized()
	if cur.length() < 0.5: return
	var nb := Basis(Quaternion(cur, want)) * gp.basis
	var par := skel.get_bone_parent(b)
	var pg: Basis = skel.get_bone_global_pose(par).basis if par >= 0 else Basis.IDENTITY
	skel.set_bone_pose_rotation(b, (pg.inverse() * nb).get_rotation_quaternion())
