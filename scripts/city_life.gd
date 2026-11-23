class_name CityLife
extends Node3D
## v13.276 (owner: "populate the city with people", the way GTA does it: people only in a ring round you, made out of
## sight ahead and gone behind): the people of a city tile. A fixed pool of rigged characters (the crowd models, their
## own Walk / Idle clips, people-sized like a ship's crew) is reused: while you're near the city each one walks the
## pavement round a lot, now and then turns in at a building's street door and goes inside, while others step out of
## doors; a few stand about in the ground-floor rooms. Only blocks whose real blocks are standing get people (the
## ones round you); anyone further than CITY_PED_RANGE is taken back into the pool.

var space: Node
var planet_id := ""
var tile := -1
var pool: Array = []           # {node, anim, state: "off" | "walk" | "in" | "idle", path: [Vector2], y, speed, door}
var made := 0                  # (tests) people placed so far
var entered := 0               # (tests) people who went in at a door
var came_out := 0              # (tests) people who came out of one
var _models: Array = []        # [PackedScene, height (model units), aabb]
var _spawn_t := 0.0

func setup(sp: Node, pid: String, t: int) -> void:
	space = sp
	planet_id = pid
	tile = t
	name = "CityLife"

func _ready_models() -> bool:
	if not _models.is_empty(): return true
	if not Packs.is_ready(Crowd3D.PACK):
		Packs.request(Crowd3D.PACK)
		return false
	for m in Data.CITY_PED_MODELS:
		var path := "res://assets/crowd3d/%s.glb" % m
		if not ResourceLoader.exists(path): continue
		var ps: PackedScene = load(path)
		var probe: Node3D = ps.instantiate()
		var bb := PilotRig._aabb(probe)
		probe.free()
		_models.append([ps, bb])
	if _models.is_empty(): return false
	for i in Data.CITY_PEDS:   # the pool: made once, reused (no hitch while you fly about)
		var md: Array = _models[i % _models.size()]
		var inst: Node3D = (md[0] as PackedScene).instantiate()
		var bb: AABB = md[1]
		var k := Data.SHIP_PILOT_H / maxf(0.01, bb.size.y)
		inst.scale = Vector3.ONE * k
		inst.position = Vector3(-bb.get_center().x * k, -bb.position.y * k, -bb.get_center().z * k)
		inst.rotation.y = PI / 2 if bb.size.z > bb.size.x * 1.3 else PI   # (the models face +Z: turned to look down -Z)
		var holder := Node3D.new()
		holder.name = "Person%d" % i
		holder.add_child(inst)
		holder.visible = false
		add_child(holder)
		var ap: AnimationPlayer = null
		for a in inst.find_children("*", "AnimationPlayer", true, false):
			ap = a
			for an in ap.get_animation_list(): ap.get_animation(an).loop_mode = Animation.LOOP_LINEAR
			break
		pool.append({"node": holder, "anim": ap, "state": "off", "path": [], "y": 0.0, "speed": 0.0})
	return true

func _clip(p: Dictionary, clip: String) -> void:
	var ap: AnimationPlayer = p["anim"]
	if ap == null: return
	for a in ap.get_animation_list():
		if str(a).to_lower().ends_with(clip.to_lower()):
			if ap.current_animation != a: ap.play(a, 0.25)
			return

## The city blocks standing round you (their real blocks built): [region].
func _live_regions() -> Array:
	var out: Array = []
	var cr := CityPlan.rect(planet_id, tile)
	for rz in cr.size.y:
		for rx in cr.size.x:
			var r := cr.position + Vector2i(rx, rz)
			var k := Vector4i(0, 0, r.x, r.y)
			if space._regions.has(k) and is_instance_valid(space._regions[k]) and (space._regions[k] as BlockField).built: out.append(r)
	return out

func tick(dt: float) -> void:
	if not _ready_models(): return
	var pp: Vector3 = space.player.global_position
	var g := CityPlan.ground(planet_id, tile)
	var live := _live_regions()
	var near: bool = not live.is_empty() and pp.y < g + Data.CITY_PED_ALT
	for p in pool:   # move everyone, and take back anyone too far away
		if p["state"] == "off": continue
		var n: Node3D = p["node"]
		if not near or Vector2(n.position.x - pp.x, n.position.z - pp.z).length() > Data.CITY_PED_RANGE + 60.0:
			_off(p)
			continue
		_move(p, dt)
	if not near: return
	_spawn_t -= dt
	if _spawn_t > 0.0: return
	_spawn_t = 0.25   # (a few a second, until the ring is full)
	for p in pool:
		if p["state"] == "off":
			_spawn(p, live, pp, g)
			break

func _off(p: Dictionary) -> void:
	p["state"] = "off"
	(p["node"] as Node3D).visible = false
	var ap: AnimationPlayer = p["anim"]
	if ap != null: ap.stop()

