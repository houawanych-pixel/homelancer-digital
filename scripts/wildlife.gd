class_name Wildlife
extends Node3D
## v12.28 (owner: "how do the animals work? ... the sheep or the deer", alien versions): wildlife on a planet's ground.
## Like Minecraft's animals they are not blocks: shaped models with a simple brain, that appear round the player and go
## when you are far away, so they cost little.
## v12.41 (owner: planet fauna - "sheep, deer, bear, giant worm", original alien animals with clear roles;
## docs/WILDLIFE.md): every species is a data profile (Data.WILDLIFE) with an archetype that picks its brain:
##   grazer   - graze / roam -> alert (head up) -> flee with the herd                    (Mossfleece, Drift woolly, Glow grazer)
##   prey     - graze -> alert (tail flag warns the herd) -> bolt                          (Strider, Prismhart, Hopper)
##   predator - patrol -> warn (jaws open / rears, back off and it stops) -> attack -> give up past its territory -> return
##              (Grumbark, Vexmaw, Shale stalker); they also hunt the prey animals when you're not about
##   burrower - under the ground -> ripple (a sand wake towards you) -> telegraph (a shaking ring, 1.5 s) -> emerge (a bite
##              in the ring only) -> exposed (4 s) -> re-burrow                            (Sandmaw)
##   giant    - roam -> threat display -> charge -> ground slam (a shock ring: jump or dash it) / ice throw at range (Rimeback)
## Nothing kills you outright; everything gives up at the edge of its territory and keeps away from bases and pads.
## Shots near an animal hurt it (Data.WILDLIFE_DMG): hunters turn on you, the rest scatter.

var space: Node   # the SpaceSystem (for the ground height, the player and the hits)
var animals: Array = []   # [{kind, spec, node, legs, head, jaw, arms, tail, extra, vel, target, state, t, phase, home, hp, cd, ...}]
var _spawn_t := 0.0
var _rng := RandomNumberGenerator.new()
var fled := 0   # (tests)
var test_park := false   # the wildlife test area: every species at fixed spots, nothing spawned by biome
var park_c := Vector3.INF
var events: Array = []   # (tests) "warn:vexmaw", "attack:grumbark", "emerge:sandmaw", "slam:rimeback", "hit:...", "gave_up:..."
var hits := 0   # (tests) how often the animals hit the player
var _fx: Array = []   # rings, shock waves, ice chunks: [{node, kind, t, life, ...}]
var _told := {}   # (the test area) one note per animal on what it's doing

func _ready() -> void:
	name = "Wildlife"
	_rng.randomize()

func _note(ev: String) -> void:
	events.append(ev)
	if events.size() > 200: events.pop_front()

## Every frame on the surface: spawn near the player, run the brains, drop the far ones.
func tick(dt: float, player_pos: Vector3, kind_of_ground: String) -> void:
	_spawn_t -= dt
	if test_park:
		if park_c == Vector3.INF:
			park_c = player_pos
			_build_park()
	elif _spawn_t <= 0.0:
		_spawn_t = 0.7
		for i in range(animals.size() - 1, -1, -1):   # gone when far away
			var a: Dictionary = animals[i]
			var ap: Vector3 = (a["node"] as Node3D).global_position if is_instance_valid(a["node"]) else Vector3.INF
			if ap == Vector3.INF or Vector2(ap.x - player_pos.x, ap.z - player_pos.z).length() > Data.WILDLIFE_DESPAWN:   # (across the ground: flying high doesn't clear them)
				if is_instance_valid(a["node"]): (a["node"] as Node).queue_free()
				animals.remove_at(i)
		var cfg: Dictionary = Data.WILDLIFE_BIOMES.get(kind_of_ground, {})
		if not cfg.is_empty() and animals.size() < int(cfg.get("max", 0)):
			_spawn_group(player_pos, cfg)
	for a in animals: _think(a, dt, player_pos)
	_update_fx(dt, player_pos)

func count_of(kind: String) -> int:
	var n := 0
	for a in animals: if a["kind"] == kind: n += 1
	return n

## Not too near a base / facility / the floating pad island: nothing spawns there and hunters stop at the edge.
var _pads: Array = []   # (worked out once: the bases / facilities near by, as x/z)
var _pads_done := false
func near_pad(p: Vector3) -> bool:
	if space == null or not space.has_method("base_spots"): return false
	if not _pads_done:
		_pads_done = true
		for sp in space.base_spots() + space.facility_spots():
			var q: Vector3 = sp["pos"]
			_pads.append(Vector2(q.x, q.z))
	for q in _pads:
		if Vector2(q.x - p.x, q.y - p.z).length() < Data.WILDLIFE_PAD_CLEAR: return true
	return not Surface.island_at(space.planet_id, space.tile, p.x, p.z).is_empty()

func _ground_ok(kind: String, c: Vector3) -> bool:
	var spec: Dictionary = Data.WILDLIFE[kind]
	var f: BlockField = space._block_field_at(c.x, c.z)
	if f == null: return false
	match str(spec.get("ground", "grass")):
		"grass": return f.grass_at(c.x, c.z, false)
		"flowers": return f.grass_at(c.x, c.z, true)
		_: return space._ground(c.x, c.z) > 1.0   # any dry land
	return false

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
	if spec.has("cap") and count_of(kind) >= int(spec["cap"]): return
	# somewhere between the near and far rings round the player, on its kind of ground, away from pads
	for tries in 20:
		var ang := _rng.randf() * TAU
		var d := _rng.randf_range(Data.WILDLIFE_SPAWN[0], Data.WILDLIFE_SPAWN[1])
		var c := pp + Vector3(cos(ang), 0, sin(ang)) * d
		if not _ground_ok(kind, c) or near_pad(c): continue
		var herd := _rng.randi_range(int(spec["herd"][0]), int(spec["herd"][1]))
		for i in herd:
			var p := c + Vector3(_rng.randf_range(-12, 12), 0, _rng.randf_range(-12, 12))
			_add(kind, p, c)
		return

## The test area: every species at its spot round the landing point (Data.WILDLIFE_PARK).
func _build_park() -> void:
	for row in Data.WILDLIFE_PARK:
		_park_group(str(row[0]), float(row[1]), float(row[2]), int(row[3]))

func _park_group(kind: String, ang_deg: float, dist: float, n: int) -> void:
	var a := deg_to_rad(ang_deg)
	var c := park_c + Vector3(cos(a), 0, sin(a)) * dist
	for i in n:
		_add(kind, c + Vector3(_rng.randf_range(-10, 10), 0, _rng.randf_range(-10, 10)) if n > 1 else c, c)

func _add(kind: String, p: Vector3, home: Vector3) -> Dictionary:
	var spec: Dictionary = Data.WILDLIFE[kind]
	var root := Node3D.new()
	root.name = "Animal_" + kind
	add_child(root)
	var parts := _build(str(spec.get("model", kind)), root, spec)
	var s: float = float(spec["size"]) * _rng.randf_range(0.9, 1.1)
	root.scale = Vector3.ONE * s
	p.y = space._ground(p.x, p.z)
	root.global_position = p
	root.rotation.y = _rng.randf() * TAU
	if Data.WILDLIFE_SHADOWLESS: for mi in root.find_children("*", "MeshInstance3D", true, false): (mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var a := {"kind": kind, "spec": spec, "arch": str(spec.get("arch", "grazer")), "node": root, "legs": parts["legs"], "head": parts["head"],
		"jaw": parts.get("jaw"), "arms": parts.get("arms", []), "tail": parts.get("tail"), "extra": parts.get("extra", []),
		"vel": Vector3.ZERO, "target": p, "state": "graze", "t": _rng.randf_range(1.0, 4.0), "phase": _rng.randf() * TAU, "hop": 0.0,
		"home": home, "hp": float(spec.get("hp", 50.0)), "cd": 0.0, "pose": 0.0, "size": s, "prey": null, "provoked": false}
	if a["arch"] == "burrower":
		a["state"] = "under"
		root.visible = false
		root.global_position.y = p.y - s * 1.2
	animals.append(a)
	return a

# ---------------------------------------------------------------- the brains
func _think(a: Dictionary, dt: float, pp: Vector3) -> void:
	var node: Node3D = a["node"]
	if not is_instance_valid(node): return
	a["t"] = float(a["t"]) - dt
	a["cd"] = maxf(0.0, float(a["cd"]) - dt)
	var dir := Vector3.ZERO
	var speed := 0.0
	match a["arch"]:
		"grazer", "prey":
			var r := _brain_prey(a, dt, pp)
			dir = r[0]
			speed = r[1]
		"predator":
			var r := _brain_predator(a, dt, pp)
			dir = r[0]
			speed = r[1]
		"giant":
			var r := _brain_giant(a, dt, pp)
			dir = r[0]
			speed = r[1]
		"burrower":
			_brain_burrower(a, dt, pp)
			return
	_move(a, dt, dir, speed)
	_animate(a, dt)

func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)

