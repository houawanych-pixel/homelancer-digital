class_name PartIcons
extends Node
## v13.268 (owner: "picture cards for the parts, all the same across the board: mech parts from the front, ship parts
## from the top with the nose up, weapons from the side"): square pictures of each part, taken in code from the 3D
## models. One small hidden viewport takes them one at a time (a model, a fixed light, an orthographic camera framed on
## the part); each picture is kept (memory and user://) so a part is only ever photographed once.

const SIZE := 192
const DIR := "user://part_icons"
static var cache := {}   # key -> ImageTexture
var _queue: Array = []   # [key, builder: Callable (-> [Node3D, view "front"|"top"|"side"]), targets: Array[TextureRect]]
var _vp: SubViewport
var _cam: Camera3D
var _busy := false

func _ready() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(SIZE, SIZE)
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR   # see-through: the picture can be measured and re-framed
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.7)
	env.ambient_light_energy = 0.9
	we.environment = env
	_vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, 30, 0)
	key.light_energy = 1.3
	_vp.add_child(key)
	var front := DirectionalLight3D.new()   # the camera side (mechs are shot from -Z): faces it are never left black
	front.rotation_degrees = Vector3(-35, 200, 0)
	front.light_energy = 1.1
	_vp.add_child(front)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_vp.add_child(_cam)

## The picture for a key (null until taken: the target gets it when it's ready).
func get_icon(key: String, builder: Callable, target: TextureRect) -> void:
	if cache.has(key):
		target.texture = cache[key]
		return
	var path := "%s/%s.png" % [DIR, key.validate_filename()]
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		if img != null and not img.is_empty():
			cache[key] = ImageTexture.create_from_image(img)
			target.texture = cache[key]
			return
	for q in _queue:
		if q[0] == key:
			(q[2] as Array).append(target)
			return
	_queue.append([key, builder, [target]])
	if not _busy: _next()

func _next() -> void:
	if _queue.is_empty():
		_busy = false
		return
	_busy = true
	var q: Array = _queue.pop_front()
	var made: Array = (q[1] as Callable).call()
	var m: Node3D = made[0] if not made.is_empty() else null
	if m == null:
		_next.call_deferred()
		return
	_vp.add_child(m)
	var bb := _visible_box(m, Transform3D.IDENTITY)
	var c := bb.get_center()
	var ext := maxf(bb.size.x, maxf(bb.size.y, bb.size.z))
	match str(made[1]):
		"front":   # a mech part, face on (mechs face -Z: the camera in front, at -Z)
			_cam.size = maxf(bb.size.x, bb.size.y) * 1.15
			_cam.look_at_from_position(c + Vector3(0, 0, -ext * 3.0), c, Vector3.UP)
		"top":   # a ship part from straight above, the nose (-Z) pointing up the picture
			_cam.size = maxf(bb.size.x, bb.size.z) * 1.15
			_cam.look_at_from_position(c + Vector3(0, ext * 3.0, 0), c, Vector3(0, 0, -1))
		_:   # a weapon from the side, the barrel (-Z) pointing right
			_cam.size = maxf(bb.size.z, bb.size.y) * 1.15
			_cam.look_at_from_position(c + Vector3(ext * 3.0, 0, 0), c, Vector3.UP)
	_cam.near = 0.01
	_cam.far = ext * 8.0 + 10.0
	var img := await _shot()
	# re-frame on what was really drawn (skinned parts can sit away from their mesh box): centre it and fill the card
	var r := img.get_used_rect() if img != null else Rect2i()
	if r.size.x > 2 and r.size.y > 2:
		var fx := (r.position.x + r.size.x * 0.5) / float(SIZE) - 0.5
		var fy := (r.position.y + r.size.y * 0.5) / float(SIZE) - 0.5
		var b := _cam.global_transform.basis
		var sz := _cam.size
		_cam.global_position += b.x * fx * sz - b.y * fy * sz
		_cam.size = sz * maxf(r.size.x, r.size.y) / float(SIZE) * 1.12
		img = await _shot()
	m.queue_free()
	if img != null and not img.is_empty():
		var tex := ImageTexture.create_from_image(img)
		cache[q[0]] = tex
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
		img.save_png(ProjectSettings.globalize_path("%s/%s.png" % [DIR, str(q[0]).validate_filename()]))
		for t in q[2]:
			if is_instance_valid(t): (t as TextureRect).texture = tex
	_next()