## Somewhere near you on a live block: walking a lot's pavement, out of a door, or standing in a ground-floor room.
func _spawn(p: Dictionary, live: Array, pp: Vector3, g: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var cands: Array = []
	for r in live:
		var plan := CityPlan.block(planet_id, tile, r)
		for lot in plan["lots"]: cands.append([r, lot, plan])
	if cands.is_empty(): return
	cands.shuffle()
	for c in cands:
		var r: Vector2i = c[0]
		var lot: Rect2i = c[1]
		var plan: Dictionary = c[2]
		var ring := _ring(r, lot)
		var mid: Vector2 = (ring[0] + ring[2]) * 0.5
		if mid.distance_to(Vector2(pp.x, pp.z)) > Data.CITY_PED_RANGE: continue
		var roll := rng.randf()
		var n: Node3D = p["node"]
		p["y"] = g
		p["speed"] = rng.randf_range(1.3, 1.9) * Data.SHIP_PILOT_H / 1.8 * 0.5
		if roll < Data.CITY_PED_INDOORS:   # standing about in a ground-floor room
			var bs: Array = plan["buildings"]
			var b: Dictionary = bs[rng.randi() % bs.size()]
			var rooms: Array = (b["rooms"] as Dictionary).keys().filter(func(q): return int(b["cells"].get(q, 0)) >= 1)
			if rooms.is_empty(): continue
			var q: Vector2i = rooms[rng.randi() % rooms.size()]
			n.position = Vector3(CityPlan.cell_pos(r, Vector2(q)).x, g, CityPlan.cell_pos(r, Vector2(q)).y)
			n.rotation.y = rng.randf() * TAU
			p["state"] = "idle"
			p["path"] = []
			_clip(p, "Idle")
		else:
			var start: int = rng.randi() % 4
			var t := rng.randf()
			var a: Vector2 = ring[start]
			var b2: Vector2 = ring[(start + 1) % 4]
			var at: Vector2 = a.lerp(b2, t)
			var dir := 1 if rng.randf() < 0.5 else -1
			var path: Array = []
			for k in 4: path.append(ring[posmod(start + (k + 1 if dir > 0 else -k), 4)])
			var door := _door_near(plan, r, lot, rng)
			if roll < Data.CITY_PED_INDOORS + Data.CITY_PED_OUT_OF_DOOR and not door.is_empty():   # stepping out of a door
				at = door[0]
				path = [door[1]] + path
				came_out += 1
			elif not door.is_empty() and rng.randf() < Data.CITY_PED_GO_IN:   # will turn in at a door later
				path.append(door[1])
				path.append(door[0])
				p["door"] = true
			n.position = Vector3(at.x, g, at.y)
			p["path"] = path
			var loop: Array = []
			for k in 4: loop.append(ring[posmod(start + (k + 1 if dir > 0 else -k), 4)])
			p["loop"] = loop
			p["state"] = "walk"
			_clip(p, "Walk")
		n.visible = true
		made += 1
		return

## A lot's pavement loop (the ring one cell in from its edge), its four corners, tile-local.
func _ring(r: Vector2i, lot: Rect2i) -> Array:
	var x0 := float(lot.position.x + 1)
	var z0 := float(lot.position.y + 1)
	var x1 := float(lot.end.x - 2)
	var z1 := float(lot.end.y - 2)
	return [CityPlan.cell_pos(r, Vector2(x0, z0)), CityPlan.cell_pos(r, Vector2(x1, z0)), CityPlan.cell_pos(r, Vector2(x1, z1)), CityPlan.cell_pos(r, Vector2(x0, z1))]

## A street door of a building on this lot: [inside the door, out on the pavement in front of it] ([] if none).
func _door_near(plan: Dictionary, r: Vector2i, lot: Rect2i, rng: RandomNumberGenerator) -> Array:
	var opts: Array = []
	for b in plan["buildings"]:
		var at: Vector2i = b["at"]
		if not lot.has_point(at): continue
		var doors: Array = b["door"]
		var outs: Array = b.get("door_out", [])
		for i in doors.size():
			if i < outs.size() and outs[i] != Vector2i.ZERO: opts.append([doors[i], outs[i]])
	if opts.is_empty(): return []
	var o: Array = opts[rng.randi() % opts.size()]
	var dc: Vector2i = o[0]
	var od: Vector2i = o[1]
	var inside: Vector2 = CityPlan.cell_pos(r, Vector2(dc - od))
	var front: Vector2 = CityPlan.cell_pos(r, Vector2(dc + od))
	return [inside, front]

func _move(p: Dictionary, dt: float) -> void:
	var n: Node3D = p["node"]
	if p["state"] == "idle": return
	var path: Array = p["path"]
	if path.is_empty():
		if bool(p.get("door", false)):   # went in at the door: gone inside
			p["door"] = false
			entered += 1
			_off(p)
			return
		p["path"] = (p.get("loop", []) as Array).duplicate()
		if (p["path"] as Array).is_empty():
			p["state"] = "idle"
			_clip(p, "Idle")
		return
	var to: Vector2 = path[0]
	var here := Vector2(n.position.x, n.position.z)
	var d := to - here
	var step := float(p["speed"]) * dt
	if d.length() <= step:
		n.position = Vector3(to.x, float(p["y"]), to.y)
		path.pop_front()
		if path.is_empty() and not bool(p.get("door", false)):   # round the block again
			p["path"] = (p.get("loop", []) as Array).duplicate()
		return
	var v := d.normalized() * step
	n.position += Vector3(v.x, 0.0, v.y)
	n.position.y = float(p["y"])
	n.rotation.y = atan2(-d.x, -d.y)

func active() -> int:
	return pool.filter(func(p): return p["state"] != "off").size()