## The nearest threat to a prey animal: the player, or a hunter that is chasing it.
func _threat(a: Dictionary, pp: Vector3) -> Vector3:
	var pos: Vector3 = (a["node"] as Node3D).global_position
	var best := pp
	var bd := _flat(pp - pos).length()
	for h in animals:
		if h["arch"] != "predator" or h["state"] != "hunt" or not is_same(h["prey"], a) or not is_instance_valid(h["node"]): continue
		var d := _flat((h["node"] as Node3D).global_position - pos).length()
		if d < bd:
			bd = d
			best = (h["node"] as Node3D).global_position
	return best

## Grazers and prey: graze, wander, notice, alert (a strider flashes its tail flag to the herd), flee.
func _brain_prey(a: Dictionary, _dt: float, pp: Vector3) -> Array:
	var spec: Dictionary = a["spec"]
	var pos: Vector3 = (a["node"] as Node3D).global_position
	var th := _threat(a, pp)
	var away := _flat(pos - th)
	var dist := away.length()
	var st: String = a["state"]
	if st in ["graze", "wander"]:
		if dist < float(spec["flee"]):
			_start_flee(a)
		elif dist < float(spec.get("notice", spec["flee"])):
			a["state"] = "alert"
			a["t"] = float(spec.get("alert_t", 0.6))
			if spec.has("flag"): _alarm(pos, float(spec["flag"]), a)
	match a["state"]:
		"graze":
			if float(a["t"]) <= 0.0:
				a["state"] = "wander"
				a["t"] = _rng.randf_range(2.0, 5.0)
				a["target"] = pos + Vector3(_rng.randf_range(-30, 30), 0, _rng.randf_range(-30, 30))
		"wander":
			var to := _flat((a["target"] as Vector3) - pos)
			if to.length() < 3.0 or float(a["t"]) <= 0.0:
				a["state"] = "graze"
				a["t"] = _rng.randf_range(2.0, 6.0)
			else:
				return [to.normalized(), float(spec["walk"])]
		"alert":   # stand still, head up, face the threat
			_face(a, -away, 0.1)
			if float(a["t"]) <= 0.0: _start_flee(a)
			elif dist > float(spec.get("notice", 60.0)) * 1.2:
				a["state"] = "graze"
				a["t"] = 1.0
		"flee":
			var d := away.normalized() if dist > 0.1 else Vector3.FORWARD
			if a["arch"] == "grazer":   # the herd bunches up as it runs
				var mid := _herd_mid(a)
				if mid != Vector3.INF: d = (d + _flat(mid - pos).normalized() * 0.35).normalized()
			if a["arch"] == "prey" and a["kind"] != "hopper":   # zig-zag
				d = d.rotated(Vector3.UP, sin(float(a["phase"]) * 0.7) * 0.45)
			if float(a["t"]) <= 0.0 and dist > float(spec["flee"]) * 1.4:
				a["state"] = "graze"
				a["t"] = _rng.randf_range(1.0, 3.0)
			return [d, float(spec["run"])]
	return [Vector3.ZERO, 0.0]

func _start_flee(a: Dictionary) -> void:
	if a["state"] == "flee": return
	a["state"] = "flee"
	a["t"] = _rng.randf_range(2.5, 4.0)
	fled += 1

## A strider's tail flag: every grazer / prey animal round it goes on alert too.
func _alarm(at: Vector3, r: float, from: Dictionary) -> void:
	_note("flag:" + str(from["kind"]))
	for b in animals:
		if is_same(b, from) or not (b["arch"] in ["grazer", "prey"]) or not is_instance_valid(b["node"]): continue
		if _flat((b["node"] as Node3D).global_position - at).length() < r and b["state"] in ["graze", "wander"]:
			b["state"] = "alert"
			b["t"] = 0.3

func _herd_mid(a: Dictionary) -> Vector3:
	var sum := Vector3.ZERO
	var n := 0
	var pos: Vector3 = (a["node"] as Node3D).global_position
	for b in animals:
		if is_same(b, a) or b["kind"] != a["kind"] or not is_instance_valid(b["node"]): continue
		var q: Vector3 = (b["node"] as Node3D).global_position
		if _flat(q - pos).length() < 50.0:
			sum += q
			n += 1
	return sum / n if n > 0 else Vector3.INF

## Hunters: patrol their ground, warn you once, attack if you stay (or shoot), give up past the edge, go home.
func _brain_predator(a: Dictionary, _dt: float, pp: Vector3) -> Array:
	var spec: Dictionary = a["spec"]
	var pos: Vector3 = (a["node"] as Node3D).global_position
	var home: Vector3 = a["home"]
	var to_p := _flat(pp - pos)
	var dist := to_p.length()
	var p_in := _flat(pp - home).length() < float(spec["territory"]) and not near_pad(pp)
	match a["state"]:
		"graze", "wander", "patrol":
			if p_in and dist < float(spec["notice"]):
				if a["provoked"]: _start_attack(a)
				else:
					a["state"] = "warn"
					a["t"] = float(spec["warn_t"])
					_note("warn:" + str(a["kind"]))
					_tell(a, "%s is warning you - back off" % spec["name"])
				return [Vector3.ZERO, 0.0]
			if spec.get("hunts", false) and float(a["t"]) <= 0.0 and _rng.randf() < 0.3:   # go after a prey animal near by
				var pr := _near_prey(a, 90.0)
				if not pr.is_empty():
					a["prey"] = pr
					a["state"] = "hunt"
					a["t"] = 12.0
					_note("hunt:" + str(a["kind"]))
					return [Vector3.ZERO, 0.0]
			if a["state"] != "patrol" or float(a["t"]) <= 0.0 or _flat((a["target"] as Vector3) - pos).length() < 4.0:
				a["state"] = "patrol"
				a["t"] = _rng.randf_range(4.0, 8.0)
				var ang := _rng.randf() * TAU
				a["target"] = home + Vector3(cos(ang), 0, sin(ang)) * _rng.randf_range(0.0, float(spec["territory"]) * 0.45)
			return [_flat((a["target"] as Vector3) - pos).normalized(), float(spec["walk"])]
		"warn":   # face you, jaws open / rear up; close in or stay and it attacks, back off and it stops
			_face(a, to_p, 0.15)
			if not p_in or dist > float(spec["notice"]) * 1.15:
				a["state"] = "patrol"
				a["t"] = 2.0
				_note("calm:" + str(a["kind"]))
			elif (float(a["t"]) <= 0.0 and spec.get("role", "predator") == "predator") or dist < float(spec["notice"]) * 0.45 or a["provoked"]:
				_start_attack(a)
			elif float(a["t"]) <= 0.0:   # (defense: keeps warning while you stand off)
				a["t"] = float(spec["warn_t"])
			return [Vector3.ZERO, 0.0]
		"attack":
			if not p_in or _flat(pos - home).length() > float(spec["territory"]) * 1.1:
				a["state"] = "return"
				a["provoked"] = false
				_note("gave_up:" + str(a["kind"]))
				_tell(a, "%s gave up and went home" % spec["name"])
				return [Vector3.ZERO, 0.0]
			if dist < float(spec["reach"]) * a["size"] / float(spec["size"]) + 2.0 and float(a["cd"]) <= 0.0:
				_bite(a, pp)
			var d := to_p.normalized() if dist > 0.1 else Vector3.ZERO
			if dist < float(spec["reach"]) * 0.6: d = d.rotated(Vector3.UP, PI * 0.5)   # circle round you between lunges
			return [d, float(spec["run"]) * (1.35 if float(a["cd"]) > float(spec["cd"]) * 0.75 else 1.0)]
		"hunt":   # chasing a prey animal (you can watch it)
			var pr: Dictionary = a["prey"] if a["prey"] is Dictionary else {}
			if p_in and dist < float(spec["notice"]) * 0.6:
				a["prey"] = null
				a["state"] = "warn"
				a["t"] = float(spec["warn_t"])
				_note("warn:" + str(a["kind"]))
				return [Vector3.ZERO, 0.0]
			if pr.is_empty() or not is_instance_valid(pr.get("node")) or float(a["t"]) <= 0.0 or _flat(pos - home).length() > float(spec["territory"]):
				a["prey"] = null
				a["state"] = "return"
				return [Vector3.ZERO, 0.0]
			var q: Vector3 = (pr["node"] as Node3D).global_position
			if _flat(q - pos).length() < float(spec["reach"]) + 2.0:
				_note("caught:" + str(a["kind"]) + ">" + str(pr["kind"]))
				_kill(pr)
				a["prey"] = null
				a["state"] = "return"
				return [Vector3.ZERO, 0.0]
			return [_flat(q - pos).normalized(), float(spec["run"])]
		"return":
			var back := _flat(home - pos)
			if back.length() < 8.0:
				a["state"] = "patrol"
				a["t"] = 1.0
				return [Vector3.ZERO, 0.0]
			if p_in and dist < float(spec["notice"]) * 0.4 and _flat(pos - home).length() < float(spec["territory"]) * 0.8:
				a["state"] = "warn"
				a["t"] = float(spec["warn_t"]) * 0.5
			return [back.normalized(), float(spec["walk"]) * 1.6]
	return [Vector3.ZERO, 0.0]