func _shot() -> Image:
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return _vp.get_texture().get_image()

## The box round the meshes you can see (hidden parts don't count).
static func _visible_box(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	if n is Node3D:
		if not (n as Node3D).visible: return AABB()
		xf = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out = xf * (n as MeshInstance3D).mesh.get_aabb()
		first = false
	for c in n.get_children():
		var cb := _visible_box(c, xf)
		if cb.size == Vector3.ZERO: continue
		out = cb if first else out.merge(cb)
		first = false
	return out

## A mech frame showing only one part (head / arms / core / legs), standing in its rest pose.
static func mech_part(fid: String, part: String) -> Array:
	var key := str(Data.MECHS[fid]["model"])
	if not ShipFactory.has_real_model(key): return []
	var m := ShipFactory.build(key)
	var skel := MechParts.find_skeleton(m)
	if skel != null: skel.reset_bone_poses()
	var meshes: Array = MechParts.skinned_meshes(m)
	for mi: MeshInstance3D in meshes:
		var nm := str(mi.name)
		var p := ""
		for q in ["arms", "core", "legs"]:
			if nm.begins_with("Part_" + q): p = q
		if p == "":   # an uncut model: cut its mesh here
			var cut := MechParts.split(mi, skel)
			if part in ["arms", "legs"]:
				mi.mesh = cut[part] if cut[part] != null else mi.mesh
				mi.visible = cut[part] != null
			else:
				var hc := MechParts.split_head(mi, skel) if cut["core"] != null else [null, null]
				mi.visible = (hc[1] != null) if part == "head" else (cut["core"] != null)
			continue
		if part in ["arms", "legs"]: mi.visible = p == part
		elif p != "core": mi.visible = false
		else:
			var hc := MechParts.split_head(mi, skel)
			if part == "head":
				mi.visible = hc[1] != null
				if hc[1] != null: mi.mesh = hc[1]
			elif hc[0] != null: mi.mesh = hc[0]
	return [m, "front"]

## v13.293 (owner: "thumbnails of the ships next to the purchase"): a whole ship from the top, nose up.
static func ship(sid: String) -> Array:
	var key := str(Data.SHIPS.get(sid, {}).get("model", ""))
	if key == "" or not ShipFactory.has_real_model(key): return []
	var root := Node3D.new()
	root.add_child(ShipFactory.build(key))
	return [root, "top"]

## One ship's cockpit / body / wings / tail on its own.
static func ship_part(sid: String, part: String) -> Array:
	var key := str(Data.SHIPS[sid]["model"])
	if not ShipFactory.has_real_model(key): return []
	var root := Node3D.new()
	for mesh in ShipParts.cut(key).get(part, []):
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		root.add_child(mi)
	return [root, "top"]

## v13.269 (owner: "weapons from the side"): a gun or missile pod on its own, barrel pointing right. Guns that share a
## model (the Nexus blasters) get a light in their own colour, so each card still looks like its gun.
static func weapon(id: String) -> Array:
	var d: Dictionary = Data.WEAPONS.get(id, Data.MOUNT_PODS.get(id, {}))
	var key := str(d.get("model", ""))
	if key == "" or not ShipFactory.has_real_model(key): return []
	var root := Node3D.new()
	root.add_child(ShipFactory.build(key))
	if d.has("color"):
		var l := OmniLight3D.new()
		l.light_color = d["color"]
		l.light_energy = 2.5
		l.omni_range = 40.0
		l.position = Vector3(20.0, 4.0, 0.0)
		root.add_child(l)
	return [root, "side"]