func _start_attack(a: Dictionary) -> void:
	a["state"] = "attack"
	_note("attack:" + str(a["kind"]))

func _near_prey(a: Dictionary, r: float) -> Dictionary:
	var pos: Vector3 = (a["node"] as Node3D).global_position
	var best: Dictionary = {}
	var bd := r
	for b in animals:
		if not (b["arch"] in ["grazer", "prey"]) or not is_instance_valid(b["node"]): continue
		var d := _flat((b["node"] as Node3D).global_position - pos).length()
		if d < bd and _flat((b["node"] as Node3D).global_position - (a["home"] as Vector3)).length() < float(a["spec"]["territory"]):
			bd = d
			best = b
	return best

func _bite(a: Dictionary, pp: Vector3) -> void:
	var spec: Dictionary = a["spec"]
	a["cd"] = float(spec["cd"])
	a["pose"] = 1.0   # the lunge / swipe
	_note("hit:" + str(a["kind"]))
	_hit_player(float(spec["dmg"]), pp)

func _hit_player(dmg: float, at: Vector3) -> void:
	hits += 1
	if space and space.has_method("_player_hit"): space._player_hit(dmg, at)

## The snow giant: roams its peak, threat display, charges, slams the ground (a ring you can jump / dash), throws ice.
func _brain_giant(a: Dictionary, _dt: float, pp: Vector3) -> Array:
	var spec: Dictionary = a["spec"]
	var pos: Vector3 = (a["node"] as Node3D).global_position
	var home: Vector3 = a["home"]
	var to_p := _flat(pp - pos)
	var dist := to_p.length()
	var p_in := _flat(pp - home).length() < float(spec["territory"]) and not near_pad(pp)
	match a["state"]:
		"graze", "wander", "patrol":
			if p_in and dist < float(spec["notice"]):
				a["state"] = "warn"
				a["t"] = float(spec["warn_t"])
				_note("warn:" + str(a["kind"]))
				_tell(a, "%s is beating its chest - back off" % spec["name"])
				return [Vector3.ZERO, 0.0]
			if a["state"] != "patrol" or float(a["t"]) <= 0.0:
				a["state"] = "patrol"
				a["t"] = _rng.randf_range(5.0, 9.0)
				var ang := _rng.randf() * TAU
				a["target"] = home + Vector3(cos(ang), 0, sin(ang)) * _rng.randf_range(0.0, float(spec["territory"]) * 0.4)
			return [_flat((a["target"] as Vector3) - pos).normalized(), float(spec["walk"])]
		"warn":
			_face(a, to_p, 0.1)
			if not p_in or dist > float(spec["notice"]) * 1.15:
				a["state"] = "patrol"
				a["t"] = 2.0
				_note("calm:" + str(a["kind"]))
			elif (float(a["t"]) <= 0.0 and spec.get("role", "defense") == "predator") or a["provoked"] or dist < float(spec["notice"]) * 0.4:
				_start_attack(a)
			elif float(a["t"]) <= 0.0:   # (defense: keeps up the display while you stand off)
				a["t"] = float(spec["warn_t"])
			return [Vector3.ZERO, 0.0]
		"attack":
			if not p_in or _flat(pos - home).length() > float(spec["territory"]) * 1.1:
				a["state"] = "return"
				a["provoked"] = false
				_note("gave_up:" + str(a["kind"]))
				_tell(a, "%s gave up and went home" % spec["name"])
				return [Vector3.ZERO, 0.0]
			if a.get("slam_t", -1.0) >= 0.0:   # winding up the slam: stands still
				a["slam_t"] = float(a["slam_t"]) - _dt
				if float(a["slam_t"]) < 0.0: _slam(a, pp)
				return [Vector3.ZERO, 0.0]
			if dist < float(spec["reach"]) and float(a["cd"]) <= 0.0:
				a["slam_t"] = 0.55   # (the wind-up you can read)
				a["pose"] = 1.0
				return [Vector3.ZERO, 0.0]
			if dist > 45.0 and float(a["cd"]) <= 0.0 and _rng.randf() < 0.02:
				_throw(a, pp)
			return [to_p.normalized(), float(spec["run"])]
		"return":
			var back := _flat(home - pos)
			if back.length() < 10.0:
				a["state"] = "patrol"
				a["t"] = 1.0
			return [back.normalized(), float(spec["walk"]) * 1.4]
	return [Vector3.ZERO, 0.0]

func _slam(a: Dictionary, pp: Vector3) -> void:
	var spec: Dictionary = a["spec"]
	a["cd"] = float(spec["cd"])
	a["slam_t"] = -1.0
	var at: Vector3 = (a["node"] as Node3D).global_position + (a["node"] as Node3D).global_basis.z.normalized() * float(spec["reach"]) * 0.4
	_note("slam:" + str(a["kind"]))
	_ring(at, float(spec["slam_r"]), Color(0.65, 0.95, 1.0), 0.55, "shock")
	if space: space._spark(at, Color(0.85, 0.97, 1.0), 9.0, 0.5)
	var on_ground: bool = pp.y - space._ground(pp.x, pp.z) < 4.0   # (jump it and it misses)
	if on_ground and _flat(pp - at).length() < float(spec["slam_r"]):
		_note("hit:" + str(a["kind"]))
		_hit_player(float(spec["dmg"]), pp)

func _throw(a: Dictionary, pp: Vector3) -> void:
	var spec: Dictionary = a["spec"]
	a["cd"] = float(spec["cd"]) * 1.5
	a["pose"] = 0.8
	var from: Vector3 = (a["node"] as Node3D).global_position + Vector3(0, a["size"] * 0.9, 0)
	var mi := MeshInstance3D.new()
	mi.mesh = _rock_mesh()
	mi.material_override = _mat_ice()
	mi.scale = Vector3.ONE * 2.2
	add_child(mi)
	mi.global_position = from
	var tt := clampf(_flat(pp - from).length() / 40.0, 0.8, 2.2)   # flight time
	var v := (pp - from) / tt + Vector3(0, 9.8 * tt * 0.5, 0)
	_fx.append({"node": mi, "kind": "ice", "t": 0.0, "life": tt + 0.5, "vel": v, "dmg": float(spec["throw_dmg"])})
	_note("throw:" + str(a["kind"]))

## The giant burrower's cycle. It's a hidden mover until it telegraphs; the bite only lands inside the ring.
func _brain_burrower(a: Dictionary, dt: float, pp: Vector3) -> void:
	var spec: Dictionary = a["spec"]
	var node: Node3D = a["node"]
	var pos := node.global_position
	var home: Vector3 = a["home"]
	var s: float = a["size"]
	var p_in := _flat(pp - home).length() < float(spec["territory"]) and not near_pad(pp)
	var on_ground: bool = pp.y - space._ground(pp.x, pp.z) < 30.0   # (it hunts by footsteps: high flyers it can't feel)
	match a["state"]:
		"under":
			node.visible = false
			var goal := home
			var spd := float(spec["walk"])
			if p_in and on_ground and _flat(pp - pos).length() < float(spec["notice"]) and float(a["cd"]) <= 0.0:
				goal = pp
				spd = float(spec["run"])
				if a.get("rippling", false) == false:
					a["rippling"] = true
					_note("ripple:" + str(a["kind"]))
					_tell(a, "Something is moving under the sand...")
			else:
				a["rippling"] = false
			var to := _flat(goal - pos)
			if to.length() > 1.0:
				var step := to.normalized() * minf(spd * dt, to.length())
				pos += step
			pos.y = space._ground(pos.x, pos.z) - s * 1.2
			node.global_position = pos
			a["wake_t"] = float(a.get("wake_t", 0.0)) - dt
			if a["rippling"] and float(a["wake_t"]) <= 0.0:   # the sand wake: you see it coming
				a["wake_t"] = 0.12
				var gp := Vector3(pos.x, space._ground(pos.x, pos.z) + 0.5, pos.z)
				space._spark(gp + Vector3(_rng.randf_range(-3, 3), 0, _rng.randf_range(-3, 3)), Color(0.9, 0.75, 0.48), 4.5, 0.6)
			if a["rippling"] and _flat(pp - pos).length() < 6.0:
				a["state"] = "telegraph"
				a["t"] = float(spec["tele_t"])
				a["target"] = Vector3(pp.x, space._ground(pp.x, pp.z), pp.z)
				_note("telegraph:" + str(a["kind"]))
				_ring(a["target"], float(spec["ring"]), Color(1.0, 0.8, 0.35), float(spec["tele_t"]), "tele")
		"telegraph":   # the ring shakes for 1.5 s: get out of it
			var tg: Vector3 = a["target"]
			if _rng.randf() < 0.5: space._spark(tg + Vector3(_rng.randf_range(-1, 1), 0.5, _rng.randf_range(-1, 1)) * float(spec["ring"]) * 0.8, Color(0.95, 0.8, 0.5), 3.5, 0.4)
			if float(a["t"]) <= 0.0:
				a["state"] = "emerge"
				a["t"] = 0.35
				node.global_position = Vector3(tg.x, tg.y - s * 1.2, tg.z)
				node.rotation.y = _rng.randf() * TAU
				node.visible = true
				_note("emerge:" + str(a["kind"]))
				space._spark(tg + Vector3(0, 2, 0), Color(0.95, 0.8, 0.5), 14.0, 0.7)
				var ppf := _flat(pp - tg).length()
				if ppf < float(spec["ring"]) and pp.y - space._ground(pp.x, pp.z) < 8.0:
					_note("hit:" + str(a["kind"]))
					_hit_player(float(spec["dmg"]), pp)
		"emerge":
			var tg: Vector3 = a["target"]
			var k := clampf(1.0 - float(a["t"]) / 0.35, 0.0, 1.0)
			node.global_position = Vector3(tg.x, tg.y - s * 1.2 * (1.0 - ease(k, 0.4)), tg.z)
			if float(a["t"]) <= 0.0:
				a["state"] = "exposed"
				a["t"] = float(spec["exposed_t"])
				_tell(a, "The Sandmaw is exposed - hit it now")
		"exposed":   # out of the sand, swaying, jaws open: the time to hit it
			var tg: Vector3 = a["target"]
			node.global_position = tg
			a["phase"] = float(a["phase"]) + dt
			node.rotation.z = sin(float(a["phase"]) * 1.6) * 0.08
			node.rotation.x = sin(float(a["phase"]) * 1.1) * 0.06
			if a["jaw"] != null: (a["jaw"] as Node3D).scale = Vector3.ONE * (1.0 + 0.25 * absf(sin(float(a["phase"]) * 2.0)))
			if float(a["t"]) <= 0.0:
				a["state"] = "reburrow"
				a["t"] = 0.8
				_note("reburrow:" + str(a["kind"]))
		"reburrow":
			var tg: Vector3 = a["target"]
			var k := clampf(1.0 - float(a["t"]) / 0.8, 0.0, 1.0)
			node.global_position = Vector3(tg.x, tg.y - s * 1.2 * k, tg.z)
			if float(a["t"]) <= 0.0:
				a["state"] = "under"
				a["cd"] = 3.0
				node.visible = false
				node.rotation = Vector3(0, node.rotation.y, 0)
				space._spark(tg + Vector3(0, 1, 0), Color(0.95, 0.8, 0.5), 10.0, 0.5)

func _tell(a: Dictionary, msg: String) -> void:
	if not test_park or _told.has(a["node"]) or space == null: return
	_told[a["node"]] = true
	space.message.emit(msg)

func _face(a: Dictionary, d: Vector3, k: float) -> void:
	if d.length() < 0.1: return
	var node: Node3D = a["node"]
	node.rotation.y = lerp_angle(node.rotation.y, atan2(d.x, d.z), k)

# ---------------------------------------------------------------- moving and the procedural animation
func _move(a: Dictionary, dt: float, dir: Vector3, speed: float) -> void:
	var node: Node3D = a["node"]
	var spec: Dictionary = a["spec"]
	var pos := node.global_position
	var v: Vector3 = a["vel"]
	v = v.lerp(dir * speed, minf(1.0, dt * 3.0))
	a["vel"] = v
	var np := pos + v * dt
	if a["arch"] in ["predator", "giant"] and near_pad(np) and not near_pad(pos):   # they stop at a base's edge
		np = pos
		a["vel"] = -v * 0.3
	var gy: float = space._ground(np.x, np.z)
	if gy > pos.y + 6.0 and not (a["arch"] in ["predator", "giant"]):   # a wall: turn back (hunters and giants scramble up anything)
		a["vel"] = -v * 0.5
		a["target"] = pos - v
		np = pos
		gy = pos.y
	var hopping: bool = a["kind"] == "hopper" and v.length() > 0.5
	if hopping:
		a["hop"] = fmod(float(a["hop"]) + dt * 3.2, 1.0)
		gy += sin(float(a["hop"]) * PI) * float(spec["size"]) * 1.6
	np.y = lerpf(pos.y, gy, minf(1.0, dt * 10.0)) if not hopping else gy
	node.global_position = np
	if v.length() > 0.3 and a["state"] != "alert" and a["state"] != "warn":
		node.rotation.y = lerp_angle(node.rotation.y, atan2(v.x, v.z), minf(1.0, dt * 6.0))   # (the models face +z)

func _animate(a: Dictionary, dt: float) -> void:
	var node: Node3D = a["node"]
	var spec: Dictionary = a["spec"]
	var v: Vector3 = a["vel"]
	var st: String = a["state"]
	a["phase"] = float(a["phase"]) + dt * (2.0 + v.length() * 0.9 / maxf(1.0, float(a["size"]) * 0.25))
	a["pose"] = maxf(0.0, float(a["pose"]) - dt * 2.2)
	var swing := clampf(v.length() / maxf(1.0, float(spec["run"])), 0.0, 1.0) * 0.9 + 0.05
	var legs: Array = a["legs"]
	for i in legs.size():
		var lg: Node3D = legs[i]
		var off := PI * float(i % 2) + (PI * 0.66 * float(i / 2) if legs.size() == 6 else 0.0)   # (six legs: a tripod gait)
		lg.rotation.x = sin(float(a["phase"]) * 2.0 + off) * swing
	var warn: bool = st == "warn"
	var head: Node3D = a["head"]
	if head != null:
		var dip := 0.5 if st == "graze" else (-0.25 if st == "alert" else 0.0)
		head.rotation.x = lerpf(head.rotation.x, dip + sin(float(a["phase"]) * 0.7) * 0.08 - float(a["pose"]) * 0.3, minf(1.0, dt * 4.0))
	if a["jaw"] != null:   # jaws open to warn and to bite
		var jo := 0.55 if warn else (0.7 * float(a["pose"]) + (0.15 if st == "attack" else 0.0))
		(a["jaw"] as Node3D).rotation.x = lerpf((a["jaw"] as Node3D).rotation.x, jo, minf(1.0, dt * 8.0))
	if a["tail"] != null:   # the strider's tail flag flicks up when it's alarmed
		var up := 1.0 if st in ["alert", "flee"] else 0.0
		(a["tail"] as Node3D).rotation.x = lerpf((a["tail"] as Node3D).rotation.x, -1.2 * up, minf(1.0, dt * 8.0))
	for e in a["extra"]:   # spines up (warn), glow pulse
		if e is Node3D: (e as Node3D).scale = (e as Node3D).scale.lerp(Vector3.ONE * (1.35 if warn else 1.0), minf(1.0, dt * 6.0))
	var arms: Array = a["arms"]
	var rear := 0.0
	match a["arch"]:
		"giant":   # threat display: rears up, arms high, beating; a knuckle walk when it runs
			var up := 1.0 if warn or a.get("slam_t", -1.0) >= 0.0 else 0.0
			for i in arms.size():
				var sd := 1.0 if i == 0 else -1.0
				var arm: Node3D = arms[i]
				var walk := sin(float(a["phase"]) * 2.0 + PI * i) * swing * 0.8
				var beat := sin(float(a["phase"]) * 9.0) * 0.25 * up
				arm.rotation.x = lerpf(arm.rotation.x, walk * (1.0 - up) - 2.6 * up + beat, minf(1.0, dt * 6.0))
				arm.rotation.z = lerpf(arm.rotation.z, 0.5 * sd * up, minf(1.0, dt * 6.0))
			rear = -0.08 * up + 0.22 * swing * (1.0 - up)
		"predator":
			if a["kind"] == "grumbark" or a["spec"].get("model", "") == "grumbark":
				rear = -0.45 if warn else 0.0   # rears up on its hind legs
			else:
				rear = 0.12 if warn else -0.1 * float(a["pose"])   # head low, coiled
	node.rotation.x = lerpf(node.rotation.x, rear, minf(1.0, dt * 4.0))

# ---------------------------------------------------------------- hits from the player
## A shot / blast landed at `at` (space._blast_blocks): animals near it get hurt; hunters turn on you, others scatter.
func on_blast(at: Vector3, kind: String) -> void:
	var r: float = (Data.BLOCK_BLAST.get(kind, Data.BLOCK_BLAST["gun"]) as Array)[0]
	var dmg: float = float(Data.WILDLIFE_DMG.get(kind, 10.0))
	for a in animals.duplicate():
		var node: Node3D = a["node"]
		if not is_instance_valid(node): continue
		if a["arch"] == "burrower" and a["state"] == "under": continue
		var c := node.global_position + Vector3(0, float(a["size"]) * 0.5, 0)
		var d := c.distance_to(at)
		var reach := r + float(a["size"]) * 0.6
		if d < reach:
			a["hp"] = float(a["hp"]) - dmg * (2.0 if a["state"] == "exposed" else 1.0)
			a["provoked"] = true
			_note("hurt:" + str(a["kind"]))
			if float(a["hp"]) <= 0.0:
				_kill(a)
				continue
			if a["arch"] in ["predator", "giant"] and a["state"] != "attack": _start_attack(a)
		if d < 60.0 and a["arch"] in ["grazer", "prey"]:
			_start_flee(a)

func _kill(a: Dictionary) -> void:
	var node: Node3D = a["node"]
	if is_instance_valid(node):
		if space: space._spark(node.global_position + Vector3(0, float(a["size"]) * 0.5, 0), Color(1.0, 0.85, 0.6), float(a["size"]) * 0.8, 0.5)
		node.queue_free()
	_note("down:" + str(a["kind"]))
	animals.erase(a)
	if test_park:   # the test area keeps everyone: back after a while
		var row: Array = []
		for r in Data.WILDLIFE_PARK: if r[0] == a["kind"]: row = r
		if not row.is_empty():
			get_tree().create_timer(20.0).timeout.connect(func():
				if is_instance_valid(self): _park_group(str(row[0]), float(row[1]), float(row[2]), 1))

# ---------------------------------------------------------------- effects: rings, shock waves, ice chunks
func _ring(at: Vector3, r: float, col: Color, life: float, kind: String) -> void:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.9
	tm.outer_radius = 1.0
	tm.rings = 32
	tm.ring_segments = 6
	mi.mesh = tm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = at + Vector3(0, 0.6, 0)
	mi.scale = Vector3(r, r * 0.6, r) if kind == "tele" else Vector3(1, 1, 1)
	_fx.append({"node": mi, "kind": kind, "t": 0.0, "life": life, "r": r, "mat": m})

func _update_fx(dt: float, pp: Vector3) -> void:
	for i in range(_fx.size() - 1, -1, -1):
		var e: Dictionary = _fx[i]
		var n: Node3D = e["node"]
		e["t"] = float(e["t"]) + dt
		var k := float(e["t"]) / float(e["life"])
		if not is_instance_valid(n) or k >= 1.0:
			if is_instance_valid(n): n.queue_free()
			_fx.remove_at(i)
			continue
		match e["kind"]:
			"tele":   # pulses faster as it's about to burst
				var m: StandardMaterial3D = e["mat"]
				m.albedo_color.a = 0.45 + 0.45 * absf(sin(float(e["t"]) * (6.0 + 14.0 * k)))
				n.scale = Vector3(e["r"], float(e["r"]) * 0.6, e["r"]) * (1.0 + 0.05 * sin(float(e["t"]) * 30.0))
			"shock":
				var rr: float = lerpf(2.0, float(e["r"]), ease(k, 0.5))
				n.scale = Vector3(rr, 1.5, rr)
				(e["mat"] as StandardMaterial3D).albedo_color.a = 1.0 - k
			"ice":
				var v: Vector3 = e["vel"]
				v.y -= 9.8 * dt
				e["vel"] = v
				n.global_position += v * dt
				n.rotate_x(dt * 3.0)
				if n.global_position.distance_to(pp) < 7.0:
					_note("hit:ice")
					_hit_player(float(e["dmg"]), pp)
					space._spark(n.global_position, Color(0.8, 0.95, 1.0), 5.0, 0.4)
					e["t"] = e["life"]
				elif n.global_position.y < space._ground(n.global_position.x, n.global_position.z):
					space._spark(n.global_position, Color(0.8, 0.95, 1.0), 6.0, 0.4)
					e["t"] = e["life"]

static func _rock_mesh() -> ArrayMesh:
	var rings: Array = []
	for i in 6:
		var t := float(i) / 5.0
		var r := sin(t * PI) * 0.6 * (1.0 + 0.2 * sin(t * 11.0)) + 0.02
		rings.append([-0.5 + t, 0.0, r, r * 0.8, Color(0.75, 0.92, 1.0)])
	return _loft(rings, 6)

static var _ice_m: StandardMaterial3D
static func _mat_ice() -> StandardMaterial3D:
	if _ice_m == null:
		_ice_m = StandardMaterial3D.new()
		_ice_m.vertex_color_use_as_albedo = true
		_ice_m.emission_enabled = true
		_ice_m.emission = Color(0.4, 0.8, 1.0)
		_ice_m.emission_energy_multiplier = 0.6
	return _ice_m

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
	if Data.WILDLIFE_TOON:   # the anime look: flat cel bands and a dark ink outline (an inverted hull)
		m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
		m.specular_mode = BaseMaterial3D.SPECULAR_TOON
		var ink := StandardMaterial3D.new()
		ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ink.albedo_color = Color(0.08, 0.05, 0.11)
		ink.cull_mode = BaseMaterial3D.CULL_FRONT
		ink.grow = true
		ink.grow_amount = 0.012
		m.next_pass = ink
	_mat_cache[key] = m
	return m

func _piece(parent: Node3D, mesh: ArrayMesh, at: Vector3, glow := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(glow)
	mi.position = at
	parent.add_child(mi)
	return mi

static func _c(spec: Dictionary, key: String, def: Color) -> Color:
	return spec.get("col", {}).get(key, def)

## Each model is about 1 unit tall before the animal's own size scales it. Returns its moving parts.
func _build(kind: String, root: Node3D, spec: Dictionary = {}) -> Dictionary:
	var legs: Array = []
	var head := Node3D.new()
	var out := {}
	match kind:
		"strider":   # the six-legged deer: a long lean body, a raised neck, a slim head with branching antlers
			var hide := _c(spec, "hide", Color(0.62, 0.45, 0.3))
			var belly := _c(spec, "belly", Color(0.85, 0.78, 0.62))
			var stripe := _c(spec, "stripe", Color(0.25, 0.55, 0.6))
			var antler := _c(spec, "antler", Color(0.9, 0.95, 1.0))
			_piece(root, _loft([[-0.55, 0.62, 0.05, 0.05, hide], [-0.45, 0.66, 0.13, 0.15, stripe], [-0.1, 0.68, 0.17, 0.18, hide], [0.2, 0.7, 0.16, 0.17, stripe], [0.45, 0.74, 0.12, 0.14, hide], [0.5, 0.78, 0.06, 0.06, belly]]), Vector3.ZERO)
			head.position = Vector3(0, 0.78, 0.48)
			root.add_child(head)
			_piece(head, _loft([[0.0, 0.0, 0.07, 0.07, hide], [0.08, 0.2, 0.06, 0.06, hide], [0.14, 0.34, 0.05, 0.05, hide]], 8), Vector3.ZERO)   # the neck, up and forward
			_piece(head, _loft([[0.08, 0.36, 0.06, 0.07, hide], [0.2, 0.38, 0.06, 0.06, hide], [0.32, 0.35, 0.03, 0.035, belly]], 8), Vector3.ZERO)   # the head
			if spec.get("crystal", false):   # Prismhart: faceted crystal shards instead of antlers
				for sd in [-1.0, 1.0]:
					var base := Vector3(0.035 * sd, 0.42, 0.12)
					for tip in [base + Vector3(0.05 * sd, 0.3, -0.02), base + Vector3(0.12 * sd, 0.2, 0.0), base + Vector3(0.02 * sd, 0.24, -0.1)]:
						_piece(head, _stick(base, tip, 0.04, antler), Vector3.ZERO, true)
			else:
				for sd in [-1.0, 1.0]:   # antlers: a stem forking in two, then two again
					var base := Vector3(0.035 * sd, 0.42, 0.12)
					var a1 := base + Vector3(0.06 * sd, 0.16, -0.04)
					for tip in [a1 + Vector3(0.08 * sd, 0.1, 0.03), a1 + Vector3(0.0, 0.14, -0.06), a1 + Vector3(0.1 * sd, 0.02, -0.08)]:
						_piece(head, _stick(a1, tip, 0.012, antler), Vector3.ZERO, true)
					_piece(head, _stick(base, a1, 0.018, antler.darkened(0.05)), Vector3.ZERO)
			var tail := Node3D.new()   # the white tail flag (flicks up to warn the herd)
			tail.position = Vector3(0, 0.66, -0.52)
			root.add_child(tail)
			_piece(tail, _loft([[0.0, 0.0, 0.04, 0.04, belly], [-0.12, 0.02, 0.05, 0.03, Color(1, 1, 1)], [-0.22, 0.0, 0.01, 0.01, Color(1, 1, 1)]], 6), Vector3.ZERO, true)
			out["tail"] = tail
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
		"mossfleece":   # the woolly grazer: a lumpy cloud of wool, a moss saddle with glowing spores, a long dark face, curled horns
			var wool := _c(spec, "wool", Color(0.94, 0.89, 0.81))
			var wool2 := wool.darkened(0.12).lerp(Color(0.72, 0.66, 0.8), 0.3)
			var skin := _c(spec, "skin", Color(0.29, 0.23, 0.39))
			var moss := _c(spec, "moss", Color(0.47, 0.79, 0.37))
			var horn := _c(spec, "horn", Color(0.85, 0.81, 0.91))
			var rings: Array = []
			for i in 11:
				var t := float(i) / 10.0
				var r := sin(t * PI) * 0.5 * (1.0 + 0.1 * sin(t * 31.0)) + 0.03
				rings.append([-0.55 + t * 1.1, 0.62, r, r * 0.82, wool if i % 2 == 0 else wool2])
			_piece(root, _loft(rings, 14), Vector3.ZERO)
			_piece(root, _loft([[-0.32, 0.0, 0.02, 0.01, moss], [-0.2, 0.02, 0.24, 0.06, moss], [0.1, 0.03, 0.26, 0.07, moss.darkened(0.1)], [0.32, 0.0, 0.03, 0.01, moss]], 10), Vector3(0, 0.98, 0))
			for k in 6:
				var sp := _loft([[-0.025, 0.0, 0.0, 0.0, Color(0.85, 1.0, 0.5)], [0.0, 0.0, 0.03, 0.03, Color(0.85, 1.0, 0.5)], [0.025, 0.0, 0.0, 0.0, Color(0.85, 1.0, 0.5)]], 5)
				_piece(root, sp, Vector3(sin(k * 2.1) * 0.15, 1.07, -0.25 + 0.1 * k), true)
			head.position = Vector3(0, 0.78, 0.5)
			root.add_child(head)
			_piece(head, _loft([[-0.05, 0.02, 0.13, 0.14, wool], [0.06, 0.0, 0.11, 0.12, skin], [0.2, -0.08, 0.08, 0.09, skin], [0.32, -0.18, 0.05, 0.05, skin.darkened(0.2)]], 10), Vector3.ZERO)
			for sd in [-1.0, 1.0]:
				var prev := Vector3(0.08 * sd, 0.08, 0.02)
				for k in 7:   # a curled horn: a spiral of short sticks
					var a := -0.6 + k * 0.85
					var rr := 0.12 * (1.0 - k * 0.1)
					var nxt := Vector3((0.1 + 0.02 * k) * sd, 0.1 + sin(a) * rr, 0.02 + cos(a) * rr - 0.06)
					_piece(head, _stick(prev, nxt, 0.035 - 0.003 * k, horn), Vector3.ZERO)
					prev = nxt
				_piece(head, _loft([[0.0, 0.0, 0.03, 0.01, moss], [-0.1, -0.08, 0.05, 0.012, moss], [-0.2, -0.2, 0.01, 0.01, moss]], 6), Vector3(0.1 * sd, 0.02, 0.06)).rotation.z = 0.3 * sd   # droopy leaf ears
			for i in 4:
				var pv := Node3D.new()
				pv.position = Vector3(0.22 * (1.0 if i % 2 == 0 else -1.0), 0.36, 0.28 if i < 2 else -0.28)
				root.add_child(pv)
				_piece(pv, _limb(0.36, 0.06, 0.045, skin, 0.08), Vector3.ZERO)
				legs.append(pv)
		"grumbark":   # the bear-like omnivore: a humped, shaggy body, bark plates growing down its back (with moss), a heavy head
			var fur := _c(spec, "fur", Color(0.42, 0.29, 0.21))
			var bark := _c(spec, "bark", Color(0.23, 0.17, 0.15))
			var moss := _c(spec, "moss", Color(0.5, 0.75, 0.35))
			var muzzle := Color(0.79, 0.64, 0.5).lerp(fur, 0.3)
			_piece(root, _loft([[-0.55, 0.52, 0.12, 0.12, fur], [-0.42, 0.54, 0.36, 0.34, fur], [-0.1, 0.6, 0.42, 0.42, fur.lightened(0.05)], [0.18, 0.66, 0.42, 0.46, fur], [0.4, 0.62, 0.32, 0.34, fur], [0.52, 0.6, 0.16, 0.16, fur]], 12), Vector3.ZERO)
			var plates: Array = []
			for k in 5:   # bark plates down the hump, layered like shingles (spines-up when it warns)
				var pl := Node3D.new()
				pl.position = Vector3(0, 0.98 + 0.06 * sin(k * 0.9 + 0.6), -0.3 + 0.15 * k)
				pl.rotation.x = -0.35
				root.add_child(pl)
				_piece(pl, _loft([[-0.09, 0.0, 0.02, 0.01, bark], [0.0, 0.05, 0.16, 0.05, bark], [0.09, 0.0, 0.02, 0.01, bark.darkened(0.2)]], 8), Vector3.ZERO)
				_piece(pl, _loft([[-0.04, 0.0, 0.0, 0.0, moss], [0.0, 0.0, 0.06, 0.03, moss], [0.04, 0.0, 0.0, 0.0, moss]], 6), Vector3(0, 0.08, -0.02))
				plates.append(pl)
			out["extra"] = plates
			head.position = Vector3(0, 0.62, 0.55)
			root.add_child(head)
			_piece(head, _loft([[-0.05, 0.0, 0.2, 0.2, fur], [0.12, -0.02, 0.17, 0.16, fur], [0.26, -0.04, 0.1, 0.09, muzzle], [0.34, -0.05, 0.05, 0.05, Color(0.1, 0.07, 0.08)]], 10), Vector3.ZERO)
			for sd in [-1.0, 1.0]:
				_piece(head, _loft([[-0.03, 0.0, 0.0, 0.0, fur], [0.0, 0.0, 0.06, 0.05, fur], [0.03, 0.0, 0.0, 0.0, fur]], 6), Vector3(0.12 * sd, 0.17, 0.0))
				_piece(head, _loft([[-0.015, 0.0, 0.0, 0.0, Color(1, 0.7, 0.3)], [0.0, 0.0, 0.022, 0.022, Color(1, 0.7, 0.3)], [0.015, 0.0, 0.0, 0.0, Color(1, 0.7, 0.3)]], 6), Vector3(0.1 * sd, 0.06, 0.15), true)
			var jaw := Node3D.new()
			jaw.position = Vector3(0, -0.1, 0.04)
			head.add_child(jaw)
			_piece(jaw, _loft([[0.0, 0.0, 0.14, 0.05, fur], [0.16, -0.01, 0.1, 0.04, muzzle], [0.26, 0.0, 0.05, 0.02, Color(0.35, 0.08, 0.15)]], 8), Vector3.ZERO)
			out["jaw"] = jaw
			for i in 4:
				var pv := Node3D.new()
				pv.position = Vector3(0.26 * (1.0 if i % 2 == 0 else -1.0), 0.42, 0.32 if i < 2 else -0.34)
				root.add_child(pv)
				_piece(pv, _limb(0.42, 0.13, 0.1, fur.darkened(0.08), 0.04), Vector3.ZERO)
				for k in 3:
					_piece(pv, _stick(Vector3(-0.05 + 0.05 * k, -0.4, 0.06), Vector3(-0.05 + 0.05 * k, -0.42, 0.14), 0.018, Color(0.94, 0.89, 0.78)), Vector3.ZERO)
				legs.append(pv)
		"vexmaw":   # the lean red ambush hunter: low body, long spiked tail, huge jaws, scythe claws, digitigrade legs
			var skin := _c(spec, "skin", Color(0.78, 0.2, 0.23))
			var belly := Color(0.92, 0.84, 0.68)
			var stripe := _c(spec, "stripe", Color(0.49, 0.09, 0.19))
			var spikec := Color(0.16, 0.08, 0.13)
			var eyec := _c(spec, "eye", Color(1.0, 0.88, 0.29))
			_piece(root, _loft([[-1.45, 0.42, 0.02, 0.02, skin], [-1.1, 0.48, 0.06, 0.06, stripe], [-0.7, 0.54, 0.1, 0.1, skin], [-0.3, 0.6, 0.17, 0.17, stripe], [0.05, 0.64, 0.2, 0.2, skin], [0.4, 0.66, 0.16, 0.17, stripe], [0.6, 0.7, 0.1, 0.11, skin]], 10), Vector3.ZERO)
			_piece(root, _loft([[-0.25, 0.5, 0.12, 0.05, belly], [0.1, 0.52, 0.15, 0.06, belly], [0.45, 0.58, 0.1, 0.04, belly]], 8), Vector3.ZERO)
			var spines: Array = []
			for k in 9:   # dorsal spines down the spine and tail (up when it warns)
				var z := 0.45 - 0.2 * k
				var y := 0.66 + 0.18 - 0.03 * k if k < 5 else 0.72 - 0.04 * (k - 4)
				var sp := Node3D.new()
				sp.position = Vector3(0, y, z)
				root.add_child(sp)
				_piece(sp, _stick(Vector3.ZERO, Vector3(0, 0.16 - 0.008 * k, -0.06), 0.03, spikec), Vector3.ZERO)
				spines.append(sp)
			for sd in [-1.0, 1.0]:   # the tail club spikes
				_piece(root, _stick(Vector3(0, 0.42, -1.4), Vector3(0.12 * sd, 0.5, -1.55), 0.025, spikec), Vector3.ZERO)
			out["extra"] = spines
			head.position = Vector3(0, 0.72, 0.62)
			root.add_child(head)
			_piece(head, _loft([[-0.05, 0.0, 0.12, 0.12, skin], [0.15, 0.03, 0.13, 0.1, skin], [0.4, 0.02, 0.09, 0.06, skin], [0.52, 0.0, 0.04, 0.03, stripe]], 10), Vector3.ZERO)   # the upper jaw / skull
			for sd in [-1.0, 1.0]:
				_piece(head, _loft([[-0.015, 0.0, 0.0, 0.0, eyec], [0.0, 0.0, 0.03, 0.02, eyec], [0.015, 0.0, 0.0, 0.0, eyec]], 6), Vector3(0.1 * sd, 0.07, 0.15), true)
				_piece(head, _stick(Vector3(0.06 * sd, 0.1, 0.12), Vector3(0.1 * sd, 0.2, 0.0), 0.022, spikec), Vector3.ZERO)   # brow horns
				for k in 5:   # teeth along the upper jaw
					_piece(head, _stick(Vector3(0.07 * sd, -0.05, 0.12 + 0.07 * k), Vector3(0.07 * sd, -0.11, 0.13 + 0.07 * k), 0.012, Color(0.97, 0.93, 0.85)), Vector3.ZERO)
			var jaw := Node3D.new()
			jaw.position = Vector3(0, -0.06, 0.02)
			head.add_child(jaw)
			_piece(jaw, _loft([[0.0, 0.0, 0.11, 0.05, skin], [0.2, -0.03, 0.1, 0.04, skin], [0.44, -0.02, 0.05, 0.03, skin]], 8), Vector3.ZERO)
			_piece(jaw, _loft([[0.04, 0.03, 0.07, 0.02, Color(0.35, 0.06, 0.13)], [0.36, 0.01, 0.05, 0.015, Color(0.55, 0.1, 0.2)]], 6), Vector3.ZERO, true)
			out["jaw"] = jaw
			for sd in [-1.0, 1.0]:   # two big digitigrade hind legs
				var pv := Node3D.new()
				pv.position = Vector3(0.16 * sd, 0.58, -0.08)
				root.add_child(pv)
				_piece(pv, _loft([[0.0, 0.0, 0.11, 0.13, skin], [0.08, -0.2, 0.08, 0.09, skin], [-0.06, -0.4, 0.05, 0.05, skin], [0.04, -0.58, 0.04, 0.04, skin.darkened(0.3)]], 8), Vector3.ZERO)
				for k in 3:
					_piece(pv, _stick(Vector3(0.04 + 0.03 * (k - 1), -0.57, 0.04), Vector3(0.04 + 0.05 * (k - 1), -0.58, 0.16), 0.014, Color(0.95, 0.9, 0.8)), Vector3.ZERO)
				legs.append(pv)
			var arms: Array = []
			for sd in [-1.0, 1.0]:   # forearms with scythe claws
				var pv := Node3D.new()
				pv.position = Vector3(0.13 * sd, 0.55, 0.45)
				root.add_child(pv)
				_piece(pv, _limb(0.26, 0.05, 0.035, skin, 0.4), Vector3.ZERO)
				for k in 3:
					_piece(pv, _stick(Vector3(0.0, -0.25, 0.08), Vector3((k - 1) * 0.04, -0.3, 0.26), 0.014, Color(0.95, 0.92, 0.85)), Vector3.ZERO)
				arms.append(pv)
			out["arms"] = arms
		"rimeback":   # the giant snow ape: a huge white shaggy body, ice crystals out of its shoulders, long arms, a blue face
			var fur := Color(0.94, 0.96, 1.0)
			var fur2 := Color(0.74, 0.8, 0.92)
			var skin := Color(0.35, 0.47, 0.66)
			var ice := Color(0.65, 0.94, 1.0)
			var torso := Node3D.new()
			torso.position = Vector3(0, 0.3, 0)
			torso.rotation.x = -PI * 0.5   # the loft runs up
			root.add_child(torso)
			var rings: Array = []
			for i in 8:
				var t := float(i) / 7.0
				var r := (0.22 + 0.16 * sin(t * PI * 0.9)) * (1.0 + 0.06 * sin(t * 37.0))
				rings.append([t * 0.62, 0.0, r * 1.15, r * 0.85, fur if i % 2 == 0 else fur2])
			_piece(torso, _loft(rings, 14), Vector3.ZERO)
			for sd in [-1.0, 1.0]:   # ice crystals from the shoulders
				for k in 3:
					var b := Vector3(0.22 * sd + 0.06 * sd * k, 0.84 - 0.04 * k, -0.08)
					_piece(root, _stick(b, b + Vector3(0.08 * sd * (k + 1), 0.22 - 0.04 * k, -0.08), 0.05 - 0.01 * k, ice), Vector3.ZERO, true)
			head.position = Vector3(0, 0.9, 0.04)
			root.add_child(head)
			_piece(head, _loft([[-0.12, 0.0, 0.14, 0.14, fur], [0.0, 0.0, 0.16, 0.15, fur2], [0.12, -0.02, 0.12, 0.11, skin], [0.17, -0.04, 0.06, 0.05, skin.darkened(0.3)]], 10), Vector3.ZERO)
			for sd in [-1.0, 1.0]:
				_piece(head, _loft([[-0.012, 0.0, 0.0, 0.0, Color(0.5, 0.97, 1.0)], [0.0, 0.0, 0.022, 0.016, Color(0.5, 0.97, 1.0)], [0.012, 0.0, 0.0, 0.0, Color(0.5, 0.97, 1.0)]], 6), Vector3(0.06 * sd, 0.03, 0.15), true)
			var jaw := Node3D.new()
			jaw.position = Vector3(0, -0.06, 0.08)
			head.add_child(jaw)
			_piece(jaw, _loft([[0.0, 0.0, 0.08, 0.03, skin], [0.08, -0.01, 0.06, 0.025, Color(0.2, 0.18, 0.3)]], 8), Vector3.ZERO)
			out["jaw"] = jaw
			var arms: Array = []
			for sd in [-1.0, 1.0]:
				var pv := Node3D.new()
				pv.position = Vector3(0.36 * sd, 0.76, 0.0)
				root.add_child(pv)
				_piece(pv, _limb(0.55, 0.13, 0.1, fur, 0.1), Vector3.ZERO)
				_piece(pv, _loft([[-0.06, -0.55, 0.0, 0.0, skin], [0.0, -0.58, 0.09, 0.06, skin], [0.06, -0.6, 0.0, 0.0, skin]], 8), Vector3.ZERO)
				arms.append(pv)
			out["arms"] = arms
			for sd in [-1.0, 1.0]:
				var pv := Node3D.new()
				pv.position = Vector3(0.15 * sd, 0.34, 0.0)
				root.add_child(pv)
				_piece(pv, _limb(0.34, 0.12, 0.1, fur2, 0.06), Vector3.ZERO)
				legs.append(pv)
		"sandmaw":   # the giant burrower: armoured segments rising in an arc, three petal jaws round a glowing toothed maw
			var hide := Color(0.79, 0.54, 0.29)
			var plate := Color(0.48, 0.29, 0.18)
			var gum := Color(0.85, 0.31, 0.42)
			var n := 9
			var top := Vector3.ZERO
			for i in n:   # segments from under the sand up and over
				var t := float(i) / float(n - 1)
				var c := Vector3(0, -0.25 + t * 1.15, 0.05 + 0.32 * sin(t * PI * 0.7))
				var r := 0.2 - 0.07 * t
				var seg := _loft([[-r * 0.6, 0.0, r, r, hide], [0.0, 0.0, r * 1.06, r * 1.04, hide.lightened(0.05)], [r * 0.6, 0.0, r * 0.95, r * 0.95, hide]], 12)
				var mi := _piece(root, seg, c)
				mi.rotation.x = -PI * 0.5 + 0.5 * t
				var pl := _piece(root, _loft([[-r * 0.5, 0.0, r * 0.7, r * 0.18, plate], [r * 0.5, 0.0, r * 0.6, r * 0.12, plate]], 8), c + Vector3(0, 0.0, -r * 0.85))
				pl.rotation.x = -PI * 0.5 + 0.5 * t
				top = c
			var jaw := Node3D.new()   # the mouth: opens (scales) when it's exposed
			jaw.position = top + Vector3(0, 0.08, 0.05)
			jaw.rotation.x = -0.6
			root.add_child(jaw)
			_piece(jaw, _loft([[-0.03, 0.0, 0.12, 0.12, gum], [0.0, 0.0, 0.13, 0.13, gum], [0.02, 0.0, 0.05, 0.05, Color(0.25, 0.05, 0.12)]], 14), Vector3.ZERO, true)
			for k in 3:   # three petal jaws
				var a := TAU * k / 3.0
				var d := Vector3(cos(a), sin(a), 0.0)
				_piece(jaw, _stick(d * 0.1, d * 0.34 + Vector3(0, 0, 0.12), 0.07, plate), Vector3.ZERO)
				for j in 3:
					_piece(jaw, _stick(d * (0.14 + 0.06 * j), d * (0.1 + 0.06 * j) + Vector3(0, 0, 0.05), 0.012, Color(1.0, 0.95, 0.86)), Vector3.ZERO)
			out["jaw"] = jaw
	return {"legs": legs, "head": head, "jaw": out.get("jaw"), "arms": out.get("arms", []), "tail": out.get("tail"), "extra": out.get("extra", [])}

## A thin tapered stick from a to b (antlers, feelers, horns, claws, spines).
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
