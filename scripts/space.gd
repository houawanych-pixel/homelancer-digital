class_name SpaceSystem
extends Node3D
## One star system in flight: environment, player flight, combat, AI, docking and gate proximity.

signal enemy_killed(reward: int, name: String)
signal mission_done(said: String)   # v1.5f: a mission ended (paid, or "failed")
signal player_destroyed
signal message(text: String)
signal atmosphere_entered(planet_node: Node3D) # flew into a planet that has a surface
signal tile_edge(dir: Vector2i)                 # crossed the edge of a planet tile
signal leave_atmosphere                         # climbed above the ceiling of a planet tile
signal collided(kind: String, dmg: float, k: float)   # Job L: a damaging collision (k = 0..1 how hard, for feedback)

const DOCK_RANGE_STATION := Data.DOCK_RANGE_STATION
const DOCK_RANGE_PLANET := Data.DOCK_RANGE_PLANET # measured from the planet surface
const GATE_RANGE := 320.0

var sys: Dictionary
var sys_id := ""
var player: Node3D
var model: Node3D
var cam: Camera3D
var env: WorldEnvironment
var controls := true

# player flight state
var yaw := 0.0
var pitch := 0.0
var vel := Vector3.ZERO
var move := Vector2.ZERO # x strafe, y forward(+)/back(-)
var aim := Vector2.ZERO # stick deflection -1..1
var fire_held := false
var fire_lock := false            # v1.4l: the FIRE button: on = the guns fire nonstop until you press it again
var shield_cd := 0.0
var energy_cd := 0.0
var repair_cd := 0.0
var missile_cd := 0.0
var mine_cd := 0.0
var lock_time := 0.0
var enemy_dodge_chance := Data.ENEMY_DODGE_CHANCE
var mines_live: Array = []
var loot: Array = [] # {node, vel, value, life}
var tractor_t := 0.0
# ---- planet surface mode (see surface.gd): one flat tile of a planet instead of a star system
var surface_mode := false
var planet_id := ""
var tile := 0
var tile_root: Node3D
var surf_busy := false   # a tile / atmosphere transition is running
var entering := false    # atmosphere entry from space is running
var altitude := 0.0
var _water := false
var atmo_depth := 0.0     # 0 outside a planet's outer atmosphere .. 1 at the entry sphere
var planet_hazard := 0    # 0 none, 1 warp near planet (warning), 2 warp impact
var sun_pos := Vector3.INF      # where the sun's sphere sits (INF = no sun here, e.g. on a planet)
var sun_glow: MeshInstance3D
var sun_core: MeshInstance3D
var sun_body: Node3D
var sun_surface := false        # on the surface of a star
var heat_shielded := false      # on a star with a working heat shield
var _sun_burned := false
var sun_flare := 0.0            # 0..1: how hard the sun blooms on screen (looking at it, and close)
var sun_hazard := 0             # 0 none, 1 heat warning, 2 burned up
var _atmo_rumbled := false
var _edge_warned := false
var _sky: ProceduralSkyMaterial
var player_vis := {} # the player ship's wing sections (Sections handle)
var player_spark := 3.0
signal system_used(id: String, text: String)
var warp_state := "off" # off | charging | on
var warp_t := 0.0
var engine_kill := false
var warp_drift := false   # v1.9u: engines were cut at warp, so the drift carries warp speed
var braking := false
var thrust_held := false
var boosting := false
var thrust_arc := 0.0   # v1.5n: the nose-up arc on the ship model while THRUST is on (radians)
var call_cd := 0.0
var holding := false   # stopped and staying stopped (after a full stop) until the stick moves
static var cruise_assist := true   # centred stick holds Data.CRUISE (the route test turns it off for its fixed setups)
var _particle_acc := 0.0
signal hail(from: String, line: String, hostile: bool)
signal enemy_hail(pilot: Dictionary)
signal enemy_chatter(pilot: Dictionary, line: String)   # a generic pilot's short radio line ("[normal]..." / "[damaged]...")
var chatter_cd := 0.0
var last_chatter := {}      # {pilot, event, state, line} of the latest generic chatter (route test / debugging)
var _warp_spotted := false
var _group_serial := 0
const TAUNTS := ["Give up, cadet. Power down and we might let you drift home.",
	"Nice ship. It'll look better in our colours.",
	"You're a long way from your patrol, little lancer.",
	"Turn around now and nobody has to hear about this.",
	"Your escort isn't coming. It's just you and us."]
var gun_cd := 0.0
var mount_next := {}   # v1.9e: mount index -> time it can fire again
var shield_delay := 0.0
var hit_shake := 0.0
var autopilot: Node3D = null # fly toward this node when set
var speed_now := 0.0

# world objects
var station: Node3D
var carrier: Node3D
var planet: Node3D
var gate: Node3D
var gates: Array = []            # every gate in this system (gate = the first one)
var gate_portals: Array = []
var sun_radius: float = Data.SUN_RADIUS   # void systems have a small sun
var gate_portal: MeshInstance3D
var gate_standin: Node3D          # the code-made ring, shown until the "structures" pack arrives
var gate_model: MeshInstance3D    # the owner's jump gate ring (assets/structures/jump_gate_ring.glb)
var jump_rings: Array = []
const GATE_RING_PATH := "res://assets/structures/jump_gate_ring.glb"
const GATE_RING_SCALE := 44.0     # the model's clear opening has radius 1.0
const GATE_RING_TRIS := 5316
const JUMP_RINGS := 6
const DOCK_RING_SCALE := 26.0      # docking gate ring: opening radius, the same as the old green beacon ring
const DOCK_ARCH_SCALE := 140.0     # the arch piece is about 0.64 long: 90 m when placed
const DOCK_GATE_TRIS := 5316 + 4 * 2264
var station_model: MeshInstance3D   # the owner's station model, for stations whose data says "model"
const STATION_WIDTH := 170.0       # the model is 1.0 wide; its ring then sits where the code-made ring was
const STATION_TRIS := 14900
var nebula_center := Vector3.ZERO
var nebula_radius := 0.0
var nebula_color := Color.WHITE
var belt_center := Vector3.ZERO
const BlockAsteroid := preload("res://scripts/block_asteroid.gd")
var asteroids: Array = []        # v1.7x: the field's block asteroids (each also has a [centre, radius] entry in rocks)
var belt_radius := 0.0
var rocks: Array = [] # [Vector3 pos, float radius]
var enemies: Array = [] # Dictionaries
var traffic: Array = []
var tanker: Node3D           # the big liquid tanker by the planet
var bolts: Array = []
var missiles_live: Array = []
var enemy_missiles: Array = []    # Job M: missiles flying at the player
var volley_queue: Array = []      # Job M: the rest of a volley, launched VOLLEY_GAP apart
var missile_warn := -1.0          # distance of the nearest missile homing on you (-1 = none)
var missiles_evaded := 0          # enemy missiles you shook off
var sig_stats := {"darts": 0, "kinks": 0, "impacts": 0, "blooms": 0, "brands": 0}   # Job N: signature attack counters
var sig_pending: Array = []       # delayed parts of a signature impact (the bloom after the punch)
var sig_brands: Array = []        # lock-brand scorches still pulsing
var _hex_mesh: ArrayMesh
var retargets := 0                # missiles that picked a new target after theirs was gone
var enemy_evades := 0             # your missiles an enemy shook off
var effects: Array = []
var popups: Array = [] # floating damage numbers: {pos, text, col, life}
var target: Node3D = null
var respawn_timer := 0.0
var in_nebula := 0.0 # 0..1 how deep inside
var in_belt := false
var time := 0.0
var _enemy_serial := 0

var _bolt_mesh: BoxMesh
var _bolt_halo: BoxMesh
var _laser_sfx_cd := 0.0
var _rng := RandomNumberGenerator.new()

# ---------------------------------------------------------------- build
func setup(id: String, arrival: String) -> void:
	await _setup(id, arrival, false)

## v1.5d: the same build spread over several frames (one step a frame), for the jump: the warp effect keeps moving
## while the next system is built behind it instead of freezing for one long frame. Nothing runs here until the end.
func setup_staged(id: String, arrival: String) -> void:
	await _setup(id, arrival, true)

func _setup(id: String, arrival: String, staged: bool) -> void:
	set_process(staged == false)
	sys_id = id
	sys = Data.SYSTEMS[id]
	sun_radius = Data.SUN_RADIUS * (0.35 if sys.get("small_sun", false) else 1.0)
	_rng.seed = hash(id)
	_bolt_mesh = BoxMesh.new()
	_bolt_mesh.size = Vector3(0.6, 0.6, 14.0)   # bright core
	_bolt_halo = BoxMesh.new()
	_bolt_halo.size = Vector3(2.2, 2.2, 18.0)    # soft glow around it, so bolts read at range and on phones
	_prof("start")
	_build_environment()
	_prof("environment (sky, sun, camera)")
	_build_station(sys["station"])
	_prof("station")
	if staged: await get_tree().process_frame
	_build_planet(sys["planet"])
	_prof("planet")
	if staged: await get_tree().process_frame
	for gd in sys["gates"]: _build_gate(gd)
	gate = gates[0]
	gate_portal = gate_portals[0]
	gate_standin = gate.get_meta("standin")
	_gate_model()
	if gate_model == null and not Packs.pack_ready.is_connected(_on_gate_pack): Packs.pack_ready.connect(_on_gate_pack)
	_prof("gate")
	if staged: await get_tree().process_frame
	_build_belt(sys["asteroids"])
	_build_ring()   # v1.8f
	_prof("asteroid belt")
	_build_nebula(sys["nebula"])
	_build_beacon()
	_prof("nebula")
	if staged: await get_tree().process_frame
	_build_player()
	_prof("player ship")
	if staged: await get_tree().process_frame
	_named_down = {}
	_incursion = Factions.raider_of(str(sys.get("faction", ""))) if randf() < Data.INCURSION_CHANCE else ""
	faction_mech(str(sys.get("faction", "")))   # v1.9i: fetch this space's own mech early (its patrols and ground jobs use it)
	for p in (sys["patrols"] as Array).slice(0, Data.PATROL_GROUPS): _spawn_group(p, Data.ROSTER_PATROL_SIZE if Factions.replaces_patrols(str(sys.get("faction", ""))) else 2)   # v1.8v: fewer wings
	spawn_guard()
	spawn_bounty()
	_prof("patrols")
	if staged: await get_tree().process_frame
	_build_traffic()
	_build_carrier()
	_prof("traffic + carrier")
	if staged: await get_tree().process_frame
	_build_lanes()
	_prof("trade lanes")
	place_player(arrival)
	spawn_hunters()
	set_process(true)

## One line of memory numbers (GPU textures, GPU buffers, engine RAM, node count) for load/soak testing.
static func memory_report() -> String:
	return "[memory] textures %.1f MB · buffers %.1f MB · RAM %.1f MB · nodes %d · objects %d" % [
		Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1e6, Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1e6,
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1e6, Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_COUNT)]

var _prof_t := 0
## Startup timing per step, printed when HL_PROFILE is set (and always on the web, so the browser log shows it).
func _prof(step: String) -> void:
	var now := Time.get_ticks_usec()
	if step != "start" and (OS.has_feature("web") or OS.get_environment("HL_PROFILE") != ""):
		print("[profile] %s: %d ms" % [step, (now - _prof_t) / 1000])
	_prof_t = now

var launch_from: Node3D = null   # v1.9d: the 3D station you docked at (you launch from it again)
func place_player(arrival: String) -> void:
	var at: Vector3
	var face: Vector3
	player.visible = true   # (hidden when the ship blew up)
	if surface_mode:
		if station.get_meta("kind", "") == "station":
			at = dock_point(station)
			face = Vector3(0, 0, 1)
		else:
			at = Vector3(0, 1200, 0)
			face = Vector3(0, 0, -1)
		player.global_position = at
		_face(face)
		vel = -player.global_basis.z * 10.0
		_update_camera(1.0, true)
		return
	if arrival.begins_with("orbit:"):
		# climbing out of a planet tile: appear above that part of the planet, facing away from it
		# "orbit:<tile>" = the main planet; "orbit:<tile>:<planet id>" = one of the system's other planets (v1.4l)
		var parts := arrival.split(":")
		var pid: String = planet.get_meta("info")["id"]
		var centre: Vector3 = planet.global_position
		var prad: float = planet.get_meta("radius")
		if parts.size() > 2 and parts[2] != pid:
			for mp: Dictionary in sys.get("more_planets", []):
				if mp["id"] == parts[2]:
					pid = parts[2]
					centre = mp["pos"]
					prad = float(mp["radius"])
		var d := Surface.direction_from_tile(pid, int(parts[1]))
		at = centre + d * (prad * Data.ATMO_OUTER + 60.0)
		face = d
		player.global_position = at
		_face(face)
		vel = -player.global_basis.z * 30.0
		_update_camera(1.0, true)
		return
	if arrival == "sunorbit":
		# climbing out of the star: appear outside its heat zone, on the side facing the system, flying home
		var sd := sun_pos.normalized()
		player.global_position = sun_pos - sd * (sun_radius * Data.SUN_WARN + 300.0)
		_face(-sd)
		vel = -player.global_basis.z * 30.0
		_update_camera(1.0, true)
		return
	if arrival.begins_with("gate"):
		# come out of the gate that leads back to where you came from ("gate:<system>"), else the first gate
		var ag: Node3D = gate
		for g in gates:
			if arrival == "gate:" + str(g.get_meta("info").get("to", "")): ag = g
		at = ag.global_position + ag.global_basis.z * 150.0
		face = ag.global_basis.z
	elif arrival == "planet":
		at = dock_point(planet) + (dock_point(planet) - planet.global_position).normalized() * 40.0
		face = (station.global_position - at).normalized()
	elif is_instance_valid(launch_from) and launch_from.has_meta("dock"):   # v1.9d: back out of the station you docked at
		at = dock_point(launch_from) + Vector3(0, 0, 30)
		face = Vector3(0, 0, 1)
	else:
		at = dock_point(station) + Vector3(0, 0, 30)
		face = Vector3(0, 0, 1)
	launch_from = null
	player.global_position = at
	_face(face)
	vel = -player.global_basis.z * 10.0
	_update_camera(1.0, true)

func _face(dir: Vector3) -> void:
	dir = dir.normalized()
	yaw = atan2(-dir.x, -dir.z)
	pitch = asin(clampf(dir.y, -1.0, 1.0))
	player.basis = Basis.from_euler(Vector3(pitch, yaw, 0))

func _build_environment() -> void:
	env = WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var pano := PanoramaSkyMaterial.new()
	_pano = pano
	# the system's own painted sky (the "sky" pack, assets/sky/<system>.jpg); stars-and-haze made in code until it arrives
	if Packs.is_ready(sky_pack()) and ResourceLoader.exists(sky_path()): pano.panorama = load(sky_path())
	else:
		pano.panorama = _star_panorama(sys["sky_tint"], sys["nebula"]["color"])
		if not Packs.pack_ready.is_connected(_on_sky_pack): Packs.pack_ready.connect(_on_sky_pack)
		Packs.request(sky_pack())
	sky.sky_material = pano
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = sys["ambient"]
	e.ambient_light_energy = 0.9
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_color = sys["star"]
	sun.light_energy = 1.25
	var d: Vector3 = (sys["sun_dir"] as Vector3).normalized()
	sun.look_at_from_position(Vector3.ZERO, d, Vector3.UP)
	add_child(sun)
	# The sun: an invisible sphere holds its place (and is the kill line); a bright core you can see from anywhere
	# and a billboard glow ride on it. It sits far out, toward the edge of the system but not on the border.
	sun_pos = -d * Data.SUN_DIST
	var core := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = sun_radius
	sm.height = sun_radius * 2.0
	sm.radial_segments = 48
	sm.rings = 24
	core.mesh = sm
	var cm := StandardMaterial3D.new()
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cm.albedo_color = (sys["star"] as Color).lerp(Color.WHITE, 0.6)
	core.material_override = cm
	core.name = "SunCore"
	core.position = sun_pos
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(core)
	sun_core = core
	sun_body = _placeholder("%s's Star" % sys["name"], "sun", sun_pos, {"id": sys_id + "_sun"})   # the real place: what you fly into
	sun_body.set_meta("radius", sun_radius)
	var glow := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE * sun_radius * 6.0
	glow.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.albedo_texture = _radial_texture(sys["star"], 0.0)
	glow.material_override = m
	glow.name = "Sun"
	glow.position = sun_pos
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(glow)
	sun_glow = glow
	cam = Camera3D.new()
	cam.far = Data.SPACE_CAM_FAR   # v1.9k (owner: a far planet flickered on and off): far enough for every planet in the system
	cam.near = 0.5
	cam.fov = 70.0
	cam.current = true
	add_child(cam)

var _pano: PanoramaSkyMaterial
## Hand-made systems keep their sky in the shared "sky" pack; every other system has its own small pack (sky_<id>),
## fetched when you arrive there, so the game never downloads skies it does not show.
func sky_pack() -> String: return "sky" if Data.CORE_SYSTEMS.has(sys_id) else "sky_" + sys_id
func sky_path() -> String: return ("res://assets/sky/%s.jpg" if Data.CORE_SYSTEMS.has(sys_id) else "res://assets/skies/%s.jpg") % sys_id
func _on_sky_pack(pk: String) -> void:
	if pk == sky_pack() and _pano != null and not surface_mode and ResourceLoader.exists(sky_path()): _pano.panorama = load(sky_path())

## Job AB: the sky picture on show right now (the painted one, or the stars-and-haze made in code).
func sky_texture() -> Texture2D:
	return _pano.panorama if _pano != null else null

func _star_panorama(tint: Color, band: Color) -> ImageTexture:
	var w := 1024
	var h := 512
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(tint * 0.35, 1.0))
	# faint galactic band of soft blobs
	var blob := Image.create(48, 24, false, Image.FORMAT_RGBA8)
	var bc: Color = (tint * 1.4).lerp(band, 0.45)
	for by in 24:
		for bx in 48:
			var dd := Vector2((bx - 23.5) / 24.0, (by - 11.5) / 12.0).length()
			blob.set_pixel(bx, by, Color(bc.r, bc.g, bc.b, clampf(1.0 - dd, 0.0, 1.0) * 0.07))
	for i in 260:
		var x := _rng.randi_range(-24, w - 24)
		var y := int(h * 0.5 + sin(float(x) / w * TAU) * h * 0.12 + _rng.randfn(0.0, h * 0.05)) - 12
		img.blend_rect(blob, Rect2i(0, 0, 48, 24), Vector2i(x, y))
	for i in 2600:
		var x := _rng.randi_range(0, w - 1)
		var y := _rng.randi_range(0, h - 1)
		var b := pow(_rng.randf(), 3.0)
		var c := Color(0.75 + b * 0.25, 0.8 + b * 0.2, 1.0).lerp(Color(1.0, 0.85, 0.7), _rng.randf() * 0.5) * (0.35 + b * 0.9)
		img.set_pixel(x, y, c)
		if b > 0.75 and x + 1 < w: img.set_pixel(x + 1, y, c * 0.6)
	return ImageTexture.create_from_image(img)

func _radial_texture(col: Color, core: float) -> ImageTexture:
	var s := 64
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var d := Vector2(x - s / 2.0 + 0.5, y - s / 2.0 + 0.5).length() / (s / 2.0)
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = pow(a, 2.2) + (1.0 if d < core else 0.0) * 0.8
			img.set_pixel(x, y, Color(col.r, col.g, col.b, clampf(a, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)

func _cloud_texture(col: Color, seed_v: int) -> ImageTexture:
	var s := 96
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.frequency = 0.045
	n.fractal_octaves = 3
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var d := Vector2(x - s / 2.0, y - s / 2.0).length() / (s / 2.0)
			var v := (n.get_noise_2d(x, y) + 1.0) * 0.5
			var a := clampf((1.0 - d) * 1.4, 0.0, 1.0) * clampf(v * 1.6 - 0.35, 0.0, 1.0)
			img.set_pixel(x, y, Color(col.r * (0.7 + v * 0.5), col.g * (0.7 + v * 0.5), col.b * (0.8 + v * 0.3), a))
	return ImageTexture.create_from_image(img)

func _mesh(parent: Node3D, mesh: Mesh, pos: Vector3, col: Color, scl := Vector3.ONE, rot := Vector3.ZERO, emissive := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.scale = scl
	mi.rotation_degrees = rot
	mi.material_override = ShipFactory.mat(col, emissive, 0.5)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

func _build_station(d: Dictionary) -> void:
	station = Node3D.new()
	station.name = d["name"]
	station.position = d["pos"]
	station.set_meta("kind", "station")
	station.set_meta("info", d)
	station.set_meta("radius", 70.0)
	add_child(station)
	var c: Color = d["color"]
	var cyl := CylinderMesh.new()
	cyl.radial_segments = 16
	cyl.rings = 1
	var box := BoxMesh.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 52.0
	torus.outer_radius = 60.0
	torus.rings = 40
	torus.ring_segments = 8
	var body := Node3D.new()
	station.add_child(body)
	if ShipFactory.has_real_model("station"):
		# real station model: 150 units tall, round docking port facing +Z (front face at about z = 45)
		body.add_child(ShipFactory.build("station"))
		for i in 5:
			for s in [-1.0, 1.0]:
				var gl := _mesh(body, BoxMesh.new(), Vector3(s * 12, -6, 64 + i * 14), Color(0.3, 1.0, 0.6), Vector3(1.2, 1.2, 1.2), Vector3.ZERO, true)
				gl.set_meta("blink", i * 0.12)
		station.set_meta("body", body)
		_station_model()
		if d.has("model") and station_model == null and not Packs.pack_ready.is_connected(_on_gate_pack): Packs.pack_ready.connect(_on_gate_pack)
		return
	_mesh(body, cyl, Vector3.ZERO, c, Vector3(14, 70, 14))
	_mesh(body, cyl, Vector3(0, 40, 0), c.darkened(0.3), Vector3(22, 10, 22))
	_mesh(body, cyl, Vector3(0, -40, 0), c.darkened(0.3), Vector3(22, 10, 22))
	_mesh(body, torus, Vector3.ZERO, c.darkened(0.15))
	for i in 4:
		var a := i * PI / 2.0
		_mesh(body, box, Vector3(cos(a) * 30, 0, sin(a) * 30), c.darkened(0.25), Vector3(48, 4, 4), Vector3(0, -rad_to_deg(a), 0))
	# solar wings
	for s in [-1.0, 1.0]:
		_mesh(body, box, Vector3(0, s * 62, 0), Color(0.12, 0.2, 0.42), Vector3(90, 1.5, 22))
	# docking bay facing +Z with guide lights
	_mesh(body, box, Vector3(0, 0, 44), c.darkened(0.4), Vector3(26, 16, 30))
	_mesh(body, box, Vector3(0, 0, 59.2), Color(0.02, 0.03, 0.05), Vector3(18, 10, 0.5))
	for i in 5:
		for s in [-1.0, 1.0]:
			var l := _mesh(body, BoxMesh.new(), Vector3(s * 12, -6, 64 + i * 14), Color(0.3, 1.0, 0.6), Vector3(1.2, 1.2, 1.2), Vector3.ZERO, true)
			l.set_meta("blink", i * 0.12)
	for i in 8:
		var a2 := i * TAU / 8.0
		_mesh(body, BoxMesh.new(), Vector3(cos(a2) * 60, 0, sin(a2) * 60), Color(1.0, 0.85, 0.5), Vector3(2, 2, 2), Vector3.ZERO, true)
	station.set_meta("body", body)
	_station_model()
	if d.has("model") and station_model == null and not Packs.pack_ready.is_connected(_on_gate_pack): Packs.pack_ready.connect(_on_gate_pack)

## A station whose data names a model (assets/structures/<model>.glb) wears it once the "structures" pack is in.
## The code-made station stays as the stand-in until then; the green docking guide lights are kept.
func _station_model() -> void:
	if station_model != null or not is_instance_valid(station) or station.get_meta("kind", "") != "station": return
	var d: Dictionary = station.get_meta("info")
	if not d.has("model") or not station.has_meta("body"): return
	if Data.is_st3d(d["model"]):   # v1.9d: the owner's 3D stations: three LODs from their own pack (v1.9q: or the RETOPO set)
		var key := str(d["model"])
		if not Packs.is_ready(key):
			_want_st3d(key)
			return
		var holder := station3d(key)
		if holder == null: return
		var body3: Node3D = station.get_meta("body")
		for ch in body3.get_children():
			if ch is Node3D and not ch.has_meta("blink"): ch.visible = false
		body3.add_child(holder)
		station_model = holder.get_meta("lod0")
		_set_box(station, holder)   # v1.9q: a box to bump into instead of the sphere
		return
	var path := "res://assets/structures/%s.glb" % d["model"]
	if not (Packs.is_ready("structures") and ResourceLoader.exists(path)): return
	var sc := (load(path) as PackedScene).instantiate()
	var found := sc.find_children("*", "MeshInstance3D", true, false)
	if not found.is_empty():
		var body: Node3D = station.get_meta("body")
		for ch in body.get_children():
			if ch is Node3D and not ch.has_meta("blink"): ch.visible = false
		station_model = MeshInstance3D.new()
		station_model.mesh = (found[0] as MeshInstance3D).mesh
		station_model.scale = Vector3.ONE * STATION_WIDTH * float(Data.STATION_MODEL_SCALE.get(d["model"], 1.0))
		station_model.rotation_degrees.y = float(Data.STATION_MODEL_YAW.get(d["model"], 0.0))
		station_model.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(station_model)
	sc.free()

## v1.9d (Station3D-Retopo v1): one of the owner's 3D stations as a node: LOD0 / LOD1 / LOD2 switched by distance
## (visibility ranges), scaled to the standard station width (provisional) and turned so its front (-Z in the file)
## faces the docking approach. Null until its pack is in.
func station3d(key: String, scale_k := 1.0) -> Node3D:
	var base := "res://assets/stations3d/%s" % key
	if not ResourceLoader.exists(base + ".glb"): return null
	var holder := Node3D.new()
	holder.name = "Station3D"
	holder.set_meta("station3d", key)
	var sc := STATION_WIDTH * Data.st3d_scale(key) * scale_k
	holder.scale = Vector3.ONE * sc
	holder.rotation_degrees.y = float(Data.STATION3D_YAW.get(key, Data.STATION3D_DEFAULT_YAW))
	var ranges: Array = Data.STATION3D_LOD   # [LOD0 out to, LOD1 out to] (m)
	var files := [base + ".glb", base + "_lod1.glb", base + "_lod2.glb"]
	for i in 3:
		if not ResourceLoader.exists(files[i]): continue
		var ps := load(files[i]) as PackedScene
		if ps == null: continue
		var inst := ps.instantiate()
		var found := inst.find_children("*", "MeshInstance3D", true, false)
		if not found.is_empty():
			var mi := MeshInstance3D.new()
			mi.name = "LOD%d" % i
			mi.mesh = (found[0] as MeshInstance3D).mesh
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visibility_range_begin = 0.0 if i == 0 else float(ranges[i - 1])
			mi.visibility_range_end = float(ranges[i]) if (i < 2 and ResourceLoader.exists(files[i + 1])) else 0.0   # v1.9q: a single-file model stays drawn at any distance
			holder.add_child(mi)
			holder.set_meta("lod%d" % i, mi)
		inst.free()
	if not holder.has_meta("lod0"):
		holder.free()
		return null
	return holder

## v1.9q: a simple collision box for a 3D model (the RETOPO stations): the mesh's own bounds, kept in the model's frame
## so it turns and scales with it. The bump test pushes the ship out through the nearest face.
func _set_box(n: Node3D, holder: Node3D) -> void:
	var mi: MeshInstance3D = holder.get_meta("lod0", null)
	if mi == null or mi.mesh == null: return
	n.set_meta("box_holder", holder)
	n.set_meta("box_aabb", mi.transform * mi.mesh.get_aabb())

func _bump_box(body: Node3D) -> void:
	_push_out_box(body.get_meta("box_holder"), body.get_meta("box_aabb"), "station")

## Push the ship out of a model's box through the nearest face (box = the mesh bounds in the holder's own frame).
func _push_out_box(hd: Node3D, bb: AABB, kind: String) -> bool:
	var xf := hd.global_transform
	var k := maxf(xf.basis.get_scale().x, 0.001)
	var pad := Data.RETOPO_BOX_PAD / k
	var q := xf.affine_inverse() * player.global_position
	var lo := bb.position - Vector3.ONE * pad
	var hi := bb.end + Vector3.ONE * pad
	if q.x <= lo.x or q.x >= hi.x or q.y <= lo.y or q.y >= hi.y or q.z <= lo.z or q.z >= hi.z: return false
	var pens := [q.x - lo.x, hi.x - q.x, q.y - lo.y, hi.y - q.y, q.z - lo.z, hi.z - q.z]
	var best := 0
	for i in 6:
		if pens[i] < pens[best]: best = i
	var axis := best / 2
	q[axis] = lo[axis] if best % 2 == 0 else hi[axis]
	var local_n := Vector3.ZERO
	local_n[axis] = -1.0 if best % 2 == 0 else 1.0
	var n2 := (xf.basis * local_n).normalized()
	player.global_position = xf * q
	if not (kind == "ground" and ground_mode): collision_damage(kind, -vel.dot(n2))
	if vel.dot(n2) < 0.0: vel = vel - n2 * vel.dot(n2) * (1.0 if ground_mode else 1.5)
	if ground_mode and n2.y > 0.7: grounded = true   # standing on a roof
	return true

## v1.9q RETOPO planetary buildings: a faction's Command Center and Hangar stand on its homeworld (the system's main
## planet), sat on the ground near the sector centre, each with a simple box to collide with. Built when the
## faction's building pack is in (asked for on landing).
var surf_boxes: Array = []   # [holder, AABB]
func building_faction() -> String:
	if not surface_mode and planet_id == "": return ""
	for sid in Data.RETOPO_BUILDINGS:
		if planet_id == "%s_planet" % sid: return str(Data.RETOPO_BUILDINGS[sid])
	return ""

func _faction_buildings() -> void:
	surf_boxes = []
	var fac := building_faction()
	if fac == "" or tile != 0 or not is_instance_valid(tile_root): return
	var pk := "bld_%s" % fac.to_lower()
	if not Packs.is_ready(pk):
		if not Packs.pack_ready.is_connected(_on_bld_pack): Packs.pack_ready.connect(_on_bld_pack)
		Packs.request(pk)
		return
	for kind: String in Data.BUILDING_KINDS:
		var path := Data.building_file(fac, kind)
		if not ResourceLoader.exists(path): continue
		var ps := load(path) as PackedScene
		if ps == null: continue
		var inst := ps.instantiate()
		var found := inst.find_children("*", "MeshInstance3D", true, false)
		var mesh: Mesh = (found[0] as MeshInstance3D).mesh if not found.is_empty() else null
		inst.free()
		if mesh == null: continue
		var mi := MeshInstance3D.new()
		mi.name = "Mesh"
		mi.mesh = mesh
		var holder := Node3D.new()
		holder.name = "HL_%s_%s" % [fac, kind]
		holder.set_meta("building", kind)
		holder.add_child(mi)
		var bb := mesh.get_aabb()
		var w: float = float(Data.BUILDING_WIDTH[kind]) / maxf(maxf(bb.size.x, bb.size.z), 0.001)
		var half := maxf(bb.size.x, bb.size.z) * w * 0.5
		var site := building_site(Data.BUILDING_SPOT[kind], half, surf_boxes)
		holder.scale = Vector3.ONE * w
		holder.rotation_degrees.y = float(Data.BUILDING_YAW[kind])
		holder.position = Vector3(site.x, site.y - Data.BUILDING_SINK - bb.position.y * w, site.z)
		holder.set_meta("half", half)
		tile_root.add_child(holder)
		surf_boxes.append([holder, bb])

## The flattest dry ground for a building near `want` (sector-local x, z): candidates on a grid round it, scored by how
## uneven the ground under its footprint is (plus a little for distance), away from buildings already placed.
## Returns (x, lowest ground under the footprint, z), so no corner floats.
func building_site(want: Vector2, half: float, placed: Array) -> Vector3:
	var best := Vector3(want.x, _ground(want.x, want.y), want.y)
	var best_score := INF
	var r: int = Data.BUILDING_SEARCH_STEPS
	for j in range(-r, r + 1):
		for i in range(-r, r + 1):
			var c := want + Vector2(i, j) * Data.BUILDING_SEARCH_STEP
			var clash := false
			for bx: Array in placed:
				var hp: Node3D = bx[0]
				if Vector2(hp.position.x, hp.position.z).distance_to(c) < half + float(hp.get_meta("half", half)) + Data.BUILDING_GAP: clash = true
			if clash: continue
			var lo := INF
			var hi := -INF
			for o: Vector2 in Data.BUILDING_PROBES:
				var g := _ground(c.x + o.x * half, c.y + o.y * half)
				lo = minf(lo, g)
				hi = maxf(hi, g)
			if _water and lo < 0.5: continue   # not in the sea
			var score := (hi - lo) + c.distance_to(want) * 0.02
			if score < best_score:
				best_score = score
				best = Vector3(c.x, lo, c.y)
	return best

func _on_bld_pack(pk: String) -> void:
	if not pk.begins_with("bld_") or not surface_mode or not is_inside_tree() or not surf_boxes.is_empty(): return
	_faction_buildings()

var _st3d_wanted := {}   # v1.9d: station packs asked for in this system
func _want_st3d(key: String) -> void:
	if _st3d_wanted.has(key): return
	_st3d_wanted[key] = true
	if not Packs.pack_ready.is_connected(_on_st3d_pack): Packs.pack_ready.connect(_on_st3d_pack)
	Packs.request(key)

func _on_st3d_pack(pk: String) -> void:
	if not Data.is_st3d(pk) or surface_mode or not is_inside_tree(): return
	_station_model()
	_extras_st3d()

## v1.9d: the other stations of a system that wear a 3D model: dockable (their hub pages), a sphere to bump into.
var docks3d: Array = []
func _extras_st3d() -> void:
	for n: Node3D in docks3d + roamers:
		if not is_instance_valid(n) or n.has_meta("dressed"): continue
		var key: String = n.get_meta("station3d")
		if not Packs.is_ready(key):
			_want_st3d(key)
			continue
		var holder := station3d(key, float(n.get_meta("scale_k", 1.0)))
		if holder == null: continue
		for ch in n.get_children():
			if ch is Node3D and not ch.has_meta("blink"): ch.visible = false
		n.add_child(holder)
		n.set_meta("dressed", true)
		_set_box(n, holder)   # v1.9q

## v1.9d: Cybermorph battleships that roam the system on a slow loop (not docks).
var roamers: Array = []
func _update_roamers(dt: float) -> void:
	for n: Node3D in roamers:
		if not is_instance_valid(n): continue
		var a: float = float(n.get_meta("angle")) + dt * Data.ROAMER_SPEED / Data.ROAMER_ORBIT
		n.set_meta("angle", a)
		var c: Vector3 = n.get_meta("centre")
		var p := c + Vector3(cos(a), 0.0, sin(a)) * Data.ROAMER_ORBIT + Vector3(0, sin(a * 2.0) * Data.ROAMER_BOB, 0)
		var ahead := c + Vector3(cos(a + 0.05), 0.0, sin(a + 0.05)) * Data.ROAMER_ORBIT
		n.global_position = p
		if ahead.distance_to(p) > 0.1: n.look_at(Vector3(ahead.x, p.y, ahead.z), Vector3.UP)

# planet type: deep, shallow, land, high, sea level (-1 = no sea), polar caps, cloud cover, atmosphere tint
const PLANET_LOOKS := {
	"terran": [Color(0.05, 0.16, 0.42), Color(0.12, 0.42, 0.7), Color(0.25, 0.48, 0.2), Color(0.52, 0.45, 0.32), -0.05, true, 0.75, Color(0.45, 0.7, 1.0)],
	"jungle": [Color(0.03, 0.2, 0.3), Color(0.08, 0.45, 0.5), Color(0.12, 0.5, 0.18), Color(0.3, 0.6, 0.25), -0.05, true, 0.75, Color(0.45, 1.0, 0.7)],
	"ocean": [Color(0.02, 0.1, 0.4), Color(0.1, 0.45, 0.8), Color(0.75, 0.7, 0.5), Color(0.3, 0.55, 0.3), 0.28, true, 0.8, Color(0.4, 0.7, 1.0)],
	"ice": [Color(0.55, 0.7, 0.85), Color(0.75, 0.87, 0.95), Color(0.88, 0.93, 0.98), Color(0.6, 0.72, 0.85), -0.2, true, 0.4, Color(0.7, 0.9, 1.0)],
	"desert": [Color(0.55, 0.38, 0.2), Color(0.7, 0.5, 0.28), Color(0.82, 0.66, 0.4), Color(0.6, 0.36, 0.22), -1.0, false, 0.15, Color(1.0, 0.75, 0.5)],
	"lava": [Color(1.0, 0.45, 0.08), Color(0.9, 0.2, 0.05), Color(0.16, 0.1, 0.1), Color(0.3, 0.2, 0.18), -0.18, false, 0.2, Color(1.0, 0.45, 0.25)],
	"dead": [Color(0.2, 0.2, 0.23), Color(0.3, 0.3, 0.33), Color(0.42, 0.41, 0.42), Color(0.58, 0.56, 0.55), -1.0, false, 0.0, Color(0.5, 0.55, 0.65)],
	"gas": [Color(0.75, 0.55, 0.35), Color(0.9, 0.75, 0.55), Color(0.6, 0.42, 0.3), Color(0.95, 0.85, 0.7), -1.0, false, 0.0, Color(1.0, 0.85, 0.65)],
	"city": [Color(0.05, 0.1, 0.22), Color(0.1, 0.2, 0.35), Color(0.35, 0.37, 0.42), Color(0.75, 0.7, 0.5), -0.15, true, 0.5, Color(0.6, 0.8, 1.0)],
	"crystal": [Color(0.3, 0.15, 0.5), Color(0.5, 0.35, 0.8), Color(0.55, 0.8, 0.9), Color(0.9, 0.75, 1.0), -0.1, false, 0.3, Color(0.8, 0.6, 1.0)],
	"toxic": [Color(0.15, 0.3, 0.05), Color(0.4, 0.6, 0.1), Color(0.25, 0.28, 0.12), Color(0.6, 0.65, 0.2), -0.05, false, 0.6, Color(0.6, 1.0, 0.3)],
	"machine": [Color(0.06, 0.07, 0.1), Color(0.12, 0.14, 0.2), Color(0.3, 0.32, 0.38), Color(0.2, 0.75, 0.85), -0.2, false, 0.1, Color(0.4, 0.9, 1.0)],
}

# Real planet maps (the "worlds" pack, assets/worlds/<map>.jpg, made from NASA's public maps by
# tools/planets/make_worlds.py). planet type: variants of [map, colour tint, saturation]; a planet picks one by its id.
const PLANET_MAPS := {
	"terran": [["earth", Color(1, 1, 1), 1.0]],
	"jungle": [["earth", Color(0.72, 1.1, 0.68), 1.0]],
	"ocean": [["earth", Color(0.6, 0.86, 1.25), 0.7]],
	"ice": [["europa", Color(0.82, 0.93, 1.1), 1.0], ["pluto", Color(0.82, 0.95, 1.12), 0.35]],
	"desert": [["mars", Color(1, 1, 1), 1.0], ["io", Color(1.0, 0.86, 0.68), 0.9]],
	"lava": [["venus", Color(1.15, 0.62, 0.42), 1.1]],
	"dead": [["charon", Color(1, 1, 1), 0.8], ["ganymede", Color(0.72, 0.72, 0.75), 1.0]],
	"gas": [["jupiter", Color(1, 1, 1), 1.0], ["saturn", Color(1, 1, 1), 1.0], ["neptune", Color(1, 1, 1), 1.0], ["titan", Color(1, 0.95, 0.9), 1.0]],
	"city": [["ganymede", Color(0.55, 0.63, 0.82), 1.0], ["earth", Color(0.72, 0.78, 0.95), 0.25]],
	"crystal": [["europa", Color(1.0, 0.7, 1.28), 1.0], ["pluto", Color(0.92, 0.7, 1.25), 0.6]],
	"toxic": [["io", Color(0.7, 1.12, 0.4), 1.0], ["venus", Color(0.5, 1.05, 0.35), 0.9]],
	"machine": [["ganymede", Color(0.4, 0.76, 0.86), 1.0], ["charon", Color(0.45, 0.72, 0.82), 0.6]],
}
const PLANET_SHADER := """shader_type spatial;
render_mode unshaded, cull_back;
// One real map, coloured for this world. The sun and the planet never move, so the day and night sides are fixed:
// a single dot product, no lights. The atmosphere glows INSIDE the edge of the disc, on the lit side.
uniform sampler2D map : source_color, repeat_enable, filter_linear_mipmap;
uniform vec3 tint = vec3(1.0);
uniform float sat = 1.0;
uniform float roll = 0.0;
uniform vec2 flip = vec2(0.0);      // 1 = mirror that way, so one map gives four different worlds
uniform vec3 sun_dir = vec3(0.0, 0.0, 1.0);
uniform vec3 air : source_color = vec3(0.45, 0.7, 1.0);
uniform float air_k = 1.0;
varying vec3 wn;
void vertex() { wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz); }
void fragment() {
	vec2 uv = mix(UV, vec2(1.0) - UV, flip);
	vec3 c = texture(map, vec2(uv.x + roll, uv.y)).rgb;
	float g = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(g), c, sat) * tint;
	float day = smoothstep(-0.16, 0.3, dot(normalize(wn), sun_dir));
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.4);
	ALBEDO = c * (0.03 + 0.97 * day) + air * rim * air_k * (0.06 + 0.94 * day);
}"""
const CLOUD_SHADER := """shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never;
uniform sampler2D map : repeat_enable, filter_linear_mipmap;
uniform float amount = 0.7;
uniform float roll = 0.0;
uniform vec3 sun_dir = vec3(0.0, 0.0, 1.0);
varying vec3 wn;
void vertex() { wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz); }
void fragment() {
	float day = smoothstep(-0.16, 0.3, dot(normalize(wn), sun_dir));
	ALBEDO = vec3(0.04 + 0.96 * day);
	ALPHA = clamp(texture(map, vec2(UV.x + roll, UV.y)).r * 1.6, 0.0, 1.0) * amount;
}"""
const HALO_SHADER := """shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never;
// a THIN haze just outside the planet's edge, lit side only (the old one was a thick shell: a glass ball)
uniform vec4 tint : source_color;
uniform vec3 sun_dir = vec3(0.0, 0.0, 1.0);
varying vec3 wn;
void vertex() { wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz); }
void fragment() {
	// brightest right at the planet's edge (where this shell's facing is about 0.26), fading to nothing outward
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float f = smoothstep(0.0, 0.26, ndv) * (1.0 - smoothstep(0.26, 0.5, ndv));
	float day = smoothstep(-0.25, 0.35, dot(normalize(wn), sun_dir));
	ALBEDO = tint.rgb * f * 0.8 * (0.06 + 0.94 * day);
	ALPHA = f;
}"""
var planet_clouds: MeshInstance3D
var planet_real := false      # the planet wears its real map (the "worlds" pack is in)
var dock_gate: Node3D         # the planet docking gate: the owner's ring with four arch pieces round it

## Which map, tint and saturation this planet wears.
func planet_map(d: Dictionary) -> Array:
	var v: Array = PLANET_MAPS.get(d["palette"], PLANET_MAPS["terran"])
	return v[absi(hash(d["id"])) % v.size()]

## The real-map material for one world: its type's map, tinted, rolled and mirrored by its id, lit from the sun's side.
func _world_material(d: Dictionary, at: Vector3) -> ShaderMaterial:
	var pm := planet_map(d)
	var look: Array = PLANET_LOOKS.get(d["palette"], PLANET_LOOKS["terran"])
	if _world_shader == null:
		_world_shader = Shader.new()
		_world_shader.code = PLANET_SHADER
	var m := ShaderMaterial.new()
	m.shader = _world_shader
	m.set_shader_parameter("map", load("res://assets/worlds/%s.jpg" % pm[0]))
	m.set_shader_parameter("tint", Vector3(pm[1].r, pm[1].g, pm[1].b))
	m.set_shader_parameter("sat", pm[2])
	m.set_shader_parameter("roll", float(absi(hash(str(d["id"]) + "roll")) % 1000) / 1000.0)
	var fh := absi(hash(str(d["id"]) + "flip"))
	m.set_shader_parameter("flip", Vector2(float(fh % 2), float((fh / 2) % 2)))
	m.set_shader_parameter("sun_dir", (sun_pos - at).normalized())
	m.set_shader_parameter("air", look[7])
	m.set_shader_parameter("air_k", 0.25 if d["palette"] in ["dead", "machine"] else 0.9)
	return m
var _world_shader: Shader

## Placeholder planets and stations: the rest of the system's catalog contents. You can see them, target them and fly
## to them; no docking or landing yet. Planets wear their type's real map (a flat temporary colour until the "worlds"
## pack is in); stations are a small code-made stand-in in the faction's colour.
var extras: Array = []          # Node3D, meta kind "landmark"
var platforms: Array = []       # v1.9b: the docking platforms floating over the other planets (dock there for its jobs)
var extra_worlds: Array = []    # [MeshInstance3D, data] waiting for / wearing the real map
func _build_extras() -> void:
	if surface_mode or not extras.is_empty() or not is_inside_tree(): return
	platforms = platforms.filter(func(x): return is_instance_valid(x))
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = Data.PH_SPHERE_SEGMENTS
	sphere.rings = Data.PH_SPHERE_SEGMENTS / 2
	for d: Dictionary in sys.get("more_planets", []):
		var n := Node3D.new()
		n.name = d["name"]
		n.position = d["pos"]
		n.set_meta("kind", "landmark")
		n.set_meta("info", d)
		n.set_meta("radius", float(d["radius"]))
		add_child(n)
		var mi := MeshInstance3D.new()
		mi.mesh = sphere
		mi.scale = Vector3.ONE * float(d["radius"])
		var look: Array = PLANET_LOOKS.get(d["palette"], PLANET_LOOKS["terran"])
		var tm := StandardMaterial3D.new()      # temporary colouring
		tm.albedo_color = (look[2] as Color).lerp(look[1], 0.4)
		tm.roughness = 1.0
		mi.material_override = tm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(mi)
		extras.append(n)
		extra_worlds.append([mi, d])
		_build_platform(n, d)   # v1.9b
	var cyl := CylinderMesh.new()
	cyl.radial_segments = 12
	cyl.rings = 1
	var tor := TorusMesh.new()
	tor.inner_radius = 30.0
	tor.outer_radius = 36.0
	tor.rings = 24
	tor.ring_segments = 6
	for d: Dictionary in sys.get("more_stations", []):
		var n := Node3D.new()
		n.name = d["name"]
		n.position = d["pos"]
		n.set_meta("kind", "landmark")
		n.set_meta("info", d)
		n.set_meta("radius", Data.PH_STATION_RADIUS)
		add_child(n)
		var c: Color = d["color"]
		_mesh(n, cyl, Vector3.ZERO, c, Vector3(9, 44, 9))
		_mesh(n, tor, Vector3.ZERO, c.darkened(0.2))
		_mesh(n, BoxMesh.new(), Vector3.ZERO, Color(0.12, 0.2, 0.42), Vector3(70, 1.2, 14))
		_mesh(n, BoxMesh.new(), Vector3(0, 24, 0), Color(1.0, 0.85, 0.5), Vector3(2, 2, 2), Vector3.ZERO, true)
		extras.append(n)
		if Data.is_st3d(d.get("model", "")):   # v1.9d: one of the owner's 3D stations: dockable, its own size
			n.set_meta("station3d", str(d["model"]))
			n.set_meta("radius", STATION_WIDTH * Data.st3d_scale(str(d["model"])) * Data.STATION3D_HIT)
			n.set_meta("dock", true)
			docks3d.append(n)
	for r: Array in Data.STATION3D_ROAMERS.get(sys_id, []):   # v1.9d: roaming Cybermorph battleships
		var rn := Node3D.new()
		rn.name = str(r[1])
		rn.set_meta("kind", "landmark")
		rn.set_meta("info", {"id": "%s_%s" % [sys_id, r[0]], "name": str(r[1]), "kind": "landmark", "desc": "Roaming Cybermorph battleship. It patrols this system; it is not a dock."})
		rn.set_meta("station3d", str(r[0]))
		rn.set_meta("scale_k", Data.ROAMER_SCALE)
		rn.set_meta("radius", STATION_WIDTH * Data.ROAMER_SCALE * Data.STATION3D_HIT)
		rn.set_meta("roamer", true)
		rn.set_meta("angle", float(roamers.size()) * PI + float(absi(hash(sys_id)) % 628) / 100.0)
		rn.set_meta("centre", (sys["station"]["pos"] as Vector3))
		add_child(rn)
		_mesh(rn, cyl, Vector3.ZERO, Color(0.55, 0.2, 0.6), Vector3(20, 60, 20))   # (stand-in until its pack is in)
		roamers.append(rn)
		extras.append(rn)
	_update_roamers(0.0)
	_extras_st3d()
	_extra_worlds_real()

func _extra_worlds_real() -> void:
	if surface_mode or not Packs.is_ready("worlds"): return
	for w in extra_worlds:
		if not is_instance_valid(w[0]) or (w[0] as MeshInstance3D).material_override is ShaderMaterial: continue
		if ResourceLoader.exists("res://assets/worlds/%s.jpg" % planet_map(w[1])[0]):
			(w[0] as MeshInstance3D).material_override = _world_material(w[1], (w[0] as MeshInstance3D).global_position)

## Swap the code-made planet texture for the real map with fixed day/night and clouds (once the pack is in).
func _planet_real() -> void:
	if planet_real or surface_mode or not is_instance_valid(planet) or not planet.has_meta("surface"): return
	var d: Dictionary = planet.get_meta("info")
	var pm := planet_map(d)
	var path := "res://assets/worlds/%s.jpg" % pm[0]
	if not (Packs.is_ready("worlds") and ResourceLoader.exists(path)): return
	var look: Array = PLANET_LOOKS.get(d["palette"], PLANET_LOOKS["terran"])
	var to_sun: Vector3 = (sun_pos - planet.global_position).normalized()
	var roll := float(absi(hash(str(d["id"]) + "roll")) % 1000) / 1000.0
	var m := _world_material(d, planet.global_position)
	(planet.get_meta("surface") as MeshInstance3D).material_override = m
	if planet.has_meta("halo"): ((planet.get_meta("halo") as MeshInstance3D).material_override as ShaderMaterial).set_shader_parameter("sun_dir", to_sun)
	if float(look[6]) >= 0.3 and ResourceLoader.exists("res://assets/worlds/clouds.jpg"):
		var r: float = planet.get_meta("radius")
		var cs := SphereMesh.new()
		cs.radius = r * 1.012
		cs.height = r * 2.024
		cs.radial_segments = 48
		cs.rings = 24
		planet_clouds = MeshInstance3D.new()
		planet_clouds.mesh = cs
		planet_clouds.visibility_range_end = Data.PLANET_SHELL_RANGE   # v1.9k (as the haze)
		var csh := Shader.new()
		csh.code = CLOUD_SHADER
		var cm := ShaderMaterial.new()
		cm.shader = csh
		cm.set_shader_parameter("map", load("res://assets/worlds/clouds.jpg"))
		cm.set_shader_parameter("amount", float(look[6]))
		cm.set_shader_parameter("roll", fmod(roll * 3.7, 1.0))
		cm.set_shader_parameter("sun_dir", to_sun)
		planet_clouds.material_override = cm
		planet_clouds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		planet.add_child(planet_clouds)
	planet_real = true

## The planet docking gate: the owner's ring lying over the dock point with four arch pieces standing round it,
## feet toward the planet, so it sits on top of the atmosphere. Replaces the plain green beacon ring.
func _dock_gate() -> void:
	if dock_gate != null or surface_mode or not is_instance_valid(planet): return
	var beacon: Node3D = planet.get_node_or_null("LandingBeacon")
	if beacon == null or not rings_ready() or not ResourceLoader.exists("res://assets/structures/dock_arch.glb"): return
	var meshes: Array = []
	for path in [GATE_RING_PATH, "res://assets/structures/dock_arch.glb"]:
		var sc := (load(path) as PackedScene).instantiate()
		var found := sc.find_children("*", "MeshInstance3D", true, false)
		meshes.append((found[0] as MeshInstance3D).mesh if not found.is_empty() else null)
		sc.free()
	if meshes[0] == null or meshes[1] == null: return
	dock_gate = Node3D.new()
	dock_gate.name = "DockGate"
	beacon.add_child(dock_gate)      # the beacon faces the planet: -Z is down toward it
	var ring := MeshInstance3D.new()
	ring.mesh = meshes[0]
	ring.scale = Vector3.ONE * DOCK_RING_SCALE
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dock_gate.add_child(ring)
	for i in 4:
		var a := i * TAU / 4.0 + TAU / 8.0
		var out := Vector3(cos(a), sin(a), 0)
		var arch := MeshInstance3D.new()
		arch.mesh = meshes[1]
		arch.transform = Transform3D(Basis(Vector3(0, 0, 1).cross(out), Vector3(0, 0, 1), out).scaled(Vector3.ONE * DOCK_ARCH_SCALE), out * DOCK_ARCH_SCALE * 0.62 + Vector3(0, 0, -8))
		arch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		dock_gate.add_child(arch)

## v1.9b (owner: every planet gets a docking ring): a small floating platform: a round deck with a landing pad, a glowing
## rim and lamp posts, room left to build on later, and the docking ring floating over the pad. Its top faces +Y of
## `parent`.
func _platform_deck(parent: Node3D, with_ring := true) -> void:
	var deck := CylinderMesh.new()
	deck.top_radius = Data.PLATFORM_RADIUS
	deck.bottom_radius = Data.PLATFORM_RADIUS * 0.82
	deck.height = 8.0
	deck.radial_segments = 24
	deck.rings = 1
	_mesh(parent, deck, Vector3(0, -4, 0), Color(0.42, 0.45, 0.5))
	var under := CylinderMesh.new()
	under.top_radius = Data.PLATFORM_RADIUS * 0.5
	under.bottom_radius = 6.0
	under.height = 30.0
	under.radial_segments = 12
	under.rings = 1
	_mesh(parent, under, Vector3(0, -23, 0), Color(0.26, 0.28, 0.32))
	var pad := CylinderMesh.new()
	pad.top_radius = Data.PLATFORM_RADIUS * 0.45
	pad.bottom_radius = pad.top_radius
	pad.height = 0.6
	pad.radial_segments = 24
	pad.rings = 1
	_mesh(parent, pad, Vector3(0, 0.3, 0), Color(0.95, 0.75, 0.2), Vector3.ONE, Vector3.ZERO, true)
	var rim := TorusMesh.new()
	rim.inner_radius = Data.PLATFORM_RADIUS - 2.0
	rim.outer_radius = Data.PLATFORM_RADIUS + 1.0
	rim.rings = 32
	rim.ring_segments = 6
	_mesh(parent, rim, Vector3.ZERO, Color(0.3, 0.9, 1.0), Vector3.ONE, Vector3.ZERO, true)
	var post := BoxMesh.new()
	post.size = Vector3(2.5, 12.0, 2.5)
	for i in 6:
		var a := i * TAU / 6.0
		var at := Vector3(cos(a), 0, sin(a)) * (Data.PLATFORM_RADIUS - 6.0)
		_mesh(parent, post, at + Vector3(0, 6, 0), Color(0.3, 0.32, 0.36))
		_mesh(parent, SphereMesh.new(), at + Vector3(0, 13, 0), Color(0.3, 1.0, 0.6), Vector3.ONE * 2.0, Vector3.ZERO, true)
	if not with_ring: return
	var ring := TorusMesh.new()   # the docking ring standing over the pad: fly through it to dock
	ring.inner_radius = 24.0
	ring.outer_radius = 28.0
	ring.rings = 32
	ring.ring_segments = 6
	_mesh(parent, ring, Vector3(0, 40, 0), Color(0.3, 1.0, 0.6), Vector3.ONE, Vector3.ZERO, true)

## v1.9b: the planet with this id in this system (the main one or one of the others); null = not here.
func planet_node(pid: String) -> Node3D:
	if is_instance_valid(planet) and str((planet.get_meta("info", {}) as Dictionary).get("id", sys["planet"].get("id", ""))) == pid: return planet
	for x in extras:
		if is_instance_valid(x) and str((x.get_meta("info", {}) as Dictionary).get("id", "")) == pid: return x
	return planet if is_instance_valid(planet) and pid == str(sys["planet"].get("id", "")) else null

## v1.9b: a dockable platform over one of the other planets (d = its more_planets entry). Docking opens that planet's
## own board: jobs on that planet only.
func _build_platform(world: Node3D, d: Dictionary) -> void:
	var r := float(d["radius"])
	var toward: Vector3 = (station.global_position - world.global_position).normalized() if is_instance_valid(station) else Vector3.UP
	var pl := Node3D.new()
	pl.name = "%s Dock" % d["name"]
	world.add_child(pl)
	pl.global_position = world.global_position + toward * (r + Data.PLATFORM_ALT)
	pl.global_basis = Basis.IDENTITY   # the deck floats level: fly down through the ring onto the pad
	pl.set_meta("kind", "platform")
	pl.set_meta("radius", Data.PLATFORM_RADIUS)
	pl.set_meta("info", {"id": str(d["id"]), "name": pl.name, "kind": "planet", "planet": str(d["id"]),
		"desc": "Docking platform over %s. Jobs here are on %s." % [d["name"], d["name"]]})
	_platform_deck(pl)
	platforms.append(pl)

func _planet_texture(palette: String, seed_text := "") -> ImageTexture:
	var w := 512
	var h := 256
	var look: Array = PLANET_LOOKS.get(palette, PLANET_LOOKS["terran"])
	var key := palette if seed_text == "" else seed_text      # hand-made planets keep their old look
	var n := FastNoiseLite.new()
	n.seed = hash(key)
	n.frequency = 0.012
	n.fractal_octaves = 4
	var clouds := FastNoiseLite.new()
	clouds.seed = hash(key) + 7
	clouds.frequency = 0.03
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var deep: Color = look[0]
	var shallow: Color = look[1]
	var land: Color = look[2]
	var high: Color = look[3]
	var sea: float = look[4]
	var banded: bool = palette == "gas"
	for y in h:
		var lat := (float(y) / h - 0.5) * PI
		for x in w:
			var lon := float(x) / w * TAU
			var p := Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon)) * 180.0
			var v := n.get_noise_3dv(p)
			var c: Color
			if banded:      # gas giant: colour bands by latitude, stirred a little
				var b := sin(lat * 9.0 + v * 2.5) * 0.5 + 0.5
				c = deep.lerp(shallow, b).lerp(high, clampf(v * 1.5, 0.0, 0.6))
			elif v < sea: c = deep.lerp(shallow, clampf((v + 0.5) / 0.45, 0.0, 1.0))
			else: c = land.lerp(high, clampf((v - maxf(sea, -0.3)) * 2.2, 0.0, 1.0))
			if look[5] and absf(lat) > 1.25: c = c.lerp(Color(0.92, 0.95, 1.0), 0.8)
			var cl := clouds.get_noise_3dv(p)
			if float(look[6]) > 0.0 and cl > 0.15: c = c.lerp(Color(1, 1, 1), clampf((cl - 0.15) * 2.2, 0.0, float(look[6])))
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

func _build_planet(d: Dictionary) -> void:
	planet = Node3D.new()
	planet.name = d["name"]
	planet.position = d["pos"]
	planet.set_meta("kind", "planet")
	planet.set_meta("info", d)
	var r: float = d["radius"]
	planet.set_meta("radius", r)
	add_child(planet)
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 72
	sm.rings = 36
	var mi := MeshInstance3D.new()
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_texture = _planet_texture(d["palette"], d["id"] if sys.get("generated", false) else "")
	m.roughness = 0.9
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	planet.add_child(mi)
	planet.set_meta("surface", mi)
	# atmosphere rim
	var atm := MeshInstance3D.new()
	var am := SphereMesh.new()
	am.radius = r * 1.035   # a thin haze past the edge (it was 1.12: a glass ball)
	am.height = r * 2.07
	am.radial_segments = 48
	am.rings = 24
	atm.mesh = am
	var sh := Shader.new()
	sh.code = HALO_SHADER
	var sm2 := ShaderMaterial.new()
	sm2.shader = sh
	sm2.set_shader_parameter("tint", PLANET_LOOKS.get(d["palette"], PLANET_LOOKS["jungle"])[7])
	atm.material_override = sm2
	sm2.set_shader_parameter("sun_dir", (sun_pos - planet.global_position).normalized() if sun_pos != Vector3.INF else Vector3(0, 0, 1))
	atm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	atm.visibility_range_end = Data.PLANET_SHELL_RANGE   # v1.9k: thin shells fight the surface for depth far away (the flicker)
	planet.add_child(atm)
	planet.set_meta("halo", atm)
	# landing beacon ring at the dock point
	var beacon := Node3D.new()
	beacon.name = "LandingBeacon"
	planet.add_child(beacon)
	var tor := TorusMesh.new()
	tor.inner_radius = 26.0
	tor.outer_radius = 29.0
	tor.rings = 32
	tor.ring_segments = 6
	var bm := _mesh(beacon, tor, Vector3.ZERO, Color(0.3, 1.0, 0.6), Vector3.ONE, Vector3(90, 0, 0), true)
	bm.set_meta("blink", 0.0)
	var dp := dock_point(planet)
	beacon.global_position = dp
	beacon.look_at(planet.global_position, Vector3.UP)
	var deck := Node3D.new()   # v1.9b: the main planet's ring floats on a platform too
	deck.name = "DockPlatform"
	beacon.add_child(deck)
	deck.transform = Transform3D(Basis(Vector3.RIGHT, Vector3(0, 0, 1), Vector3(0, -1, 0)), Vector3(0, 0, -30))   # deck top faces away from the planet, 30 m under the ring
	_platform_deck(deck, false)   # (the docking gate is its ring)
	_planet_real()
	_dock_gate()
	# placeholders are built a moment after arrival, so they never add to the load hitch of a jump
	get_tree().create_timer(Data.PH_BUILD_DELAY).timeout.connect(_build_extras)
	if not Packs.pack_ready.is_connected(_on_world_pack): Packs.pack_ready.connect(_on_world_pack)
	Packs.request("worlds")
	for rp in Data.RING_PACKS: Packs.request(rp)   # v1.9r: the jump gate ring and the dock arch come first (small), not last with the stations

func _on_world_pack(pk: String) -> void:
	if pk == "worlds":
		_planet_real()
		_extra_worlds_real()
	if pk == "structures" or pk in Data.RING_PACKS: _dock_gate()

func dock_point(n: Node3D) -> Vector3:
	if n.get_meta("kind", "") == "waypoint": return n.global_position
	if surface_mode and n == station: return station.global_position + Vector3(0, 90, 160)
	if n == planet:
		var toward: Vector3 = (station.global_position - planet.global_position).normalized()
		return planet.global_position + toward * (float(planet.get_meta("radius")) + 60.0)
	if n.get_meta("kind", "") == "platform": return n.global_position + n.global_basis.y * 40.0   # v1.9b: through its ring
	if n.has_meta("dock"): return n.global_position + Vector3(0, 0, float(n.get_meta("radius")) + 60.0)   # v1.9d: in front of its hull
	return n.global_position + Vector3(0, 0, 150)

func _build_gate(d: Dictionary) -> void:
	var g := Node3D.new()
	g.name = d["name"]
	g.position = d["pos"]
	g.set_meta("kind", "gate")
	g.set_meta("info", d)
	g.set_meta("radius", 55.0)
	add_child(g)
	gates.append(g)
	# face the gate toward the system centre so arrivals come out facing inward
	var inward: Vector3 = (Vector3(0, 0, -1200) - g.position)
	if inward.length() < 10.0: inward = Vector3(0, 0, -1)
	g.look_at(g.position - inward.normalized(), Vector3.UP)
	var standin := Node3D.new()
	g.add_child(standin)
	g.set_meta("standin", standin)
	if str(d.get("gkind", "")) == "warp":   # v1.9z (owner): a warp gate is a Freelancer-style hole in space, no ring
		g.set_meta("hole", true)
		gate_portals.append(_warp_hole(g))
		return
	var ring := TorusMesh.new()
	ring.inner_radius = 44.0
	ring.outer_radius = 52.0
	ring.rings = 48
	ring.ring_segments = 8
	_mesh(standin, ring, Vector3.ZERO, Color(0.55, 0.6, 0.7), Vector3.ONE, Vector3(90, 0, 0))
	var box := BoxMesh.new()
	for i in 6:
		var a := i * TAU / 6.0
		_mesh(standin, box, Vector3(cos(a) * 56, sin(a) * 56, 0), Color(0.3, 0.33, 0.4), Vector3(10, 10, 16), Vector3(0, 0, rad_to_deg(a)))
		_mesh(standin, box, Vector3(cos(a) * 56, sin(a) * 56, 8.5), Color(0.3, 0.85, 1.0), Vector3(4, 4, 1), Vector3.ZERO, true)
	var portal := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 44.0
	disc.bottom_radius = 44.0
	disc.height = 0.5
	disc.radial_segments = 40
	portal.mesh = disc
	portal.rotation_degrees = Vector3(90, 0, 0)
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	# portal colour tells the gate type: the old cyan for hand-made gates, green jump, blue warp, purple rift
	var pc := Color(0.35, 0.8, 1.0)
	if (d["id"] as String).contains("_gate_"): pc = SystemBuilder.GATE_KINDS[d.get("gkind", "jump")][1]
	pm.albedo_texture = _radial_texture(pc, 0.0)
	pm.albedo_color = Color(1, 1, 1, 0.55)
	pm.cull_mode = BaseMaterial3D.CULL_DISABLED
	portal.material_override = pm
	g.add_child(portal)
	gate_portals.append(portal)

## v1.9z (owner: "make the warp gates like Freelancer's"): a hole in space, not a ring. A ragged, shifting opening
## (his red warp picture swirling inside it, see-through in the middle, a bright rim), sparks spiralling into it and a
## few wisps of cloud round it. Returns the opening (kept with the gate portals).
const WARP_HOLE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D noise : repeat_enable, filter_linear;
uniform vec3 rim_col : source_color = vec3(1.0, 0.55, 0.8);
uniform float power = 1.5;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0].xyz), INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1].xyz), INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x) / 6.2831853;
	float t = TIME;
	float edge = 0.52 + 0.22 * texture(noise, vec2(a * 2.0 + t * 0.03, t * 0.05)).r + 0.14 * texture(noise, vec2(a * 7.0 - t * 0.07, 0.5 + t * 0.09)).r;
	vec2 tuv = vec2(r * 1.4 - t * 0.35, a + r * 0.7 + t * 0.06);   // the picture swirling into the hole
	vec3 c = texture(tex, tuv).rgb;
	float inside = smoothstep(edge, edge - 0.3, r);
	float rim = exp(-pow((r - edge) * 10.0, 2.0));
	float core = smoothstep(0.35, 0.0, r);
	ALBEDO = c * 1.4 + rim_col * rim * 1.2 + vec3(1.0, 0.85, 0.95) * core * 0.5;
	ALPHA = clamp((inside * (0.25 + 0.55 * smoothstep(0.0, edge, r)) + rim * 0.9 + core * 0.3) * power, 0.0, 1.0);
}
"""
static var _hole_noise: ImageTexture
func _warp_hole(g: Node3D) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var hole := MeshInstance3D.new()
	hole.name = "WarpHole"
	hole.mesh = q
	var sh := Shader.new()
	sh.code = WARP_HOLE_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	if ResourceLoader.exists("res://assets/fx/warp_gate_tunnel.jpg"): m.set_shader_parameter("tex", load("res://assets/fx/warp_gate_tunnel.jpg"))
	if _hole_noise == null:
		var fn := FastNoiseLite.new()
		fn.seed = 31
		fn.frequency = 0.03
		fn.fractal_octaves = 3
		_hole_noise = ImageTexture.create_from_image(fn.get_seamless_image(128, 128))
	m.set_shader_parameter("noise", _hole_noise)
	m.set_shader_parameter("rim_col", Data.WARP_HOLE_RIM)
	hole.material_override = m
	hole.scale = Vector3.ONE * Data.WARP_HOLE_SIZE
	hole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hole.extra_cull_margin = Data.WARP_HOLE_SIZE
	g.add_child(hole)
	# sparks spiralling in
	var sp := CPUParticles3D.new()
	sp.name = "WarpSparks"
	sp.amount = Data.WARP_HOLE_SPARKS
	sp.lifetime = 2.6
	sp.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE_SURFACE
	sp.emission_sphere_radius = Data.WARP_HOLE_SIZE * 0.7
	sp.gravity = Vector3.ZERO
	sp.direction = Vector3.ZERO
	sp.spread = 180.0
	sp.initial_velocity_min = 2.0
	sp.initial_velocity_max = 8.0
	sp.radial_accel_min = -42.0
	sp.radial_accel_max = -26.0
	sp.tangential_accel_min = 18.0
	sp.tangential_accel_max = 34.0
	sp.scale_amount_min = 1.2
	sp.scale_amount_max = 3.2
	var sq := QuadMesh.new()
	sq.size = Vector2(1, 1)
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	smat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	smat.vertex_color_use_as_albedo = true
	smat.disable_fog = true
	smat.albedo_texture = _radial_texture(Color.WHITE, 0.0)
	sq.material = smat
	sp.mesh = sq
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.85, 0.9, 0.0))
	grad.add_point(0.25, Color(1.0, 0.6, 0.85, 1.0))
	grad.set_color(1, Color(Data.WARP_HOLE_RIM, 0.0))
	sp.color_ramp = grad
	g.add_child(sp)
	# wisps of cloud round it
	for i in 7:
		var w := MeshInstance3D.new()
		w.mesh = q
		var wm := _puff_mat(Data.WARP_HOLE_CLOUD, 0.55, Vector2(0.2, 0.7))
		w.material_override = wm
		var a := TAU * i / 7.0 + _rng.randf() * 0.5
		w.position = Vector3(cos(a), sin(a), _rng.randf_range(-0.3, 0.3)) * Data.WARP_HOLE_SIZE * _rng.randf_range(0.45, 0.75)
		w.scale = Vector3.ONE * Data.WARP_HOLE_SIZE * _rng.randf_range(0.5, 0.85)
		w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.add_child(w)
	g.set_meta("radius", Data.WARP_HOLE_SIZE * 0.45)
	return hole

## v1.9r: the gate ring and dock arch models are in: their own small packs, or the whole structures pack.
func rings_ready() -> bool:
	if Packs.is_ready("structures"): return true
	for rp in Data.RING_PACKS:
		if not Packs.is_ready(rp): return false
	return true

## The owner's jump gate ring replaces the code-made ring once the "structures" pack is in.
func _gate_model() -> void:
	if gate_model != null or gates.is_empty() or not is_instance_valid(gate_standin): return
	if not (rings_ready() and ResourceLoader.exists(GATE_RING_PATH)): return
	var sc := (load(GATE_RING_PATH) as PackedScene).instantiate()
	var found := sc.find_children("*", "MeshInstance3D", true, false)
	if not found.is_empty():
		for g in gates:
			if g.get_meta("hole", false): continue   # (a warp gate has no ring)
			var mi := MeshInstance3D.new()
			mi.mesh = (found[0] as MeshInstance3D).mesh
			mi.scale = Vector3.ONE * GATE_RING_SCALE
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			g.add_child(mi)
			(g.get_meta("standin") as Node3D).visible = false
			g.set_meta("radius", 2.9 * GATE_RING_SCALE)
			if g == gate: gate_model = mi
	sc.free()

func _on_gate_pack(pk: String) -> void:
	if (pk == "structures" or pk in Data.RING_PACKS) and not surface_mode:
		_gate_model()
		_station_model()

## Jump rings: a short tunnel of glowing rings behind the gate that the ship flies through as it jumps.
## Cheap: one shared torus mesh and one unshaded additive material; they light up one after another.
func show_jump_rings(col: Color, reach: float, at: Node3D = null) -> void:
	if at == null: at = gate
	clear_jump_rings()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.9
	tor.outer_radius = 1.0
	tor.rings = 32
	tor.ring_segments = 6
	for i in JUMP_RINGS:
		var k := float(i + 1) / JUMP_RINGS
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_color = Color(col.r, col.g, col.b, 0.0)
		var mi := MeshInstance3D.new()
		mi.mesh = tor
		mi.material_override = m
		mi.rotation_degrees = Vector3(90, 0, 0)
		mi.position = Vector3(0, 0, -reach * k)
		mi.scale = Vector3.ONE * lerpf(40.0, 16.0, k)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		at.add_child(mi)
		jump_rings.append(mi)
		var tw := mi.create_tween()
		tw.tween_interval(0.12 * i)
		tw.tween_property(m, "albedo_color:a", 0.9, 0.25)
		tw.parallel().tween_property(mi, "scale", mi.scale * 1.12, 0.25)

func clear_jump_rings() -> void:
	for r in jump_rings:
		if is_instance_valid(r): r.queue_free()
	jump_rings.clear()

func _rock_mesh(seed_v: int, ice: bool) -> ArrayMesh:
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.frequency = 1.3
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 10
	sm.rings = 6
	var arr := sm.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		var v := verts[i]
		verts[i] = v * (1.0 + n.get_noise_3dv(v * 1.7) * 0.45) * Vector3(1.0, 0.8, 1.15)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	for i in idx.size():
		st.add_vertex(verts[idx[i]])
	st.generate_normals()
	var m := st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.72, 0.85, 0.95) if ice else Color(0.42, 0.37, 0.33)
	mat.roughness = 0.35 if ice else 0.95
	mat.metallic = 0.1
	m.surface_set_material(0, mat)
	return m

func _build_belt(d: Dictionary) -> void:
	belt_center = d["center"]
	belt_radius = d["radius"]
	if Data.ASTEROIDS_BLOCK:
		_build_block_belt(d)
		return
	var variants := 3
	var per := int(d["count"]) / variants
	for v in variants:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _rock_mesh(hash(sys_id) + v, d["ice"])
		mm.instance_count = per
		for i in per:
			var a := _rng.randf() * TAU
			var dist := sqrt(_rng.randf()) * belt_radius
			var p := belt_center + Vector3(cos(a) * dist, _rng.randfn(0.0, 30.0), sin(a) * dist * 0.8)
			var r := lerpf(3.0, 24.0, pow(_rng.randf(), 2.2))
			var b := Basis.from_euler(Vector3(_rng.randf() * TAU, _rng.randf() * TAU, _rng.randf() * TAU)).scaled(Vector3.ONE * r)
			mm.set_instance_transform(i, Transform3D(b, p))
			rocks.append([p, r * 1.05])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.name = "Asteroids%d" % v
		add_child(mmi)

## v1.7x: the field as block asteroids: a few big ones and many small, spread through the field without overlapping.
func _build_block_belt(d: Dictionary) -> void:
	var holder := Node3D.new()
	holder.name = "Asteroids"
	add_child(holder)
	var big: int = int(Data.ASTEROID_BIG[0])
	for i in Data.ASTEROID_COUNT:
		var size: int = int(Data.ASTEROID_BIG[1]) if i < big else int(round(lerpf(float(Data.ASTEROID_SIZE[0]), float(Data.ASTEROID_SIZE[1]), pow(_rng.randf(), 1.8))))
		var r: float = size * Data.ASTEROID_CELL * 0.9
		var p := Vector3.INF
		for k in 12:
			var a := _rng.randf() * TAU
			var dist := sqrt(_rng.randf()) * maxf(10.0, belt_radius - r)
			var c: Vector3 = belt_center + Vector3(cos(a) * dist, _rng.randfn(0.0, 30.0), sin(a) * dist * 0.8)
			var clear := true
			for o in rocks:
				if (o[0] as Vector3).distance_to(c) < float(o[1]) + r + 6.0: clear = false
			if clear:
				p = c
				break
		if p == Vector3.INF: continue
		var ast = BlockAsteroid.new()
		ast.name = "Asteroid%d" % i
		ast.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(ast)
		ast.global_position = p
		ast.setup(hash(sys_id) * 31 + i, size, Data.ASTEROID_CELL, bool(d.get("ice", false)), Data.ASTEROID_TREASURE)
		ast.health = _piece_hp(ast)
		asteroids.append(ast)
		rocks.append([p, float(ast.radius)])
		ast.set_meta("rock", rocks[-1])

## Every frame: the asteroids tumble, broken pieces drift apart, and anything past the field's invisible sphere is gone.
func _update_asteroids(dt: float) -> void:
	if asteroids.is_empty(): return
	var near: bool = is_instance_valid(player) and (player.global_position.distance_to(belt_center) < belt_radius + 3000.0 or in_ring(player.global_position, 3000.0))
	var bound: float = belt_radius * Data.ASTEROID_BOUND
	for k in range(asteroids.size() - 1, -1, -1):
		if k >= asteroids.size(): continue
		var a = asteroids[k]
		if not is_instance_valid(a):
			asteroids.remove_at(k)
			continue
		if near: a.tick(dt)
		if a.vel != Vector3.ZERO:
			a.global_position += a.vel * dt
			var out_of: bool = not in_ring(a.global_position, 150.0) if a.has_meta("ring") else a.global_position.distance_to(belt_center) > bound
			if out_of: _remove_asteroid(a)   # drifted out of its field / ring: gone
	for i in range(loot.size() - 1, -1, -1):   # mined gold / diamond that drifts out of the field is lost too
		var l: Dictionary = loot[i]
		var lp: Vector3 = (l["node"] as Node3D).global_position if l.get("zero_g", false) else Vector3.ZERO
		if l.get("zero_g", false) and ((l.get("ring", false) and not in_ring(lp, 150.0)) or (not l.get("ring", false) and lp.distance_to(belt_center) > bound)):
			(l["node"] as Node3D).queue_free()
			loot.remove_at(i)

## The block asteroid a segment meets first: [asteroid, cell, point] or [].
func ray_asteroids(a: Vector3, b: Vector3) -> Array:
	if asteroids.is_empty() or not (in_belt_region(a) or in_belt_region(b)): return []
	var best: Array = []
	var bd := INF
	for ast in asteroids:
		if not is_instance_valid(ast): continue
		if _seg_closest(a, b, ast.global_position).distance_to(ast.global_position) > float(ast.radius): continue
		var h: Array = ast.ray(a, b)
		if h.is_empty(): continue
		var d := a.distance_to(h[1])
		if d < bd:
			bd = d
			best = [ast, h[0], h[1]]
	return best

## v1.8d: how much damage a piece takes before it splits (its tier; obsidian makes it tougher).
func _piece_hp(ast) -> float:
	var tier: int = clampi(int(ast.tier), 0, Data.ASTEROID_TIER_HP.size() - 1)
	var obs := float(ast.count(2)) / maxf(1.0, float(ast.solid_count))
	return float(Data.ASTEROID_TIER_HP[tier]) * (1.0 + Data.ASTEROID_OBSIDIAN_TOUGH * obs)

## v1.8d: damage to a piece; worn down, it splits (or, at the last tier, is destroyed).
func damage_asteroid(ast, dmg: float, at: Vector3, weapon: String) -> void:
	if not is_instance_valid(ast) or not (ast in asteroids): return
	ast.health = float(ast.health) - dmg
	if float(ast.health) > 0.0:
		_spark(at, ast.color_of(1).lightened(0.3), 2.5, 0.2)
		return
	split_asteroid(ast, weapon)

var asteroid_splits := 0      # (tests)
var asteroid_destroyed := 0   # (tests)
func split_asteroid(ast, weapon: String) -> Array:
	var at: Vector3 = ast.global_position
	var tier: int = int(ast.tier)
	if tier >= Data.ASTEROID_SPLIT.size() or ast.solid_count <= 1 or asteroids.size() >= Data.ASTEROID_PIECES_MAX:
		# the smallest pieces are destroyed: a burst, and any gold / diamond in it comes out for the tractor
		_spark(at, Color(1.0, 0.75, 0.4), maxf(8.0, float(ast.radius) * 1.2), 0.35)
		var gems := 0
		for mid in [3, 4]:
			var c: int = mini(int(ast.count(mid)), 4 - gems)
			for k in c:
				var before := loot.size()
				_on_mined(at + Vector3(_rng.randfn(0, 2), _rng.randfn(0, 2), _rng.randfn(0, 2)), "gold" if mid == 3 else "diamond", weapon)
				for q in range(before, loot.size()):
					loot[q]["zero_g"] = true
					loot[q]["ring"] = ast.has_meta("ring")
					loot[q]["vel"] = ast.vel + Vector3(_rng.randfn(0, 1), _rng.randfn(0, 1), _rng.randfn(0, 1)).normalized() * 4.0
				gems += 1
		asteroid_destroyed += 1
		_remove_asteroid(ast)
		return []
	var out: Array = []
	var holder: Node = ast.get_parent()
	for grp in ast.split_groups(int(Data.ASTEROID_SPLIT[tier])):
		var child = BlockAsteroid.new()
		child.name = "AsteroidPiece"
		child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(child)
		var local: Vector3 = child.setup_from(grp, int(ast.n), float(ast.cell), bool(ast.ice), tier + 1)
		child.global_transform = Transform3D(ast.global_transform.basis, ast.global_transform * local)
		var away: Vector3 = child.global_position - at
		if away.length() < 0.1: away = Vector3(_rng.randfn(0, 1), _rng.randfn(0, 1), _rng.randfn(0, 1))
		child.vel = ast.vel + away.normalized() * _rng.randf_range(Data.ASTEROID_SPLIT_SPEED[0], Data.ASTEROID_SPLIT_SPEED[1])
		child.spin = Vector3(_rng.randfn(0, 1), _rng.randfn(0, 1), _rng.randfn(0, 1)).normalized() * _rng.randf_range(0.1, 0.4)
		child.health = _piece_hp(child)
		if ast.has_meta("ring"): child.set_meta("ring", true)
		asteroids.append(child)
		rocks.append([child.global_position, float(child.radius)])
		child.set_meta("rock", rocks[-1])
		out.append(child)
	_spark(at, Color(1.0, 0.8, 0.5), maxf(10.0, float(ast.radius)), 0.3)
	asteroid_splits += 1
	_remove_asteroid(ast)
	return out

func _remove_asteroid(ast) -> void:
	var k := asteroids.find(ast)
	if k >= 0: asteroids.remove_at(k)
	if ast.has_meta("rock"): rocks.erase(ast.get_meta("rock"))
	ast.queue_free()

## A missile meets an asteroid: the piece it hit takes a big hit, and the blast hits every piece near it.
func blast_asteroid(ast, at: Vector3, kind: String) -> int:
	var spec: Array = Data.ASTEROID_MISSILE.get(kind, Data.ASTEROID_MISSILE["missile"])
	var hit := 0
	var others: Array = []
	for o in asteroids:
		if o != ast and is_instance_valid(o) and (o.global_position as Vector3).distance_to(at) < float(spec[1]) + float(o.radius): others.append(o)
	if is_instance_valid(ast):
		damage_asteroid(ast, float(spec[0]), at, kind)
		hit += 1
	for o in others:
		if not is_instance_valid(o) or not (o in asteroids): continue
		var d: float = maxf(0.0, (o.global_position as Vector3).distance_to(at) - float(o.radius) * 0.5)
		damage_asteroid(o, float(spec[2]) * clampf(1.0 - d / float(spec[1]), 0.2, 1.0), at, kind)
		hit += 1
	return hit

## v1.9s (owner: Freelancer-style nebulae). Every cloud in a system: the system's own nebula (grown Data.NEBULA_SIZE
## times) plus Data.NEBULA_EXTRA smaller unnamed clouds in other sizes and colours, placed clear of the station,
## planets, belt and gates. The same list every time for a system, so the nav map draws the same clouds.
static func nebulae_of(id: String, s: Dictionary) -> Array:
	var out: Array = []
	var n: Dictionary = s.get("nebula", {})
	if n.is_empty() or float(n.get("radius", 0.0)) <= 1.0: return out
	out.append({"name": str(n["name"]), "center": n["center"], "radius": float(n["radius"]) * Data.NEBULA_SIZE, "color": n["color"], "main": true})
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id + "_nebulae")
	var o: Vector3 = s["station"]["pos"]
	var avoid: Array = [[o, 1100.0], [s["planet"]["pos"], float(s["planet"]["radius"]) + 700.0]]
	var belt: Dictionary = s.get("asteroids", {})
	if not belt.is_empty(): avoid.append([belt["center"], float(belt["radius"]) + 300.0])
	for g in s.get("gates", []): avoid.append([g["pos"], 600.0])
	for x in s.get("more_planets", []): avoid.append([x["pos"], float(x.get("radius", 300.0)) + 600.0])
	for x in s.get("more_stations", []): avoid.append([x["pos"], 700.0])
	var shifts := [0.11, -0.13, 0.33, -0.3, 0.5]
	# v1.9z (owner: "the warp gates are hidden inside the nebula clouds, wherever they are"): every WARP gate sits in
	# its own cloud, Freelancer jump-hole style; systems without one have no gate cloud
	var gs: Array = s.get("gates", []).filter(func(x): return str(x.get("gkind", "")) == "warp")
	for g in gs:
		var gp: Vector3 = g["pos"]
		var gr := minf(rng.randf_range(Data.NEBULA_GATE_RADIUS[0], Data.NEBULA_GATE_RADIUS[1]), gp.distance_to(o) - 1100.0)
		if gr < Data.NEBULA_GATE_RADIUS[0] * 0.7: continue
		var c0 := gp + Vector3(rng.randfn(0, 1), rng.randfn(0, 0.4), rng.randfn(0, 1)).normalized() * gr * 0.2
		if c0.distance_to(out[0]["center"]) < gr + float(out[0]["radius"]) * 0.6: continue
		var gcol: Color = Data.WARP_HOLE_CLOUD.lerp(n["color"], 0.25)   # (the warp gate's red-purple, a touch of the system's)
		out.append({"name": "", "center": c0, "radius": gr, "color": gcol, "main": false, "gate": str(g.get("id", ""))})
	var tries := 0
	var gate_clouds := out.size() - 1
	while out.size() < 1 + gate_clouds + Data.NEBULA_EXTRA and tries < 120:
		tries += 1
		var r := rng.randf_range(Data.NEBULA_EXTRA_RADIUS[0], Data.NEBULA_EXTRA_RADIUS[1])
		var a := rng.randf() * TAU
		var dist := rng.randf_range(Data.NEBULA_EXTRA_DIST[0], Data.NEBULA_EXTRA_DIST[1])
		var c := o + Vector3(cos(a) * dist, rng.randf_range(-350.0, 350.0), sin(a) * dist)
		var ok := true
		for av in avoid:
			if c.distance_to(av[0]) < r + float(av[1]): ok = false
		for nd in out:
			if c.distance_to(nd["center"]) < r + float(nd["radius"]) + 500.0: ok = false
		if not ok: continue
		var col: Color = (n["color"] as Color)
		col.h = fposmod(col.h + float(shifts[(out.size() - 1 + rng.randi_range(0, 1)) % shifts.size()]), 1.0)
		col.s = clampf(col.s * rng.randf_range(0.8, 1.15), 0.25, 0.9)
		col.v = clampf(col.v * rng.randf_range(0.85, 1.1), 0.55, 1.0)
		out.append({"name": "", "center": c, "radius": r, "color": col, "main": false})
	for i in out.size():   # v1.9z: each cloud's own weather (the same every visit)
		out[i]["weather"] = Data.NEBULA_WEATHERS[absi(hash(id + "_wx%d" % i)) % Data.NEBULA_WEATHERS.size()]
	return out

var nebulae: Array = []          # v1.9s: the clouds in this system (see nebulae_of), each with its puff batch and lightning
var nebula_now := -1             # the cloud you're deepest in (-1: none)
var nebula_tint := Color.WHITE   # the colour of the haze you're in
var nebula_flash := 0.0          # 0..1 lightning lighting up the cloud around you
var nebula_flashes := 0          # lightning flashes so far (checks)
var _neb_stream: MultiMeshInstance3D
var _neb_stream_mat: ShaderMaterial
var _neb_fog_on := false
static var _puff_tex: ImageTexture
static var _puff_sh: Shader
static var _puff_quad: QuadMesh

## One soft smoke puff picture (white, the shader tints it), made once and shared by every cloud.
static func puff_texture() -> ImageTexture:
	if _puff_tex != null: return _puff_tex
	var sz := 128
	var nz := FastNoiseLite.new()
	nz.seed = 1977
	nz.frequency = 0.035
	nz.fractal_octaves = 4
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	for y in sz:
		for x in sz:
			var d := Vector2(x - sz / 2.0 + 0.5, y - sz / 2.0 + 0.5).length() / (sz / 2.0)
			var v := (nz.get_noise_2d(x, y) + 1.0) * 0.5
			var fall := clampf(1.0 - d, 0.0, 1.0)
			var a := pow(fall, 1.4) * clampf(v * 1.7 - 0.25, 0.0, 1.0)
			var b := 0.72 + 0.4 * v
			img.set_pixel(x, y, Color(b, b, b, clampf(a, 0.0, 1.0)))
	img.generate_mipmaps()
	_puff_tex = ImageTexture.create_from_image(img)
	return _puff_tex

## The puff shader: each puff faces the camera, turned its own way, fades out as you get close (so you fly into the fog,
## not through a flat picture), and lights up white when lightning flashes near it.
static func puff_shader() -> Shader:
	if _puff_sh != null: return _puff_sh
	_puff_sh = Shader.new()
	_puff_sh.code = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float alpha = 0.3;
uniform vec2 near_fade = vec2(0.3, 1.0);
uniform vec3 flash_pos = vec3(0.0);
uniform float flash_amt = 0.0;
uniform float flash_r = 600.0;
varying float v_fade;
varying float v_fl;
void vertex() {
	vec3 wpos = MODEL_MATRIX[3].xyz;
	float sc = length(MODEL_MATRIX[0].xyz);
	float h = fract(sin(dot(wpos, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
	float an = h * 6.2831853;
	vec2 q = mat2(vec2(cos(an), sin(an)), vec2(-sin(an), cos(an))) * VERTEX.xy;
	VERTEX = vec3(q, 0.0);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * sc, INV_VIEW_MATRIX[1] * sc, INV_VIEW_MATRIX[2] * sc, vec4(wpos, 1.0));
	float d = distance(wpos, INV_VIEW_MATRIX[3].xyz);
	v_fade = smoothstep(sc * near_fade.x, sc * near_fade.y, d);
	v_fl = flash_amt * clamp(1.0 - distance(wpos, flash_pos) / flash_r, 0.0, 1.0);
}
void fragment() {
	vec4 t = texture(tex, UV);
	ALBEDO = t.rgb * tint.rgb * COLOR.rgb + vec3(0.85, 0.92, 1.0) * v_fl * 1.4;
	ALPHA = clamp(t.a * (alpha * COLOR.a * (1.0 + v_fl * 0.8)) * v_fade, 0.0, 1.0);
}
"""
	return _puff_sh

func _puff_mat(col: Color, a: float, near: Vector2) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = puff_shader()
	m.set_shader_parameter("tex", puff_texture())
	m.set_shader_parameter("tint", col)
	m.set_shader_parameter("alpha", a)
	m.set_shader_parameter("near_fade", near)
	return m

func _build_nebula(d: Dictionary) -> void:
	nebulae = []
	nebula_now = -1
	nebula_flash = 0.0
	_neb_fog_on = false
	nebula_center = d["center"]
	nebula_color = d["color"]
	nebula_radius = 0.0
	var list := nebulae_of(sys_id, sys)
	if list.is_empty(): return
	nebula_radius = float(list[0]["radius"])
	if _puff_quad == null:
		_puff_quad = QuadMesh.new()
		_puff_quad.size = Vector2(1, 1)
	var holder := Node3D.new()
	holder.name = "Nebula"
	add_child(holder)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(sys_id) + 7
	for nd: Dictionary in list:
		var r := float(nd["radius"])
		var count := int(Data.NEBULA_PUFFS * clampf(r / 1500.0, 0.45, 1.0))
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = _puff_quad
		mm.instance_count = count
		var lobes: Array = []   # a lumpy cloud: puffs gather round a few lobes, not one ball
		for i in rng.randi_range(4, 7): lobes.append(Vector3(rng.randfn(0, 1), rng.randfn(0, 0.5), rng.randfn(0, 1)).normalized() * rng.randf_range(0.0, r * 0.5))
		var pts := PackedVector3Array()
		for i in count:
			var p: Vector3 = lobes[i % lobes.size()] + Vector3(rng.randfn(0, 1), rng.randfn(0, 0.6), rng.randfn(0, 1)) * r * 0.27
			if p.length() > r * 0.9: p = p.normalized() * r * rng.randf_range(0.55, 0.9)
			var k := p.length() / r
			var sc := r * rng.randf_range(0.13, 0.36) * (1.2 - 0.5 * k)
			mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * sc), p))
			var v := rng.randf_range(0.45, 1.3) if rng.randf() < 0.8 else rng.randf_range(0.2, 0.4)   # light and dark smoke
			var hue := Color(v, v * rng.randf_range(0.9, 1.08), v * rng.randf_range(0.92, 1.15), rng.randf_range(0.45, 1.0) * (1.0 - 0.35 * k))
			mm.set_instance_color(i, hue)
			pts.append(p)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Cloud" if nd["main"] else "Cloud%d" % nebulae.size()
		mmi.multimesh = mm
		mmi.position = nd["center"]
		mmi.custom_aabb = AABB(-Vector3.ONE * r * 1.6, Vector3.ONE * r * 3.2)
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := _puff_mat(nd["color"], Data.NEBULA_PUFF_ALPHA, Vector2(0.3, 1.0))
		mat.set_shader_parameter("flash_r", r * 0.5)
		mmi.material_override = mat
		holder.add_child(mmi)
		nd["mmi"] = mmi
		nd["mat"] = mat
		nd["pts"] = pts
		nd["next_flash"] = rng.randf_range(0.5, Data.NEBULA_FLASH_EVERY[1])
		if nd["weather"] == "rocks": _nebula_rocks(holder, nd, rng)
		nd["flash_t"] = -1.0
		nd["flash_at"] = nd["center"]
		nebulae.append(nd)
	# smoke streaming past the ship inside a cloud: a few small puffs kept round the player, shown only in the fog
	var sm := MultiMesh.new()
	sm.transform_format = MultiMesh.TRANSFORM_3D
	sm.use_colors = true
	sm.mesh = _puff_quad
	sm.instance_count = Data.NEBULA_STREAM
	for i in Data.NEBULA_STREAM:
		sm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * rng.randf_range(28.0, 70.0)), Vector3(0, -1e6, 0)))
		sm.set_instance_color(i, Color(1, 1, 1, rng.randf_range(0.5, 1.0)))
	_neb_stream = MultiMeshInstance3D.new()
	_neb_stream.name = "NebulaStream"
	_neb_stream.multimesh = sm
	_neb_stream.top_level = true
	_neb_stream.custom_aabb = AABB(-Vector3.ONE * 4e6, Vector3.ONE * 8e6)
	_neb_stream.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_neb_stream_mat = _puff_mat(nebula_color, 0.0, Vector2(0.12, 0.7))
	_neb_stream.material_override = _neb_stream_mat
	_neb_stream.visible = false
	holder.add_child(_neb_stream)

## How deep you are in the deepest cloud (0..1), and which one.
func _nebula_depth(p: Vector3) -> void:
	var best := 0.0
	var idx := -1
	for i in nebulae.size():
		var nd: Dictionary = nebulae[i]
		var r: float = nd["radius"]
		var k := clampf((r - p.distance_to(nd["center"])) / (r * 0.35), 0.0, 1.0)
		if k > best:
			best = k
			idx = i
	in_nebula = best
	nebula_now = idx
	if idx >= 0: nebula_tint = nebulae[idx]["color"]

func nebula_name() -> String:
	if nebula_now < 0 or nebula_now >= nebulae.size(): return ""
	return str(nebulae[nebula_now]["name"])

## v1.9z: the cloud closing round you: a big shell in the haze's colour round the camera, opaque deep inside, so the
## sky, stars and far planets are gone (the phone renderer does not fog the sky itself). Nearer things show in front.
var _dome: MeshInstance3D
var dome_alpha := 0.0
const DOME_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, cull_front, depth_draw_never, shadows_disabled, fog_disabled;
uniform sampler2D noise : repeat_enable, filter_linear_mipmap;
uniform sampler2DArray frames : repeat_enable, filter_linear_mipmap;   // v1.9z: the owner's looping cloud clip
uniform bool anim = false;
uniform float fpos = 0.0;
uniform float nframes = 48.0;
uniform vec4 col : source_color = vec4(1.0);
uniform float contrast = 1.0;
uniform float drift = 0.0;
varying vec3 dir;
void vertex() { dir = VERTEX; }
// sampled by direction on all three axes (no seam, no pinch at the top and bottom like a wrapped picture)
float tri(vec3 p, vec3 w) { return texture(noise, p.yz).r * w.x + texture(noise, p.xz).r * w.y + texture(noise, p.xy).r * w.z; }
float trif(vec3 p, vec3 w, float l) { return texture(frames, vec3(p.yz, l)).r * w.x + texture(frames, vec3(p.xz, l)).r * w.y + texture(frames, vec3(p.xy, l)).r * w.z; }
void fragment() {
	vec3 n = normalize(dir);
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec3 p = n * 2.2 + vec3(drift, drift * 0.3, drift * 0.6);
	float v;
	if (anim) {   // the clip, its frames blended so the slow loop runs smooth
		float f0 = floor(fpos);
		float f1 = mod(f0 + 1.0, nframes);
		vec3 q = n * 1.6;
		v = mix(trif(q, w, f0), trif(q, w, f1), fpos - f0);
	} else {
		v = tri(p, w) * 0.65 + tri(p * 2.7 + 0.37, w) * 0.35;
		v = clamp((v - 0.5) * 2.4 + 0.5, 0.0, 1.0);   // billows, not a flat wash
	}
	ALBEDO = col.rgb * mix(1.0, mix(0.4, 1.35, v), contrast);
	ALPHA = col.a;
}
"""
## The shell round the camera: in a cloud (its colour, billowing) or deep in a planet's atmosphere (bright and even,
## the sky's colour), so space fades out and the next view fades in without a black gap.
## v1.9z: the owner's looping cloud clips as a layered texture (one layer a frame), built once per clip from its
## picture of frames when its pack is in. null until then (the shell shows the still pattern meanwhile).
static var _anim_tex := {}
func _cloud_anim(clip: String) -> Texture2DArray:
	if _anim_tex.has(clip): return _anim_tex[clip]
	var pk := "cloudanim_" + clip
	var path := "res://assets/fx/cloudanim_%s.jpg" % clip
	if not (Packs.is_ready(pk) and ResourceLoader.exists(path)):
		Packs.request(pk)
		return null
	var src: Image = (load(path) as Texture2D).get_image()
	if src.is_compressed(): src.decompress()
	src.convert(Image.FORMAT_L8)
	var fw := src.get_width() / 8
	var layers: Array[Image] = []
	for i in Data.CLOUD_ANIM_FRAMES:
		var fr := src.get_region(Rect2i((i % 8) * fw, (i / 8) * fw, fw, fw))
		fr.generate_mipmaps()
		layers.append(fr)
	var arr := Texture2DArray.new()
	arr.create_from_images(layers)
	_anim_tex[clip] = arr
	return arr

var _dome_clip := ""
func _cloud_dome(a: float, col: Color, contrast := 1.0, clip := "") -> void:
	dome_alpha = a
	if a <= 0.01:
		if is_instance_valid(_dome): _dome.visible = false
		return
	if not is_instance_valid(_dome):
		_dome = MeshInstance3D.new()
		_dome.name = "CloudDome"
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 2.0
		sm.radial_segments = 32
		sm.rings = 16
		_dome.mesh = sm
		var sh := Shader.new()
		sh.code = DOME_SHADER
		var m := ShaderMaterial.new()
		m.shader = sh
		m.render_priority = -10
		var nt := NoiseTexture2D.new()   # billowing cloud walls, not a flat colour
		nt.width = 256
		nt.height = 256
		nt.seamless = true
		nt.generate_mipmaps = true
		var fn := FastNoiseLite.new()
		fn.frequency = 0.012
		fn.fractal_octaves = 5
		nt.noise = fn
		m.set_shader_parameter("noise", nt)
		_dome.material_override = m
		_dome.top_level = true
		_dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_dome.extra_cull_margin = 16384.0
		add_child(_dome)
	_dome.visible = true
	_dome.global_position = cam.global_position if is_instance_valid(cam) else player.global_position
	_dome.scale = Vector3.ONE * minf(Data.NEBULA_DOME_R, cam.far * 0.9 if is_instance_valid(cam) else Data.NEBULA_DOME_R)
	var mat := _dome.material_override as ShaderMaterial
	mat.set_shader_parameter("col", Color(col.darkened(0.15 * contrast), a))
	mat.set_shader_parameter("contrast", contrast)
	mat.set_shader_parameter("drift", fmod(time * 0.01, 100.0))   # the walls drift slowly
	var at: Texture2DArray = _cloud_anim(clip) if clip != "" else null
	if clip != _dome_clip or (at != null and mat.get_shader_parameter("frames") != at):
		_dome_clip = clip
		mat.set_shader_parameter("frames", at)
	mat.set_shader_parameter("anim", at != null)
	if at != null:
		mat.set_shader_parameter("nframes", float(Data.CLOUD_ANIM_FRAMES))
		mat.set_shader_parameter("fpos", fmod(time * Data.CLOUD_ANIM_FPS, float(Data.CLOUD_ANIM_FRAMES)))
		mat.set_shader_parameter("contrast", maxf(contrast, 0.85))

## The planet's daytime sky colour (from its surface biome), pale toward white; plain white when it has no surface.
func _sky_color_of(body: Node3D) -> Color:
	var pid: String = str(body.get_meta("info", {}).get("id", ""))
	if pid != "" and Surface.has_surface(pid):
		var b: Dictionary = Surface.biome(pid, 4 if Surface.grid(pid) == 3 else 0)
		return (b.get("sky", b.get("horizon", Color.WHITE)) as Color).lerp(Color.WHITE, 0.55)
	return Color(0.92, 0.95, 1.0)

## v1.9z (owner: "inside the atmosphere it should be white, not space"): the deeper you go into a planet's air, the
## more the sky's own colour closes round you, so the entry flows into the surface instead of through black space.
var atmo_color := Color.WHITE
func _update_atmo_dome() -> void:
	if surface_mode or in_nebula > 0.001: return
	if atmo_depth <= 0.0:
		if dome_alpha > 0.0 and not _neb_fog_on: _cloud_dome(0.0, Color.BLACK)
		return
	_cloud_dome(clampf(atmo_depth * 1.25, 0.0, 1.0), atmo_color, 0.35, Data.CLOUD_ANIM["atmo"])

func nebula_weather() -> String:
	if nebula_now < 0 or nebula_now >= nebulae.size(): return ""
	return str(nebulae[nebula_now].get("weather", ""))

## v1.9z: a rock-field cloud: drifting rocks through its middle (they block you like the belt's), one batch.
func _nebula_rocks(holder: Node3D, nd: Dictionary, rng: RandomNumberGenerator) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _rock_mesh(hash(sys_id) + 91, false)
	mm.instance_count = Data.NEBULA_ROCKS
	var r: float = nd["radius"]
	for i in Data.NEBULA_ROCKS:
		var p: Vector3 = (nd["center"] as Vector3) + Vector3(rng.randfn(0, 1), rng.randfn(0, 0.5), rng.randfn(0, 1)).normalized() * rng.randf_range(r * 0.08, r * 0.7)
		var rr := lerpf(6.0, 34.0, pow(rng.randf(), 1.8))
		mm.set_instance_transform(i, Transform3D(Basis.from_euler(Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)).scaled(Vector3.ONE * rr), p))
		rocks.append([p, rr * 1.05])
	var mi := MultiMeshInstance3D.new()
	mi.name = "NebulaRocks"
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(mi)
	nd["rocks_n"] = Data.NEBULA_ROCKS

## v1.9z: the weather round the ship inside a cloud: snow flakes drifting, rain streaks (longer the faster you fly),
## dust in a rock field. One batch; each flake is kept within NEBULA_WX_RANGE of the ship.
var _neb_wx: MultiMeshInstance3D
var _neb_wx_mat: ShaderMaterial
var _wx_kind := ""
static var _wx_sh: Shader
func _weather_shader() -> Shader:
	if _wx_sh != null: return _wx_sh
	_wx_sh = Shader.new()
	_wx_sh.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec3 dir = vec3(0.0, -1.0, 0.0);
uniform float len = 4.0;
uniform float wid = 0.12;
uniform vec4 col : source_color = vec4(1.0);
uniform float alpha = 0.6;
void vertex() {
	vec3 w = MODEL_MATRIX[3].xyz;
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 d = normalize(dir);
	vec3 side = normalize(cross(d, cam - w) + vec3(0.0001));
	vec3 p = w + d * VERTEX.y * len + side * VERTEX.x * wid;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(p, 1.0);
}
void fragment() {
	float edge = 1.0 - abs(UV.x * 2.0 - 1.0);
	float tail = 1.0 - abs(UV.y * 2.0 - 1.0);
	ALBEDO = col.rgb;
	ALPHA = clamp(alpha * edge * tail * 1.6, 0.0, 1.0);
}
"""
	return _wx_sh

func _update_weather(dt: float) -> void:
	var kind := nebula_weather() if in_nebula > 0.05 else ""
	if kind == "":
		if is_instance_valid(_neb_wx): _neb_wx.visible = false
		return
	if not is_instance_valid(_neb_wx):
		var q := QuadMesh.new()
		q.size = Vector2(1, 1)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = q
		mm.instance_count = Data.NEBULA_WX
		_neb_wx = MultiMeshInstance3D.new()
		_neb_wx.name = "NebulaWeather"
		_neb_wx.multimesh = mm
		_neb_wx.top_level = true
		_neb_wx.custom_aabb = AABB(-Vector3.ONE * 4e6, Vector3.ONE * 8e6)
		_neb_wx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_neb_wx_mat = ShaderMaterial.new()
		_neb_wx_mat.shader = _weather_shader()
		_neb_wx.material_override = _neb_wx_mat
		add_child(_neb_wx)
		_wx_kind = ""
	_neb_wx.visible = true
	var pp: Vector3 = player.global_position
	var R: float = Data.NEBULA_WX_RANGE
	var mm2 := _neb_wx.multimesh
	if kind != _wx_kind:   # scatter afresh round the ship
		_wx_kind = kind
		for i in mm2.instance_count:
			mm2.set_instance_transform(i, Transform3D(Basis(), pp + Vector3(_rng.randf_range(-R, R), _rng.randf_range(-R, R), _rng.randf_range(-R, R))))
	var fall := Vector3(0.6, -1.0, 0.25).normalized()
	var fv := Vector3.ZERO
	var col := Color(1, 1, 1)
	var alpha := 0.55
	var ln := 1.0
	var wd := 0.5
	match kind:
		"snow":
			fv = fall * 5.0
			col = Color(0.95, 0.97, 1.0)
			alpha = 0.9
			ln = 0.9
			wd = 0.9
		"rain", "storm":
			fv = fall * 70.0
			col = nebula_tint.lightened(0.7)
			alpha = 0.7
			wd = 0.16
		"rocks":
			fv = Vector3(1.5, -0.4, 0.8)
			col = Color(0.75, 0.7, 0.62)
			alpha = 0.6
			ln = 0.6
			wd = 0.6
	var rel := fv - vel   # what the eye sees: the weather's motion against the ship's
	if kind in ["rain", "storm"]: ln = clampf(rel.length() * 0.07, 2.5, 14.0)
	elif vel.length() > 40.0: ln = maxf(ln, minf(vel.length() * 0.03, 6.0))   # flakes stretch into streaks at speed
	_neb_wx_mat.set_shader_parameter("dir", rel.normalized() if rel.length() > 0.1 else Vector3.DOWN)
	_neb_wx_mat.set_shader_parameter("len", ln)
	_neb_wx_mat.set_shader_parameter("wid", wd)
	_neb_wx_mat.set_shader_parameter("col", col.lerp(Color(0.9, 0.95, 1.0), nebula_flash * 0.8))
	_neb_wx_mat.set_shader_parameter("alpha", alpha * clampf(in_nebula * 1.5, 0.0, 1.0) * (1.0 + nebula_flash))
	var ahead: Vector3 = vel.normalized() if vel.length() > 8.0 else -player.global_basis.z
	for i in mm2.instance_count:
		var t := mm2.get_instance_transform(i)
		t.origin += fv * dt
		var off := t.origin - pp
		if absf(off.x) > R or absf(off.y) > R or absf(off.z) > R:   # left behind: back in front of the ship
			t.origin = pp + ahead * _rng.randf_range(0.0, R * 0.9) + Vector3(_rng.randf_range(-R, R), _rng.randf_range(-R, R), _rng.randf_range(-R, R)) * 0.8
		mm2.set_instance_transform(i, t)

## Lightning, the fog and the streaming smoke, every frame.
func _update_nebulae(dt: float) -> void:
	if nebulae.is_empty() or surface_mode: return
	var pp: Vector3 = player.global_position
	nebula_flash = 0.0
	for i in nebulae.size():
		var nd: Dictionary = nebulae[i]
		var r: float = nd["radius"]
		nd["next_flash"] = float(nd["next_flash"]) - dt
		if float(nd["next_flash"]) <= 0.0:
			var fe: Array = Data.NEBULA_STORM_FLASH if nd.get("weather", "") == "storm" else Data.NEBULA_FLASH_EVERY
			nd["next_flash"] = _rng.randf_range(fe[0], fe[1])
			var pts: PackedVector3Array = nd["pts"]
			nd["flash_at"] = (nd["center"] as Vector3) + pts[_rng.randi() % pts.size()]
			nd["flash_t"] = 0.0
			nebula_flashes += 1
			(nd["mat"] as ShaderMaterial).set_shader_parameter("flash_pos", nd["flash_at"])
			var far := pp.distance_to(nd["flash_at"])
			if far < r * 1.6: Sfx.play("atmo", -8.0 - 14.0 * clampf(far / (r * 1.6), 0.0, 1.0), _rng.randf_range(0.42, 0.6))   # thunder
		var ft: float = nd["flash_t"]
		if ft < 0.0: continue
		ft += dt
		nd["flash_t"] = ft
		var amt := 0.0   # flicker, flicker, then fade
		if ft < 0.07: amt = 1.0
		elif ft < 0.13: amt = 0.2
		elif ft < 0.21: amt = 0.85
		elif ft < 0.7: amt = 0.85 * (1.0 - (ft - 0.21) / 0.49)
		else: nd["flash_t"] = -1.0
		(nd["mat"] as ShaderMaterial).set_shader_parameter("flash_amt", amt)
		if i == nebula_now: nebula_flash = maxf(nebula_flash, amt * clampf(1.0 - pp.distance_to(nd["flash_at"]) / r, 0.0, 1.0))
	# real fog inside: thickens the deeper you go
	var e: Environment = env.environment if is_instance_valid(env) else null
	if e != null:
		if in_nebula > 0.001:
			var clear := 1.0 - Data.BEACON_HAZE_CLEAR * beacon_lit
			if not _neb_fog_on:
				e.fog_enabled = true
				e.fog_mode = Environment.FOG_MODE_EXPONENTIAL
				e.fog_light_energy = 1.0
				_neb_fog_on = true
			e.fog_density = Data.NEBULA_FOG_DENSITY * pow(in_nebula, 1.5) * clear
			e.fog_light_color = nebula_tint.darkened(0.35).lerp(Data.BEACON_LIGHT_COLOR, beacon_lit * 0.5).lerp(Color(0.85, 0.9, 1.0), nebula_flash * 0.7)
			e.fog_sky_affect = clampf(in_nebula * 1.6, 0.0, 1.0) * clear   # (v1.9z: deep inside, no stars: you can't see out)
			_cloud_dome(clampf(in_nebula * 1.6, 0.0, 1.0) * clear, e.fog_light_color, 1.0, str(Data.CLOUD_ANIM.get(nebula_weather(), "nebula")))
		elif _neb_fog_on:
			e.fog_enabled = false
			_neb_fog_on = false
			_cloud_dome(0.0, Color.BLACK)
	# smoke streaming past: puffs left behind are put back ahead of the ship
	if not is_instance_valid(_neb_stream): return
	_neb_stream.visible = in_nebula > 0.02
	if not _neb_stream.visible:
		if is_instance_valid(_neb_wx): _neb_wx.visible = false
		return
	_neb_stream_mat.set_shader_parameter("tint", nebula_tint.lightened(0.15))
	_neb_stream_mat.set_shader_parameter("alpha", 0.5 * in_nebula)
	var mm := _neb_stream.multimesh
	var R: float = Data.NEBULA_STREAM_RANGE
	var ahead: Vector3 = vel.normalized() if vel.length() > 8.0 else -player.global_basis.z
	for i in mm.instance_count:
		var t := mm.get_instance_transform(i)
		if t.origin.distance_to(pp) < R: continue
		var side := Vector3(_rng.randfn(0, 1), _rng.randfn(0, 0.7), _rng.randfn(0, 1)) * R * 0.45
		t.origin = pp + ahead * _rng.randf_range(R * 0.35, R * 0.95) + side
		mm.set_instance_transform(i, t)
	_update_weather(dt)

## v1.4r: the light beacon station, hidden in the nebula. Its lamp is a real light (it lights ships, rocks and the
## station itself) plus a bright halo that lights up the cloud around it; the cloud puffs nearest the lamp are brightened.
var beacon: Node3D
var beacon_light: OmniLight3D
var beacon_glow: MeshInstance3D
var beacon_core: MeshInstance3D
var beacon_model: MeshInstance3D
var beacon_puffs: Array = []
var beacon_lit := 0.0   # 0..1 how strongly the lamp lights where the ship is (clears the nebula haze, helps the sensors)
static func has_beacon(id: String, system: Dictionary) -> bool:
	return id in Data.BEACON_SYSTEMS or str(system.get("faction", "")) in Data.BEACON_FACTIONS

func _build_beacon() -> void:
	beacon = null
	beacon_light = null
	beacon_glow = null
	beacon_core = null
	beacon_model = null
	if surface_mode: return
	# v1.4v: a station that IS a beacon (Greywhistle, Hushmark) carries the lamp itself
	if is_instance_valid(station) and sys["station"].get("lamp", false):
		_lamp(station, Vector3(0, Data.BEACON_LAMP_Y * STATION_WIDTH * float(Data.STATION_MODEL_SCALE.get(str(sys["station"].get("model", "")), 1.0)), 0))
		return
	if not has_beacon(sys_id, sys) or nebula_radius <= 1.0: return
	beacon = Node3D.new()
	beacon.name = "Light Beacon"
	beacon.position = nebula_center
	beacon.set_meta("kind", "landmark")
	beacon.set_meta("radius", Data.BEACON_SIZE * 0.5)
	beacon.set_meta("info", {"id": sys_id + "_beacon", "name": "Light Beacon", "kind": "station", "pos": nebula_center, "color": Data.BEACON_LIGHT_COLOR,
		"desc": "A lighthouse station hidden in the cloud. Its lamp lights the way through."})
	add_child(beacon)
	var body := Node3D.new()
	body.name = "Body"
	beacon.add_child(body)
	# code-made tower until the structures pack is in
	var cyl := CylinderMesh.new()
	cyl.radial_segments = 10
	cyl.rings = 1
	_mesh(body, cyl, Vector3.ZERO, Color(0.7, 0.74, 0.82), Vector3(7, Data.BEACON_SIZE * 0.6, 7))
	_mesh(body, BoxMesh.new(), Vector3.ZERO, Color(0.55, 0.6, 0.7), Vector3(Data.BEACON_SIZE, 3, 6))
	_mesh(body, BoxMesh.new(), Vector3.ZERO, Color(0.55, 0.6, 0.7), Vector3(6, 3, Data.BEACON_SIZE))
	beacon.set_meta("body", body)
	_lamp(beacon, Vector3(0, Data.BEACON_LAMP_Y * Data.BEACON_SIZE, 0))
	_beacon_model()
	if beacon_model == null and not Packs.pack_ready.is_connected(_on_beacon_pack): Packs.pack_ready.connect(_on_beacon_pack)

## The lamp: a real light, a bright star, a halo and lit cloud puffs, at `lamp` on `host` (a beacon or a station).
func _lamp(host: Node3D, lamp: Vector3) -> void:
	beacon_light = OmniLight3D.new()
	beacon_light.name = "Lamp"
	beacon_light.position = lamp
	beacon_light.light_color = Data.BEACON_LIGHT_COLOR
	beacon_light.light_energy = Data.BEACON_LIGHT_ENERGY
	beacon_light.omni_range = Data.BEACON_LIGHT_RANGE
	beacon_light.omni_attenuation = 0.6
	beacon_light.shadow_enabled = false
	host.add_child(beacon_light)
	beacon_glow = MeshInstance3D.new()
	beacon_glow.name = "Glow"
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	beacon_glow.mesh = q
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	gm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	gm.billboard_keep_scale = true
	gm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var gi := Image.create(96, 96, false, Image.FORMAT_RGBA8)   # soft round falloff, made here (no art file)
	for y in 96:
		for x in 96:
			var r := Vector2(x - 47.5, y - 47.5).length() / 48.0
			var a := clampf(1.0 - r, 0.0, 1.0)
			gi.set_pixel(x, y, Color(1, 1, 1, pow(a, 1.6) * 0.75 + pow(a, 6.0) * 0.25))
	var gt := ImageTexture.create_from_image(gi)
	gm.albedo_texture = gt
	gm.albedo_color = Color(Data.BEACON_LIGHT_COLOR, Data.BEACON_GLOW_ALPHA)
	beacon_glow.material_override = gm
	beacon_glow.position = lamp
	beacon_glow.scale = Vector3.ONE * Data.BEACON_GLOW_SIZE
	beacon_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(beacon_glow)
	beacon_core = MeshInstance3D.new()   # the lamp itself: a small, very bright star
	beacon_core.name = "Core"
	beacon_core.mesh = q
	var cm := gm.duplicate() as StandardMaterial3D
	cm.albedo_color = Color(1, 1, 1, 1)
	beacon_core.material_override = cm
	beacon_core.position = lamp
	beacon_core.scale = Vector3.ONE * Data.BEACON_CORE_SIZE
	beacon_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(beacon_core)
	# the cloud round the lamp, lit by it: a few big soft puffs in the lamp's colour
	var ctex := _cloud_texture(Data.BEACON_LIGHT_COLOR.lerp(nebula_color, 0.35), hash(sys_id) + 11)
	beacon_puffs = []
	for i in Data.BEACON_PUFFS:
		var pm := StandardMaterial3D.new()
		pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		pm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		pm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		pm.billboard_keep_scale = true
		pm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		pm.albedo_texture = ctex
		pm.albedo_color = Color(1, 1, 1, Data.BEACON_PUFF_ALPHA)
		var puff := MeshInstance3D.new()
		puff.mesh = q
		puff.material_override = pm
		var dir := Vector3(_rng.randfn(0, 1), _rng.randfn(0, 0.45), _rng.randfn(0, 1)).normalized()
		puff.position = lamp + dir * _rng.randf_range(Data.BEACON_SIZE * 0.9, Data.BEACON_GLOW_SIZE * 0.7)
		puff.scale = Vector3.ONE * _rng.randf_range(0.5, 0.9) * Data.BEACON_GLOW_SIZE
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		host.add_child(puff)
		beacon_puffs.append(puff)

func _on_beacon_pack(_name: String) -> void: _beacon_model()

## Swap the code-made tower for the owner's beacon model once the structures pack is in.
func _beacon_model() -> void:
	if beacon_model != null or not is_instance_valid(beacon): return
	var path := "res://assets/structures/light_beacon_station.glb"
	if not (Packs.is_ready("structures") and ResourceLoader.exists(path)): return
	var sc := (load(path) as PackedScene).instantiate()
	var found := sc.find_children("*", "MeshInstance3D", true, false)
	if not found.is_empty():
		var body: Node3D = beacon.get_meta("body")
		for ch in body.get_children(): (ch as Node3D).visible = false
		beacon_model = MeshInstance3D.new()
		beacon_model.mesh = (found[0] as MeshInstance3D).mesh
		beacon_model.scale = Vector3.ONE * Data.BEACON_SIZE
		beacon_model.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(beacon_model)
	sc.free()

## The lamp breathes.
func _update_beacon() -> void:
	beacon_lit = 0.0
	if not is_instance_valid(beacon_light): return
	if is_instance_valid(player): beacon_lit = clampf(1.0 - player.global_position.distance_to(beacon_light.global_position) / Data.BEACON_LIGHT_RANGE, 0.0, 1.0)
	var k := 1.0 - Data.BEACON_PULSE * (0.5 + 0.5 * sin(time * TAU * Data.BEACON_PULSE_RATE))
	beacon_light.light_energy = Data.BEACON_LIGHT_ENERGY * k
	(beacon_glow.material_override as StandardMaterial3D).albedo_color = Color(Data.BEACON_LIGHT_COLOR, Data.BEACON_GLOW_ALPHA * k)
	if is_instance_valid(beacon_core): (beacon_core.material_override as StandardMaterial3D).albedo_color = Color(1, 1, 1, k)

func _build_player() -> void:
	player = Node3D.new()
	player.name = "Player"
	add_child(player)
	set_player_model()

## v1.9i: the player's mech, built from the fitted arms / core / legs. Until a part's pack is in, the Black-Gold frame
## stands in and the mech is rebuilt when the pack arrives.
func _player_mech_model() -> Node3D:
	var k: Dictionary = GS.mech_keys()
	var waiting := false
	for p in ["arms", "core", "legs"]:
		var pk := ShipFactory.pack_of(str(k[p]))
		if pk != "" and not Packs.is_ready(pk):
			waiting = true
			if not Packs.pack_ready.is_connected(_on_mech_pack): Packs.pack_ready.connect(_on_mech_pack)
			Packs.request(pk)
	if waiting: return ShipFactory.build("mech_player")
	return ShipFactory.build_mech(str(k["core"]), str(k["arms"]), str(k["legs"]))

func _on_mech_pack(pk: String) -> void:
	if not pk.begins_with("mf_") or not is_inside_tree() or GS.form != "mech" or transform_t > 0.0: return
	if is_instance_valid(model) and model.has_meta("mech_keys"): return   # already the fitted mech
	set_player_model()

## v1.9i: a faction's own mech, if its pack is in (asked for otherwise; the tan assault mech stands in meanwhile).
func faction_mech(faction: String) -> String:
	var key := Data.faction_mech_model(faction)
	var pk := ShipFactory.pack_of(key)
	if pk != "" and not Packs.is_ready(pk):
		Packs.request(pk)
		return "mech_tan"
	return key

func set_player_model() -> void:
	if is_instance_valid(model): model.queue_free()
	if GS.form == "mech" and not Packs.is_ready("mechs"): GS.form = "ship"
	var mech := GS.form == "mech"
	model = _player_mech_model() if mech else ShipFactory.build(Data.SHIPS[GS.ship_id]["model"])   # (v1.9i: the mech wears its fitted parts)
	player.add_child(model)
	model.visible = GS.view != "cockpit"
	# damage maps between forms: left wing = left arm, right wing = right arm, hull = core
	player_vis = Sections.setup(model, mech)
	Sections.set_side_visible(player_vis, "l", GS.wing_l > 0.0)
	Sections.set_side_visible(player_vis, "r", GS.wing_r > 0.0)
	_hw_cache.erase(str(GS.ship_id))
	mount_visuals()

## v1.9g (owner): what each wing mount carries, on the wing: the shoulder gun on top near the core, the tip gun under
## the wing's end (hung upside down). Models come from the "wing_guns" pack; until it is in, nothing extra shows.
func mount_visuals() -> void:
	if not is_instance_valid(model): return
	var old := model.get_node_or_null("WingMounts")
	if old != null: old.free()
	if GS.form == "mech": return
	if not Packs.is_ready("wing_guns"):
		if not Packs.pack_ready.is_connected(_on_wing_guns): Packs.pack_ready.connect(_on_wing_guns)
		Packs.request("wing_guns")
		return
	var holder := Node3D.new()
	holder.name = "WingMounts"
	model.add_child(holder)
	var hw := _ship_half_width()
	var sc: float = maxf(model.scale.x, 0.001)
	var items: Array = GS.mount_items()
	for g in items.size():
		var it: String = items[g]
		var info: Dictionary = Data.WEAPONS.get(it, Data.MOUNT_PODS.get(it, {}))
		var key: String = str(info.get("model", ""))
		if key == "" or not ShipFactory.has_real_model(key): continue
		var side := GS.mount_side(g)
		var tip: bool = GS.is_tip(g)
		var gun := ShipFactory.build(key)
		gun.name = "Mount%d" % g
		var at: float = Data.MOUNT_TIP_AT if tip else (Data.MOUNT_MID_AT if g >= 4 else Data.MOUNT_SHOULDER_AT)
		gun.position = Vector3(side * hw * at, -Data.MOUNT_DROP if tip else Data.MOUNT_DROP, 0.0) / sc
		var share: float = float(info.get("share", Data.WING_POD_SHARE if Data.MOUNT_PODS.has(it) else Data.WING_GUN_SHARE))   # (v1.9h: heavy mounts carry their own)
		gun.scale = Vector3.ONE * (_ship_length() * share / Data.WING_GUN_LEN) / sc   # (sized by the ship)
		if tip: gun.rotation_degrees.z = 180.0   # hung under the wing
		gun.set_meta("mount", g)
		holder.add_child(gun)

func _on_wing_guns(pk: String) -> void:
	if pk == "wing_guns" and is_inside_tree(): mount_visuals()

func is_mech_form() -> bool:
	return GS.form == "mech"

# ---------------------------------------------------------------- ship <-> mech transformation
var transform_t := 0.0      # > 0 while transforming (counts up to TRANSFORM_TIME)
var transform_to := ""
var _swapped := false
var _flash: MeshInstance3D
const TRANSFORM_TIME := 3.0
var last_transform_s := 0.0

## Start transforming to the other form. Returns a reason when it can't.
func start_transform() -> String:
	if transform_t > 0.0: return "busy"
	if warp_state != "off": return "warp"
	var to := "ship" if GS.form == "mech" else "mech"
	if to == "mech" and not Packs.is_ready("mechs"):
		Packs.request("mechs")
		return "loading"
	transform_to = to
	transform_t = 0.001
	var ge := _nearest_generic(1600.0)
	if not ge.is_empty(): _chatter(ge, "enemy_transforming", true)
	_swapped = false
	engine_kill = false
	Sfx.play("transform", -2.0)
	return to

## 3 s: the current form tucks/compresses (0-1.4 s), an energy flash covers the swap (1.4 s), the new form
## unfolds and locks (1.4-2.8 s), final lock at 3 s — timed to the clack / chunk / lock / thoom of the sound.
func _update_transform(dt: float) -> void:
	if transform_t <= 0.0: return
	transform_t += dt
	var t := transform_t
	var fold := clampf(t / 1.4, 0.0, 1.0) if t < 1.4 else clampf(1.0 - (t - 1.4) / 1.4, 0.0, 1.0)
	if t >= 1.4 and not _swapped:
		_swapped = true
		GS.form = transform_to
		set_player_model()
		_spark(player.global_position, Color(0.75, 0.85, 1.0), 22.0, 0.35)
		_spark(player.global_position, Color(1, 1, 1), 12.0, 0.2)
	if is_instance_valid(model):
		if GS.form == "mech":
			model.scale = Vector3.ONE * lerpf(1.0, 0.7, fold)
			Sections.pose_mech(player_vis, 10.0, 1.0, fold)
		else:
			model.scale = Vector3(1.0, lerpf(1.0, 0.8, fold), lerpf(1.0, 0.55, fold))
			model.rotation.z += dt * 9.0 * fold   # wings roll as they fold
	if t >= TRANSFORM_TIME:
		last_transform_s = t
		transform_t = 0.0
		if is_instance_valid(model):
			model.scale = Vector3.ONE
			model.rotation.z = 0.0
		_spark(player.global_position, Color(0.8, 0.9, 1.0), 9.0, 0.25)
		message.emit("Transformation complete: %s form." % GS.form.to_upper())

# ---------------------------------------------------------------- mech movement (no warp, directional boost dashes)
var _boost_was := false
var dash_t := 0.0
var dash_cd := 0.0
var dash_dir := Vector3.ZERO   # local direction of the current dash
var last_dash := ""            # e.g. "back-left" (for the HUD and tests)

## Stick direction -> one of 8 forgiving 45-degree sectors (centre stick = forward).
static func dash_sector(stick: Vector2) -> Vector2:
	if stick.length() < 0.3: return Vector2(0, 1)
	var a := snappedf(stick.angle(), PI / 4.0)
	return Vector2(cos(a), sin(a)).round().normalized()

## v1.4n: where a THRUST burst goes, in the craft's own axes. Stick centred = straight UP; otherwise the stick's
## 45-degree sector (x = strafe, y = forward/back). Same rule for the ship and the mech.
static func burst_dir(stick: Vector2) -> Vector3:
	if stick.length() < 0.3: return Vector3.UP
	var sec := dash_sector(stick)
	return Vector3(sec.x, 0, -sec.y).normalized()

static func burst_name(stick: Vector2) -> String:
	if stick.length() < 0.3: return "up"
	var sec := dash_sector(stick)
	return ("forward" if sec.y > 0.5 else ("back" if sec.y < -0.5 else "")) + ("-" if absf(sec.y) > 0.5 and absf(sec.x) > 0.5 else "") + ("right" if sec.x > 0.5 else ("left" if sec.x < -0.5 else ""))

# ---------------------------------------------------------------- v1.8r GROUND mode
var ground_mode := false   # gravity on: walking / landed (mech and ship)
var grounded := false      # standing on the ground right now

## The GROUND button. "on" / "off", or why not: "space" (no ground here), "warp".
func toggle_ground() -> String:
	if not surface_mode or sun_surface: return "space"
	if warp_state != "off": return "warp"
	ground_mode = not ground_mode
	engine_kill = false
	braking = false
	holding = false
	autopilot = null
	dash_t = 0.0
	if not ground_mode: grounded = false
	return "on" if ground_mode else "off"

func _ground_move(dt: float, thrust: Vector2, base_speed: float) -> void:
	var yb := Basis.from_euler(Vector3(0, yaw, 0))   # it moves the way it faces on the flat, whatever the nose is doing
	var sp := base_speed * Data.GROUND_WALK
	dash_t = maxf(0.0, dash_t - dt)
	dash_cd = maxf(0.0, dash_cd - dt)
	boosting = false
	var boost_now := thrust_held and controls and transform_t <= 0.0
	if boost_now and not _boost_was:
		if not grounded: last_dash = "air"   # in the air THRUST does nothing: gravity brings you down
		elif dash_cd <= 0.0 and GS.energy > Data.GROUND_THRUST_ENERGY:
			GS.energy -= Data.GROUND_THRUST_ENERGY
			dash_cd = Data.GROUND_THRUST_CD
			if thrust.length() < 0.3:   # stick centred: a jump
				vel.y = Data.GROUND_JUMP
				grounded = false
				last_dash = "jump"
			else:   # stick pushed: a burst that way, along the ground
				dash_dir = burst_dir(thrust)
				dash_t = Data.GROUND_DASH_TIME
				last_dash = burst_name(thrust)
			Sfx.play("whoosh", -6.0, 1.4)
			_spark_v(player.global_position - Vector3(0, 4.0, 0), Vector3(0, -12.0, 0), Color(0.7, 0.85, 1.0), 6.0, 0.3)
	_boost_was = boost_now
	var desired := -yb.z * sp * thrust.y + yb.x * sp * 0.9 * thrust.x
	var rate: float = Data.GROUND_GRIP if grounded else Data.GROUND_AIR_STEER
	if dash_t > 0.0:
		desired = yb * dash_dir * sp * Data.GROUND_DASH_MULT
		rate = 9.0
		boosting = true
	var h := Vector3(vel.x, 0.0, vel.z).lerp(desired, minf(1.0, dt * rate))
	vel = Vector3(h.x, maxf(vel.y - Data.GROUND_GRAVITY * dt, -Data.GROUND_FALL_MAX), h.z)
	if GS.form == "mech" and is_instance_valid(model) and transform_t <= 0.0:   # upright, leaning a little into the walk, legs striding
		var k := clampf(h.length() / maxf(1.0, sp), 0.0, 2.0)
		model.rotation.x = lerpf(model.rotation.x, -deg_to_rad(6.0 * k), minf(1.0, dt * 4.0))
		model.rotation.z = lerpf(model.rotation.z, 0.0, minf(1.0, dt * 4.0))
		Sections.pose_mech(player_vis, 8.0, dt)
		if grounded: Sections.stride(player_vis, sin(time * Data.WALKER_STRIDE_RATE * 1.4) * Data.WALKER_STRIDE_DEG * minf(1.0, k))

func _mech_move(dt: float, thrust: Vector2, base_speed: float) -> void:
	var fwd := -player.global_basis.z
	var right := player.global_basis.x
	var sp := base_speed * 0.85 * GS.mech_speed()   # v1.9i: the legs set the pace
	dash_t = maxf(0.0, dash_t - dt)
	dash_cd = maxf(0.0, dash_cd - dt)
	boosting = false
	var boost_now := thrust_held and controls and transform_t <= 0.0
	if boost_now and not _boost_was and dash_cd <= 0.0 and GS.energy > 18.0:
		dash_dir = burst_dir(thrust)   # thrust.x = strafe, thrust.y = forward(+)/back(-); centred = straight up (v1.4n)
		dash_t = 0.45
		dash_cd = 0.8
		GS.energy -= 18.0
		last_dash = burst_name(thrust)
		Sfx.play("whoosh", -6.0, 1.4)
		_spark_v(player.global_position - player.global_basis * dash_dir * 4.0, -(player.global_basis * dash_dir) * 20.0, Color(0.7, 0.85, 1.0), 6.0, 0.3)
	_boost_was = boost_now
	var desired := fwd * sp * thrust.y + right * sp * 0.9 * thrust.x
	var rate := 2.2
	if dash_t > 0.0:
		desired = player.global_basis * dash_dir * sp * Data.MECH_BURST_MULT
		rate = 9.0
		boosting = true
	elif boost_now and GS.energy > 1.0 and dash_dir != Vector3.ZERO:
		desired = player.global_basis * dash_dir * sp * 1.7   # holding BOOST keeps pushing that way
		GS.energy = maxf(0.0, GS.energy - Data.THRUST_ENERGY * dt)
		boosting = true
		_booster_particles(dt, 0.2)
	if braking:
		desired = Vector3.ZERO
		if vel.length() < 0.6: braking = false
	vel = vel.lerp(desired, minf(1.0, dt * rate))
	# posture: lean into the motion, arms back when going forward fast
	if is_instance_valid(model) and transform_t <= 0.0:
		var lv := player.global_basis.inverse() * vel
		var fwd_k := clampf(-lv.z / sp, -1.5, 3.2)
		var side_k := clampf(lv.x / sp, -3.0, 3.0)
		model.rotation.x = lerpf(model.rotation.x, -deg_to_rad(clampf(fwd_k * 12.0, -18.0, 30.0)), minf(1.0, dt * 4.0))
		model.rotation.z = lerpf(model.rotation.z, -deg_to_rad(side_k * 10.0), minf(1.0, dt * 4.0))
		if special_state == "charging": model.rotation.z = special_roll   # v1.5o: the mech rolls too
		Sections.pose_mech(player_vis, clampf(8.0 + fwd_k * 14.0, -15.0, 55.0), dt)

func _spawn_group(center: Vector3, count: int) -> Array:
	# a fight already going on nearby, or the player close: the new group announces itself as reinforcements
	var busy := enemies.any(func(o): return o["aggro"]) or (is_instance_valid(player) and player.global_position.distance_to(center) < 2500.0 and time > 1.0)
	_group_serial += 1
	var group: Array = []
	var leader := ""
	for i in count:
		# the last ship of a pair or bigger group is sometimes an assault mech
		var kind: String = sys["enemy"]
		# v1.4r / v1.4w: a faction whose own people fly its patrols (Savagers), or its guard wing / hunters
		var own: String = str(sys.get("faction", ""))
		var soldier: Dictionary = roster_pick(own, mini(_guard_slot, Data.PATROL_MAX_SLOT)) if (Factions.replaces_patrols(own) or _guard_spawn) else {}
		# v1.5k: the opening system: the rival nation's low ranks, always hostile (no raider leaders, no story bosses)
		var opening: Dictionary = opening_rule()
		if not opening.is_empty() and not _guard_spawn: soldier = roster_pick(str(opening["faction"]), int(opening["max_slot"]))
		# v1.4z: an enemy home system whose faction has a roster and ships (Phenom, Kaijurai): its own people fly the patrols
		if soldier.is_empty() and not _guard_spawn and str(sys.get("enemy_faction", "")) != "": soldier = roster_pick(str(sys["enemy_faction"]), Data.PATROL_MAX_SLOT)
		if soldier.is_empty() and _incursion != "" and not _guard_spawn:   # a rival's raiding party: common soldiers, now and then led by slot 02
			soldier = roster_pick(_incursion, 2 if (i == 0 and randf() < Data.INCURSION_NAMED_CHANCE) else 1)
			if i == count - 1 or count > Data.INCURSION_SIZE: _incursion_done = true
		if not soldier.is_empty(): kind = roster_fighter(soldier)
		# v1.4y: an enemy home system with its own ships (Kaijurai, Phenom) flies them, taken from its list in turn
		var fleet: Array = sys.get("enemy_ships", []) if soldier.is_empty() and not _guard_spawn else []
		if not fleet.is_empty(): kind = fleet[(_fleet_serial + i) % fleet.size()]
		if fleet.is_empty() and soldier.is_empty() and count >= 2 and i == count - 1 and _rng.randf() < 0.5 and Packs.is_ready("mechs"): kind = "mech"
		var mkey: String = faction_mech(str(sys.get("enemy_faction", own)) if own == "" else own) if kind == "mech" else ""   # v1.9i: the system's faction's own mech
		var e := spawn_unit(kind, center + Vector3(_rng.randf_range(-60, 60), _rng.randf_range(-20, 20), _rng.randf_range(-60, 60)), center, mkey)
		e["group"] = _group_serial
		# the first ship flies under a NAMED squad leader (Scar Jackal, Iron Revenant...); everyone else is a generic
		# pilot in that leader's wing
		if not soldier.is_empty():
			assign_roster(e, soldier)
			if not opening.is_empty(): e["provoked"] = true   # the rival's raiders fight you whatever the standing
		elif not fleet.is_empty(): _make_generic(e, str(e["def"].get("faction", "")))   # no named squad leader: they are not the raiders' or corsairs' people
		elif i == 0 and e["node"].has_meta("pilot"): leader = e["node"].get_meta("pilot")["name"]
		elif i > 0: _make_generic(e, leader)
		group.append(e)
	_fleet_serial += count
	if _incursion_done:
		_incursion = ""
		_incursion_done = false
	if busy and group.size() > 1 and not (_guard_spawn and not Factions.hostile(str(sys.get("faction", "")))): _chatter(group[-1], "reinforcements", true)   # (a peaceful guard wing does not announce itself as a threat)
	return group

## v1.5k: the opening-system rule for the system being flown ({} = none). Matched on the system's own data, so code
## that borrows another system's data (the tests do) gets that system's patrols.
func opening_rule() -> Dictionary:
	for k in Data.OPENING_SYSTEMS:
		if is_same(sys, Data.SYSTEMS.get(k, null)): return Data.OPENING_SYSTEMS[k]
	return {}

var _named_down := {}        # named characters you shot down on this visit: they have left the area
var _incursion := ""         # the rival faction raiding this system on this visit ("" = none)
var _incursion_done := false

## Who flies the next ship of a faction's roster: weighted by spawn_weight, slot 01 most often. A NAMED character is
## never out twice at once, and sits out while in custody, while being hunted as a bounty, or after you shot them down
## on this visit. max_slot limits how senior (raiding parties send low ranks). {} = that faction has no roster.
func roster_pick(faction: String, max_slot := 6) -> Dictionary:
	var pilots: Array = Data.ROSTERS.get(faction, {}).get("pilots", [])
	if pilots.is_empty(): return {}
	var open_list: Array = []
	var total := 0.0
	for p in pilots:
		if int(p["slot"]) > max_slot or not Data.ENEMIES.has(str(p["fighter_primary"])): continue   # (no fighter in the game yet: known, but not flying)
		if p["named_unique"]:
			var cid: String = p["character_id"]
			if _named_down.has(cid) or GS.cast_state(cid)["custody"] or not GS.cast_state(cid)["alive"]: continue
			if GS.bounty.get("id", "") == p["id"]: continue
			if enemies.any(func(o): return o.get("pilot", {}).get("character_id", "") == cid): continue
		open_list.append(p)
		total += float(p["spawn_weight"])
	if open_list.is_empty(): return {}
	var roll := randf() * total
	for p in open_list:
		roll -= float(p["spawn_weight"])
		if roll <= 0.0: return Data.roster_pilot(p["id"])
	return Data.roster_pilot(open_list[0]["id"])

## The fighter a character takes out: the primary one, now and then an alternate.
func roster_fighter(p: Dictionary) -> String:
	var alts: Array = p.get("fighter_alternates", [])
	if not alts.is_empty() and randf() < Data.ALT_FIGHTER_CHANCE: return alts[randi() % alts.size()]
	return p["fighter_primary"]

var _fleet_serial := 0        # v1.4y: where the next patrol starts in the system's own ship list
var _guard_spawn := false     # the group being spawned is the faction's own (guard wing or hunters), not a placeholder patrol

## v1.4w: a faction that has fighters keeps a small wing of its own people near its main station. They follow the
## reputation rules: peaceful (shown as a patrol, not a hostile) unless that faction is hostile to you or you shoot.
func spawn_guard() -> Array:
	var f: String = str(sys.get("faction", ""))
	if surface_mode or Factions.replaces_patrols(f) or not Factions.has_fighters(f) or not is_instance_valid(station): return []
	if roster_pick(f, Data.GUARD_MAX_SLOT).is_empty(): return []
	if not opening_rule().is_empty(): return []   # v1.5q: the opening system keeps the owner's test flow (only its opening enemies)
	_guard_spawn = true
	_guard_slot = Data.GUARD_MAX_SLOT
	var g: Array = _spawn_group(station.global_position + Vector3(Data.GUARD_DIST, 60, -Data.GUARD_DIST * 0.4), Data.GUARD_SIZE)
	_guard_spawn = false
	_guard_slot = 6
	for e in g: e["guard"] = true
	return g
var _guard_slot := 6

## RED standing: a hunter group meets you when you enter that faction's space.
func spawn_hunters() -> Array:
	var f: String = str(sys.get("faction", ""))
	if roster_pick(f).is_empty() or not Factions.hunted(f) or not is_instance_valid(player): return []
	_guard_spawn = true
	var at: Vector3 = player.global_position - player.global_basis.z * Data.REP_HUNTER_DIST + Vector3(0, 80, 0)
	var g: Array = _spawn_group(at, Data.REP_HUNTER_SIZE)
	_guard_spawn = false
	for e in g:
		e["aggro"] = true
		e["hunter"] = true
	_guard_spawn = false
	message.emit("%s hunters inbound. You are marked." % Factions.def(f)["display_name"])
	return g

## Put a roster pilot in a unit: their face (normal / damaged) on the radio, and the rank rule on the ship.
func assign_roster(e: Dictionary, p: Dictionary) -> void:
	var g: Dictionary = p.duplicate()
	g["generic"] = true
	e["pilot"] = g
	e["pstate"] = "normal"
	e["node"].set_meta("pilot", g)
	e["faction"] = p.get("faction", "")
	if p.get("named_unique", false):
		e["node"].name = p["name"]
		GS.cast_state(p["character_id"])["current_system"] = sys_id
	apply_rank(e, int(p["rank"]))

## THE RULE: the higher the number, the stronger the ship (Data.RANK_*).
func apply_rank(e: Dictionary, rank: int) -> void:
	var k: float = Data.rank_mult(rank, Data.RANK_HULL_STEP)
	for key in ["hp", "max", "sh", "sh_max", "l", "r", "side_max"]: e[key] = float(e[key]) * k
	var d: Dictionary = (e["def"] as Dictionary).duplicate()
	d["damage"] = float(d["damage"]) * Data.rank_mult(rank, Data.RANK_DAMAGE_STEP)
	d["speed"] = float(d["speed"]) * Data.rank_mult(rank, Data.RANK_SPEED_STEP)
	d["reward"] = int(float(d["reward"]) * Data.rank_mult(rank, Data.RANK_REWARD_STEP))
	e["def"] = d
	e["rank"] = rank

## The bounty you carry hides in this system: put the target out by the first patrol point. {} = not here.
func spawn_bounty() -> Dictionary:
	if not GS.mission.is_empty(): return {}   # v1.5f: a bounty taken from the board turns up at the end of its waypoint chain
	if GS.bounty.get("state", "") != "hunt" or GS.bounty.get("sys", "") != sys_id: return {}
	for o in enemies:
		if o.get("bounty", "") == GS.bounty["id"]: return o
	var p: Dictionary = Data.roster_pilot(GS.bounty["id"])
	if p.is_empty(): return {}
	var at: Vector3 = (sys["patrols"][0] as Vector3) + Vector3(0, 70, 0)
	var fac := str(p.get("faction", ""))
	if Factions.DEFS.has(fac):   # v1.9b (owner): the target flies with at least six of its own (the boss first)
		var grp := spawn_mission_group(at, fac, 1 + Data.BOUNTY_HELPERS, mini(int(p.get("slot", 2)), 2), str(p["id"]), -1)
		if not grp.is_empty():
			for o in grp: o.erase("mission")
			return grp[0]
	var e := spawn_unit(p["fighter_primary"], at, at)
	assign_roster(e, p)
	e["bounty"] = p["id"]
	e["provoked"] = true   # v1.6g: a bounty target is hostile whatever your standing with its faction
	e["node"].name = "%s (bounty)" % p["name"]
	for i in Data.BOUNTY_HELPERS:   # (no faction defs: plain wingmen of the system's enemy kind)
		var h := spawn_unit(sys["enemy"], at + Vector3(_rng.randf_range(-70, 70), _rng.randf_range(-25, 25), _rng.randf_range(-70, 70)), at)
		h["provoked"] = true
	return e

## A bounty ship is gone: its pilot drifts out in a space suit (stand-in model) for the tractor beam.
func _drop_pilot(at: Vector3, id: String) -> void:
	var pod := Node3D.new()
	pod.name = "Pilot"
	if ShipFactory.has_real_model("pilot_pod"): pod.add_child(ShipFactory.build("pilot_pod"))
	else:
		var mi := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.8
		cm.height = 3.6
		mi.mesh = cm
		mi.material_override = ShipFactory.mat(Color(0.8, 0.82, 0.86), false, 0.2)
		pod.add_child(mi)
	var glow := MeshInstance3D.new()
	var gm := SphereMesh.new()
	gm.radius = 3.2
	gm.height = 6.4
	glow.mesh = gm
	glow.material_override = _glow_mat(Color(1.0, 0.3, 0.25))
	pod.add_child(glow)
	add_child(pod)
	pod.global_position = at
	loot.append({"node": pod, "vel": Vector3(_rng.randfn(0, 1), 0.4, _rng.randfn(0, 1)).normalized() * 6.0, "value": 0, "life": Data.PILOT_POD_LIFE, "bounty": id})
	message.emit("%s bailed out. TRACTOR the pilot in." % Data.roster_pilot(id).get("name", "The pilot"))

## Give a unit a generic pilot (AX-01..06) flying under the named leader. Keeps NORMAL until its health falls to
## GENERIC_HURT, then DAMAGED for the rest of the encounter.
func _make_generic(e: Dictionary, leader: String) -> void:
	var g: Dictionary = Data.GENERIC_PILOTS[(_enemy_serial * 7 + _group_serial) % Data.GENERIC_PILOTS.size()].duplicate()
	g["generic"] = true
	g["leader"] = leader if leader != "" else ("Shade" if sys.get("enemy", "") == "raider" else "Hoard")
	e["pilot"] = g
	e["pstate"] = "normal"
	e["node"].set_meta("pilot", g)

## Total health share 0..1 (core + both sides), the number a generic pilot's portrait state follows.
static func unit_health(e: Dictionary) -> float:
	var tot := float(e["max"]) + 2.0 * float(e["side_max"])
	return clampf((maxf(0.0, float(e["hp"])) + maxf(0.0, float(e["l"])) + maxf(0.0, float(e["r"]))) / tot, 0.0, 1.0)

## Latch NORMAL -> DAMAGED at or below GENERIC_HURT. Never flips back, so the portrait cannot flicker around 50 %.
func _update_pilot_state(e: Dictionary) -> void:
	if e.get("pstate", "") == "normal" and unit_health(e) <= Data.GENERIC_HURT: e["pstate"] = "damaged"

## One short radio line from a generic pilot. Important events (force) skip the chatter cooldown.
func _chatter(e: Dictionary, ev: String, force := false) -> bool:
	var p: Dictionary = e.get("pilot", {})
	if p.is_empty() or not controls: return false
	if not force and chatter_cd > 0.0: return false
	chatter_cd = 3.5
	var lines: Array = Data.CHATTER[ev]
	var line: String = lines[_rng.randi() % lines.size()]
	if ev == "critical_damage" and e["pstate"] == "damaged" and _rng.randf() < 0.5: line = p["hurt"]
	last_chatter = {"pilot": p, "event": ev, "state": e["pstate"], "line": line}
	enemy_chatter.emit(p, "[%s]%s" % [e["pstate"], line])
	return true

## The nearest generic pilot that is in the fight (for events about the player: warp, transform).
func _nearest_generic(r: float) -> Dictionary:
	var best := {}
	var bd := r
	for e in enemies:
		if e.get("pilot", {}).is_empty() or not e["aggro"]: continue
		var d: float = (e["node"] as Node3D).global_position.distance_to(player.global_position)
		if d < bd:
			bd = d
			best = e
	return best

## Spawn one hostile ship or mech with three sections (left / core / right).
func spawn_unit(kind: String, pos: Vector3, home: Vector3, model_key := "", scale_k := 1.0) -> Dictionary:
	var e: Dictionary = Data.ENEMIES[kind]
	var is_mech: bool = e.get("mech", false)
	var mk: String = model_key if model_key != "" else str(e.get("model", "enemy"))   # (v1.9i: a faction's own mech)
	if not (ShipFactory.has_real_model(mk) or mk.begins_with("mech")): mk = "enemy"
	var n := ShipFactory.build(mk)
	if scale_k != 1.0: n.scale *= scale_k   # v1.9i: a boss mech is bigger
	var node := Node3D.new()
	_enemy_serial += 1
	node.name = "%s %d" % [e["name"], _enemy_serial]
	node.add_child(n)
	node.position = pos
	node.set_meta("kind", "enemy")
	node.set_meta("radius", float(e.get("radius", 7.0)) * maxf(1.0, scale_k * 0.6))
	var pilots: Array = Data.PILOTS.get(sys["enemy"], [])
	if not pilots.is_empty() and not is_mech: node.set_meta("pilot", pilots[_enemy_serial % pilots.size()])
	add_child(node, true)
	var side_hp: float = float(e["hull"]) * Data.SECTION_SHARE
	var ent := {"node": node, "model": n, "hp": e["hull"], "max": e["hull"], "sh": e.get("shield", 0.0), "sh_max": e.get("shield", 0.0), "sh_cd": 0.0,
		"def": e, "vel": Vector3.ZERO, "home": home, "mech": is_mech,
		"l": side_hp, "r": side_hp, "side_max": side_hp, "vis": Sections.setup(n, is_mech) if not e.get("capital", false) else {"l": [], "r": []},   # (v1.9n: a capital ship is not split into wings: its meshes keep their LODs)
		"spark_l": 0.0, "spark_r": 0.0, "sparks": 0, "gun": 0, "core_cd": _rng.randf_range(1.5, 3.0),
		"cd": _rng.randf_range(0.5, 2.0), "orbit": _rng.randf() * TAU, "aggro": false, "strafe": _rng.randf_range(-1, 1), "prev_fwd": Vector3.FORWARD}
	enemies.append(ent)
	return ent

## Weapon mounts still working: "l"/"r" arm or wing guns, plus "core" for a mech's chest cannon.
func unit_guns(e: Dictionary) -> Array:
	var g: Array = []
	if float(e["l"]) > 0.0: g.append("l")
	if float(e["r"]) > 0.0: g.append("r")
	return g

func _build_traffic() -> void:
	for pair in sys["traffic"]:
		for k in Data.TRAFFIC_PER_RUN:      # a cargo hauler, a freighter and a liquid tanker (water, fuel) on each run (v1.8v: fewer)
			var mk: String = ["fleet", "fleet2", "fleet3"][k]
			if not ShipFactory.has_real_model(mk): mk = "fleet"
			var node := Node3D.new()
			node.name = ("Tanker %s-%d" if mk == "fleet3" else "Freighter %s-%d") % [sys["name"], k + 1]
			node.add_child(ShipFactory.build(mk))
			node.set_meta("kind", "traffic")
			node.set_meta("radius", 12.0)
			add_child(node)
			traffic.append({"node": node, "t": float(k) / float(Data.TRAFFIC_PER_RUN), "dir": 1.0 if k != 1 else -1.0})

## v1.4q: Savagers space flies the Savagers' own salvaged carrier; everyone else keeps the fleet carrier.
static func carrier_key(system: Dictionary) -> String:
	return "savager_carrier" if str(system.get("faction", "")) == "Savagers" and ShipFactory.has_real_model("savager_carrier") else "carrier"

func _build_carrier() -> void:
	carrier = Node3D.new()
	var savage: bool = carrier_key(sys) == "savager_carrier"
	carrier.name = "%s Carrier" % ("Savagers" if savage else ("Unity" if sys_id == "solara" else "Frontier"))
	carrier.set_meta("model_key", carrier_key(sys))
	carrier.add_child(ShipFactory.build(carrier_key(sys)))
	carrier.set_meta("kind", "traffic")
	carrier.set_meta("radius", 60.0)
	add_child(carrier)
	var st: Vector3 = station.global_position
	carrier.global_position = st + Vector3(-420, 60, -180)
	carrier.look_at(carrier.global_position + Vector3(1, 0, 0.3), Vector3.UP)
	# a big liquid tanker (water, fuel) holding station off the planet, on the station's side
	if ShipFactory.has_real_model("tanker") and is_instance_valid(planet):
		tanker = Node3D.new()
		tanker.name = "%s Fuel Tanker" % sys["name"]
		tanker.add_child(ShipFactory.build("tanker"))
		tanker.set_meta("kind", "traffic")
		tanker.set_meta("radius", 55.0)
		add_child(tanker)
		var out: Vector3 = (st - planet.global_position).normalized()
		tanker.global_position = planet.global_position + out * (float(planet.get_meta("radius")) + 520.0) + out.cross(Vector3.UP).normalized() * 380.0
		tanker.look_at(tanker.global_position + out.cross(Vector3.UP).normalized(), Vector3.UP)

# ---------------------------------------------------------------- per frame
var _mem_reported := false
func _process(dt: float) -> void:
	time += dt
	warp_flash = maxf(0.0, warp_flash - dt)
	_follow_mission(dt)
	if not _mem_reported and time > 3.0:
		_mem_reported = true
		if OS.has_feature("web") or OS.get_environment("HL_PROFILE") != "": print(memory_report())
	if not is_instance_valid(player): return
	_update_player(dt)
	Missions.tick(self, dt)   # v1.5f
	_update_special(dt)   # v1.5o
	_update_nav()   # v1.5i
	_update_beacon()
	_update_nebulae(dt)   # v1.9s
	_update_atmo_dome()   # v1.9z
	_update_enemies(dt)
	if not allies.is_empty(): _update_allies(dt)   # v1.9n
	_update_traffic(dt)
	_update_bolts(dt)
	_update_missiles(dt)
	_update_trails(dt)
	_update_blasts(dt)
	_update_mines(dt)
	_update_loot(dt)
	_update_asteroids(dt)   # v1.7x
	_update_effects(dt)
	if not roamers.is_empty(): _update_roamers(dt)   # v1.9d
	_collisions(dt)
	if surface_mode: _surface_update(dt)
	_update_camera(dt, false)
	_update_sun(dt)
	_ambient_anim(dt)
	if not is_instance_valid(target): target = null
	if target == null or target.get_meta("kind", "") != "enemy": _auto_target()
	# respawn hostiles once a system is cleared
	if enemies.is_empty() and not surface_mode:
		respawn_timer += dt
		if respawn_timer > 40.0:
			respawn_timer = 0.0
			for p in (sys["patrols"] as Array).slice(0, Data.PATROL_GROUPS):
				if p.distance_to(player.global_position) > 700.0: _spawn_group(p, 2)

## The sun: blooms the closer and the more head-on you look at it; warns inside the heat zone; the sphere destroys the ship.
func _update_sun(dt: float) -> void:
	if surface_mode and sun_surface:
		_sun_heat(dt)
		return
	if surface_mode or sun_pos == Vector3.INF or not is_instance_valid(cam):
		sun_flare = 0.0
		sun_hazard = 0
		return
	var to := sun_pos - cam.global_position
	var dist := to.length()
	var surf := maxf(dist - sun_radius, 0.0)
	var facing := clampf(((-cam.global_basis.z).dot(to / maxf(dist, 1.0)) - 0.82) / 0.18, 0.0, 1.0)
	var near := clampf(1.0 - surf / Data.SUN_BLOOM_RANGE, 0.0, 1.0)
	var want := facing * facing * (0.12 + 0.88 * near * near)
	sun_flare = lerpf(sun_flare, want, clampf(dt * 5.0, 0.0, 1.0))
	# The sun is real-sized and very far; its picture is drawn at most SUN_DRAW_MAX away, shrunk to look identical.
	var k := minf(dist, Data.SUN_DRAW_MAX) / maxf(dist, 1.0)
	var at := cam.global_position + to * k
	if is_instance_valid(sun_core):
		sun_core.global_position = at
		sun_core.scale = Vector3.ONE * k
	if is_instance_valid(sun_glow):
		sun_glow.global_position = at
		sun_glow.scale = Vector3.ONE * k * (1.0 + 0.9 * sun_flare + 0.06 * sin(time * 1.7))
	var pd := (sun_pos - player.global_position).length()
	var was := sun_hazard
	sun_hazard = 1 if pd < sun_radius * Data.SUN_WARN else 0
	if sun_hazard == 1 and was == 0: message.emit("Hull temperature rising — %s" % ("heat shield holding." if GS.heat_shield else "turn away from the star!"))
	if pd < sun_radius and controls and not entering:
		if warp_state != "off":   # hitting it at warp is a crash, like a planet
			sun_hazard = 2
			message.emit("Warp impact with the star!")
			_explode(player.global_position)
			controls = false
			drop_warp()
			_die()
			return
		entering = true
		Packs.request("planets")
		atmosphere_entered.emit(sun_body)   # the star has a surface: same way in as a planet

## On a star's surface the heat eats the shields, then the hull, fast. A heat shield (GS.heat_shield) stops it.
func _sun_heat(dt: float) -> void:
	sun_flare = 0.0
	heat_shielded = GS.heat_shield
	sun_hazard = 0 if heat_shielded else 1
	if heat_shielded or not controls: return
	if not _sun_burned:
		GS.shield = maxf(0.0, GS.shield - GS.max_shield() / Data.SUN_SHIELD_SECS * dt)
		if GS.shield <= 0.0: _sun_burned = true   # once the shields are gone they stay gone here
	else:
		GS.shield = 0.0
		GS.hull -= GS.max_hull() / Data.SUN_HULL_SECS * dt
	hit_shake = maxf(hit_shake, 0.12)
	if GS.hull <= 0.0:
		GS.hull = 0.0
		sun_hazard = 2
		message.emit("Burned up in the star.")
		_explode(player.global_position)
		controls = false
		_die()

func _update_player(dt: float) -> void:
	var s: Dictionary = GS.ship()
	var base_speed: float = s["speed"]
	var turn: float = float(s["turn"]) * (1.0 + GS.mod("turn"))   # (v1.9w: + Control Unit)
	gun_cd = maxf(0.0, gun_cd - dt)
	shield_delay = maxf(0.0, shield_delay - dt)
	hit_shake = maxf(0.0, hit_shake - dt * 2.5)
	call_cd = maxf(0.0, call_cd - dt)
	chatter_cd = maxf(0.0, chatter_cd - dt)
	GS.energy = minf(Data.ENERGY_MAX, GS.energy + Data.ENERGY_REGEN * (1.0 + GS.mod("energy_regen")) * dt)   # (v1.9w: + Power Cell)
	if GS.mod("repair") > 0.0 and shield_delay <= 0.0 and GS.hull < GS.max_hull(): GS.hull = minf(GS.max_hull(), GS.hull + GS.max_hull() * GS.mod("repair") * dt)   # v1.9w: Maintenance Port
	for k in ["shield_cd", "energy_cd", "repair_cd", "missile_cd", "mine_cd"]: set(k, maxf(0.0, float(get(k)) - dt))
	if GS.wing_l <= 0.0 or GS.wing_r <= 0.0:
		player_spark -= dt
		if player_spark <= 0.0 and model.visible:
			player_spark = _rng.randf_range(3.0, 5.0)
			var ps := Sections.side_point(player_vis, "l" if GS.wing_l <= 0.0 else "r", model)
			_spark_v(ps, Vector3(_rng.randfn(0, 5), _rng.randfn(0, 5), _rng.randfn(0, 5)), Color(1.0, 0.85, 0.5), 1.8, 0.15)
	if shield_delay <= 0.0 and GS.shield < GS.max_shield():
		GS.shield = minf(GS.max_shield(), GS.shield + GS.max_shield() * 0.12 * dt)
	if not lane.is_empty():   # v1.4l: riding a trade lane: the lane flies the ship
		_lane_update(dt)
		return
	_update_transform(dt)
	if GS.form == "mech": turn *= 1.3   # mechs pivot faster
	var steer := aim if controls else Vector2.ZERO
	var thrust := move if controls else Vector2.ZERO
	if autopilot != null and is_instance_valid(autopilot) and controls:
		var ap := _autopilot_input()
		steer = ap[0]
		thrust = ap[1]
	if special_state == "turning": steer = Vector2.ZERO   # v1.9c: on release the special turns the ship itself (while you hold it you fly)
	if man_kind != "":   # v1.9l: a SPECIAL manoeuvre flies the ship for a moment
		steer = Vector2.ZERO
		_man_update(dt)
	if warp_state == "on": steer *= 0.35 # heavy steering at warp speed
	# full loops: pitch is not capped. Upside down, left/right steering is mirrored so it still turns the way the
	# stick points on screen (the camera rolls over with the ship).
	yaw -= steer.x * turn * dt * (1.0 if cos(pitch) >= 0.0 else -1.0)
	pitch = wrapf(pitch - steer.y * turn * 0.8 * dt, -PI, PI)
	player.basis = Basis.from_euler(Vector3(pitch, yaw, 0))
	# v1.5n THRUST ARC: while THRUST is on, the ship's nose rears up into an arc (more when you are climbing or pulling
	# up), and settles back to level when you let go. The model only: the flight itself does not change.
	var climb := 0.0
	if vel.length() > 5.0: climb = maxf(0.0, vel.normalized().dot(Vector3.UP))
	var arc_want := 0.0
	if boosting and warp_state == "off": arc_want = deg_to_rad(Data.THRUST_ARC_DEG) * clampf(Data.THRUST_ARC_BASE + maxf(0.0, -steer.y) + climb, 0.0, 1.0)
	thrust_arc = lerpf(thrust_arc, arc_want, minf(1.0, dt * (Data.THRUST_ARC_IN if arc_want > thrust_arc else Data.THRUST_ARC_OUT)))
	if is_instance_valid(model) and GS.form != "mech" and transform_t <= 0.0:
		model.rotation.z = lerpf(model.rotation.z, -steer.x * 0.55, minf(1.0, dt * 4.0))
		model.rotation.x = lerpf(model.rotation.x, -steer.y * 0.12 + thrust_arc, minf(1.0, dt * 6.0))
		if special_state == "charging": model.rotation.z = special_roll   # v1.5o: the barrel roll while the special charges
		if man_kind != "": model.rotation.z = man_roll   # v1.9l: the manoeuvre's barrel roll
	var fwd := -player.global_basis.z
	var right := player.global_basis.x
	boosting = false
	var rate := 1.8
	if warp_state == "charging":
		# the drive spools while you keep flying (escape run): energy builds behind the ship, weapons stay locked
		warp_t += dt
		_booster_particles(dt, clampf(warp_t / Data.WARP_CHARGE, 0.0, 1.0))
		_warp_bulge(clampf(warp_t / Data.WARP_CHARGE, 0.0, 1.0))
		if warp_t >= Data.WARP_CHARGE:
			warp_state = "on"
			warp_flash = 0.8
			engine_kill = false
			_warp_bulge(-1.0)
			vel = fwd * base_speed * Data.WARP_MULT   # the ship shoots forward
			_spark(player.global_position - fwd * 4.0, Color(0.8, 0.85, 1.0), 26.0, 0.4)
			Sfx.play("warp_go", -2.0)
			message.emit("Warp! Weapons locked until you drop out.")
	if ground_mode and surface_mode and warp_state == "off":   # v1.8r: gravity, walking / landed
		_ground_move(dt, thrust, base_speed)
	elif GS.form == "mech" and warp_state == "off":
		_mech_move(dt, thrust, base_speed)
	elif warp_state == "on":
		vel = vel.lerp(fwd * base_speed * Data.WARP_MULT, minf(1.0, dt * 1.2))
		_booster_particles(dt, 0.5)
	elif engine_kill:
		# engines off: keep drifting on the current vector while the nose turns freely.
		# v1.9u (owner): THRUST restarts the engines and puts you straight back at full thrust speed
		if thrust_held and controls and GS.energy > 1.0:
			engine_kill = false
			warp_drift = false
			_boost_was = false
			message.emit("Engines restarted.")
	elif braking:
		vel = vel.lerp(Vector3.ZERO, minf(1.0, dt * 3.0))
		if vel.length() < 0.6:
			vel = Vector3.ZERO
			braking = false
			holding = true
			message.emit("Full stop.")
	else:
		# default cruise: centred stick holds Data.CRUISE, forward speeds up to full, pulling back slows to a stop
		var f := thrust.y if thrust.y >= 0.0 else thrust.y * 0.5
		if cruise_assist:
			if thrust.length() > 0.15 or thrust_held: holding = false
			if thrust.y < -0.9 and vel.length() < 2.0: holding = true   # pulled all the way back to a stop: stay there
			# v1.4n: holding the stick forward IS the throttle: it builds gradually to FORWARD_MULT x ship speed
			# (Cadet: 100 m/s) and settles back to cruise when you let go. The autopilot keeps its old, gentler top speed.
			var top: float = 1.0 if (autopilot != null and is_instance_valid(autopilot)) else Data.FORWARD_MULT
			f = Data.CRUISE + thrust.y * (top - Data.CRUISE) if thrust.y >= 0.0 else Data.CRUISE * (1.0 + thrust.y)
			if thrust.y > 0.15 and top > 1.0: rate = Data.FORWARD_RATE
			if holding: f = 0.0
		var desired := fwd * base_speed * f + right * base_speed * 0.6 * thrust.x
		# v1.4n: THRUST = an instant burst at BURST_MULT x ship speed (Cadet: 120 m/s) the way the stick points,
		# straight up with the stick centred. Holding the button keeps you moving that way.
		var burst_now := thrust_held and controls and GS.energy > 1.0
		if burst_now and not _boost_was:
			dash_dir = burst_dir(thrust)
			last_dash = burst_name(thrust)
			vel = player.global_basis * dash_dir * base_speed * Data.BURST_MULT
			Sfx.play("whoosh", -6.0, 1.3)
		_boost_was = burst_now
		if burst_now and dash_dir != Vector3.ZERO:
			boosting = true
			GS.energy = maxf(0.0, GS.energy - Data.THRUST_ENERGY * dt)
			desired = player.global_basis * dash_dir * base_speed * Data.BURST_MULT
			rate = Data.BURST_RATE
			_booster_particles(dt, 0.25)
		vel = vel.lerp(desired, minf(1.0, dt * rate))
	player.global_position += vel * dt
	speed_now = vel.length()
	if controls and warp_state == "off" and transform_t <= 0.0:
		var want := fire_held or fire_lock
		if GS.is_auto("guns") and _in_fire_cone(target): want = true
		var cost := Data.ENERGY_PER_GUN * float(GS.core_slots().size() + GS.mount_items().filter(func(x): return Data.WEAPONS.has(x)).size())   # (v1.9e: only fitted guns use gun energy; v1.9u: + the core gun)
		if want and gun_cd <= 0.0 and GS.energy >= cost:
			GS.energy -= cost
			_fire_guns()
		_auto_systems(dt)

# ---------------------------------------------------------------- engine controls
func full_stop() -> void:
	if warp_state != "off": drop_warp("Dropping out of warp.")
	engine_kill = false
	braking = true
	autopilot = null

func toggle_engine_kill() -> bool:
	if GS.form == "mech": return false
	if warp_state == "on":   # v1.9u (owner): KILL at warp = engines off, still drifting at warp speed; turn and shoot freely
		warp_state = "off"
		warp_t = 0.0
		_warp_bulge(-1.0)
		engine_kill = true
		warp_drift = true
		braking = false
		return true
	if warp_state == "charging": return false
	engine_kill = not engine_kill
	warp_drift = false
	braking = false
	return engine_kill

## Warp spools for WARP_CHARGE seconds while you keep flying (no stop needed). Weapons lock from the first second;
## nearby enemies see the charge and close in to stop you. Tap WARP again during the spool to cancel.
func request_warp() -> String:
	if warp_state == "on":
		drop_warp("Warp disengaged.")
		return "off"
	if warp_state == "charging":
		warp_state = "off"
		warp_t = 0.0
		_warp_bulge(-1.0)
		return "cancelled"
	if surface_mode: return "atmosphere"
	if GS.form == "mech": return "mech"
	if transform_t > 0.0: return "busy"
	braking = false
	warp_state = "charging"
	warp_t = 0.0
	Sfx.play("warp_spool", -4.0)
	return "charging"

var warp_flash := 0.0   # seconds of "WARP" banner after engaging
var _bulge: MeshInstance3D
## Bright energy bulge behind the ship while the warp drive spools (k 0..1), hidden with k < 0.
func _warp_bulge(k: float) -> void:
	if k < 0.0:
		if is_instance_valid(_bulge): _bulge.visible = false
		return
	if not is_instance_valid(_bulge):
		_bulge = MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 2.0
		sm.radial_segments = 16
		sm.rings = 8
		_bulge.mesh = sm
		var m := _glow_mat(Color(0.55, 0.7, 1.0)).duplicate() as StandardMaterial3D
		_bulge.material_override = m
		_bulge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		player.add_child(_bulge)
	_bulge.visible = true
	var pulse := 1.0 + 0.12 * sin(time * (8.0 + 22.0 * k))
	_bulge.position = Vector3(0, 0, 4.5 + k * 2.0)
	_bulge.scale = Vector3(1.2 + 2.6 * k, 1.0 + 2.0 * k, 1.6 + 4.0 * k) * pulse
	(_bulge.material_override as StandardMaterial3D).albedo_color = Color(0.55 + 0.4 * k, 0.7 + 0.25 * k, 1.0, 0.25 + 0.5 * k)

func drop_warp(why := "") -> void:
	if warp_state == "off": return
	warp_state = "off"
	warp_t = 0.0
	if is_instance_valid(player): _warp_bulge(-1.0)
	vel = vel.normalized() * GS.ship()["speed"]
	if why != "": message.emit(why)

func warp_active() -> bool:
	return warp_state != "off"

func _booster_particles(dt: float, k: float) -> void:
	_particle_acc += dt * (8.0 + 40.0 * k)
	var back := player.global_basis.z
	while _particle_acc >= 1.0:
		_particle_acc -= 1.0
		var side := player.global_basis.x * _rng.randf_range(-1.2, 1.2) + player.global_basis.y * _rng.randf_range(-0.6, 0.6)
		var at := player.global_position + back * 4.5 + side
		var col := Color(0.4, 0.8, 1.0).lerp(Color(1.0, 1.0, 1.0), k)
		_spark_v(at, back * (6.0 + 16.0 * k) + side * 2.0 + vel, col, 0.6 + 1.2 * k, 0.25 + 0.15 * k)

var last_arrived: Node3D = null
func _autopilot_input() -> Array:
	var goal: Vector3 = autopilot.global_position
	var kind: String = autopilot.get_meta("kind", "")
	if kind == "planet" or kind == "station": goal = dock_point(autopilot)
	if kind == "landmark":      # stop a little way off a placeholder planet or station
		var off: Vector3 = (player.global_position - autopilot.global_position).normalized()
		goal = autopilot.global_position + off * (float(autopilot.get_meta("radius")) + Data.PH_GOTO_STANDOFF)
	if kind == "gate": goal = autopilot.global_position + autopilot.global_basis.z * 120.0
	var to := goal - player.global_position
	var local := player.global_basis.inverse() * to.normalized()
	var steer := Vector2(clampf(local.x * 3.0, -1, 1), clampf(-local.y * 3.0, -1, 1))
	var dist := to.length()
	if dist < 170.0:
		last_arrived = autopilot   # v1.9k: main sees where the autopilot got to (a job's GO TO carries on through gates)
		autopilot = null
		drop_warp()
		if cruise_assist: braking = true   # stop at the destination instead of cruising past it
		message.emit("Autopilot: arrived.")
		return [Vector2.ZERO, Vector2.ZERO]
	var aligned := local.z < -0.97
	# long legs: spool the warp drive while flying on, warp, drop out near the destination (and before any atmosphere)
	if warp_state == "off" and aligned and dist > 1500.0 and planet_hazard == 0: request_warp()
	if warp_state == "on" and (dist < 650.0 or planet_hazard > 0): drop_warp("Autopilot: dropping out of warp.")
	var th := 1.0 if local.z < -0.3 else 0.2
	return [steer, Vector2(0, th)]

func _in_fire_cone(tv) -> bool:   # (untyped: a target freed this frame is just "no", not a script error)
	if tv == null or not is_instance_valid(tv): return false
	var t: Node3D = tv
	if t.get_meta("kind", "") != "enemy": return false
	var to := t.global_position - player.global_position
	var w: Dictionary = GS.weapon()
	if to.length() > float(w["range"]): return false
	return (-player.global_basis.z).dot(to.normalized()) > cos(deg_to_rad(8.0))

## Where to aim so the guns hit the target: its position plus how far it moves (relative to you) while the bolt flies.
func lead_point(t: Node3D) -> Vector3:
	var tv: Vector3 = _enemy_entry(t).get("vel", Vector3.ZERO)
	var d := t.global_position.distance_to(player.global_position)
	return t.global_position + (tv - vel) * (d / float(GS.weapon()["speed"]))

func _fire_guns() -> void:
	var w: Dictionary = GS.weapon()
	gun_cd = 1.0 / float(w["rate"])
	var guns: int = GS.ship()["guns"]
	var fwd := -player.global_basis.z
	var aim_dir := fwd
	# light aim assist toward the lead point of a target inside a small cone
	if target and is_instance_valid(target) and target.get_meta("kind", "") == "enemy":
		var to := target.global_position - player.global_position
		if fwd.dot(to.normalized()) > cos(deg_to_rad(10.0)):
			aim_dir = (lead_point(target) - player.global_position).normalized()
	if mech_fpv() and fpv != null:   # v1.7z: in the mech's first-person view the rifle fires (all guns' worth, one bolt) at the crosshair
		var muzzle: Vector3 = cam.global_position - cam.global_basis.z * 4.0 if zoomed else fpv.global_transform * fpv_muzzle
		var at: Vector3 = cam.global_position - cam.global_basis.z * float(w["range"])
		if aim_dir != fwd: at = lead_point(target)
		_spawn_bolt(muzzle, (at - muzzle).normalized() * float(w["speed"]) + vel, float(w["damage"]) * guns * (GS.mech_arm() if GS.form == "mech" else 1.0), w["color"], "player", float(w["range"]) / float(w["speed"]))
		fpv_shot()
		if _laser_sfx_cd <= 0.0:
			Sfx.play("laser", -9.0)
			_laser_sfx_cd = 0.07
		return
	# v1.9e (owner): each mount fires its own gun at its own rate; a mount with a missile pod does not fire bolts.
	# v1.9u (owner): the core gun fires from the nose too, so a core + 2 wing guns = 3 shots forward.
	var items: Array = GS.mount_items()
	var slots: Array = []
	for k in GS.core_slots(): slots.append("core%d" % k)   # v1.9w: 1-3 front guns by ship level
	for g in items.size(): slots.append(g)
	var next_cd := 10.0
	var sounds := {}
	var mk := GS.mech_arm() if GS.form == "mech" else 1.0
	for g in slots:
		var ck: int = int(str(g).substr(4)) if g is String else 0
		var gid: String = GS.core_item(ck) if g is String else str(items[g])
		if not Data.WEAPONS.has(gid): continue
		var wg: Dictionary = Data.WEAPONS[gid]
		var ready_at: float = float(mount_next.get(g, 0.0))
		if time + 0.001 < ready_at:
			next_cd = minf(next_cd, ready_at - time)
			continue
		mount_next[g] = time + 1.0 / float(wg["rate"])
		next_cd = minf(next_cd, 1.0 / float(wg["rate"]))
		var from: Vector3
		if g is String:   # the core: straight out of the nose (level 2+: two side by side; level 3: and one under the belly)
			var off := Vector3.ZERO
			if GS.core_slots().size() > 1 and ck in [-1, -5]: off = player.global_basis.x * _ship_half_width() * (0.12 if ck == -5 else -0.12)
			if ck == -6: off = -player.global_basis.y * 1.2
			from = player.global_position + fwd * maxf(5.0, _ship_length() * 0.5) - player.global_basis.y * 0.3 + off
		else:
			var side := GS.mount_side(g)
			if side < 0.0 and GS.wing_l <= 0.0: continue   # left wing gone: its guns are gone
			if side > 0.0 and GS.wing_r <= 0.0: continue
			var tip: bool = GS.is_tip(g)   # v1.9e (owner): shoulder = close to the core on top; tip = the wing's end underneath
			var hw := _ship_half_width()
			var at: float = Data.MOUNT_TIP_AT if tip else (Data.MOUNT_MID_AT if g >= 4 else Data.MOUNT_SHOULDER_AT)
			from = player.global_position + player.global_basis.x * side * hw * at \
				+ player.global_basis.y * (-Data.MOUNT_DROP if tip else Data.MOUNT_DROP) + fwd * 5.0
		_spawn_bolt(from, aim_dir * float(wg["speed"]) + vel, GS.gun_damage(gid) * mk, wg["color"], "player", float(wg["range"]) / float(wg["speed"]), float(wg.get("shield", -1.0)))
		_spark(from + fwd * 1.5, (wg["color"] as Color).lightened(0.4), 3.2, 0.09)
		sounds[str(wg.get("sound", "laser"))] = true
	gun_cd = clampf(next_cd, 0.02, 1.0)
	if _laser_sfx_cd <= 0.0 and not sounds.is_empty():
		var k := 0
		for snd in sounds:   # v1.9u: each blaster colour has its own sound
			Sfx.play(snd if Sfx.streams.get(snd) != null else "laser", -9.0 - 3.0 * k)
			k += 1
			if k >= 2: break
		_laser_sfx_cd = 0.07

## v1.9g: the player ship's length (m), for sizing the wing guns.
func _ship_length() -> float:
	if not is_instance_valid(model): return 10.0
	var bb: AABB = ShipFactory._aabb(model, Transform3D.IDENTITY)
	return maxf(bb.size.z * model.scale.z, 2.0)

## v1.9e: half the player ship's wingspan (m), for where the wing mounts sit.
var _hw_cache := {}
func _ship_half_width() -> float:
	var key := str(GS.ship_id)
	if _hw_cache.has(key): return _hw_cache[key]
	var hw := 3.0
	if is_instance_valid(model):
		var bb: AABB = ShipFactory._aabb(model, Transform3D.IDENTITY)
		if bb.size.x > 0.5: hw = bb.size.x * 0.5 * model.scale.x
	_hw_cache[key] = hw
	return hw

func _spawn_bolt(from: Vector3, v: Vector3, dmg: float, col: Color, owner: String, life: float, sf := -1.0) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _bolt_mesh
	mi.material_override = ShipFactory.mat(col, true)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = from
	mi.look_at(from + v, Vector3.UP)
	var halo := MeshInstance3D.new()
	halo.mesh = _bolt_halo
	halo.material_override = _glow_mat(col)
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.add_child(halo)
	var head := MeshInstance3D.new()   # glowing head: keeps bolts readable when they fly straight away from the camera
	head.mesh = _bolt_head_mesh()
	head.material_override = _head_mat(col)
	head.position = Vector3(0, 0, -6.0)
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.add_child(head)
	bolts.append({"node": mi, "vel": v, "life": life, "dmg": dmg, "owner": owner, "sf": sf})   # sf: v1.9u shield share (-1 = normal)

static var _head_q: QuadMesh
static var _head_mats := {}
func _bolt_head_mesh() -> QuadMesh:
	if _head_q == null:
		_head_q = QuadMesh.new()
		_head_q.size = Vector2(5.5, 5.5)
	return _head_q
func _head_mat(col: Color) -> StandardMaterial3D:
	var k := col.to_html()
	if _head_mats.has(k): return _head_mats[k]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = _spark_tex()
	m.albedo_color = col.lightened(0.35)
	_head_mats[k] = m
	return m

static var _glow_mats := {}
func _glow_mat(col: Color) -> StandardMaterial3D:
	var k := col.to_html()
	if _glow_mats.has(k): return _glow_mats[k]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(col, 0.33)
	_glow_mats[k] = m
	return m

## Locks held right now for a slot item ("light_missile" / "heavy_missile"): one per LOCK_STEP seconds on target,
## up to what the rack holds and the ammo left.
func lock_count(item := "light_missile") -> int:
	var ammo := GS.heavy_missiles if item == "heavy_missile" else GS.missiles
	var step: float = (Data.HEAVY_LOCK_STEP if item == "heavy_missile" else Data.LOCK_STEP) * (1.0 - GS.mod("lock"))   # v1.5x: the super missile locks slowly (v1.9w: Processor Unit)
	return mini(mini(GS.max_locks(item), int(lock_time / step)), ammo)

## v1.9r (owner): the locks are SHARED: they build on the target (one per LOCK_STEP, the heavy missile's slower, one per
## HEAVY_LOCK_STEP) up to the rack's full count, and are spread over every hostile in view: the target first, then
## the nearest others in the wide lock cone, one each in turn. [[node, locks], ...]
func lock_spread(item := "light_missile") -> Array:
	var n := lock_count(item)
	if n <= 0: return []
	var cands := lock_candidates()
	if cands.is_empty(): return []
	var counts := {}
	for i in n:
		var c: Node3D = cands[i % cands.size()]
		counts[c] = int(counts.get(c, 0)) + 1
	var out: Array = []
	for c in cands:
		if counts.has(c): out.append([c, counts[c]])
	return out

## The hostiles the locks go to: the target, then the nearest others in view inside the wide lock cone.
func lock_candidates() -> Array:
	var out: Array = []
	var t: Node3D = target if is_instance_valid(target) and target.get_meta("kind", "") == "enemy" else null
	if t == null: return out
	out.append(t)
	var others: Array = []
	for e in enemies:
		var nd: Node3D = e["node"]
		if nd == t or not is_instance_valid(nd) or nd.get_meta("kind", "enemy") != "enemy": continue
		if _cone(nd, Data.LOCK_SPREAD_DEG, Data.LOCK_RANGE): others.append(nd)
	others.sort_custom(func(a, b): return a.global_position.distance_squared_to(player.global_position) < b.global_position.distance_squared_to(player.global_position))
	out.append_array(others.slice(0, maxi(0, Data.LOCK_SPREAD_MAX - 1)))
	return out

## Fire `count` missiles: the first now, the rest VOLLEY_GAP apart, fanned out; each one at the hostile its lock is on.
func fire_volley(heavy: bool, count: int) -> int:
	count = clampi(count, 1, GS.heavy_missiles if heavy else GS.missiles)
	var scale := 1.0 if heavy else float(Data.MISSILE_RACKS.get(GS.rack, Data.MISSILE_RACKS["triple"])["damage"])
	if count <= 1 and not heavy: scale = 1.0   # a single shot without locks is a full-strength missile
	var aims: Array = []   # v1.9r: one hostile per shot, from the shared locks
	for pr in lock_spread("heavy_missile" if heavy else "light_missile"):
		for k in int(pr[1]): aims.append(pr[0])
	if not fire_missile(heavy, 0, count, scale, aims[0] if not aims.is_empty() else null): return 0
	var t = missiles_live[-1]["target"]
	for k in range(1, count):
		var tk = aims[k] if k < aims.size() and is_instance_valid(aims[k]) else t
		volley_queue.append({"t": Data.VOLLEY_GAP * k, "heavy": heavy, "k": k, "n": count, "scale": scale, "target": tk})
	lock_time = 0.0
	return count

func fire_missile(heavy := false, k := 0, n := 1, scale := 1.0, forced: Node3D = null, straight := false) -> bool:
	if (GS.heavy_missiles if heavy else GS.missiles) <= 0: return false
	var t := target if (target and is_instance_valid(target) and target.get_meta("kind", "") == "enemy") else null
	if forced != null and is_instance_valid(forced): t = forced
	if t == null and not straight: t = _nearest_enemy(900.0)
	if straight: t = null   # v1.9u: no lock: straight ahead
	var ground_shot := t == null and (straight or (surface_mode and _over_blocks()) or not surface_mode)   # no target: fire straight (v1.5t: to dig; v1.8b owner: in space too, it blows up on its fuse or on what it meets)
	if t == null and not ground_shot:
		message.emit("No hostile target for missile lock.")
		return false
	if heavy: GS.heavy_missiles -= 1
	else: GS.missiles -= 1
	var te := _enemy_entry(t) if t != null else {}
	if te.has("pilot"): _chatter(te, "missile_incoming", true)
	# v1.4m: a launch is noticed. The target and its wing turn on you.
	for ae in enemies:
		if t == null: break
		if ae["node"] == t or (ae["node"] as Node3D).global_position.distance_to(t.global_position) < Data.MISSILE_ALERT: ae["aggro"] = true
	GS.changed.emit()
	var mi := _missile_node(heavy)
	add_child(mi)
	mi.global_position = player.global_position - player.global_basis.y * 1.5
	var fan := Vector3.ZERO   # a volley fans out left/right and a little up
	if n > 1:
		var a := (float(k) / float(n - 1) - 0.5) * 2.0
		fan = (player.global_basis.x * a + player.global_basis.y * (1.0 - absf(a)) * 0.5) * Data.VOLLEY_SPREAD
	missiles_live.append({"node": mi, "vel": -player.global_basis.z * (Data.MISSILE_SPEED if ground_shot else 90.0) + vel + fan, "target": t, "life": Data.MISSILE_LIFE, "heavy": heavy, "scale": scale, "shaken": ground_shot,
		"wp": _rng.randf() * TAU, "wf": _rng.randf_range(Data.WEAVE_HZ[0], Data.WEAVE_HZ[1]), "wo": _rng.randf() * TAU, "special": _special_left > 0})
	if _special_left > 0: _special_left -= 1
	_trail_new(mi)
	Sfx.play("missile", -4.0 if k == 0 else -9.0)
	return true

func _missile_node(heavy: bool) -> Node3D:
	var mi: Node3D
	if ShipFactory.has_real_model("missile"):
		mi = ShipFactory.build("missile")
		var flare := MeshInstance3D.new()   # engine glow at the tail (+Z)
		var fm := SphereMesh.new()
		fm.radius = 0.35
		fm.height = 0.7
		flare.mesh = fm
		flare.position = Vector3(0, 0, 1.8)
		flare.material_override = ShipFactory.mat(Data.HEAVY_LOCK_COLOR if heavy else Color(1.0, 0.85, 0.55), true)   # v1.9r: the heavy missile glows purple, like its lock counter
		mi.add_child(flare)
	else:
		var box := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.6, 0.6, 2.6)
		box.mesh = bm
		box.material_override = ShipFactory.mat(Color(1.0, 0.8, 0.4), true)
		mi = box
	if heavy: mi.scale = Vector3.ONE * 1.5
	_add_missile_flame(mi)
	return mi

## Exhaust flame out of the missile's tail (+Z): a hot inner cone and a wider outer cone that flicker.
func _add_missile_flame(mi: Node3D) -> void:
	for layer in [[0.45, 4.5, Color(1.0, 0.95, 0.7), 0.95], [0.9, 7.5, Color(1.0, 0.5, 0.15), 0.6]]:
		var cone := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = layer[0]
		cm.height = layer[1]
		cm.radial_segments = 10
		cm.rings = 1
		cone.mesh = cm
		var m := _glow_mat(layer[2]).duplicate() as StandardMaterial3D
		m.albedo_color = Color(layer[2], layer[3])
		cone.material_override = m
		cone.rotation_degrees = Vector3(90, 0, 0)            # cone tip points back along +Z
		cone.position = Vector3(0, 0, 1.7 + layer[1] * 0.5)
		cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cone.name = "Flame"
		mi.add_child(cone)

func _update_bolts(dt: float) -> void:
	for i in range(bolts.size() - 1, -1, -1):
		var b: Dictionary = bolts[i]
		var n: MeshInstance3D = b["node"]
		var from := n.global_position
		var to: Vector3 = from + b["vel"] * dt
		n.global_position = to
		b["life"] -= dt
		var hit := false
		if b["owner"] == "player" or b["owner"] == "ally":   # v1.9n: allied ships' shots hit the enemy too
			for e in enemies:
				if _seg_hit(from, to, e["node"].global_position, float(e["def"].get("hit_r", 7.5))):
					_damage_enemy(e, b["dmg"], _seg_closest(from, to, e["node"].global_position) if not e["def"].get("capital", false) else Vector3.INF, float(b.get("sf", -1.0)))
					hit = true
					break
		elif b["owner"] != "fx":
			if _seg_hit(from, to, player.global_position, 5.0):
				_player_hit(b["dmg"], _seg_closest(from, to, player.global_position))
				hit = true
			else:
				for a in allies:   # v1.9n: enemy fire hits your allies as well
					if is_instance_valid(a["node"]) and _seg_hit(from, to, a["node"].global_position, float(a["hit_r"])):
						_damage_ally(a, float(b["dmg"]))
						hit = true
						break
		if not hit and surface_mode:   # EXPERIMENT (v1.5t): shots dig the block ground
			var rb := _ray_blocks(from, to)
			if rb[0] != null:
				var bfg: BlockField = rb[0]
				var at: Vector3 = rb[1]
				if true:
					hit = true
					if b["owner"] == "player":
						var res := _blast_blocks(at, "gun", bfg)
						_spark(at, bfg.tone(str(res["mat"])) if str(res["mat"]) != "" else Color(1, 0.85, 0.6), 4.5 if int(res["broken"]) > 0 else 2.5, 0.25)
					else:
						_spark(at, Color(1, 0.8, 0.5), 2.0)
		if not hit and in_belt_region(to):
			if not asteroids.is_empty():   # v1.7x: shots chip the block asteroids (yours break blocks)
				var ah := ray_asteroids(from, to)
				if not ah.is_empty():
					hit = true
					var ast = ah[0]
					if b["owner"] == "player": damage_asteroid(ast, float(b["dmg"]), ah[2], "gun")   # v1.8d: wear the piece down until it splits
					else: _spark(ah[2], Color(1, 0.8, 0.5), 2.0)
			else:
				for r in rocks:
					if _seg_hit(from, to, r[0], r[1]):
						_spark(to, Color(1, 0.8, 0.5), 3.0)
						hit = true
						break
		if hit or b["life"] <= 0.0:
			n.queue_free()
			bolts.remove_at(i)

func in_belt_region(p: Vector3) -> bool:
	return p.distance_to(belt_center) < belt_radius + 60.0 or in_ring(p)

# ---------------------------------------------------------------- v1.8f the ringed planet
var ring := {}                    # {centre, normal, inner, outer, thick} when this system's planet has a ring
var ring_band: MeshInstance3D = null

## Inside the ring's band of rock (near its plane, between its edges)?
func in_ring(p: Vector3, pad := 60.0) -> bool:
	if ring.is_empty(): return false
	var rel: Vector3 = p - (ring["centre"] as Vector3)
	var up: float = rel.dot(ring["normal"])
	if absf(up) > float(ring["thick"]) + pad: return false
	var flat := (rel - (ring["normal"] as Vector3) * up).length()
	return flat > float(ring["inner"]) - pad and flat < float(ring["outer"]) + pad

func _build_ring() -> void:
	var spec: Dictionary = Data.RINGED_PLANETS.get(sys_id, {})
	if spec.is_empty() or not is_instance_valid(planet): return
	var r: float = float(sys["planet"]["radius"])
	var tilt := Basis(Vector3.RIGHT, deg_to_rad(float(spec["tilt_deg"])))
	ring = {"centre": planet.global_position, "normal": (tilt * Vector3.UP).normalized(), "inner": r * float(spec["inner"]), "outer": r * float(spec["outer"]), "thick": float(spec["thick"])}
	# the band: a flat see-through disc with lighter and darker rings, seen from far away
	var seg := 96
	var bands := 7
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var base: Color = spec["band"]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(sys_id) + 77
	var radii: Array = []
	var alphas: Array = []
	for b in bands + 1:
		radii.append(lerpf(float(ring["inner"]), float(ring["outer"]), float(b) / bands))
		alphas.append(0.0 if b == 0 or b == bands else rng.randf_range(0.35, 0.7))
	for b in bands + 1:
		for k in seg + 1:
			var a := TAU * k / seg
			verts.append(Vector3(cos(a), 0, sin(a)) * float(radii[b]))
			cols.append(Color(base.r, base.g, base.b, alphas[b]).darkened(0.15 if b % 2 == 0 else 0.0))
	for b in bands:
		for k in seg:
			var i0 := b * (seg + 1) + k
			var i1 := i0 + seg + 1
			idx.append_array([i0, i1, i0 + 1, i0 + 1, i1, i1 + 1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	am.surface_set_material(0, m)
	ring_band = MeshInstance3D.new()
	ring_band.name = "RingBand"
	ring_band.mesh = am
	ring_band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring_band)
	ring_band.global_transform = Transform3D(tilt, planet.global_position)
	# the rocks in it: block asteroids, mined like any field's
	var holder := Node3D.new()
	holder.name = "RingAsteroids"
	add_child(holder)
	for i in int(spec["count"]):
		var a := rng.randf() * TAU
		var d := rng.randf_range(float(ring["inner"]) * 1.03, float(ring["outer"]) * 0.97)
		var p: Vector3 = planet.global_position + tilt * (Vector3(cos(a), 0, sin(a)) * d + Vector3(0, rng.randf_range(-1.0, 1.0) * float(ring["thick"]) * 0.6, 0))
		var size := rng.randi_range(int(spec["size"][0]), int(spec["size"][1]))
		var ast = BlockAsteroid.new()
		ast.name = "RingRock%d" % i
		ast.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(ast)
		ast.global_position = p
		ast.setup(hash(sys_id) * 17 + i, size, Data.ASTEROID_CELL, false, spec["treasure"])
		ast.set_meta("ring", true)
		ast.health = _piece_hp(ast)
		asteroids.append(ast)
		rocks.append([p, float(ast.radius)])
		ast.set_meta("rock", rocks[-1])

func _seg_closest(a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var ab := b - a
	var l2 := ab.length_squared()
	var t := 0.0
	if l2 > 0.0: t = clampf((c - a).dot(ab) / l2, 0.0, 1.0)
	return a + ab * t

func _seg_hit(a: Vector3, b: Vector3, c: Vector3, r: float) -> bool:
	var ab := b - a
	var t := 0.0
	var l2 := ab.length_squared()
	if l2 > 0.0: t = clampf((c - a).dot(ab) / l2, 0.0, 1.0)
	return (a + ab * t).distance_to(c) < r

## Speed across the line from a missile to its target: what shakes a missile off.
func side_speed(v: Vector3, line: Vector3) -> float:
	if line.length() < 0.01: return 0.0
	var l := line.normalized()
	return (v - l * v.dot(l)).length()

func _missile_trail(n: Node3D) -> void:
	for c in n.get_children():
		if c.name.begins_with("Flame"): c.scale = Vector3(1.0, 0.8 + _rng.randf() * 0.45, 1.0)
	# v1.4l: the long trail is the white ribbon (_update_trails); only a small glow stays at the nozzle
	_spark_v(n.global_position + n.global_basis.z * 2.2, n.global_basis.z * 6.0, Color(1.0, 0.8, 0.5), 2.4, 0.18)

## The swing a missile adds to its path (Robotech style). It dies away near the target so the missile still hits.
func weave(m: Dictionary, v: Vector3, dist: float, dt: float) -> Vector3:
	if not m.has("wp") or v.length() < 1.0: return Vector3.ZERO
	m["wp"] = float(m["wp"]) + dt * TAU * float(m["wf"])
	var k := clampf((dist - Data.WEAVE_FADE * 0.3) / Data.WEAVE_FADE, 0.0, 1.0)
	var fw := v.normalized()
	var sx := fw.cross(Vector3.UP)
	if sx.length() < 0.05: sx = Vector3.RIGHT
	sx = sx.normalized()
	var sy := sx.cross(fw)
	return (sx * sin(float(m["wp"])) + sy * cos(float(m["wp"]) * 0.73 + float(m["wo"]))) * Data.WEAVE_AMP * k

# ---------------------------------------------------------------- Job O: missile ribbon trails
var trails: Array = []            # {"mi", "im", "src", "pts": [[pos, time]...] newest first, "t"}
var _trail_mat: StandardMaterial3D

## Start a ribbon behind a missile: a flat strip that always faces the camera, white at the missile, widening and
## fading toward the end. It outlives the missile by TRAIL_LIFE.
func _trail_new(src: Node3D) -> void:
	if _trail_mat == null:
		_trail_mat = StandardMaterial3D.new()
		_trail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_trail_mat.vertex_color_use_as_albedo = true
		_trail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_trail_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_trail_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	mi.mesh = im
	mi.material_override = _trail_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	add_child(mi)
	mi.global_transform = Transform3D.IDENTITY
	trails.append({"mi": mi, "im": im, "src": src, "pts": [], "t": 0.0})

func _update_trails(dt: float) -> void:
	var cp: Vector3 = cam.global_position if is_instance_valid(cam) else Vector3.ZERO
	for i in range(trails.size() - 1, -1, -1):
		var tr: Dictionary = trails[i]
		var pts: Array = tr["pts"]
		var src = tr["src"]
		var alive: bool = is_instance_valid(src) and not (src as Node).is_queued_for_deletion()
		if alive:
			tr["t"] = float(tr["t"]) - dt
			if tr["t"] <= 0.0:
				tr["t"] = Data.TRAIL_STEP
				pts.push_front([(src as Node3D).global_position, time])
		while not pts.is_empty() and time - float(pts[-1][1]) > Data.TRAIL_LIFE: pts.pop_back()
		var im: ImmediateMesh = tr["im"]
		im.clear_surfaces()
		if pts.is_empty() and not alive:
			(tr["mi"] as Node).queue_free()
			trails.remove_at(i)
			continue
		var line: Array = pts.duplicate()
		if alive: line.push_front([(src as Node3D).global_position, time])
		if line.size() < 2: continue
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		for k in line.size():
			var p: Vector3 = line[k][0]
			var a: Vector3 = line[maxi(k - 1, 0)][0]
			var b: Vector3 = line[mini(k + 1, line.size() - 1)][0]
			var side := (a - b).cross(cp - p)
			side = side.normalized() if side.length() > 0.0001 else Vector3.UP
			var age := clampf((time - float(line[k][1])) / Data.TRAIL_LIFE, 0.0, 1.0)
			var w := lerpf(Data.TRAIL_WIDTH0, Data.TRAIL_WIDTH1, age)
			im.surface_set_color(Color(Data.TRAIL_COLOR, pow(1.0 - age, 1.6)))
			im.surface_add_vertex(p + side * w)
			im.surface_set_color(Color(Data.TRAIL_COLOR, pow(1.0 - age, 1.6)))
			im.surface_add_vertex(p - side * w)
		im.surface_end()

# ---------------------------------------------------------------- Job O: trade lanes (Freelancer style)
## In-system highways. A lane is a row of four-bracket rings between two places; each place on the row has two
## rings, one above the other: the upper row runs A -> B, the lower row B -> A. Dock at a ring and the ship is locked
## and carried ring to ring. The warp look is an energy tunnel that rides ON THE SHIP (plus a glow and a splash at
## each ring): there is no tube between the rings. Jump gates still do the hops between systems.
var lanes: Array = []            # {"a": name, "b": name, "up": [Vector3...], "down": [Vector3...], "dir": unit A->B}
var lane := {}                   # the ride in progress: {"i": lane index, "fwd": bool, "k": next ring, "speed", "t"}
var lane_stats := {"docks": 0, "passes": 0, "exits": 0}
var lane_tunnel: MeshInstance3D
var _lane_mm: MultiMeshInstance3D
var _lane_lights: Array = []

const LANE_TUNNEL_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform vec3 tint : source_color = vec3(0.35, 0.85, 1.0);
uniform float power = 0.0;
void fragment() {
	float streak = pow(fract(sin(floor(UV.x * 240.0) * 91.7) * 43758.5), 5.0);   // v1.4u: finer streaks for the wider tunnel
	float flow = fract(UV.y * 2.0 + TIME * (1.6 + streak * 2.4) + streak * 7.0);
	float band = smoothstep(0.0, 0.25, flow) * smoothstep(1.0, 0.55, flow);
	float ends = smoothstep(0.0, 0.2, UV.y) * smoothstep(1.0, 0.75, UV.y);
	ALBEDO = mix(tint, vec3(1.0), streak * 0.6);
	ALPHA = (0.03 + streak * band * 0.6) * ends * power;
}
"""

## One ring: four metal brackets round a circle with a light strip on each (unit radius; scaled per ring).
func _lane_ring_mesh() -> ArrayMesh:
	var metal := SurfaceTool.new()
	metal.begin(Mesh.PRIMITIVE_TRIANGLES)
	var light := SurfaceTool.new()
	light.begin(Mesh.PRIMITIVE_TRIANGLES)
	var box := BoxMesh.new()
	for b in 4:
		var mid := TAU * b / 4.0 + TAU / 8.0
		for part in [-1, 0, 1]:
			var a: float = mid + part * 0.3
			var xf := Transform3D(Basis(Vector3.BACK, a), Vector3(cos(a), sin(a), 0.0))
			box.size = Vector3(0.14, 0.34, 0.2)       # a slab of the bracket, lying along the circle
			metal.append_from(box, 0, xf)
			box.size = Vector3(0.03, 0.26, 0.06)      # its light strip, on the inside face
			light.append_from(box, 0, xf * Transform3D(Basis.IDENTITY, Vector3(-0.08, 0, 0)))
		var xo := Transform3D(Basis(Vector3.BACK, mid), Vector3(cos(mid), sin(mid), 0.0) * 1.16)
		box.size = Vector3(0.22, 0.12, 0.3)           # the claw on the outside
		metal.append_from(box, 0, xo)
	metal.generate_normals()
	light.generate_normals()
	var mesh: ArrayMesh = metal.commit()
	light.commit(mesh)
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color(0.36, 0.4, 0.46)
	mm.metallic = 0.6
	mm.roughness = 0.45
	mesh.surface_set_material(0, mm)
	var lm := StandardMaterial3D.new()
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.albedo_color = Data.LANE_TINT
	mesh.surface_set_material(1, lm)
	return mesh

## Is the straight run a -> b clear of the sun, the planet and the station (other than its own two ends)?
func _lane_clear(a: Vector3, b: Vector3, skip: Array) -> bool:
	var bodies: Array = [[sun_pos, sun_radius + 400.0]] if sun_pos != Vector3.INF else []
	for n: Node3D in [station, planet]:
		if not (n in skip): bodies.append([n.global_position, float(n.get_meta("radius", 80.0)) + 250.0])
	for d: Dictionary in sys.get("more_planets", []) + sys.get("more_stations", []): bodies.append([d["pos"], float(d["radius"]) + 200.0])
	for q in bodies:
		if _seg_hit(a, b, q[0], q[1]): return false
	return true

func _build_lanes() -> void:
	lanes.clear()
	lane = {}
	if surface_mode: return
	var pairs: Array = [[station, planet]]
	for g in gates: pairs.append([station, g])
	var xfs: Array = []
	for pr in pairs:
		var a: Node3D = pr[0]
		var b: Node3D = pr[1]
		var dir := (b.global_position - a.global_position).normalized()
		var ra: float = (float(a.get_meta("radius", 80.0)) if a != station else 120.0) + Data.LANE_STANDOFF
		var rb: float = (float(b.get_meta("radius", 0.0)) if b == planet else 60.0) + Data.LANE_STANDOFF
		var p0 := a.global_position + dir * ra
		var p1 := b.global_position - dir * rb
		var length := p0.distance_to(p1)
		if length < Data.LANE_MIN_LEN or (p1 - p0).dot(dir) <= 0.0 or not _lane_clear(p0, p1, [a, b]): continue
		var n := clampi(int(ceil(length / Data.LANE_RING_GAP)) + 1, 2, Data.LANE_MAX_RINGS)
		var up := Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT
		up = (up - dir * up.dot(dir)).normalized()
		var ln := {"a": a.name, "b": b.name, "up": [], "down": [], "dir": dir}
		var basis := Basis.looking_at(dir, up).scaled(Vector3.ONE * Data.LANE_RING_RADIUS)
		for k in n:
			var c := p0.lerp(p1, float(k) / float(n - 1))
			ln["up"].append(c + up * Data.LANE_STACK * 0.5)
			ln["down"].append(c - up * Data.LANE_STACK * 0.5)
			xfs.append(Transform3D(basis, ln["up"][k]))
			xfs.append(Transform3D(basis, ln["down"][k]))
		lanes.append(ln)
		# the green light marks each live mouth: where you get on
		for mouth: Vector3 in [ln["up"][0], ln["down"][n - 1]]:
			var lamp := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 5.0
			sm.height = 10.0
			sm.radial_segments = 8
			sm.rings = 4
			lamp.mesh = sm
			lamp.material_override = ShipFactory.mat(Color(0.3, 1.0, 0.45), true)
			add_child(lamp)
			lamp.global_position = mouth + up * (Data.LANE_RING_RADIUS + 12.0)
			_lane_lights.append(lamp)
	if xfs.is_empty(): return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _lane_ring_mesh()
	mm.instance_count = xfs.size()
	for i in xfs.size(): mm.set_instance_transform(i, xfs[i])
	_lane_mm = MultiMeshInstance3D.new()
	_lane_mm.multimesh = mm
	_lane_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_lane_mm)
	# the energy tunnel that rides on the ship (hidden until a lane is in use)
	lane_tunnel = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = Data.LANE_TUNNEL_RADIUS
	cyl.bottom_radius = Data.LANE_TUNNEL_RADIUS * 1.15   # the end behind the ship flares out: its rim is off screen
	cyl.height = Data.LANE_TUNNEL_LEN
	cyl.radial_segments = 48
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = false
	lane_tunnel.mesh = cyl
	var sh := Shader.new()
	sh.code = LANE_TUNNEL_SHADER
	var tm := ShaderMaterial.new()
	tm.shader = sh
	tm.set_shader_parameter("tint", Data.LANE_TINT)
	lane_tunnel.material_override = tm
	lane_tunnel.rotation_degrees = Vector3(-90, 0, 0)      # the cylinder's length runs along the ship's nose line
	lane_tunnel.position = Vector3(0, 0, -Data.LANE_TUNNEL_LEN * (0.5 - Data.LANE_TUNNEL_BACK))   # pulled back: part of it trails behind the camera
	lane_tunnel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lane_tunnel.visible = false
	player.add_child(lane_tunnel)

## The ring you could dock right now: nearest live ring inside LANE_DOCK_RANGE (one with a ring after it).
## Returns {} or {"i": lane, "fwd": bool, "k": ring index, "to": destination name, "pos": Vector3}.
func lane_candidate() -> Dictionary:
	if surface_mode or not lane.is_empty() or not controls or warp_state != "off" or GS.form == "mech": return {}
	var best := {}
	var bd: float = Data.LANE_DOCK_RANGE
	for i in lanes.size():
		var ln: Dictionary = lanes[i]
		var n: int = ln["up"].size()
		for k in n:
			for fwd in [true, false]:
				if (fwd and k >= n - 1) or (not fwd and k <= 0): continue   # the last ring of a row is the way off
				var pos: Vector3 = (ln["up"] if fwd else ln["down"])[k]
				var d := player.global_position.distance_to(pos)
				if d < bd:
					bd = d
					best = {"i": i, "fwd": fwd, "k": k, "to": ln["b"] if fwd else ln["a"], "pos": pos}
	return best

## Dock the ring in range: controls lock and the lane takes the ship.
func lane_enter() -> bool:
	var c := lane_candidate()
	if c.is_empty(): return false
	lane = {"i": c["i"], "fwd": c["fwd"], "k": c["k"], "speed": maxf(vel.length(), 20.0), "t": 0.0, "to": c["to"]}
	autopilot = null
	engine_kill = false
	braking = false
	holding = false
	lane_stats["docks"] += 1
	Sfx.play("warp_spool", -8.0, 1.4)
	message.emit("Trade lane to %s. Controls locked." % c["to"])
	return true

## Leave the lane where you are (the button again, or the ship was destroyed).
func lane_abort() -> void:
	if lane.is_empty(): return
	lane = {}
	vel = -player.global_basis.z * Data.LANE_EXIT_SPEED
	if is_instance_valid(lane_tunnel): lane_tunnel.visible = false

func _lane_update(dt: float) -> void:
	var ln: Dictionary = lanes[lane["i"]]
	var row: Array = ln["up"] if lane["fwd"] else ln["down"]
	var step_k := 1 if lane["fwd"] else -1
	var last: int = row.size() - 1 if lane["fwd"] else 0
	lane["t"] = float(lane["t"]) + dt
	var sp: float = minf(Data.LANE_SPEED, float(lane["speed"]) + Data.LANE_SPEED / Data.LANE_RAMP * dt)
	var to_end := player.global_position.distance_to(row[last])
	if to_end < Data.LANE_SLOW_DIST: sp = minf(sp, maxf(Data.LANE_EXIT_SPEED, Data.LANE_SPEED * to_end / Data.LANE_SLOW_DIST))
	lane["speed"] = sp
	var left := sp * dt
	while left > 0.0 and not lane.is_empty():
		var target_pos: Vector3 = row[lane["k"]]
		var to := target_pos - player.global_position
		if to.length() > left:
			player.global_position += to.normalized() * left
			_face(to)
			vel = to.normalized() * sp
			left = 0.0
		else:
			left -= to.length()
			player.global_position = target_pos
			_lane_pass(target_pos, ln["dir"])
			if lane["k"] == last:
				lane_stats["exits"] += 1
				var out_dir: Vector3 = (ln["dir"] as Vector3) * (1.0 if lane["fwd"] else -1.0)
				_face(out_dir)
				vel = out_dir * Data.LANE_EXIT_SPEED
				message.emit("Lane exit: %s." % lane["to"])
				lane = {}
			else:
				lane["k"] = int(lane["k"]) + step_k
	speed_now = vel.length()
	boosting = false
	if is_instance_valid(lane_tunnel):
		lane_tunnel.visible = not lane.is_empty()
		(lane_tunnel.material_override as ShaderMaterial).set_shader_parameter("power", clampf(sp / Data.LANE_SPEED, 0.0, 1.0))
	if is_instance_valid(model): model.rotation = model.rotation.lerp(Vector3.ZERO, minf(1.0, dt * 4.0))

## Passing a ring: it lights up and throws a splash.
func _lane_pass(at: Vector3, dir: Vector3) -> void:
	lane_stats["passes"] += 1
	_ring_fx(at, Color(Data.LANE_TINT, 0.9), Data.LANE_RING_RADIUS * 0.9, Data.LANE_SPLASH, 1.5)
	_spark(at, Color(Data.LANE_TINT.lerp(Color.WHITE, 0.5), 0.8), Data.LANE_RING_RADIUS * 1.2, 0.22)
	for k in 8:
		var a := TAU * k / 8.0
		var side := (cam.global_basis.x * cos(a) + cam.global_basis.y * sin(a)) * Data.LANE_RING_RADIUS
		_spark_v(at + side, side.normalized() * 30.0 + dir * 40.0, Data.LANE_TINT, 4.0, 0.4)
	Sfx.play("whoosh", -7.0, 1.3)

# ---------------------------------------------------------------- Job O: explosions
var blast_pending: Array = []
var blasts := 0                  # how many big blasts have gone off (tests)
var last_blast := {}

func _ring_fx(at: Vector3, col: Color, size: float, life: float, grow: float) -> void:
	var mi := _hex_node(col, size)
	mi.mesh = _ring_mesh()
	add_child(mi)
	mi.global_position = at
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * size * grow, life).set_ease(Tween.EASE_OUT)
	tw.tween_property(mi.material_override, "albedo_color:a", 0.0, life)
	tw.chain().tween_callback(mi.queue_free)

var _ring_m: ArrayMesh
func _ring_mesh() -> ArrayMesh:
	if _ring_m != null: return _ring_m
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 28:
		var a0 := TAU * i / 28.0
		var a1 := TAU * (i + 1) / 28.0
		var o0 := Vector3(cos(a0), sin(a0), 0)
		var o1 := Vector3(cos(a1), sin(a1), 0)
		for v in [o0, o1, o1 * 0.94, o0, o1 * 0.94, o0 * 0.94]: st.add_vertex(v)
	_ring_m = st.commit()
	return _ring_m

## A proper explosion: white flash, a fireball cloud, a shock ring, flying debris, then a few later pops around it.
## spec = [flash size, fireballs, debris bits, later pops, seconds between pops] (Data.BLAST_*).
func _blast(at: Vector3, spec: Array, kind := "") -> void:
	var size: float = spec[0]
	blasts += 1
	last_blast = {"at": at, "kind": kind, "size": size}
	_spark(at, Color(1.0, 1.0, 0.95), size, 0.14)
	_spark(at, Color(1.0, 0.72, 0.3), size * 0.75, 0.7)
	_spark(at, Color(1.0, 0.38, 0.12), size * 0.5, 1.1)
	_ring_fx(at, Color(1.0, 0.85, 0.6, 0.6), size * 0.12, 0.5, 3.5)
	for i in int(spec[1]):
		var d := Vector3(_rng.randfn(0, 1), _rng.randfn(0, 1), _rng.randfn(0, 1)).normalized()
		_spark_v(at + d * size * 0.08, d * _rng.randf_range(4.0, 16.0) * size * 0.06, Color(1.0, _rng.randf_range(0.45, 0.85), 0.2), _rng.randf_range(0.2, 0.42) * size, _rng.randf_range(0.6, 1.3))
	for i in int(spec[2]):
		var d2 := Vector3(_rng.randfn(0, 1), _rng.randfn(0, 1), _rng.randfn(0, 1)).normalized()
		_spark_v(at, d2 * _rng.randf_range(14.0, 40.0), Color(0.5, 0.5, 0.54), _rng.randf_range(0.6, 1.4), _rng.randf_range(0.8, 1.5))
	for k in int(spec[3]):
		blast_pending.append({"t": float(spec[4]) * (k + 1), "at": at + Vector3(_rng.randfn(0, 1), _rng.randfn(0, 1), _rng.randfn(0, 1)) * size * 0.14, "size": size * _rng.randf_range(0.3, 0.55)})

func _update_blasts(dt: float) -> void:
	for i in range(blast_pending.size() - 1, -1, -1):
		var q: Dictionary = blast_pending[i]
		q["t"] -= dt
		if q["t"] > 0.0: continue
		blast_pending.remove_at(i)
		var at: Vector3 = q["at"]
		_spark(at, Color(1.0, 0.95, 0.8), float(q["size"]), 0.12)
		_spark(at, Color(1.0, 0.55, 0.2), float(q["size"]) * 0.7, 0.6)
		var dd := at.distance_to(player.global_position)
		if dd < 1200.0: Sfx.play("explosion", -8.0 - dd / 90.0, _rng.randf_range(1.1, 1.5))

## The player's ship blows up: both sides and the core go, then the wreck is gone.
func _die() -> void:
	var p := player.global_position
	for side in ["l", "r"]: _blast(Sections.side_point(player_vis, side, model) if is_instance_valid(model) else p, Data.BLAST_WING, "wing_" + side)
	_blast(p, Data.BLAST_DEATH, "death")
	Sfx.play("explosion", 0.0, 0.7)
	hit_shake = 1.6
	player.visible = false
	lane_abort()
	fire_lock = false
	player_destroyed.emit()

## An enemy launches a homing missile at the player.
func enemy_fire_missile(e: Dictionary) -> void:
	var n: Node3D = e["node"]
	var sig_id: String = e.get("def", {}).get("signature", "")
	if Data.SIGNATURES.has(sig_id):
		_fire_signature(e, sig_id)
		return
	var mi := _missile_node(false)
	add_child(mi)
	mi.global_position = n.global_position - n.global_basis.y * 1.5 - n.global_basis.z * 4.0
	enemy_missiles.append({"node": mi, "vel": -n.global_basis.z * 80.0 + (e["vel"] as Vector3), "life": Data.ENEMY_MISSILE_LIFE, "lost": false,
		"wp": _rng.randf() * TAU, "wf": _rng.randf_range(Data.WEAVE_HZ[0], Data.WEAVE_HZ[1]), "wo": _rng.randf() * TAU})
	_trail_new(mi)
	if n.global_position.distance_to(player.global_position) < 700.0: Sfx.play("missile", -8.0, 0.8)
	message.emit("Missile incoming — boost sideways!")

# ---------------------------------------------------------------- Job N: signature attacks (Data.SIGNATURES)
## A flat hexagon ring (unit radius), shared by every hex spark, shard ring and lock-brand.
func _hex_ring() -> ArrayMesh:
	if _hex_mesh != null: return _hex_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 6:
		var a0 := TAU * i / 6.0
		var a1 := TAU * (i + 1) / 6.0
		var o0 := Vector3(cos(a0), sin(a0), 0)
		var o1 := Vector3(cos(a1), sin(a1), 0)
		for v in [o0, o1, o1 * 0.84, o0, o1 * 0.84, o0 * 0.84]: st.add_vertex(v)
	_hex_mesh = st.commit()
	return _hex_mesh

func _hex_node(col: Color, size: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _hex_ring()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.albedo_color = col
	mi.material_override = m
	mi.scale = Vector3.ONE * size
	return mi

## A hex outline that grows and fades (trail dots, the shard ring).
func _hex_fx(at: Vector3, col: Color, size: float, life: float, grow := 1.0) -> void:
	var mi := _hex_node(col, size)
	add_child(mi)
	mi.global_position = at
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * size * grow, life)
	tw.tween_property(mi.material_override, "albedo_color:a", 0.0, life)
	tw.chain().tween_callback(mi.queue_free)

func _fire_signature(e: Dictionary, sig_id: String) -> void:
	var sig: Dictionary = Data.SIGNATURES[sig_id]
	var n: Node3D = e["node"]
	var count: int = sig["volley"]
	for k in count:
		var dart := Node3D.new()
		var body := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = sig["dart_size"]
		body.mesh = bm
		body.material_override = ShipFactory.mat(sig["dart"])
		dart.add_child(body)
		var slit := MeshInstance3D.new()   # the crimson optic slit across the nose
		var sm := BoxMesh.new()
		sm.size = Vector3((sig["dart_size"] as Vector3).x * 1.08, (sig["dart_size"] as Vector3).y * 0.22, (sig["dart_size"] as Vector3).z * 0.3)
		slit.mesh = sm
		slit.position = Vector3(0, 0, -(sig["dart_size"] as Vector3).z * 0.3)
		slit.material_override = ShipFactory.mat(sig["slit"], true)
		dart.add_child(slit)
		add_child(dart)
		dart.global_position = n.global_position - n.global_basis.z * 5.0
		var a := (float(k) / float(maxi(1, count - 1)) - 0.5) * 2.0 if count > 1 else 0.0
		var fan: Vector3 = (n.global_basis.x * a + n.global_basis.y * (1.0 - absf(a)) * 0.5) * float(sig["fan"])
		enemy_missiles.append({"node": dart, "vel": -n.global_basis.z * 90.0 + (e["vel"] as Vector3) + fan, "life": float(sig["life"]), "lost": false,
			"sig": sig_id, "hex_t": 0.0, "kinked": false})
		sig_stats["darts"] += 1
	if n.global_position.distance_to(player.global_position) < 700.0: Sfx.play("missile", -6.0, 1.5)
	message.emit("%s has you locked — boost sideways!" % e["def"]["name"])

## Trail of a signature dart: a razor-red needle with dotted hex sparks; one kink when the lock hardens.
func _sig_trail(m: Dictionary, dt: float, dist: float) -> void:
	var sig: Dictionary = Data.SIGNATURES[m["sig"]]
	var n: Node3D = m["node"]
	var tail := n.global_position + n.global_basis.z * 1.6
	_spark_v(tail, n.global_basis.z * 4.0, sig["trail"], float(sig["trail_size"]), float(sig["trail_life"]))
	m["hex_t"] = float(m["hex_t"]) - dt
	if m["hex_t"] <= 0.0:
		m["hex_t"] = float(sig["hex_every"])
		_hex_fx(tail, sig["trail"], float(sig["hex_size"]), float(sig["hex_life"]), 1.6)
	if not m["kinked"] and not m["lost"] and dist < Data.DODGE_RANGE:
		m["kinked"] = true
		sig_stats["kinks"] += 1
		var side := (m["vel"] as Vector3).cross(Vector3.UP).normalized() * (1.0 if _rng.randf() < 0.5 else -1.0)
		m["vel"] = (m["vel"] as Vector3) + side * float(sig["kink"])
		_hex_fx(n.global_position, sig["trail"], float(sig["hex_size"]) * 2.2, float(sig["hex_life"]), 2.0)

## Impact: the punch now; the cyan-white bloom, red hex-shard ring and the lock-brand a moment later. No blood: grey debris.
func _sig_impact(at: Vector3, sig_id: String) -> void:
	var sig: Dictionary = Data.SIGNATURES[sig_id]
	sig_stats["impacts"] += 1
	at = player.global_position + (at - player.global_position).limit_length(float(sig["hull_reach"]))
	_spark(at, Color.WHITE, float(sig["punch_size"]), float(sig["punch_delay"]) + 0.05)
	Sfx.play("hull_hit", -4.0, 0.7)
	sig_pending.append({"t": float(sig["punch_delay"]), "sig": sig_id, "off": at - player.global_position})

func _update_signatures(dt: float) -> void:
	for i in range(sig_pending.size() - 1, -1, -1):
		var q: Dictionary = sig_pending[i]
		q["t"] -= dt
		if q["t"] > 0.0: continue
		sig_pending.remove_at(i)
		var sig: Dictionary = Data.SIGNATURES[q["sig"]]
		var at: Vector3 = player.global_position + (q["off"] as Vector3)
		sig_stats["blooms"] += 1
		_spark(at, sig["bloom"], float(sig["bloom_size"]), float(sig["bloom_life"]))
		_hex_fx(at, sig["ring"], float(sig["ring_size"]), float(sig["ring_life"]), float(sig["ring_grow"]))
		for k in int(sig["shards"]):
			var a := TAU * k / float(sig["shards"])
			var dir: Vector3 = cam.global_basis.x * cos(a) + cam.global_basis.y * sin(a)
			_spark_v(at + dir * 1.0, dir * float(sig["shard_speed"]), sig["ring"], 1.2, float(sig["ring_life"]))
		for k in int(sig["debris_count"]):
			_spark_v(at, Vector3(_rng.randfn(0, 9), _rng.randfn(0, 9), _rng.randfn(0, 9)), sig["debris"], 0.9, 0.9)
		Sfx.play("explosion", -7.0, 1.6)
		var brand := _hex_node(sig["ring"], float(sig["brand_size"]))   # rides on the hull where it hit
		player.add_child(brand)
		brand.global_position = at
		sig_brands.append({"node": brand, "life": float(sig["brand_life"]), "max": float(sig["brand_life"]), "sig": q["sig"]})
		sig_stats["brands"] += 1
	for i in range(sig_brands.size() - 1, -1, -1):
		var b: Dictionary = sig_brands[i]
		b["life"] -= dt
		var bn: MeshInstance3D = b["node"]
		if b["life"] <= 0.0 or not is_instance_valid(bn):
			if is_instance_valid(bn): bn.queue_free()
			sig_brands.remove_at(i)
			continue
		var sg: Dictionary = Data.SIGNATURES[b["sig"]]
		var k: float = float(b["life"]) / float(b["max"])
		var pulse := 0.5 + 0.5 * sin(time * TAU * float(sg["brand_pulse"]))
		bn.scale = Vector3.ONE * float(sg["brand_size"]) * (0.85 + 0.25 * pulse)
		(bn.material_override as StandardMaterial3D).albedo_color.a = k * (0.35 + 0.65 * pulse)

## Missiles homing on the player. Inside DODGE_RANGE a fast sideways move (a boost across its path, or an
## engine-kill slide after one) breaks the lock and the missile flies on straight.
func _update_enemy_missiles(dt: float) -> void:
	missile_warn = -1.0
	_update_signatures(dt)
	for i in range(enemy_missiles.size() - 1, -1, -1):
		var m: Dictionary = enemy_missiles[i]
		var n: Node3D = m["node"]
		var v: Vector3 = m["vel"]
		var rel := player.global_position - n.global_position
		var dist := rel.length()
		var done := false
		if not m["lost"] and controls:
			var sg: Dictionary = Data.SIGNATURES.get(m.get("sig", ""), {})
			v = v.lerp(rel.normalized() * float(sg.get("speed", Data.ENEMY_MISSILE_SPEED)), minf(1.0, dt * float(sg.get("turn", Data.ENEMY_MISSILE_TURN))))
			if dist < Data.DODGE_RANGE and side_speed(vel, rel) > Data.DODGE_SIDE_FRAC * float(GS.ship()["speed"]):
				m["lost"] = true
				missiles_evaded += 1
				message.emit("Missile evaded!")
			else:
				if missile_warn < 0.0 or dist < missile_warn: missile_warn = dist
				if dist < Data.ENEMY_MISSILE_HIT:
					if sg.is_empty():
						_player_hit(Data.ENEMY_MISSILE_DAMAGE, n.global_position)
						_spark(n.global_position, Color(1, 0.6, 0.2), 8.0)
						Sfx.play("explosion", -8.0, 1.3)
					else:
						_player_hit(float(sg["damage"]), n.global_position)
						_sig_impact(n.global_position, m["sig"])
					done = true
		m["vel"] = v
		var wv := Vector3.ZERO if m["lost"] else weave(m, v, dist, dt)
		n.global_position += (v + wv) * dt
		if v.length() > 0.1: n.look_at(n.global_position + v + wv, Vector3.UP)
		m["life"] -= dt
		if m.has("sig"):
			m["vel"] = v
			_sig_trail(m, dt, dist)
		else: _missile_trail(n)
		if not done:   # v1.5o DECOY: one of your mines in its path: it detonates on the mine (the mine goes too)
			for mn in mines_live:
				if is_instance_valid(mn["node"]) and (mn["node"] as Node3D).global_position.distance_to(n.global_position) < Data.DECOY_RADIUS:
					_explode((mn["node"] as Node3D).global_position)
					(mn["node"] as Node3D).queue_free()
					mines_live.erase(mn)
					decoyed += 1
					_popup(n.global_position, "DECOYED", Color(0.6, 0.9, 1.0))
					done = true
					break
		if not done and m["life"] <= 0.0 and Data.MISSILE_EXPIRE_BLAST: _expire_burst(n.global_position)
		if done or m["life"] <= 0.0:
			n.queue_free()
			enemy_missiles.remove_at(i)

func _update_missiles(dt: float) -> void:
	_update_enemy_missiles(dt)
	for i in range(volley_queue.size() - 1, -1, -1):
		var q: Dictionary = volley_queue[i]
		q["t"] -= dt
		if q["t"] <= 0.0:
			volley_queue.remove_at(i)
			var qt = q["target"]
			if controls and is_instance_valid(qt): fire_missile(q["heavy"], q["k"], q["n"], q["scale"], qt)
	for i in range(missiles_live.size() - 1, -1, -1):
		var m: Dictionary = missiles_live[i]
		var n: Node3D = m["node"]
		var tv = m["target"]
		var t: Node3D = tv if is_instance_valid(tv) else null
		if t != null and t.get_meta("kind", "") != "enemy": t = null   # (a wreck is no target)
		if t == null and not m.get("shaken", false):
			# v1.4m: its target is gone: the missile goes after the nearest hostile it can reach
			var nb: Node3D = null
			var nd: float = Data.MISSILE_RETARGET
			for oe in enemies:
				var od: float = (oe["node"] as Node3D).global_position.distance_to((m["node"] as Node3D).global_position)
				if od < nd:
					nd = od
					nb = oe["node"]
			if nb != null:
				t = nb
				m["target"] = nb
				retargets += 1
		var v: Vector3 = m["vel"]
		if is_instance_valid(t):
			var rel := t.global_position - n.global_position
			v = v.lerp(rel.normalized() * Data.MISSILE_SPEED, minf(1.0, dt * Data.MISSILE_TURN * (Data.SPECIAL_SWARM_TURN if m.get("special", false) else 1.0)))
			var te := _enemy_entry(t)
			if not te.is_empty():
				# the enemy may try a side-boost as the missile closes in; moving sideways fast enough shakes it off
				if rel.length() < Data.DODGE_RANGE and not m.get("rolled", false):
					m["rolled"] = true
					if float(te.get("dodge_t", 0.0)) <= 0.0 and _rng.randf() < enemy_dodge_chance * (Data.SPECIAL_SWARM_DODGE if m.get("special", false) else 1.0):
						var sd := v.cross(Vector3.UP).normalized() * (1.0 if _rng.randf() < 0.5 else -1.0)
						te["dodge_t"] = Data.ENEMY_DODGE_TIME
						te["dodge_dir"] = sd if sd.length() > 0.5 else Vector3.RIGHT
				# v1.7u (owner): no shaking it off; a swerve can still make it overshoot, and the fuse decides
		m["vel"] = v
		var wv2 := weave(m, v, n.global_position.distance_to(t.global_position), dt) if is_instance_valid(t) else Vector3.ZERO
		n.global_position += (v + wv2) * dt
		if v.length() > 0.1: n.look_at(n.global_position + v + wv2, Vector3.UP)
		m["life"] -= dt
		_missile_trail(n)
		var done: bool = m["life"] <= 0.0
		var rbm := _ray_blocks(n.global_position - (v + wv2) * dt, n.global_position) if surface_mode else [null, Vector3.INF]
		var bfm: BlockField = rbm[0]
		var dig: Vector3 = rbm[1]
		if not is_instance_valid(t):   # v1.8b: a free-fired missile goes off on any enemy it passes close to
			for oe in enemies:
				if (oe["node"] as Node3D).global_position.distance_to(n.global_position) < (Data.HEAVY_MISSILE_HIT_RADIUS if m.get("heavy", false) else Data.MISSILE_HIT_RADIUS):
					t = oe["node"]
					break
		var ahm: Array = ray_asteroids(n.global_position - (v + wv2) * dt, n.global_position) if not surface_mode and dig == Vector3.INF else []
		if not ahm.is_empty():   # v1.7x: a missile that meets an asteroid blows a hole in it
			blast_asteroid(ahm[0], ahm[2], "heavy" if m.get("heavy", false) else "missile")
			missile_blast(ahm[2], m, null)
			_spark(ahm[2], Color(1, 0.6, 0.2), 10.0)
			done = true
		elif dig != Vector3.INF:   # EXPERIMENT (v1.5t): a missile that meets the block ground blows a crater
			_blast_blocks(dig, "heavy" if m.get("heavy", false) else "missile", bfm)
			_blast(dig, Data.BLAST_ENEMY if m.get("heavy", false) else Data.BLAST_WING, "ground")
			done = true
		elif is_instance_valid(t) and n.global_position.distance_to(t.global_position) < (Data.HEAVY_MISSILE_HIT_RADIUS if m.get("heavy", false) else Data.MISSILE_HIT_RADIUS):
			var e := _enemy_entry(t)
			if not e.is_empty():
				_damage_enemy(e, missile_damage(e, m.get("heavy", false), float(m.get("scale", 1.0))))
			if m.get("heavy", false): _blast(n.global_position, Data.BLAST_HEAVY_MISSILE, "heavy_missile")   # v1.5w: the super missile's big explosion
			else: _spark(n.global_position, Color(1, 0.6, 0.2), 8.0)
			missile_blast(n.global_position, m, t)
			done = true
		elif done and Data.MISSILE_EXPIRE_BLAST:   # v1.5o: out of life: it self-destructs in a round burst (the missile-trail sky)
			_expire_burst(n.global_position)
			missile_blast(n.global_position, m, null)   # v1.7u: the fuse ran out: it blows where it is
			missiles_expired += 1
		if done:
			n.queue_free()
			missiles_live.remove_at(i)

## Heavy: hits hard (at least HEAVY_MISSILE_HULL_FRAC of the hull). Light: MISSILE_DAMAGE or 30 % of the hull,
## times the rack's damage share (a swarm missile is lighter).
func missile_damage(e: Dictionary, heavy: bool, scale := 1.0) -> float:
	if (e.get("def", {}) as Dictionary).get("capital", false): return Data.CAPITAL_MISSILE_DAMAGE * (Data.HEAVY_MISSILE_MULT if heavy else scale)   # v1.9n: set damage on a capital ship
	var full := maxf(Data.MISSILE_DAMAGE, float(e["max"]) * Data.LIGHT_MISSILE_HULL_FRAC)
	if heavy: return maxf(maxf(Data.HEAVY_MISSILE_DAMAGE, float(e["max"]) * Data.HEAVY_MISSILE_HULL_FRAC), full * Data.HEAVY_MISSILE_MULT)   # v1.5x: = 3.5 regular missiles
	return full * scale

func _enemy_entry(n: Node3D) -> Dictionary:
	for e in enemies:
		if e["node"] == n: return e
	return {}

## Shields soak damage first. What gets through hits the section under the hit point: a wing/arm if the shot
## landed on that side (and it is still there), otherwise the core. Missiles and mines (no hit point) hit the core.
func _damage_enemy(e: Dictionary, dmg: float, hit := Vector3.INF, sf := -1.0) -> void:
	e["aggro"] = true
	e["provoked"] = true
	e["sh_cd"] = 4.0
	var at: Vector3 = e["node"].global_position if hit == Vector3.INF else hit
	var had_shield := float(e["sh"]) > 0.0
	var to_shield := minf(dmg, float(e["sh"]))
	var to_hull := dmg - to_shield
	if sf >= 0.0:   # v1.9u: a Nexus blaster: its shield share hits the shield (lost once it is down), the rest goes straight to the hull
		to_shield = minf(dmg * sf, float(e["sh"]))
		to_hull = dmg * (1.0 - sf)
	e["sh"] = float(e["sh"]) - to_shield
	if e.has("pilot"): _generic_hit(e, had_shield, to_hull)
	if to_shield > 0.0:
		_spark(at, Color(0.4, 0.8, 1.0), 9.0, 0.22)   # shield flare
		_popup(at, "-%d" % roundi(to_shield), Color(0.45, 0.85, 1.0))
		Sfx.play("shield_hit", -14.0, 1.2)
	if to_hull <= 0.0: return
	var side := "core"
	if hit != Vector3.INF: side = Sections.side_of_hit(e["vis"], e["node"], hit, 7.5)
	if side != "core" and float(e[side]) > 0.0:
		e[side] = float(e[side]) - to_hull
		_spark(at, Color(1.0, 0.6, 0.25), 3.5, 0.3)
		_popup(at + Vector3(0, 2, 0), "-%d" % roundi(to_hull), Color(1.0, 0.75, 0.3))
		Sfx.play("hull_hit", -12.0, 1.3)
		if float(e[side]) <= 0.0: _break_section(e, side)
		return
	e["hp"] -= to_hull
	_spark(at, Color(1.0, 0.6, 0.25), 3.5, 0.3)
	_popup(at + Vector3(0, 2, 0), "-%d" % roundi(to_hull), Color(1.0, 0.62, 0.3))
	Sfx.play("hull_hit", -12.0, 1.3)
	if e["hp"] <= 0.0: _destroy_unit(e)

## Generic pilot reactions to being hit. Hull effects (state latch, critical, retreat) are checked once this hit
## has been applied (deferred to the end of the frame).
func _generic_hit(e: Dictionary, had_shield: bool, to_hull: float) -> void:
	if not e.get("hit_said", false):
		e["hit_said"] = true
		_chatter(e, "taking_fire")
	elif had_shield and float(e["sh"]) <= 0.0 and float(e["sh_max"]) > 0.0 and not e.get("sh_said", false):
		e["sh_said"] = true
		_chatter(e, "shields_failing")
	if to_hull > 0.0: _after_hull_hit.call_deferred(e)

func _after_hull_hit(e: Dictionary) -> void:
	if not enemies.has(e): return
	_update_pilot_state(e)
	if unit_health(e) <= 0.25 and not e.get("crit_said", false):
		e["crit_said"] = true
		# alone and badly hurt: falls back for a few seconds; otherwise just calls it in
		if not enemies.any(func(o): return o != e and o.get("group", -1) == e.get("group", -2)):
			e["retreat"] = 6.0
			_chatter(e, "retreat", true)
		else: _chatter(e, "critical_damage", true)

## A wing or arm reaches zero: one sharp explosion at that side, the part vanishes, its weapon stops.
func _break_section(e: Dictionary, side: String) -> void:
	e[side] = 0.0
	if e.has("pilot"):
		_update_pilot_state(e)
		_chatter(e, "arm_damaged" if e["mech"] else "wing_damaged", true)
	var model: Node3D = e["model"]
	var p := Sections.side_point(e["vis"], side, model)
	var dd := p.distance_to(player.global_position)
	if dd < 1500.0: Sfx.play("explosion", -6.0 - dd / 90.0, 1.35)
	_spark(p, Color(1.0, 0.95, 0.8), 16.0, 0.25)       # flash
	_spark(p, Color(1.0, 0.55, 0.2), 11.0, 0.6)        # fireball
	_spark_v(p, Vector3(_rng.randfn(0, 3), 4, _rng.randfn(0, 3)), Color(0.45, 0.45, 0.5), 9.0, 1.0)  # smoke puff
	Sections.set_side_visible(e["vis"], side, false)
	e["spark_" + side] = _rng.randf_range(3.0, 5.0)
	var part := ("LEFT " if side == "l" else "RIGHT ") + ("ARM" if e["mech"] else "WING")
	_popup(p + Vector3(0, 4, 0), part + " DOWN", Color(1.0, 0.85, 0.3))
	if e["node"] == target: message.emit("%s %s destroyed — that weapon is offline." % [e["node"].name, part.to_lower()])

## Core reaches zero: a much bigger blast, then the unit shrinks away inside the flash and is removed.
func _destroy_unit(e: Dictionary) -> void:
	var n: Node3D = e["node"]
	_explode(n.global_position)
	_spark(n.global_position, Color(1.0, 0.95, 0.85), 40.0, 0.35)
	enemies.erase(e)
	# the wing reacts: the leader went down, or a wingmate did
	var mates: Array = enemies.filter(func(o): return o.get("group", -1) == e.get("group", -2) and o.has("pilot"))
	if not mates.is_empty():
		_chatter(mates[0], "regroup" if e.has("pilot") else "leader_down", not e.has("pilot"))
	var reward: int = e["def"]["reward"]
	_drop_loot(n.global_position, reward)
	enemy_killed.emit(reward, n.name)
	if e.has("faction"):   # v1.4r: their faction remembers; its rival approves
		Factions.adjust(e["faction"], -Data.REP_KILL * float(e.get("rank", 1)))
		var pl: Dictionary = e.get("pilot", {})
		if pl.get("named_unique", false) and not e.has("bounty"):
			_named_down[pl["character_id"]] = true   # a named pilot is not gone for good: they break off and turn up again later
			GS.cast_state(pl["character_id"])["current_system"] = ""
			message.emit("%s's fighter is finished. %s got away." % [pl["name"], {"female": "She", "male": "He"}.get(str(pl["sex"]), "It")])   # (v1.4z: a machine is "it")
	if e.has("bounty") and not Missions.wants_dead(e["bounty"]): _drop_pilot(n.global_position, e["bounty"])   # (after the kill line, so "TRACTOR the pilot in" is what stays on screen; v1.5f: wanted dead = no pod)
	Missions.on_kill(self, e)   # v1.5f: a bounty wanted dead is paid here
	if target == n: target = null
	n.set_meta("kind", "wreck")
	var tw := n.create_tween()
	tw.tween_property(n, "scale", Vector3.ONE * 0.05, 0.35).set_ease(Tween.EASE_IN)
	tw.tween_callback(n.queue_free)

func _popup(at: Vector3, txt: String, col: Color) -> void:
	popups.append({"pos": at + Vector3(_rng.randf_range(-2, 2), 4, 0), "text": txt, "col": col, "life": 0.9})
	if popups.size() > 24: popups.pop_front()

func _player_hit(dmg: float, hit := Vector3.INF) -> void:
	if GS.form == "mech": dmg *= 1.0 - GS.mech_armor()   # v1.9i: the core's armour
	Sfx.play("shield_hit" if GS.shield > 0.0 else "hull_hit", -6.0)
	shield_delay = 3.0
	hit_shake = 1.0
	var side := "core"
	if hit != Vector3.INF: side = Sections.side_of_hit(player_vis, player, hit, 5.0)
	var broke := GS.damage(dmg, side)
	if broke != "":
		var p := Sections.side_point(player_vis, broke, model)
		Sfx.play("explosion", -2.0, 1.2)
		_blast(p, Data.BLAST_WING, "wing_" + broke)   # v1.4l: the wing goes up properly
		Sections.set_side_visible(player_vis, broke, false)
		message.emit("%s wing destroyed — its guns are offline. Dock for repairs." % ("Left" if broke == "l" else "Right"))
	if warp_state != "off": drop_warp("Warp drive disrupted by weapons fire!")
	if GS.hull <= 0.0 and controls:
		_explode(player.global_position)
		controls = false
		_die()

func _update_enemies(dt: float) -> void:
	var ppos := player.global_position
	if warp_state != "charging": _warp_spotted = false
	_laser_sfx_cd -= dt
	for pu in popups:
		pu["life"] -= dt
		pu["pos"] += Vector3(0, 9.0 * dt, 0)
	popups = popups.filter(func(pu): return pu["life"] > 0.0)
	for e in enemies:
		var n: Node3D = e["node"]
		var d: Dictionary = e["def"]
		e["sh_cd"] = float(e["sh_cd"]) - dt
		if e["sh_cd"] <= 0.0: e["sh"] = minf(float(e["sh_max"]), float(e["sh"]) + float(e["sh_max"]) * (0.15 if not d.get("capital", false) else 0.02) * dt)
		if d.get("capital", false):   # v1.9n: a capital ship: slow, turrets all round
			_update_capital(e, dt)
			continue
		var tpos := ppos   # v1.9n: who it is fighting: you, or one of your allies when one is nearer
		var tvel := vel
		var fa: Dictionary = _enemy_foe(e, dt)
		if not fa.is_empty():
			tpos = fa["node"].global_position
			tvel = fa["vel"]
		var to := tpos - n.global_position
		var dist := to.length()
		var was: bool = e["aggro"]
		var spotting := warp_state == "charging" and dist < 1600.0   # they see the warp charge and come to stop you
		# v1.4r: a faction you are on speaking terms with (yellow or better) leaves you alone until you shoot at it
		var peaceful: bool = e.has("faction") and not e.get("provoked", false) and not Factions.hostile(e["faction"])
		if e.has("faction"): n.set_meta("kind", "patrol" if peaceful else "enemy")   # v1.4w: a peaceful faction ship is not a hostile contact
		if peaceful: e["aggro"] = false
		elif dist < 650.0 or e["aggro"] or spotting: e["aggro"] = dist < (1600.0 if spotting else 1400.0)
		if e.get("invasion", false): e["aggro"] = true   # v1.9n: an invasion fights whoever is there
		if e.has("pilot"):
			# generic pilots chatter instead of hailing; named leaders keep the full hail below
			if e["aggro"] and not was and warp_state != "on": _chatter(e, "target_acquired")
			if spotting and not _warp_spotted and _chatter(e, "enemy_warp", true): _warp_spotted = true
			e["retreat"] = maxf(0.0, float(e.get("retreat", 0.0)) - dt)
		elif e["aggro"] and not was and call_cd <= 0.0 and controls and warp_state != "on":
			call_cd = 30.0
			if n.has_meta("pilot"): enemy_hail.emit(n.get_meta("pilot"))
			else: hail.emit("%s pilot" % d["name"], TAUNTS[_rng.randi() % TAUNTS.size()], true)
		var goal: Vector3
		if float(e.get("retreat", 0.0)) > 0.0:
			goal = n.global_position - to.normalized() * 400.0 + Vector3(0, 60, 0)   # falling back
		elif e["aggro"] and controls:
			# attack run: approach, then peel off to the side and come back around
			var side: Vector3 = player.global_basis.x * float(e["strafe"]) * 90.0
			goal = tpos + side if dist > 140.0 else n.global_position - to.normalized() * 200.0 + side
		else:
			e["orbit"] += dt * 0.25
			goal = e["home"] + Vector3(cos(e["orbit"]) * 120.0, sin(e["orbit"] * 0.7) * 25.0, sin(e["orbit"]) * 120.0)
		var walker: bool = e.get("walker", false)   # v1.8n: a mech on foot: it stays on the ground and only turns left / right
		if walker:
			goal = (ppos if e["aggro"] and controls and dist > Data.WALKER_HOLD else (n.global_position if e["aggro"] else goal))
			goal.y = n.global_position.y
		var fwd := -n.global_basis.z
		var want := (goal - n.global_position).normalized()
		if walker and want.length() < 0.5: want = Vector3(to.x, 0, to.z).normalized()   # holding its ground: it keeps facing you
		var new_fwd := fwd.slerp(want, minf(1.0, dt * float(d["turn"]))) if want.length() > 0.5 else fwd
		if walker: new_fwd.y = 0.0
		if new_fwd.length() > 0.01:
			n.look_at(n.global_position + new_fwd, Vector3.UP)
		var sp: float = d["speed"] * (1.0 if e["aggro"] else 0.5) * (1.4 if warp_state == "charging" else 1.0)
		if walker: sp = float(d["speed"]) * Data.WALKER_SPEED * (0.0 if e["aggro"] and dist <= Data.WALKER_HOLD else 1.0) * clampf((-n.global_basis.z).dot(want) * 2.0 - 0.6, 0.0, 1.0)   # it turns on the spot first, then walks the way it faces
		e["vel"] = (e["vel"] as Vector3).lerp(-n.global_basis.z * sp, minf(1.0, dt * 1.5))
		if float(e.get("dodge_t", 0.0)) > 0.0:   # Job M: side-boost out of a missile's path
			e["dodge_t"] = float(e["dodge_t"]) - dt
			e["vel"] = (e["dodge_dir"] as Vector3) * float(d["speed"]) * Data.ENEMY_DODGE_BOOST
		if float(e.get("stuck_t", 0.0)) > 0.0:   # v1.5x: a magnetic mine has it: dragged in to the blast point and held there
			e["stuck_t"] = float(e["stuck_t"]) - dt
			e["vel"] = ((e["stuck_at"] as Vector3) - n.global_position) * Data.MAG_MINE_PULL
		if walker and _sea_at(n.global_position.x + e["vel"].x * dt * 8.0, n.global_position.z + e["vel"].z * dt * 8.0) and not _sea_at(n.global_position.x, n.global_position.z): e["vel"] = Vector3.ZERO   # it does not walk into the sea
		n.global_position += e["vel"] * dt
		if walker and surface_mode: n.global_position.y = _ground(n.global_position.x, n.global_position.z) + Data.WALKER_STAND * float(e.get("stand_k", 1.0))   # (v1.9i: a boss stands taller)
		if d.get("missiles", false) and e["aggro"] and controls and warp_state != "on" and dist < Data.ENEMY_MISSILE_RANGE:
			if not e.has("mcd"): e["mcd"] = _rng.randf_range(Data.ENEMY_MISSILE_EVERY[0], Data.ENEMY_MISSILE_EVERY[1]) * 0.5
			e["mcd"] = float(e["mcd"]) - dt
			if e["mcd"] <= 0.0 and (-n.global_basis.z).dot(to.normalized()) > 0.5:
				e["mcd"] = _rng.randf_range(Data.ENEMY_MISSILE_EVERY[0], Data.ENEMY_MISSILE_EVERY[1])
				enemy_fire_missile(e)
		# shooting
		e["cd"] -= dt
		e["core_cd"] -= dt
		var facing: bool = (-n.global_basis.z).dot(to.normalized()) > cos(deg_to_rad(12.0))
		if walker: facing = (-n.global_basis.z).dot(Vector3(to.x, 0, to.z).normalized()) > cos(deg_to_rad(14.0))   # it aims its guns up; only the body has to face you
		if e["aggro"] and controls and dist < 420.0 and facing:
			var lead := tpos + tvel * (dist / 300.0)
			var guns := unit_guns(e)
			if e["cd"] <= 0.0 and not guns.is_empty():
				# alternate between the arm/wing guns that are still attached
				e["cd"] = 1.0 / float(d["rate"]) * (2.0 / guns.size())
				e["gun"] = (int(e["gun"]) + 1) % guns.size()
				var sx := -1.0 if guns[e["gun"]] == "l" else 1.0
				var from: Vector3 = n.global_position + n.global_basis.x * sx * 3.0 - n.global_basis.z * 5.0
				var jitter := Vector3(_rng.randfn(0, 4), _rng.randfn(0, 4), _rng.randfn(0, 4))
				_spawn_bolt(from, (lead + jitter - from).normalized() * 300.0, d["damage"], Color(1.0, 0.35, 0.25), "enemy", 1.6)
				if dist < 450.0: Sfx.play("laser_enemy", -12.0 - dist / 60.0)
			if e["mech"] and e["core_cd"] <= 0.0:
				# chest cannon: slower, heavier, keeps working when both arms are gone
				e["core_cd"] = 2.6
				var cf: Vector3 = n.global_position + n.global_basis.y * 2.0 - n.global_basis.z * 5.0
				_spawn_bolt(cf, (lead - cf).normalized() * 260.0, float(d["damage"]) * 1.8, Color(1.0, 0.6, 0.2), "enemy", 1.8)
				if dist < 450.0: Sfx.play("laser_enemy", -9.0 - dist / 60.0, 0.7)
		_unit_fx(e, dt, dist)

## Cheap after-effects: a destroyed side gives one tiny spark (and a wisp of smoke) every 3–5 s, only near the
## player. Mechs lean into their flight and swing their arms back with speed.
func _unit_fx(e: Dictionary, dt: float, dist: float) -> void:
	if dist > 1400.0: return
	var n: Node3D = e["node"]
	for side in ["l", "r"]:
		if float(e[side]) > 0.0: continue
		e["spark_" + side] = float(e["spark_" + side]) - dt
		if e["spark_" + side] <= 0.0:
			e["spark_" + side] = _rng.randf_range(3.0, 5.0)
			e["sparks"] = int(e["sparks"]) + 1
			var p := Sections.side_point(e["vis"], side, e["model"])
			_spark_v(p, Vector3(_rng.randfn(0, 6), _rng.randfn(0, 6), _rng.randfn(0, 6)), Color(1.0, 0.85, 0.5), 2.2, 0.16)
			if _rng.randf() < 0.5: _spark_v(p, Vector3(0, 2.5, 0), Color(0.4, 0.4, 0.45), 3.5, 0.6)
	if e["mech"]:
		var model: Node3D = e["model"]
		var sp: float = (e["vel"] as Vector3).length() / maxf(1.0, float(e["def"]["speed"]))
		if e.get("walker", false):   # v1.8n: on foot: upright, arms up to fire, legs striding with its speed
			model.rotation.x = lerpf(model.rotation.x, 0.0, minf(1.0, dt * 2.0))
			model.rotation.z = lerpf(model.rotation.z, 0.0, minf(1.0, dt * 2.0))
			Sections.pose_mech(e["vis"], -35.0 if e["aggro"] else 0.0, dt)
			Sections.stride(e["vis"], sin(time * Data.WALKER_STRIDE_RATE) * Data.WALKER_STRIDE_DEG * clampf(sp / Data.WALKER_SPEED, 0.0, 1.0))
			return
		# forward flight posture + arms back with speed; lean into turns
		var fwd := -n.global_basis.z
		var turn: float = (e["prev_fwd"] as Vector3).cross(fwd).y / maxf(dt, 0.001)
		e["prev_fwd"] = fwd
		model.rotation.x = lerpf(model.rotation.x, -deg_to_rad(10.0 + 12.0 * sp), minf(1.0, dt * 2.0))
		model.rotation.z = lerpf(model.rotation.z, clampf(-turn * 0.6, -0.35, 0.35), minf(1.0, dt * 2.0))
		Sections.pose_mech(e["vis"], 10.0 + 25.0 * sp, dt)

func _update_traffic(dt: float) -> void:
	var a := dock_point(station)
	var b := dock_point(planet)
	for t in traffic:
		t["t"] += dt * 0.012 * t["dir"]
		if t["t"] > 1.0 or t["t"] < 0.0:
			t["dir"] *= -1.0
			t["t"] = clampf(t["t"], 0.0, 1.0)
		var n: Node3D = t["node"]
		var p := a.lerp(b, t["t"]) + Vector3(0, 40.0 + 30.0 * t["dir"], 0)
		var dir: Vector3 = (b - a).normalized() * float(t["dir"])
		n.global_position = p
		n.look_at(p + dir, Vector3.UP)

# ---------------------------------------------------------------- Job L: collision damage
var collide_grace := 0.0        # s left in the grace window after a damaging hit
var last_collision := {}        # {kind, impact, dmg, k} of the latest damaging hit (HUD / tests)
const COLLIDE_MSG := {"asteroid": "Collision alert: asteroid impact.", "ground": "Terrain impact! Pull up.",
	"building": "Collision: structure impact!", "station": "Collision: station hull impact!"}

## The ship hit something solid (asteroid, ground, building, station) at `impact` m/s into its surface.
## Below the threshold, or inside the grace window, nothing happens. Otherwise hull damage scaled by speed, hit
## feedback scaled by how hard, and the normal destruction flow at zero hull. Returns the hull taken.
func collision_damage(kind: String, impact: float, at := Vector3.INF) -> float:
	if kind == "ground" and surface_mode and _over_blocks():   # EXPERIMENT (v1.5u): bumping the block ground
		if GS.form == "mech" or braking or impact <= Data.BLOCK_SAFE_BUMP: return 0.0
		impact -= Data.BLOCK_SAFE_BUMP - Data.COLLIDE_THRESHOLD   # only the speed past cruise counts
	if impact <= Data.COLLIDE_THRESHOLD or not controls or collide_grace > 0.0: return 0.0
	var dmg := (impact - Data.COLLIDE_THRESHOLD) * Data.COLLIDE_MULT
	collide_grace = Data.COLLIDE_GRACE
	var dealt := GS.collide(dmg)
	var k := clampf(dmg / maxf(GS.max_hull() * Data.COLLIDE_FX_FULL, 1.0), 0.0, 1.0)
	hit_shake = maxf(hit_shake, lerpf(Data.COLLIDE_SHAKE_MIN, 1.0, k))
	Sfx.play("hull_hit", lerpf(Data.COLLIDE_SFX_DB_SOFT, Data.COLLIDE_SFX_DB_HARD, k))
	_spark(at if at != Vector3.INF else player.global_position, Color(1, 0.8, 0.5), 3.0 + 6.0 * k)
	last_collision = {"kind": kind, "impact": impact, "dmg": dmg, "k": k}
	collided.emit(kind, dmg, k)
	message.emit(COLLIDE_MSG.get(kind, "Collision!"))
	if warp_state != "off": drop_warp("Collision — warp drive disrupted!")
	if GS.hull <= 0.0 and controls:
		GS.hull = 0.0
		_explode(player.global_position)
		controls = false
		_die()
	return dealt

func _collisions(dt: float) -> void:
	if not lane.is_empty(): return   # nothing is solid while the lane carries you
	collide_grace = maxf(0.0, collide_grace - dt)
	var p := player.global_position
	in_belt = in_belt_region(p)
	if in_belt and not asteroids.is_empty():   # v1.7x: bump off the blocks themselves
		for ast in asteroids:
			if p.distance_to(ast.global_position) > float(ast.radius) + 4.0: continue
			var push: Vector3 = ast.push_out(p, 3.5)
			if push == Vector3.ZERO: continue
			var nrm := push.normalized()
			player.global_position += push
			collision_damage("asteroid", vel.dot(-nrm), player.global_position - nrm * 3.5)
			vel = vel - nrm * vel.dot(nrm) * 1.6
			p = player.global_position
	elif in_belt:
		for r in rocks:
			var d: float = p.distance_to(r[0])
			var rr: float = r[1] + 3.5
			if d < rr:
				var n: Vector3 = (p - r[0]).normalized()
				player.global_position = r[0] + n * rr
				collision_damage("asteroid", vel.dot(-n), player.global_position - n * 3.5)   # Job L
				vel = vel - n * vel.dot(n) * 1.6
	var solid: Array = [station, planet]
	solid.append_array(extras)        # placeholder planets and stations are solid too
	for body: Node3D in solid:
		if surface_mode: break
		var rad: float = body.get_meta("radius")
		var hitr := rad + (6.0 if body == planet else 10.0)
		var d2 := player.global_position.distance_to(body.global_position)
		if body == planet:
			# warp near a planet is deadly: warn inside 1.8x the outer atmosphere, destroy at the atmosphere line
			var outer := rad * Data.ATMO_OUTER
			planet_hazard = 0
			if warp_state == "on" and d2 < outer * 1.8:
				planet_hazard = 1
				if d2 < outer and controls:
					planet_hazard = 2
					message.emit("Warp impact with planetary mass!")
					_explode(player.global_position)
					_spark(player.global_position, Color(1, 1, 1), 60.0, 0.6)
					controls = false
					drop_warp()
					_die()
					continue
		if body != planet and body != station and Surface.has_surface(str(body.get_meta("info").get("id", ""))):
			# v1.4l: every catalog planet has a surface too. Fly into it (not at warp) to go down.
			if d2 < rad * Data.ATMO_INNER + 10.0 and controls and not entering and warp_state == "off":
				entering = true
				message.emit("Entering the atmosphere of %s." % body.name)
				atmosphere_entered.emit(body)
			continue
		if body == planet and Surface.has_surface(planet.get_meta("info")["id"]):
			# planets with a surface are not solid. Outer atmosphere: haze, glow, rumble and the planet pack starts
			# coming. Inner entry sphere (forgiving, any direction): commits to the surface.
			var outer2 := rad * Data.ATMO_OUTER
			var inner := rad * Data.ATMO_INNER
			atmo_depth = clampf((outer2 - d2) / (outer2 - inner), 0.0, 1.0) if warp_state == "off" else 0.0
			if atmo_depth > 0.0: atmo_color = _sky_color_of(body)
			if atmo_depth > 0.0:
				Packs.request("planets")
				if not _atmo_rumbled:
					_atmo_rumbled = true
					Sfx.play("atmo", -10.0, 0.8)
					message.emit("Entering upper atmosphere of %s." % planet.name)
				hit_shake = maxf(hit_shake, atmo_depth * 0.18)
			elif d2 > outer2 * 1.1: _atmo_rumbled = false
			if d2 < inner and controls and not entering and warp_state == "off":
				entering = true
				atmosphere_entered.emit(planet)
			continue
		if body.has_meta("box_aabb") and is_instance_valid(body.get_meta("box_holder", null)):   # v1.9q: the model's own box
			_bump_box(body)
			continue
		if d2 < hitr:
			var n2 := (player.global_position - body.global_position).normalized()
			player.global_position = body.global_position + n2 * hitr
			collision_damage("station" if (body == station or not body.get_meta("info", {}).has("palette")) else "ground", -vel.dot(n2))   # Job L (a planet without a surface is ground)
			vel = vel - n2 * vel.dot(n2) * 1.5
	_nebula_depth(p)   # v1.9s: every cloud in the system

var look := Vector2.ZERO   # cockpit free-look (-1..1): the pilot's head turns toward where you steer
const LOOK_YAW := 0.5      # radians at full look left/right
const LOOK_PITCH := 0.22   # radians at full look up/down (less: you shouldn't see past the canopy art)

func _update_camera(dt: float, snap: bool) -> void:
	_sync_fpv(dt)
	_sync_hand_gun()
	if GS.view == "cockpit" and GS.form == "mech" and is_instance_valid(player):   # v1.7z: out of the mech's head, rifle in hand
		var mb := player.global_basis
		cam.global_position = player.global_position + mb * Data.FPV_EYE
		var ahead2 := cam.global_position - mb.z * 80.0
		if hit_shake > 0.0: ahead2 += Vector3(_rng.randfn(0, 1), _rng.randfn(0, 1), 0) * hit_shake * 1.2
		cam.look_at(ahead2, mb.y)
		cam.fov = lerpf(cam.fov, Data.FPV_ZOOM_FOV if zoomed else Data.FPV_FOV, minf(1.0, dt * 8.0) if not snap else 1.0)
		return
	if GS.view == "cockpit":
		# pilot's eye: fixed to the hull, tiny lag-free shake on hits. The head turns with the aim stick (free-look),
		# so you can look out of the side and top glass; the crosshair shows where the nose really points.
		look = look.lerp(aim if controls else Vector2.ZERO, minf(1.0, dt * 3.0))
		cam.global_position = player.global_position + player.global_basis * Vector3(0, 0.9, -1.2)
		var b := player.global_basis
		var dir: Vector3 = (Basis(b.y, -look.x * LOOK_YAW) * Basis(b.x, -look.y * LOOK_PITCH)) * -b.z
		var ahead := cam.global_position + dir * 60.0
		if hit_shake > 0.0: ahead += Vector3(_rng.randfn(0, 1), _rng.randfn(0, 1), 0) * hit_shake * 1.2
		cam.look_at(ahead, b.y)
		cam.fov = lerpf(cam.fov, 92.0 if warp_state == "on" else (82.0 if boosting else 76.0), minf(1.0, dt * 2.0))
		return
	var back := 15.0 + (4.0 if warp_state == "on" else (1.5 if boosting else 0.0))
	var up := 2.2
	if GS.form == "mech":   # the mech stands taller: sit the camera higher and further back so it doesn't block the reticle
		back += 8.0
		up = 5.5
	var want := player.global_position + player.global_basis * Vector3(0, up, back)
	if snap: cam.global_position = want
	else: cam.global_position = cam.global_position.lerp(want, minf(1.0, dt * 6.0))
	_cam_clip()
	var look := player.global_position - player.global_basis.z * 30.0 + player.global_basis.y * 2.6
	if hit_shake > 0.0: look += Vector3(_rng.randfn(0, 1), _rng.randfn(0, 1), 0) * hit_shake * 0.8
	cam.look_at(look, player.global_basis.y)
	cam.fov = lerpf(cam.fov, 88.0 if warp_state == "on" else (76.0 if boosting else 70.0), minf(1.0, dt * 2.0))

## v1.9p (owner: "the camera pushes into the ground ... it should stop at the solid and move in, down to first
## person"): the chase camera never goes inside the ground, a cliff, a block wall or an asteroid. It slides in along
## the line from the ship to where it wants to be, and right up close the ship itself is hidden (you see from it).
var _cam_hid := false
var cam_clipped := 0.0   # (tests) how far the camera was pulled in this frame (0 = not at all)
func _cam_clip() -> void:
	cam_clipped = 0.0
	var pivot: Vector3 = player.global_position + player.global_basis.y * (Data.CAM_PIVOT_UP_MECH if GS.form == "mech" else Data.CAM_PIVOT_UP)
	var c: Vector3 = cam.global_position
	var seg := c - pivot
	var full := seg.length()
	if full < 0.01: return
	var f := 1.0
	if surface_mode:
		var n := int(Data.CAM_CLIP_STEPS)
		for i in range(1, n + 1):   # the ground and the blocks along the way
			var k := float(i) / float(n)
			var p := pivot + seg * k
			if p.y < _ground(p.x, p.z) + Data.CAM_CLEAR:
				f = maxf(0.0, k - 1.0 / float(n))
				break
		var rb := _ray_blocks(pivot, c)
		if rb[0] != null: f = minf(f, pivot.distance_to(rb[1]) / full)
	elif in_belt_region(c) or in_belt_region(pivot):
		var ah := ray_asteroids(pivot, c)
		if not ah.is_empty(): f = minf(f, pivot.distance_to(ah[2]) / full)
	var hide := false
	if f < 1.0:
		var d: float = maxf(0.0, full * f - Data.CAM_CLEAR)
		cam.global_position = pivot + seg.normalized() * d
		cam_clipped = full - d
		hide = d < Data.CAM_FPV_DIST
	if is_instance_valid(model) and hide != _cam_hid:   # (only what this hid is shown again)
		model.visible = not hide
		_cam_hid = hide

func _ambient_anim(dt: float) -> void:
	if is_instance_valid(planet_clouds): planet_clouds.rotate_y(dt * 0.006)
	for gp in gate_portals:
		if not is_instance_valid(gp): continue
		if gp.material_override is ShaderMaterial: continue   # (a warp hole animates in its shader)
		gp.rotate_object_local(Vector3.UP, dt * 0.8)
		var pm := gp.material_override as StandardMaterial3D
		pm.albedo_color.a = 0.4 + 0.15 * sin(time * 2.0)

# ---------------------------------------------------------------- effects
var _spark_pool: Array = []
static var _unit_quad: QuadMesh

## Short-lived glow sprite. Sprites are pooled (hidden and reused), so big fights don't allocate every frame.
func _spark(at: Vector3, col: Color, size: float, life := 0.3) -> void:
	var mi: MeshInstance3D
	if not _spark_pool.is_empty():
		mi = _spark_pool.pop_back()
		mi.visible = true
	else:
		if _unit_quad == null:
			_unit_quad = QuadMesh.new()
			_unit_quad.size = Vector2.ONE
		mi = MeshInstance3D.new()
		mi.mesh = _unit_quad
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.albedo_texture = _spark_tex()
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	(mi.material_override as StandardMaterial3D).albedo_color = col
	mi.global_position = at
	mi.scale = Vector3.ONE * size
	effects.append({"node": mi, "life": life, "max": life, "size": size})

func _spark_v(at: Vector3, v: Vector3, col: Color, size: float, life: float) -> void:
	_spark(at, col, size, life)
	effects[effects.size() - 1]["vel"] = v

static var _spark_texture: ImageTexture
func _spark_tex() -> ImageTexture:
	if _spark_texture == null: _spark_texture = _radial_texture(Color.WHITE, 0.08)
	return _spark_texture

func _explode(at: Vector3) -> void:
	var dd := at.distance_to(player.global_position)
	if dd < 1500.0: Sfx.play("explosion", -2.0 - dd / 90.0)
	_blast(at, Data.BLAST_ENEMY, "unit")

func _update_effects(dt: float) -> void:
	for i in range(effects.size() - 1, -1, -1):
		var f: Dictionary = effects[i]
		f["life"] -= dt
		var n: MeshInstance3D = f["node"]
		if f.has("vel"): n.global_position += (f["vel"] as Vector3) * dt
		var k: float = clampf(f["life"] / f["max"], 0.0, 1.0)
		n.scale = Vector3.ONE * float(f.get("size", 1.0)) * (1.0 + (1.0 - k) * 1.5)
		(n.material_override as StandardMaterial3D).albedo_color.a = k
		if f["life"] <= 0.0:
			effects.remove_at(i)
			if f.has("size") and _spark_pool.size() < 160:
				n.visible = false
				f.erase("vel")
				_spark_pool.append(n)
			else:
				n.queue_free()

# ---------------------------------------------------------------- cockpit systems (AUTO / MANUAL)
## Manually trigger one of the six systems. Returns false when it could not run.
func trigger_system(id: String) -> bool:
	if transform_t > 0.0 and id in ["guns", "missile", "light_missile", "heavy_missile", "mine"]:
		return _say(id, "Weapons are locked while transforming.")
	if not lane.is_empty() and id in ["guns", "missile", "light_missile", "heavy_missile", "mine"]:
		return _say(id, "Weapons are locked in the trade lane.")
	if warp_state != "off" and id in ["guns", "missile", "light_missile", "heavy_missile", "mine"]:
		return _say(id, "Weapons are locked while the warp drive is active.")
	if sun_surface and not GS.heat_shield and id in ["shield", "hull"]:
		return _say(id, "Too hot — shields and repairs cannot hold here. Climb out!")
	match id:
		"shield":
			if shield_cd > 0.0: return false
			if GS.shield_charges <= 0: return _say(id, "No shield charges left — dock to recharge.")
			if GS.shield >= GS.max_shield() - 0.5: return _say(id, "Shields already full.")
			GS.shield_charges -= 1
			GS.shield = minf(GS.max_shield(), GS.shield + GS.max_shield() * 0.5)
			shield_cd = Data.SHIELD_BOOST_COOLDOWN
			GS.changed.emit()
			system_used.emit(id, "Shield recharge: +50%%. %d charge%s left." % [GS.shield_charges, "" if GS.shield_charges == 1 else "s"])
			return true
		"hull":
			if repair_cd > 0.0: return false
			if GS.repairs <= 0: return _say(id, "No repair kits left — dock to restock.")
			if not GS.use_repair(): return _say(id, "Hull is intact.")
			repair_cd = 1.5
			system_used.emit(id, "Hull repair: +40%%. %d kit%s left." % [GS.repairs, "" if GS.repairs == 1 else "s"])
			return true
		"energy":
			if energy_cd > 0.0: return false
			if GS.energy_cells <= 0: return _say(id, "No energy cells left — dock to recharge.")
			if GS.energy >= Data.ENERGY_MAX - 1.0: return _say(id, "Energy already full.")
			GS.energy_cells -= 1
			GS.energy = Data.ENERGY_MAX
			energy_cd = Data.ENERGY_BOOST_COOLDOWN
			GS.changed.emit()
			system_used.emit(id, "Energy cell used. %d left." % GS.energy_cells)
			return true
		"missile", "light_missile", "heavy_missile":
			if missile_cd > 0.0: return false
			var heavy := id == "heavy_missile"
			if (GS.heavy_missiles if heavy else GS.missiles) <= 0:
				return _say(id, "No %s missiles left — buy more at Equipment." % ("heavy" if heavy else "light"))
			var locks := lock_count("heavy_missile" if heavy else "light_missile")
			if locks < 1:   # v1.9u (owner): no lock = the missile flies straight ahead (light and super alike); a lock = it chases
				if fire_missile(heavy, 0, 1, 1.0, null, true):
					missile_cd = 1.2
					system_used.emit(id, "%s missile fired straight — no lock." % ("Super" if heavy else "Light"))
					return true
				return false
			var shots := fire_volley(heavy, locks)
			if shots > 0:
				missile_cd = 1.2
				system_used.emit(id, "%s missile away." % ("Heavy" if heavy else "Light") if shots == 1 else "%d missiles away." % shots)
				return true
			return false
		"mine":
			return deploy_mine()
	return false

func _say(id: String, t: String) -> bool:
	system_used.emit(id, t)
	return false

func _auto_systems(_dt: float) -> void:
	if not is_instance_valid(target): target = null
	if GS.is_auto("shield") and GS.shield <= 0.5 and GS.shield_charges > 0 and shield_cd <= 0.0 and shield_delay > 0.0: trigger_system("shield")
	if GS.is_auto("hull") and GS.hull < GS.max_hull() * 0.35 and GS.repairs > 0 and repair_cd <= 0.0: trigger_system("hull")
	if GS.is_auto("energy") and GS.energy < Data.ENERGY_MAX * 0.15 and GS.energy_cells > 0 and energy_cd <= 0.0: trigger_system("energy")
	# missiles: after holding a hostile in the reticle for 1.5 s
	if _in_fire_cone(target) or (target and target.get_meta("kind", "") == "enemy" and _cone(target, Data.LOCK_CONE_DEG, Data.LOCK_RANGE)):
		lock_time += _dt
	else:
		lock_time = 0.0
	if GS.is_auto("missile") and lock_time > 1.5 and lock_count() >= mini(GS.max_locks("light_missile"), GS.missiles) and GS.missiles > 0 and missile_cd <= 0.0:
		if trigger_system("missile"): missile_cd = 5.0
	# mines: drop one when a hostile is chasing close behind
	if GS.is_auto("mine") and GS.mines > 0 and mine_cd <= 0.0:
		for e in enemies:
			var to: Vector3 = e["node"].global_position - player.global_position
			if to.length() < 160.0 and (-player.global_basis.z).dot(to.normalized()) < -0.5:
				deploy_mine()
				break

func _cone(t: Node3D, deg: float, rng: float) -> bool:
	if t == null or not is_instance_valid(t): return false
	var to := t.global_position - player.global_position
	return to.length() < rng and (-player.global_basis.z).dot(to.normalized()) > cos(deg_to_rad(deg))

func deploy_mine() -> bool:
	if mine_cd > 0.0: return false
	if GS.mines <= 0: return _say("mine", "No mines left — buy more at a dealer.")
	GS.mines -= 1
	GS.changed.emit()
	mine_cd = 2.5
	var mi: Node3D
	if ShipFactory.has_real_model("mine"):
		mi = ShipFactory.build("mine")
	else:
		var ball := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.4
		sm.height = 2.8
		sm.radial_segments = 10
		sm.rings = 5
		ball.mesh = sm
		ball.material_override = ShipFactory.mat(Color(0.25, 0.27, 0.3), false, 0.7)
		mi = ball
	var light := MeshInstance3D.new()
	var lb := BoxMesh.new()
	lb.size = Vector3(0.5, 0.5, 0.5)
	light.mesh = lb
	light.position = Vector3(0, 1.5, 0)
	light.material_override = ShipFactory.mat(Color(1.0, 0.3, 0.2), true)
	mi.add_child(light)
	add_child(mi)
	mi.global_position = player.global_position + player.global_basis.z * 10.0
	var magnetic := GS.mine_kind == "magnetic"
	if magnetic: light.material_override = ShipFactory.mat(Color(0.3, 0.6, 1.0), true)   # a blue light: the magnetic one
	mines_live.append({"node": mi, "arm": 1.0, "life": 60.0, "vel": vel * 0.2, "magnetic": magnetic})
	system_used.emit("mine", "%s mine deployed. %d left." % ["Magnetic" if magnetic else "Blast", GS.mines])
	return true

## v1.5x: a mine hits as hard as a super missile (the owner's rule), falling off over its blast radius.
var mines_detonated := 0
func mine_damage(e: Dictionary) -> float:
	return maxf(Data.MINE_DAMAGE, missile_damage(e, true))

func _update_mines(dt: float) -> void:
	for i in range(mines_live.size() - 1, -1, -1):
		var m: Dictionary = mines_live[i]
		var n: Node3D = m["node"]
		m["arm"] -= dt
		m["life"] -= dt
		m["vel"] = (m["vel"] as Vector3) * (1.0 - minf(1.0, dt * 0.8))
		n.global_position += m["vel"] * dt
		n.rotate_y(dt * 1.5)
		var boom: bool = m["life"] <= 0.0
		if m["arm"] <= 0.0:
			# sits quietly until a hostile comes close, then wakes up and chases it
			var prey: Node3D = null
			var pd := 170.0
			for e in enemies:
				var d0: float = e["node"].global_position.distance_to(n.global_position)
				if d0 < pd:
					pd = d0
					prey = e["node"]
			if prey != null:
				if not m.get("awake", false):
					m["awake"] = true
					Sfx.play("mine_wake", -8.0)
				var want := (prey.global_position - n.global_position).normalized() * 95.0
				m["vel"] = (m["vel"] as Vector3).lerp(want, minf(1.0, dt * 3.0))
				n.rotate_y(dt * 8.0)
				if pd < 12.0: boom = true
		if boom:
			_explode(n.global_position)
			for e in enemies.duplicate():
				var d: float = e["node"].global_position.distance_to(n.global_position)
				if d < Data.MINE_RADIUS:
					if m.get("magnetic", false):   # v1.5x: caught: pulled in and held stuck for a few seconds
						e["stuck_t"] = Data.MAG_MINE_HOLD
						e["stuck_at"] = n.global_position
					_damage_enemy(e, mine_damage(e) * (1.0 - d / Data.MINE_RADIUS * 0.5))
			mines_detonated += 1
			n.queue_free()
			mines_live.remove_at(i)

## Weapon slot button i: fires whatever is fitted there (light missile, heavy missile, mine).
func fire_slot(i: int) -> bool:
	if i < 0 or i >= GS.slots.size(): return false
	var item: String = GS.slots[i]
	if item == "mine": return trigger_system("mine")
	return trigger_system(item)

# ---------------------------------------------------------------- loot pods + tractor beam
func _drop_loot(at: Vector3, reward: int) -> void:
	var n := 1 + _rng.randi() % 2
	for i in n:
		var pod := MeshInstance3D.new()
		var ck: String = ["crate_a", "crate_b", "crate_c"][_rng.randi() % 3]
		if ShipFactory.has_real_model(ck):      # the owner's cargo containers
			pod.add_child(ShipFactory.build(ck))
		else:
			var bm := BoxMesh.new()
			bm.size = Vector3(2.2, 1.6, 3.0)
			pod.mesh = bm
			pod.material_override = ShipFactory.mat(Color(0.95, 0.75, 0.25), false, 0.4)
		var glow := MeshInstance3D.new()
		var gm := SphereMesh.new()
		gm.radius = 2.6
		gm.height = 5.2
		glow.mesh = gm
		glow.material_override = _glow_mat(Color(1.0, 0.8, 0.3))
		pod.add_child(glow)
		pod.name = "Loot"
		add_child(pod)
		pod.global_position = at
		var dir := Vector3(_rng.randfn(0, 1), _rng.randfn(0, 0.5), _rng.randfn(0, 1)).normalized()
		loot.append({"node": pod, "vel": dir * _rng.randf_range(8.0, 16.0), "value": maxi(10, int(reward * 0.4)), "life": 120.0})

## v1.6c mining: a gold or diamond layer broke. It drops pickup pieces (its own break count), but the blast destroys
## the rest: a careful light gun keeps 3 in 4, a missile half, the SPECIAL very little. The tractor beam pulls them in.
var mined_pieces := 0   # (tests)
func _on_mined(at: Vector3, mat: String, weapon: String) -> void:
	var pieces: int = Data.BLOCK_BREAK_PIECES.get(mat, 3)
	var keep: float = float(Data.MINING_KEEP.get(weapon, 0.5)) * pieces
	var n := int(keep) + (1 if _rng.randf() < keep - int(keep) else 0)
	var col: Color = Data.VALUABLE_COLOR.get(mat, Color.WHITE)
	for i in n:
		var gem := MeshInstance3D.new()
		var pm: PrimitiveMesh = PrismMesh.new() if mat == "diamond" else BoxMesh.new()
		if pm is PrismMesh: (pm as PrismMesh).size = Vector3(1.6, 2.2, 1.6)
		else: (pm as BoxMesh).size = Vector3(1.8, 1.0, 1.2)
		gem.mesh = pm
		gem.material_override = ShipFactory.mat(col, true)
		var glow := MeshInstance3D.new()
		var gm := SphereMesh.new()
		gm.radius = 2.2
		gm.height = 4.4
		glow.mesh = gm
		glow.material_override = _glow_mat(col)
		gem.add_child(glow)
		gem.name = "Gem"
		add_child(gem)
		gem.global_position = at + Vector3(0, 2.0, 0)
		var dir := Vector3(_rng.randfn(0, 1), absf(_rng.randfn(0, 0.6)) + 0.3, _rng.randfn(0, 1)).normalized()
		loot.append({"node": gem, "vel": dir * _rng.randf_range(5.0, 10.0), "value": int(Data.MINE_VALUE.get(mat, 20)), "life": 180.0, "gem": mat})
		mined_pieces += 1
	if n > 0: _popup(at, "%s x%d" % [mat.to_upper(), n], col)
	else: _popup(at, "%s lost in the blast" % mat.capitalize(), col)

## Switch the tractor beam on for a few seconds: every pod in range flies to you.
func tractor() -> String:
	var inrange := 0
	for l in loot:
		if (l["node"] as Node3D).global_position.distance_to(player.global_position) < Data.LOOT_RANGE: inrange += 1
	if inrange == 0: return "Tractor beam: nothing in range."
	tractor_t = Data.TRACTOR_TIME
	return "Tractor beam on — pulling in %d pod%s." % [inrange, "" if inrange == 1 else "s"]

func _update_loot(dt: float) -> void:
	tractor_t = maxf(0.0, tractor_t - dt)
	var pp := player.global_position
	for i in range(loot.size() - 1, -1, -1):
		var l: Dictionary = loot[i]
		var n: Node3D = l["node"]
		l["life"] -= dt
		var to := pp - n.global_position
		var d := to.length()
		if tractor_t > 0.0 and d < Data.LOOT_RANGE:
			l["vel"] = (l["vel"] as Vector3).lerp(to.normalized() * (60.0 + d * 0.6) + vel, minf(1.0, dt * 4.0))
			if int(time * 30.0) % 2 == 0: _spark_v(n.global_position, Vector3.ZERO, Color(0.5, 0.9, 1.0), 2.0, 0.25)
		else:
			l["vel"] = (l["vel"] as Vector3) * (1.0 - minf(1.0, dt * 0.3))
		n.global_position += l["vel"] * dt
		n.rotate_y(dt * 0.9)
		n.rotate_x(dt * 0.5)
		if d < 14.0 and l.has("bounty"):
			if GS.capture_bounty(l["bounty"]):
				_popup(n.global_position, "PILOT CAPTURED", Color(1.0, 0.5, 0.4))
				var who: Dictionary = Data.roster_pilot(l["bounty"])
				GS.cargo.append({"kind": "pilot", "id": l["bounty"], "name": str(who.get("name", "Pilot")), "note": "bounty prisoner"})   # v1.5f: in the hold
				var m0: Dictionary = GS.mission
				if m0.get("kind", "") == "bounty": message.emit("%s is in your hold. Tap the MISSION line, then GO TO: back to %s for the %d cr bounty." % [who.get("name", "The pilot"), Missions.giver_name(m0), Data.bounty_reward(l["bounty"])])
				else: message.emit("%s is in your hold. Dock at any station for the %d cr bounty." % [who.get("name", "The pilot"), Data.bounty_reward(l["bounty"])])
			Sfx.play("pickup", -6.0)
			n.queue_free()
			loot.remove_at(i)
		elif d < 14.0:
			if l.has("gem"):   # v1.8l: ore goes into the hold; a base buys it
				var have := GS.add_ore(str(l["gem"]))
				_popup(n.global_position, "%s x%d IN HOLD" % [str(l["gem"]).to_upper(), have], Color(1.0, 0.85, 0.35))
				if have == 1: message.emit("%s is in your hold. Sell it at any station or planet base, under YOUR SHIP." % Data.ORE_NAME.get(l["gem"], "Ore"))
			else:
				GS.add_credits(int(l["value"]))
				_popup(n.global_position, "+%d cr" % int(l["value"]), Color(1.0, 0.85, 0.35))
			Sfx.play("pickup", -6.0)
			n.queue_free()
			loot.remove_at(i)
		elif l["life"] <= 0.0:
			n.queue_free()
			loot.remove_at(i)

# ---------------------------------------------------------------- v1.7z mech first-person view
var fpv: Node3D = null            # the mech's own arms and rifle, held in front of the camera
var fpv_skel: Skeleton3D = null
var fpv_gun: Node3D = null
var fpv_muzzle := Vector3.ZERO    # (in fpv space)
var zoomed := false               # looking down the scope
var _fpv_base := Vector3.ZERO
var _fpv_sway := Vector2.ZERO
var _fpv_kick := 0.0
var _fpv_walk := 0.0

## v1.8h (owner): the mech carries the same gun in its right hand when seen from outside, pointing where it flies.
var hand_gun: Node3D = null
var _hand_model: Node3D = null
func _sync_hand_gun() -> void:
	var want: bool = GS.form == "mech" and is_instance_valid(model) and model.visible and player_vis.get("mech", false)
	if want and (hand_gun == null or _hand_model != model):
		if is_instance_valid(hand_gun): hand_gun.queue_free()
		hand_gun = _fpv_gun_model()
		hand_gun.name = "HandGun"
		_hand_model = model
		model.add_child(hand_gun)
		var k: float = Data.HAND_GUN_LENGTH / maxf(0.01, float(hand_gun.get_meta("length", 5.0)))
		hand_gun.set_meta("k", k)
	if not want:
		if is_instance_valid(hand_gun):
			hand_gun.queue_free()
		hand_gun = null
		return
	var sk: Skeleton3D = player_vis.get("skel")
	if not is_instance_valid(sk) or player_vis.get("gone_r", false):
		hand_gun.visible = false
		return
	var hb := sk.find_bone("RightHand")
	if hb < 0: return
	hand_gun.visible = transform_t <= 0.0   # (folded away while transforming)
	if transform_t > 0.0: return
	# v1.8h (owner: "hold the gun correctly with both hands"): both arms come up and forward every frame, the right
	# hand on the grip, the left reaching under the barrel (same pose as the first-person arms)
	for pair in [["RightUpperArm", "RightLowerArm"], ["RightLowerArm", "RightHand"], ["LeftUpperArm", "LeftLowerArm"], ["LeftLowerArm", "LeftHand"]]:
		if str(pair[0]).begins_with("Left") and player_vis.get("gone_l", false): continue
		_point_bone(sk, sk.find_bone(pair[0]), sk.find_bone(pair[1]), Data.HAND_GUN_ARM_DIRS[pair[0]])
	var hp: Vector3 = sk.global_transform * sk.get_bone_global_pose(hb).origin
	var lb := sk.find_bone("LeftHand")
	var lp: Vector3 = sk.global_transform * sk.get_bone_global_pose(lb).origin if lb >= 0 and not player_vis.get("gone_l", false) else hp - player.global_basis.z * 3.0
	var fwd := -player.global_basis.z
	var along := lp - hp   # the barrel runs from the right hand past the left one
	var dir := (fwd * 2.0 + along.normalized()).normalized() if along.length() > 0.3 else fwd
	var k2: float = hand_gun.get_meta("k", 1.0)
	var mid := hp + dir * (Data.HAND_GUN_LENGTH * 0.18) + player.global_basis.y * Data.HAND_GUN_LIFT
	hand_gun.global_transform = Transform3D(Basis.looking_at(dir, player.global_basis.y).scaled(Vector3.ONE * k2), mid)

func mech_fpv() -> bool:
	return GS.view == "cockpit" and GS.form == "mech" and transform_t <= 0.0 and is_instance_valid(player) and is_instance_valid(cam)

func toggle_zoom() -> bool:
	zoomed = mech_fpv() and not zoomed
	return zoomed

## Keep the arms there only while looking out of the mech; sway them with the sticks, bob them while walking, kick on shots.
func _sync_fpv(dt: float) -> void:
	var want := mech_fpv()
	if want and fpv == null: _build_fpv()
	if not want:
		zoomed = false
		if fpv != null:
			fpv.queue_free()
			fpv = null
		return
	if fpv == null: return
	fpv.visible = not zoomed
	var stick: Vector2 = aim if controls else Vector2.ZERO
	_fpv_sway = _fpv_sway.lerp(stick, minf(1.0, dt * 5.0))
	var walking: float = clampf(vel.length() / 30.0, 0.0, 1.0)
	_fpv_walk += dt * (4.0 + 6.0 * walking)
	var bob: float = sin(_fpv_walk) * Data.FPV_BOB * walking
	_fpv_kick = maxf(0.0, _fpv_kick - dt * 6.0)
	fpv.position = _fpv_base + Vector3(-_fpv_sway.x * Data.FPV_SWAY.x, -_fpv_sway.y * Data.FPV_SWAY.y + bob, _fpv_kick * Data.FPV_KICK)
	fpv.rotation = Vector3(_fpv_sway.y * 0.08 + _fpv_kick * 0.06, -_fpv_sway.x * 0.1, _fpv_sway.x * 0.06)

## A shot from the rifle: it kicks back and flashes at the muzzle.
func fpv_shot() -> void:
	if fpv == null or not fpv.visible: return
	_fpv_kick = 1.0
	_spark(fpv.global_transform * fpv_muzzle, Color(0.55, 0.9, 1.0), 2.6, 0.08)

func _build_fpv() -> void:
	fpv = Node3D.new()
	fpv.name = "MechFPV"
	cam.add_child(fpv)
	var body := _player_mech_model()   # v1.9i: the fitted arms show in first person too
	fpv.add_child(body)
	_shadows_off(body)
	fpv_skel = Sections._find_skeleton(body)
	var hand_r := Vector3(0.6, -1.4, -2.0)
	var hand_l := Vector3(-0.3, -1.3, -3.4)
	if fpv_skel != null:
		var sk := fpv_skel
		for bn in ["Head", "Neck", "LeftUpperLeg", "RightUpperLeg"]:
			var bi := sk.find_bone(bn)
			if bi >= 0: sk.set_bone_pose_scale(bi, Vector3.ONE * 0.0001)
		for pair in [["RightUpperArm", "RightLowerArm"], ["RightLowerArm", "RightHand"], ["LeftUpperArm", "LeftLowerArm"], ["LeftLowerArm", "LeftHand"]]:
			_point_bone(sk, sk.find_bone(pair[0]), sk.find_bone(pair[1]), Data.FPV_ARM_DIRS[pair[0]])
		# the eye sits where the neck was: move the whole body so its neck is just behind the camera
		var neck := sk.find_bone("Neck")
		if neck >= 0:
			var nw: Vector3 = sk.global_transform * sk.get_bone_global_pose(neck).origin
			body.position -= fpv.to_local(nw) - Vector3(0, -0.35, 0.5)
		var hr := sk.find_bone("RightHand")
		var hl := sk.find_bone("LeftHand")
		if hr >= 0: hand_r = fpv.to_local(sk.global_transform * sk.get_bone_global_pose(hr).origin)
		if hl >= 0: hand_l = fpv.to_local(sk.global_transform * sk.get_bone_global_pose(hl).origin)
	fpv_gun = _fpv_gun_model()
	fpv.add_child(fpv_gun)
	# the rifle sits in the right hand and runs forward past the left one
	var along := (hand_l - hand_r)
	along.x *= 0.4
	var gdir := Vector3(-0.06, 0.03, -1.0).normalized()
	if fpv_gun.has_meta("real"):   # v1.8h: the owner's gun, sized to FPV_GUN_LENGTH, its middle just ahead of the right hand
		var k: float = Data.FPV_GUN_LENGTH / maxf(0.01, float(fpv_gun.get_meta("length")))
		fpv_gun.transform = Transform3D(Basis.looking_at(gdir, Vector3.UP).scaled(Vector3.ONE * k), hand_r + Data.FPV_GUN_GRIP)
		fpv_muzzle = fpv_gun.transform * (fpv_gun.get_meta("muzzle") as Vector3)
	else:
		fpv_gun.transform = Transform3D(Basis.looking_at(gdir, Vector3.UP).scaled(Vector3.ONE * Data.FPV_GUN_SCALE), hand_r + Vector3(-0.15, 0.2, 0.1))
		fpv_muzzle = fpv_gun.transform * Vector3(0, 0.1, -4.6)
	_fpv_base = Vector3.ZERO

## Point a bone (and so its whole limb) along a direction in the model's own axes.
func _point_bone(sk: Skeleton3D, b: int, child: int, dir: Vector3) -> void:
	if b < 0 or child < 0: return
	var gp := sk.get_bone_global_pose(b)
	var cp := sk.get_bone_global_pose(child)
	var cur := (cp.origin - gp.origin).normalized()
	var to := dir.normalized()
	if cur.length() < 0.5 or cur.is_equal_approx(to): return
	var q := Quaternion(cur, to)
	sk.set_bone_global_pose(b, Transform3D(Basis(q) * gp.basis, gp.origin))

func _shadows_off(n: Node) -> void:
	if n is GeometryInstance3D: (n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children(): _shadows_off(c)

## v1.8h: the owner's gun model when it is here (mechs pack), else the code-made rifle. Meta: real, length, muzzle.
func _fpv_gun_model() -> Node3D:
	if not ResourceLoader.exists(Data.FPV_GUN_MODEL): return _fpv_rifle()
	var ps := load(Data.FPV_GUN_MODEL) as PackedScene
	if ps == null: return _fpv_rifle()
	var g := Node3D.new()
	g.name = "Rifle"
	var inst: Node3D = ps.instantiate()
	g.add_child(inst)
	_shadows_off(inst)
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in inst.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = mi.transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	inst.rotation.y = deg_to_rad(Data.FPV_GUN_YAW)   # (the model's barrel points +Z: turned so it fires along -Z)
	inst.position = -(Basis(Vector3.UP, deg_to_rad(Data.FPV_GUN_YAW)) * box.get_center())
	g.set_meta("real", true)
	g.set_meta("length", box.size.z)
	g.set_meta("muzzle", Vector3(0, box.size.y * 0.1, -box.size.z * 0.5))
	return g

## The rifle: blocky, white plates over black, cyan glow strips and a scope (concept art). Its muzzle is at -Z.
func _fpv_rifle() -> Node3D:
	var g := Node3D.new()
	g.name = "Rifle"
	var col: Dictionary = Data.FPV_GUN_COLORS
	var parts := [   # [size, centre, colour key]
		[Vector3(0.55, 0.6, 2.2), Vector3(0, 0.1, -0.9), "body"],      # receiver
		[Vector3(0.62, 0.22, 1.6), Vector3(0, 0.48, -0.8), "dark"],     # top rail
		[Vector3(0.3, 0.3, 2.2), Vector3(0, 0.12, -3.0), "dark"],       # barrel
		[Vector3(0.44, 0.44, 0.5), Vector3(0, 0.12, -4.2), "body"],     # muzzle brake
		[Vector3(0.3, 0.8, 0.35), Vector3(0, -0.45, -0.2), "dark"],     # grip
		[Vector3(0.45, 0.7, 0.4), Vector3(0, -0.35, -1.2), "body"],     # magazine
		[Vector3(0.5, 0.55, 0.9), Vector3(0, 0.05, 0.55), "dark"],      # stock
		[Vector3(0.42, 0.42, 0.9), Vector3(0, 0.85, -0.6), "dark"],     # scope body
		[Vector3(0.6, 0.14, 0.12), Vector3(0.0, 0.12, -1.4), "glow"],   # glow strip
		[Vector3(0.06, 0.08, 1.4), Vector3(0.29, 0.1, -0.9), "glow"],   # side glow
		[Vector3(0.06, 0.08, 1.4), Vector3(-0.29, 0.1, -0.9), "glow"],
		[Vector3(0.34, 0.34, 0.05), Vector3(0, 0.85, -1.06), "glow"],   # scope lens
	]
	for pt in parts:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = pt[0]
		mi.mesh = bm
		var m := StandardMaterial3D.new()
		m.albedo_color = col[pt[2]]
		m.roughness = 0.5 if pt[2] != "glow" else 0.2
		if pt[2] == "glow":
			m.emission_enabled = true
			m.emission = col["glow"]
			m.emission_energy_multiplier = 2.5
		mi.material_override = m
		mi.position = pt[1]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.add_child(mi)
	return g

## Chase camera or first-person cockpit.
func set_view(v: String) -> void:
	GS.view = v
	if is_instance_valid(model): model.visible = v != "cockpit"
	_update_camera(1.0, true)

# ---------------------------------------------------------------- targeting / queries
func _nearest_enemy(max_d: float) -> Node3D:
	var best: Node3D = null
	var bd := max_d
	for e in enemies:
		var d: float = e["node"].global_position.distance_to(player.global_position)
		if d < bd:
			bd = d
			best = e["node"]
	return best

func _auto_target() -> void:
	# keep a manually chosen non-enemy target while nothing is coming at you; otherwise pick the nearest hostile ahead.
	# v1.6g: a waypoint, GPS stop or mission marker is never "chosen": when hostiles are near, they get targeted, so a
	# job's enemies get the red brackets, the aim box and missile lock like any others.
	if target != null and is_instance_valid(target) and target.get_meta("kind", "") != "enemy":
		var soft: bool = target.get_meta("kind", "") == "waypoint" or target == nav_dest or target == _mission_marker or target == waypoint
		if not soft and not _hostiles_on_you(): return
	var best: Node3D = null
	var score := -1.0
	for e in enemies:
		var n: Node3D = e["node"]
		var to := n.global_position - player.global_position
		var d := to.length()
		if d > 1100.0: continue
		var s := (-player.global_basis.z).dot(to.normalized()) + 600.0 / maxf(d, 1.0)
		if s > score:
			score = s
			best = n
	if best == null:   # v1.8c (owner): the job's gold-marked enemy is your target even from far off (red box, lead box, locks)
		var mw := mission_waypoint()
		if not mw.is_empty() and is_instance_valid(mw.get("node")) and (mw["node"] as Node3D).get_meta("kind", "") == "enemy": best = mw["node"]
	if best != null or target == null or not is_instance_valid(target) or target.get_meta("kind", "") == "enemy": target = best

## Any hostile (red contact) within 1100 m that has turned on you?
func _hostiles_on_you() -> bool:
	for e in enemies:
		var n: Node3D = e["node"]
		if n.get_meta("kind", "") == "enemy" and e.get("aggro", false) and n.global_position.distance_to(player.global_position) < 1100.0: return true
	return false

func targetables() -> Array:
	var out: Array = []
	var list := enemies.duplicate()
	list.sort_custom(func(a, b): return a["node"].global_position.distance_to(player.global_position) < b["node"].global_position.distance_to(player.global_position))
	for e in list: out.append(e["node"])
	out.append(station)
	out.append(planet)
	for g in gates: out.append(g)
	for x in extras: out.append(x)
	if is_instance_valid(beacon): out.append(beacon)
	return out

## Job J (Freelancer "target closest enemy"): the nearest hostile; with none around, the nearest thing you can target.
func target_closest() -> Node3D:
	var best := _nearest_enemy(INF)
	if best == null:
		var bd := INF
		for n in targetables():
			if n == null or not is_instance_valid(n): continue
			var d: float = n.global_position.distance_to(player.global_position)
			if d < bd:
				bd = d
				best = n
	if best != null:
		target = best
		message.emit("Target: %s" % best.name)
	return best

## v1.8u (owner: every enemy can be picked): choose this ship as your target (a tap on its box, or TARGET).
func pick_target(n: Node3D) -> void:
	target = n
	message.emit("Target: %s" % n.name)

func cycle_target() -> void:
	var list := targetables()
	var i := list.find(target)
	target = list[(i + 1) % list.size()]
	message.emit("Target: %s" % target.name)

func dock_candidate() -> Node3D:
	var p := player.global_position
	if p.distance_to(station.global_position) < DOCK_RANGE_STATION: return station
	if p.distance_to(dock_point(station)) < DOCK_RANGE_STATION: return station
	var surf := p.distance_to(planet.global_position) - float(planet.get_meta("radius"))
	if surf < DOCK_RANGE_PLANET: return planet
	for pl in platforms:   # v1.9b: the other planets' docking platforms
		if is_instance_valid(pl) and minf(p.distance_to(pl.global_position), p.distance_to(dock_point(pl))) < DOCK_RANGE_STATION: return pl
	for ds in docks3d:   # v1.9d: the system's other stations that wear the owner's 3D model
		if is_instance_valid(ds) and minf(p.distance_to(ds.global_position) - float(ds.get_meta("radius")), p.distance_to(dock_point(ds))) < DOCK_RANGE_STATION: return ds
	return null

## v1.4u: which ONE prompt the ship gets: "dock", "jump", "lane" or "". When a station (or planet) and a trade-lane
## ring are both in reach, the NEARER one wins, so the two no longer fight: fly at the ring for the lane, fly in
## close for the dock.
func prompt() -> String:
	var dc := dock_candidate()
	var lc: Dictionary = lane_candidate() if lane.is_empty() else {}
	if not lane.is_empty(): return "lane"
	if dc != null:
		if not lc.is_empty() and player.global_position.distance_to(lc["pos"]) < dock_distance(dc): return "lane"
		return "dock"
	if gate_in_range(): return "jump"
	return "lane" if not lc.is_empty() else ""

## How far the ship is from being docked with this station or planet (station: its body or docking mouth; planet: its surface).
func dock_distance(n: Node3D) -> float:
	var p := player.global_position
	if n == planet: return p.distance_to(planet.global_position) - float(planet.get_meta("radius"))
	return minf(p.distance_to(n.global_position), p.distance_to(dock_point(n)))

func gate_in_range() -> bool:
	return player.global_position.distance_to(near_gate().global_position) < GATE_RANGE

## The gate closest to the ship: the one the JUMP button uses.
func near_gate() -> Node3D:
	var best: Node3D = gate
	var bd := INF
	for g in gates:
		var d := player.global_position.distance_to(g.global_position)
		if d < bd:
			bd = d
			best = g
	return best

func distance_to(n: Node3D) -> float:
	if n == planet: return maxf(0.0, player.global_position.distance_to(planet.global_position) - float(planet.get_meta("radius")))
	return player.global_position.distance_to(n.global_position)

func target_shield() -> float:
	if target == null: return -1.0
	var e := _enemy_entry(target)
	if e.is_empty() or float(e["sh_max"]) <= 0.0: return -1.0
	return float(e["sh"]) / float(e["sh_max"])

func target_health() -> float:
	if target == null: return -1.0
	var e := _enemy_entry(target)
	if e.is_empty(): return -1.0
	return float(e["hp"]) / float(e["max"])

## Hostiles that are actually on you (they have seen you and are within fighting range): drives the battle music.
func hostiles_engaged(r := 1500.0) -> int:
	var c := 0
	for e in enemies:
		if e.get("aggro", false) and is_instance_valid(e["node"]) and e["node"].global_position.distance_to(player.global_position) < r: c += 1
	return c

## v1.9k: how dangerous the fight is: 2 = a boss, a named leader or a rank 4+ pilot is on you, 1 = an ordinary fight.
func engaged_tier(r := 1500.0) -> int:
	var t := 0
	for e in enemies:
		if not (e.get("aggro", false) and is_instance_valid(e["node"]) and e["node"].global_position.distance_to(player.global_position) < r): continue
		t = maxi(t, 2 if (e.get("boss_mech", false) or e["def"].get("capital", false) or e.has("bounty") or int(e.get("rank", 0)) >= Data.EPIC_RANK) else 1)
	return t

func hostiles_near(r: float) -> int:
	var c := 0
	for e in enemies:
		if e["node"].global_position.distance_to(player.global_position) < r: c += 1
	return c

# ---------------------------------------------------------------- planet surface mode
## Build one planet tile as the play area. Reuses all of the flight, combat, HUD and docking code; only the world
## around the player is different. planet/gate become hidden placeholders; the tile's town pad is the dockable "station".
func setup_surface(pid: String, t: int) -> void:
	surface_mode = true
	planet_id = pid
	sun_surface = Surface.is_sun(pid)
	sys_id = Surface.PLANETS[pid]["system"]
	sys = Data.SYSTEMS[sys_id]
	_rng.seed = hash(pid)
	_bolt_mesh = BoxMesh.new()
	_bolt_mesh.size = Vector3(0.6, 0.6, 14.0)
	_bolt_halo = BoxMesh.new()
	_bolt_halo.size = Vector3(2.2, 2.2, 18.0)
	_build_surface_env()
	var far := Vector3(0, -1000000, 0)
	planet = _placeholder(sys["planet"]["name"], "planet", far, sys["planet"])
	gate = _placeholder(sys["gate"]["name"], "gate", far, sys["gate"])
	gates = [gate]
	station = _placeholder("-", "none", far, {})
	nebula_center = far
	nebula_radius = 1.0
	belt_center = far
	belt_radius = 0.0
	_build_player()
	load_tile(t)
	place_player("port")

func _placeholder(nm: String, kind: String, at: Vector3, info: Dictionary) -> Node3D:
	var n := Node3D.new()
	n.name = nm
	n.visible = false
	n.set_meta("kind", kind)
	n.set_meta("radius", 1.0)
	n.set_meta("info", info)
	add_child(n)
	n.global_position = at
	return n

func _build_surface_env() -> void:
	env = WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	_sky = ProceduralSkyMaterial.new()
	sky.sky_material = _sky
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.8
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# depth fog: clear up close, thick toward the tile edge so the end of the terrain is never seen
	e.fog_enabled = true
	e.fog_mode = Environment.FOG_MODE_DEPTH
	e.fog_density = 1.0
	e.fog_depth_begin = 1300.0
	e.fog_depth_end = 4300.0
	e.fog_depth_curve = 1.6
	e.fog_sky_affect = 0.0
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.2
	sun.rotation_degrees = Vector3(-50, -30, 0)
	add_child(sun)
	cam = Camera3D.new()
	cam.far = 9000.0
	cam.near = 0.5
	cam.fov = 70.0
	cam.current = true
	add_child(cam)

## Swap the loaded tile: frees the old tile, its enemies and effects, builds the new one. The player is untouched.
## keep: offset to carry things near the player into the new tile (seamless border crossing); Vector3.INF = free all.
func load_tile(t: int, keep := Vector3.INF) -> void:
	tile = t
	var pp := player.global_position if is_instance_valid(player) else Vector3.ZERO
	for arr in [enemies, loot, missiles_live, enemy_missiles, mines_live, bolts]:
		for i in range(arr.size() - 1, -1, -1):
			var d: Dictionary = arr[i]
			var nd: Node3D = d["node"]
			if keep != Vector3.INF and is_instance_valid(nd) and nd.global_position.distance_to(pp) < 1800.0:
				nd.global_position -= keep   # comes along across the border
				if d.has("home"): d["home"] = (d["home"] as Vector3) - keep
				continue
			if is_instance_valid(nd): nd.queue_free()
			arr.remove_at(i)
	if keep == Vector3.INF or (target != null and not is_instance_valid(target)): target = null
	autopilot = null
	var carried := {}   # v1.7d: crossing a border, the block regions round you come along (no rebuild, no gap)
	if keep != Vector3.INF:
		var sh := Vector2i(roundi(keep.x / Surface.TILE), roundi(keep.z / Surface.TILE))
		for k in _regions:
			var f: BlockField = _regions[k]
			if not is_instance_valid(f): continue
			var nk := Vector4i(k.x - sh.x, k.y - sh.y, k.z, k.w)
			if absi(nk.x) > 1 or absi(nk.y) > 1: continue
			f.get_parent().remove_child(f)
			f.reframe(Vector2(-keep.x, -keep.z))
			carried[nk] = f
	if is_instance_valid(tile_root): tile_root.queue_free()
	_regions = {}   # (v1.7a: the rest went with the old tile)
	if _building != null:
		_building.cancel = true
		_building = null
	tile_root = Surface.build_tile(planet_id, t)
	for k in carried:
		tile_root.add_child(carried[k])
		_regions[k] = carried[k]
	var bfm := tile_root.get_node_or_null("BlockField") as BlockField
	if bfm: bfm.mined.connect(_on_mined)   # v1.6c: gold and diamond pieces to pull in
	_water = Surface.has_water(planet_id, t)
	_edge_warned = false
	add_child(tile_root)
	_faction_buildings()   # v1.9q
	var b := Surface.biome(planet_id, t)
	var cols := {"sky": b["sky"], "horizon": b["horizon"], "fog": b["fog"]}
	if keep == Vector3.INF: _apply_sky(cols, 1.0)
	else:
		# seamless crossing: the sky and fog drift to the new biome's colours over a few seconds
		var from := {"sky": _sky.sky_top_color, "horizon": _sky.sky_horizon_color, "fog": env.environment.fog_light_color}
		var tw := create_tween()
		tw.tween_method(func(k: float): _apply_sky({"sky": (from["sky"] as Color).lerp(cols["sky"], k), "horizon": (from["horizon"] as Color).lerp(cols["horizon"], k), "fog": (from["fog"] as Color).lerp(cols["fog"], k)}, 1.0), 0.0, 1.0, 3.0)
	if is_instance_valid(station) and station.get_meta("kind", "") == "station": station.queue_free()
	var locs := Surface.locations_in(planet_id, t)
	if locs.is_empty():
		station = _placeholder("-", "none", Vector3(0, -1000000, 0), {})
	else:
		var l: Dictionary = locs[0]
		station = Node3D.new()
		station.name = l["name"]
		station.set_meta("kind", "station")
		station.set_meta("info", l)
		station.set_meta("radius", 40.0)
		add_child(station)
		station.global_position = Vector3(l["pos"].x, Surface.pad_top(planet_id, t) + 20.0, l["pos"].y)
	# a patrol over this tile (ships, sometimes a mech)
	var prng := RandomNumberGenerator.new()
	prng.seed = hash("%s%d" % [planet_id, t])
	var c := Vector3(prng.randf_range(-1400, 1400), 0, prng.randf_range(-1400, 1400))
	c.y = _ground(c.x, c.z) + 260.0
	if enemies.size() < 4: _spawn_rival_patrol(c, 2)   # v1.8o (owner): a planet has only its owner's rival over it
	if keep == Vector3.INF: _update_camera(1.0, true)
	_corners = Surface.wrap_corners(planet_id, t)
	_prepared.clear()

func _apply_sky(c: Dictionary, _k: float) -> void:
	_sky.sky_top_color = c["sky"]
	_sky.sky_horizon_color = c["horizon"]
	_sky.ground_horizon_color = c["fog"]      # below the horizon the sky matches the fog, so the far edge melts away
	_sky.ground_bottom_color = c["fog"]
	env.environment.fog_light_color = c["fog"]
	env.environment.ambient_light_color = c["horizon"]

var _corners: Array = []
var _prepared := {}
## v1.5a MISSION WAYPOINT: where the mission you carry wants you to go next, as a thing in THIS system.
## {} = no mission. Otherwise {"node", "title" (short name for the marker), "line" (what to do), "hops" (gate jumps left)}.
## A bounty: in another system -> the gate that starts the shortest way there; in its system -> the ship; once the
## ship is down -> the drifting pilot; once the pilot is in your hold -> the station (dock anywhere to be paid).
func mission_waypoint() -> Dictionary:
	if not GS.mission.is_empty(): return Missions.waypoint(self)   # v1.5f: a job from the board (bounties included)
	var b: Dictionary = GS.bounty
	if b.is_empty() or surface_mode or not is_instance_valid(player): return {}
	var p: Dictionary = Data.roster_pilot(str(b.get("id", "")))
	var who: String = str(p.get("name", "the pilot"))
	if b.get("state", "") == "captured":
		if not is_instance_valid(station): return {}
		return {"node": station, "title": station.name, "line": "Dock at %s to hand %s over for the bounty" % [station.name, who], "hops": 0}
	if b.get("state", "") != "hunt": return {}
	if str(b.get("sys", "")) != sys_id:
		var route: Array = Data.gate_route(sys_id, str(b["sys"]))
		if route.size() < 2: return {}
		for g in gates:
			if is_instance_valid(g) and str((g.get_meta("info", {}) as Dictionary).get("to", "")) == str(route[1]):
				var hops: int = route.size() - 1
				return {"node": g, "title": g.name, "line": "Bounty on %s: %d jump%s to %s. Take the %s" % [who, hops, "" if hops == 1 else "s", Data.SYSTEMS[b["sys"]]["name"], g.name], "hops": hops}
		return {}
	for l in loot:
		if l.get("bounty", "") == b["id"] and is_instance_valid(l["node"]):
			return {"node": l["node"], "title": "%s (pilot)" % who, "line": "TRACTOR %s in" % who, "hops": 0}
	for o in enemies:
		if o.get("bounty", "") == b["id"] and is_instance_valid(o["node"]):
			return {"node": o["node"], "title": who, "line": "Bounty on %s: destroy the ship, then TRACTOR the pilot in" % who, "hops": 0}
	return {}

var escort_node: Node3D = null   # v1.5f: the freighter of an escort mission (null = none out)

## v1.7o (owner: "the GPS doesn't work there"): with a job on, the GPS destination follows the mission waypoint (the
## gate toward it, the target, the next point...) until you pick your own destination on the map.
var gps_mission := false
var _gps_chk := 0.0
func _follow_mission(dt: float) -> void:
	if not gps_mission: return
	_gps_chk -= dt
	if _gps_chk > 0.0: return
	_gps_chk = 0.5
	if GS.mission.is_empty() and GS.bounty.is_empty():
		gps_mission = false
		return
	var mw := mission_waypoint()
	if mw.is_empty() or not is_instance_valid(mw.get("node")): return
	if nav_dest != mw["node"] and nav_route.size() <= 1: set_destination(mw["node"])

# ---------------------------------------------------------------- v1.5i GPS: the active destination (point B)
var nav_dest: Node3D = null      # what the GPS is guiding you to NOW = nav_route[0] (stays set when you take the stick)
var nav_start := 0.0             # the distance when this leg started (the GPS bar's full length)
var nav_route: Array = []        # v1.5i stage 2: the stops in order, at most Data.GPS_MAX_STOPS (the last = final destination)
var nav_go := false              # v1.5m: GO: the autopilot flies the whole route, stop after stop (steering cancels it)

## One destination: the route becomes just this stop.
func set_destination(n: Node3D) -> void:
	_drop_markers(nav_route.filter(func(x): return x != n))
	nav_route = [n] if n != null and is_instance_valid(n) else []
	_route_changed()

## ADD WAYPOINT: one more stop at the end (up to GPS_MAX_STOPS; a place already in the route is not added twice).
func add_stop(n: Node3D) -> String:
	if n == null or not is_instance_valid(n): return "Nothing to add."
	if n in nav_route: return "%s is already on your route." % n.name
	if nav_route.size() >= Data.GPS_MAX_STOPS: return "The route holds %d stops. Remove one first." % Data.GPS_MAX_STOPS
	nav_route.append(n)
	_route_changed()
	return "Stop %d: %s." % [nav_route.size(), n.name]

func remove_stop(i: int) -> void:
	if i < 0 or i >= nav_route.size(): return
	_drop_markers([nav_route[i]])
	nav_route.remove_at(i)
	_route_changed()

## Move stop i one place earlier (d = -1) or later (d = 1).
func move_stop(i: int, d: int) -> void:
	var j := i + d
	if i < 0 or j < 0 or i >= nav_route.size() or j >= nav_route.size(): return
	var tmp = nav_route[i]
	nav_route[i] = nav_route[j]
	nav_route[j] = tmp
	_route_changed()

func replace_stop(i: int, n: Node3D) -> void:
	if i < 0 or i >= nav_route.size() or n == null or not is_instance_valid(n): return
	if n in nav_route and nav_route.find(n) != i: return
	_drop_markers([nav_route[i]])
	nav_route[i] = n
	_route_changed()

func clear_route() -> void:
	_drop_markers(nav_route)
	nav_route = []
	_route_changed()

func _route_changed() -> void:
	nav_route = nav_route.filter(func(x): return x != null and is_instance_valid(x))
	var first: Node3D = nav_route[0] if not nav_route.is_empty() else null
	if first != nav_dest: nav_start = distance_to(first) if first != null else 0.0
	nav_dest = first

## A GPS-only marker for a place with no node of its own (a zone's middle, a point): one node per stop.
func nav_marker(p: Vector3, label: String) -> Node3D:
	var m := Node3D.new()
	m.name = label.validate_node_name()
	m.set_meta("kind", "waypoint")
	m.set_meta("radius", 30.0)
	m.set_meta("gps_marker", true)
	add_child(m)
	m.global_position = p
	return m

func _drop_markers(list: Array) -> void:
	for x in list:
		if x != null and is_instance_valid(x) and x.get_meta("gps_marker", false):
			if x == autopilot: autopilot = null
			if x == target: target = null
			x.queue_free()

## Whole route: [distance to the next stop, distance to the end through every stop in order].
func route_lengths() -> Array:
	if nav_route.is_empty() or not is_instance_valid(player): return [0.0, 0.0]
	var first: float = distance_to(nav_route[0])
	var total := first
	for i in range(1, nav_route.size()):
		total += (nav_route[i - 1] as Node3D).global_position.distance_to((nav_route[i] as Node3D).global_position)
	return [first, total]

## The speed the GPS counts on: the lane's while in a trade lane, warp speed at warp, otherwise what you are flying
## now (never less than cruise, so a ship sitting still still gets an honest ETA).
func eff_speed() -> float:
	if not lane.is_empty(): return Data.LANE_SPEED
	if warp_state == "on": return float(GS.ship()["speed"]) * Data.WARP_MULT
	return maxf(speed_now, float(GS.ship()["speed"]) * Data.CRUISE)

func nav_eta() -> float:
	if nav_dest == null or not is_instance_valid(nav_dest): return -1.0
	var pl := nav_plan()
	if pl.get("via", "") == "lane": return float(pl["t"])
	return distance_to(nav_dest) / maxf(eff_speed(), 1.0)

## v1.5m FASTEST ROUTE to the GPS destination: straight there, or by a trade lane (fly to its mouth, ride it, fly
## on). {via: "direct" | "lane", t, entry, exit, lane_name} with times in seconds; a lane is chosen when it beats
## flying direct by GPS_LANE_GAIN. In a lane already, the rest of the ride is the plan.
func _leg_time(d: float) -> float:
	var sp: float = float(GS.ship()["speed"])
	if d < Data.GPS_WARP_FROM: return d / maxf(sp * Data.FORWARD_MULT, 1.0)
	return Data.WARP_CHARGE + d / maxf(sp * Data.WARP_MULT, 1.0)

func nav_plan() -> Dictionary:
	if nav_dest == null or not is_instance_valid(nav_dest) or not is_instance_valid(player): return {}
	var p := player.global_position
	var goal: Vector3 = nav_dest.global_position
	var direct := {"via": "direct", "t": _leg_time(p.distance_to(goal)), "entry": goal, "exit": goal, "lane_name": ""}
	if surface_mode: return direct
	if not lane.is_empty():
		return {"via": "lane", "t": 0.0, "entry": p, "exit": p, "lane_name": "%s - %s" % [lane.get("a", ""), lane.get("b", "")], "riding": true}
	var best := direct
	for ln in lanes:
		for way in [["up", 0], ["down", -1]]:
			var rings: Array = ln[way[0]]
			if rings.size() < 2: continue
			var en: Vector3 = rings[0] if way[1] == 0 else rings[-1]
			var ex: Vector3 = rings[-1] if way[1] == 0 else rings[0]
			var t := _leg_time(p.distance_to(en)) + en.distance_to(ex) / Data.LANE_SPEED + Data.LANE_RAMP * 2.0 + _leg_time(ex.distance_to(goal))
			if t < float(best["t"]) * (Data.GPS_LANE_GAIN if best["via"] == "direct" else 1.0):
				best = {"via": "lane", "t": t, "entry": en, "exit": ex, "lane_name": "%s - %s" % [ln["a"], ln["b"]]}
	return best

## v1.5m GO: the autopilot flies the route, every stop in turn.
func route_go() -> String:
	if nav_dest == null or not is_instance_valid(nav_dest): return "No route to fly."
	nav_go = true
	autopilot = nav_dest
	target = nav_dest
	return "Flying the route: %d stop%s. Steer to take over." % [nav_route.size(), "" if nav_route.size() == 1 else "s"]

func _update_nav() -> void:
	if nav_go and autopilot == null and not (nav_dest != null and is_instance_valid(nav_dest) and distance_to(nav_dest) < Data.GPS_ARRIVE): nav_go = false   # you took the stick (not: the autopilot just arrived)
	if nav_dest == null and nav_route.is_empty(): return
	if nav_dest == null or not is_instance_valid(nav_dest):
		_route_changed()
		return
	if distance_to(nav_dest) < Data.GPS_ARRIVE:   # this stop reached: on to the next one by itself
		var here: String = str(nav_dest.name)
		_drop_markers([nav_dest])
		nav_route.pop_front()
		_route_changed()
		if nav_dest != null:
			message.emit("GPS: %s reached. Next stop: %s (%d to go)." % [here, nav_dest.name, nav_route.size()])
			if nav_go:   # on to the next stop by itself
				autopilot = nav_dest
				target = nav_dest
		else:
			message.emit("GPS: arrived at %s." % here)
			if nav_go:
				nav_go = false
				autopilot = null
var _mission_marker: Node3D = null

## v1.5f: the marker a mission point is flown to (one at a time, moved to the stage's point).
func mission_point(p: Vector3) -> Node3D:
	if not is_instance_valid(_mission_marker):
		_mission_marker = Node3D.new()
		_mission_marker.name = "Mission point"
		_mission_marker.set_meta("kind", "waypoint")
		_mission_marker.set_meta("radius", 30.0)
		add_child(_mission_marker)
	_mission_marker.global_position = p
	return _mission_marker

## v1.5f: a mission wave: `count` ships of `faction` at `at`, soldiers up to `max_slot`, always hostile to you; with a
## `boss_id` the first ship is that named bounty pilot. Tagged with the stage, so the mission knows when it is gone.
func spawn_mission_group(at: Vector3, faction: String, count: int, max_slot: int, boss_id: String, stage: int, one_rank := false) -> Array:   # v1.8x: one_rank = every ship of that slot
	_group_serial += 1
	var out: Array = []
	var pool: Array = Factions.DEFS.get(faction, {}).get("fighter_pool", [])
	for i in count:
		var soldier: Dictionary = {}
		if i == 0 and boss_id != "": soldier = Data.roster_pilot(boss_id)
		else: soldier = _pick_senior(faction, max_slot, max_slot if (i == 0 or one_rank) else mini(max_slot, 2))
		var kind := ""
		if not soldier.is_empty() and Data.ENEMIES.has(str(soldier.get("fighter_primary", ""))): kind = str(soldier["fighter_primary"])
		elif not pool.is_empty(): kind = pool[mini(i, pool.size() - 1)]
		else: kind = sys["enemy"]
		var e := spawn_unit(kind, at + Vector3(_rng.randf_range(-70, 70), _rng.randf_range(-25, 25), _rng.randf_range(-70, 70)), at)
		e["group"] = _group_serial
		e["mission"] = stage
		e["provoked"] = true   # a mission's targets fight you whatever your standing with their faction
		if not soldier.is_empty(): assign_roster(e, soldier)
		else: _make_generic(e, faction)
		if i == 0 and boss_id != "":
			e["bounty"] = boss_id
			e["node"].name = "%s (bounty)" % soldier["name"]
		out.append(e)
	return out

## v1.8n (owner: enemy mechs): `count` Assault Mechs on foot at a ground job's point. They walk the ground (never fly),
## turn to face you and fire their arm guns and chest cannon up at you; part of the wave (tagged with its stage).
## v1.8o (owner): the patrol over a planet sector: soldiers of the rival of the planet's owner (the same enemy its jobs
## are against), always hostile. A rival with nobody to send leaves the old patrol.
func _spawn_rival_patrol(center: Vector3, count: int) -> Array:
	var f := Missions.enemy_of(sys_id)
	var pool: Array = Factions.DEFS.get(f, {}).get("fighter_pool", [])
	if f == "" or (pool.is_empty() and roster_pick(f, Data.SURFACE_PATROL_SLOT).is_empty()): return _spawn_group(center, count)
	_group_serial += 1
	var out: Array = []
	for i in count:
		var soldier := roster_pick(f, Data.SURFACE_PATROL_SLOT)
		var kind: String = roster_fighter(soldier) if not soldier.is_empty() else str(pool[mini(i, pool.size() - 1)])
		var e := spawn_unit(kind, center + Vector3(_rng.randf_range(-60, 60), _rng.randf_range(-20, 20), _rng.randf_range(-60, 60)), center)
		e["group"] = _group_serial
		e["provoked"] = true
		if not soldier.is_empty(): assign_roster(e, soldier)
		else: _make_generic(e, f)
		out.append(e)
	return out

# ---------------------------------------------------------------- v1.8y planet map and bases
## Metres from this sector's centre to sector t's centre, the short way round the planet.
func surface_offset(t: int) -> Vector3:
	if not surface_mode: return Vector3.ZERO
	var g := Surface.grid(planet_id)
	var dx := t % g - tile % g
	var dz := t / g - tile / g
	if dx * 2 > g: dx -= g
	elif dx * 2 < -g: dx += g
	if dz * 2 > g: dz -= g
	elif dz * 2 < -g: dz += g
	return Vector3(dx * Surface.TILE, 0.0, dz * Surface.TILE)

## Every base on this planet, where it is from here: [{name, id, tile, x, z, pos}].
func base_spots() -> Array:
	var out: Array = []
	if not surface_mode: return out
	for l in Surface.PLANETS[planet_id].get("locations", []):
		var t := int(l["tile"])
		var lp: Vector2 = l["pos"]
		out.append({"name": str(l["name"]), "id": str(l.get("id", "")), "tile": t, "x": lp.x, "z": lp.y,
			"pos": surface_offset(t) + Vector3(lp.x, Surface.pad_top(planet_id, t) + 40.0, lp.y)})
	return out

## GO TO / the planet map: fly to a base anywhere on the planet (the marker is kept where the base is as you cross sectors).
var surf_goal := {}
var _surf_goal_node: Node3D = null
func set_surface_goal(spot: Dictionary) -> Node3D:
	surf_goal = spot.duplicate()
	if not is_instance_valid(_surf_goal_node):
		_surf_goal_node = Node3D.new()
		_surf_goal_node.set_meta("kind", "waypoint")
		_surf_goal_node.set_meta("radius", 30.0)
		add_child(_surf_goal_node)
	_surf_goal_node.name = str(spot.get("name", "Base"))
	autopilot = _surf_goal_node
	_place_surface_goal()
	return _surf_goal_node

func _place_surface_goal() -> void:
	if surf_goal.is_empty() or not is_instance_valid(_surf_goal_node): return
	if autopilot != _surf_goal_node:   # arrived, or you took the stick: forget it
		surf_goal = {}
		return
	var t := int(surf_goal["tile"])
	_surf_goal_node.global_position = surface_offset(t) + Vector3(float(surf_goal["x"]), Surface.pad_top(planet_id, t) + 60.0, float(surf_goal["z"]))

func nearest_base() -> Dictionary:
	var best := {}
	var bd := INF
	for b in base_spots():
		var d: float = (b["pos"] as Vector3).distance_to(player.global_position)
		if d < bd:
			bd = d
			best = b
	return best

func _sea_at(x: float, z: float) -> bool:
	return surface_mode and _water and _ground(x, z) <= 0.05

func spawn_ground_mechs(at: Vector3, faction: String, count: int, stage: int, bosses := 0) -> Array:
	var out: Array = []
	var mkey := faction_mech(faction)   # v1.9i: the faction's own mech; the first `bosses` of them are its boss
	for i in count:
		var a := TAU * float(i) / float(maxi(1, count)) + _rng.randf() * 0.8
		var p := at + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(60.0, 130.0)
		for k in (8 if surface_mode else 0):   # on dry land when there is some near
			if not _sea_at(p.x, p.z): break
			p = at + Vector3(cos(a + k * 0.8), 0, sin(a + k * 0.8)) * (130.0 + 60.0 * k)
		p.y = (_ground(p.x, p.z) if surface_mode else at.y) + Data.WALKER_STAND   # (v1.9i: in space they stand on nothing)
		var boss: bool = i < bosses
		if boss: p.y += Data.WALKER_STAND * (Data.MECH_BOSS_SCALE - 1.0)
		var e := spawn_unit("mech_boss" if boss else "mech", p, p, mkey, Data.MECH_BOSS_SCALE if boss else 1.0)
		e["walker"] = true
		if boss:
			e["stand_k"] = Data.MECH_BOSS_SCALE
			e["boss_mech"] = true
		e["group"] = _group_serial
		e["mission"] = stage
		e["provoked"] = true
		_make_generic(e, faction)
		e["node"].name = ("%s Boss Mech %d" if boss else "%s Ground Mech %d") % [faction, _enemy_serial]
		out.append(e)
	return out

## v1.5f: the most senior pick a few draws give (roster_pick leans to slot 01; a senior job wants the slot asked for).
func _pick_senior(faction: String, max_slot: int, want: int) -> Dictionary:
	if want >= 5:   # the elite soldier (slot 05 is a rank, not one person: always there to send)
		for p in Data.ROSTERS.get(faction, {}).get("pilots", []):
			if int(p.get("slot", 0)) == want and not p.get("named_unique", false) and Data.ENEMIES.has(str(p.get("fighter_primary", ""))): return p
	var best: Dictionary = {}
	for k in 14:
		var p := roster_pick(faction, max_slot)
		if p.is_empty(): break
		if best.is_empty() or int(p.get("slot", 0)) > int(best.get("slot", 0)): best = p
		if int(best.get("slot", 0)) >= want: break
	if int(best.get("slot", 0)) < want:   # v1.7v: the draws came up short: an elite job still sends seniors, as its card says
		for sl in range(max_slot, want - 1, -1):
			for p in Data.ROSTERS.get(faction, {}).get("pilots", []):
				if int(p.get("slot", 0)) == sl and not p.get("named_unique", false) and Data.ENEMIES.has(str(p.get("fighter_primary", ""))): return p
	return best

## v1.5g SHIP SCAN: what a scan of this ship shows: {title, sub, lines: [[label, text]], hostile}. {} = not a ship.
## Cargo is made up from the ship's name (the same every scan) from Data.SCAN_GOODS / SCAN_ENEMY_GOODS; a bounty target
## shows its price, a mission ship its job.
func scan_info(n: Node3D) -> Dictionary:
	if n == null or not is_instance_valid(n): return {}
	var h := absi(hash(n.name))
	var e := _enemy_entry(n)
	if not e.is_empty():
		var d: Dictionary = e["def"]
		var pl: Dictionary = e.get("pilot", {})
		var who := "Unknown pilot"
		if pl.has("character_id"): who = "%s — %s (slot %02d)" % [pl["name"], pl.get("type", ""), int(pl.get("slot", 1))]
		elif not pl.is_empty(): who = "%s — %s, %s's wing" % [pl.get("unit", "?"), pl.get("type", "pilot"), pl.get("leader", "?")]
		var guns: Array = []
		if float(e["l"]) > 0.0: guns.append("left %s gun" % ("arm" if e["mech"] else "wing"))
		else: guns.append("left %s DESTROYED" % ("arm" if e["mech"] else "wing"))
		if float(e["r"]) > 0.0: guns.append("right %s gun" % ("arm" if e["mech"] else "wing"))
		else: guns.append("right %s DESTROYED" % ("arm" if e["mech"] else "wing"))
		if e["mech"]: guns.append("chest cannon")
		if d.get("missiles", false): guns.append("missile rack")
		var fac := str(e.get("faction", d.get("faction", "")))
		var goods: Array = Data.SCAN_ENEMY_GOODS.get(fac, ["Scrap metal", "Munitions"])
		var cargo: Array = ["%s %d t" % [goods[h % goods.size()], 2 + h % 9]]
		if h % 3 == 0: cargo.append("%s %d t" % [Data.SCAN_GOODS[(h / 3) % Data.SCAN_GOODS.size()], 1 + (h / 7) % 6])
		cargo.append("credits on board ~%d cr" % maxi(10, int(float(d.get("reward", 100)) * 0.4)))
		var lines: Array = [["PILOT", who], ["SHIP", "%s (%s)" % [d.get("name", n.name), d.get("class", "fighter")]],
			["HULL", "%d / %d   shield %d / %d" % [int(e["hp"]), int(e["max"]), int(e["sh"]), int(e["sh_max"])]],
			["WEAPONS", ", ".join(guns)], ["CARGO", ", ".join(cargo)]]
		if e.has("bounty"): lines.append(["WANTED", "%d cr bounty" % Data.bounty_reward(str(e["bounty"]))])
		if e.has("mission"): lines.append(["JOB", "a target of your mission"])
		var hostile: bool = n.get_meta("kind", "") == "enemy"
		return {"title": n.name.to_upper(), "sub": "%s  ·  %s" % [fac if fac != "" else "Unaligned", "HOSTILE" if hostile else "not hostile"], "lines": lines, "hostile": hostile}
	var is_traffic: bool = n.get_meta("kind", "") == "traffic"
	if is_traffic:
		var cargo2: Array = []
		for k in 2 + h % 2: cargo2.append("%s %d t" % [Data.SCAN_GOODS[(h / (k + 1) + k * 3) % Data.SCAN_GOODS.size()], 10 + (h / (k + 2)) % 60])
		var lines2: Array = [["SHIP", "Civilian hauler"], ["WEAPONS", "none"], ["CARGO", ", ".join(cargo2)]]
		if n == escort_node: lines2.append(["JOB", "escort this ship (hull %d%%)" % int(100.0 * float(GS.mission.get("escort_hp", 0.0)) / Data.ESCORT_HULL)])
		return {"title": n.name.to_upper(), "sub": "%s  ·  civilian" % str(sys.get("faction", "")), "lines": lines2, "hostile": false}
	return {}

## v1.5g: the ship drawn nearest a screen point (enemies, traffic), within SHIP_TAP_RADIUS. null = none.
func ship_at_screen(p: Vector2, radius := -1.0) -> Node3D:
	var best: Node3D = null
	var best_d: float = Data.SHIP_TAP_RADIUS if radius < 0.0 else radius
	var nodes: Array = []
	for e in enemies: nodes.append(e["node"])
	for t in traffic: nodes.append(t["node"])
	if is_instance_valid(escort_node): nodes.append(escort_node)
	for n in nodes:
		if not is_instance_valid(n) or cam.is_position_behind(n.global_position): continue
		var d := cam.unproject_position(n.global_position).distance_to(p)
		if d < best_d:
			best_d = d
			best = n
	return best

## v1.5f: the escort mission's freighter, at the station's dock point, heading for the planet.
func make_escort(from := Vector3.INF, goal := Vector3.INF) -> void:   # v1.7w: the cargo run gives its own ends
	if is_instance_valid(escort_node) or not is_instance_valid(station) or not is_instance_valid(planet): return
	var node := Node3D.new()
	node.name = "Freighter %s (escort)" % sys["name"]
	node.add_child(ShipFactory.build("fleet" if ShipFactory.has_real_model("fleet") else "enemy"))
	node.set_meta("kind", "traffic")
	node.set_meta("radius", 12.0)
	add_child(node)
	var a := dock_point(station) + Vector3(0, 60, 0) if from == Vector3.INF else from
	var b := planet_dock_point() if goal == Vector3.INF else goal
	node.global_position = a
	node.set_meta("goal", b)
	node.set_meta("trip", a.distance_to(b))
	escort_node = node

func planet_dock_point() -> Vector3:
	return dock_point(planet) + Vector3(0, 60, 0)

# ---------------------------------------------------------------- v1.5o SPECIAL lock-on super move (docs/SPECIAL_MOVE.md)
var special_held := false       # the SPECIAL button is held (the HUD sets it)
var special_state := "idle"     # idle | charging | cutin | beam
var special_t := 0.0            # time in the current state
var special_target: Node3D = null
var special_roll := 0.0         # the model's roll angle during the charge
var special_which := ""         # which earned special this is: "half" | "crit"
var special_log: Array = []     # what happened, in order (tests)
var _special_left := 0          # missiles of the special swarm still to launch (they steer harder)
var _special_break_t := 0.0
var special_locks := 0          # v1.9b: missile locks the special has built (the swarm = locks x launchers)
var _special_lock_t := 0.0
var _special_was_held := false
var _special_was_held_prev := false
var missiles_expired := 0       # player missiles that ran out of life and burst (tests)
var decoyed := 0                # enemy missiles that hit one of your mines (tests)
var _beam: MeshInstance3D = null

## Which earned special is ready ("half" / "crit" / ""): hull at or under half (then critical), not yet spent.
func special_ready() -> String:
	var k: float = GS.hull / maxf(GS.max_hull(), 1.0)
	if k > Data.SPECIAL_RESET_AT and (GS.special_used["half"] or GS.special_used["crit"]): GS.special_used = {"half": false, "crit": false}
	if k <= Data.SPECIAL_ARM_AT[1] and not GS.special_used["crit"]: return "crit"
	if k <= Data.SPECIAL_ARM_AT[0] and not GS.special_used["half"]: return "half"
	return ""

func _special_locked_on(t: Node3D) -> bool:
	return t != null and is_instance_valid(t) and t.get_meta("kind", "") == "enemy" and _cone(t, Data.SPECIAL_CONE_DEG, Data.SPECIAL_RANGE)

## v1.5p: this ship's own special move (Data.SHIP_SPECIAL_MOVE by model key): "wings_out" or "roll".
func special_move() -> String:
	if GS.form == "mech": return "roll"
	return str(Data.SHIP_SPECIAL_MOVE.get(str(GS.ship().get("model", "")), "roll"))

var special_power := 1.0   # v1.9c: how charged the special was when let go (0..1): scales the beam's hull damage

## v1.9c: a full charge = a full rack of light-missile locks (at least one).
func special_full() -> int:
	return maxi(1, mini(GS.max_locks("light_missile"), maxi(GS.missiles, 1)))

## v1.9c: how charged the special is now (0..1).
func special_charge() -> float:
	if special_state == "charging": return float(special_locks) / float(special_full())
	return special_power if special_state != "idle" else 0.0

## v1.9c: the beam's strength from the charge: SPECIAL_MIN_POWER on a quick tap, 1.0 fully charged.
func special_factor() -> float:
	return lerpf(Data.SPECIAL_MIN_POWER, 1.0, special_power)

## v1.9c: what the special will hit: your target if it is a hostile in range, else the nearest hostile in range.
func _special_pick() -> Node3D:
	if target != null and is_instance_valid(target) and target.get_meta("kind", "") == "enemy" and target.global_position.distance_to(player.global_position) <= Data.SPECIAL_RANGE: return target
	return _nearest_enemy(Data.SPECIAL_RANGE)

## v1.9c: turn the ship (or the mech, on its feet) to look along `dir`.
func _special_face(dir: Vector3) -> void:
	if GS.form == "mech":
		yaw = atan2(-dir.x, -dir.z)
		player.basis = Basis.from_euler(Vector3(pitch, yaw, 0))
	else: _face(dir)

func _update_special(dt: float) -> void:
	special_t += dt
	var was := _special_was_held
	_special_was_held = special_held
	_special_was_held_prev = was
	if is_instance_valid(model) and ShipFactory.wings_open(model) >= 0.0:   # v1.5p: folding wings swing out for the special
		var want := 1.0 if special_state != "idle" and special_move() == "wings_out" else 0.0
		var k := ShipFactory.wings_open(model)
		if not is_equal_approx(k, want): ShipFactory.set_wings(model, move_toward(k, want, dt * Data.WINGS_OPEN_RATE))
	match special_state:
		"idle":
			var pressed := special_held and not _special_was_held_prev
			if pressed and controls and warp_state == "off" and special_ready() != "":
				var t := _special_pick()
				if t == null:
					message.emit("SPECIAL: no hostile in range.")
				else:
					special_state = "charging"
					special_t = 0.0
					special_target = t
					target = t
					special_locks = 0
					_special_lock_t = 0.0
					special_which = special_ready()
					special_log.append("charge")
					message.emit("SPECIAL CHARGING: hold for more missiles, let go to fire")
					Sfx.play("warp_spool", -6.0)
			elif pressed and controls and warp_state == "off" and special_ready() == "": _man_press()   # v1.9l (owner): locked = evasive moves
		"charging":
			# v1.9c (owner): HOLD to charge: the ship does NOT turn while you hold, you fly it yourself. The charge builds
			# a missile lock every LOCK_STEP (no aiming needed) up to a full rack: the longer you hold, the more missiles
			# and the harder the beam. LET GO: the ship turns itself to face the target and fires; the beam always hits.
			special_roll += dt * TAU / Data.SPECIAL_ROLL_TIME
			if special_target == null or not is_instance_valid(special_target) or not (special_target in enemies.map(func(o): return o["node"])):
				special_target = _special_pick()   # (the target died: the next one in range)
				if special_target != null: target = special_target
			var full := special_full()
			_special_lock_t += dt
			if _special_lock_t >= Data.LOCK_STEP and special_locks < full:
				_special_lock_t = 0.0
				special_locks += 1
				Sfx.play("button", -8.0)   # a lock tick
			var k := special_charge()
			_booster_particles(dt, k)   # energy building round the weapons
			if int(time * 20.0) % 2 == 0: _spark(player.global_position + player.global_basis.x * (2.5 if randf() < 0.5 else -2.5) - player.global_basis.z * 2.0, Color(0.5, 0.85, 1.0).lerp(Color(1, 1, 1), k), 2.0 + 4.0 * k, 0.2)
			if not special_held:
				if special_target == null:
					_special_end("SPECIAL: no hostile in range. The special is still ready.")
					special_log.append("no_target")
					return
				special_locks = maxi(special_locks, 1)   # (a quick tap still fires: one lock)
				special_power = float(special_locks) / float(full)
				special_state = "turning"
				special_t = 0.0
				special_roll = 0.0
				target = special_target
				special_log.append("turn")
		"turning":   # v1.9c: on release the ship swings round to face the target by itself, then fires
			if not is_instance_valid(special_target):
				_special_end("SPECIAL: the target is gone. The special is still ready.")
				special_log.append("no_target")
				return
			var want := special_target.global_position - player.global_position
			if GS.form == "mech": want.y = 0.0   # (a mech turns on its feet)
			if want.length() < 0.1:
				_special_fire()
				return
			want = want.normalized()
			var cur := -player.global_basis.z
			if GS.form == "mech": cur = Vector3(cur.x, 0.0, cur.z).normalized()
			if cur.angle_to(want) <= deg_to_rad(Data.SPECIAL_FACE_DEG) or special_t >= Data.SPECIAL_TURN_TIME:
				_special_face(want)
				_special_fire()
			else:
				_special_face(cur.slerp(want, clampf(dt * Data.SPECIAL_TURN_RATE, 0.0, 1.0)).normalized())
		"cutin":
			if special_t >= Data.SPECIAL_CUTIN_TIME: _special_beam()
		"beam":
			if is_instance_valid(_beam):
				var mat := _beam.material_override as StandardMaterial3D
				mat.albedo_color.a = clampf(1.0 - special_t / Data.SPECIAL_BEAM_TIME, 0.0, 1.0)
				if is_instance_valid(special_target): _aim_beam(special_target.global_position)
			if special_t >= Data.SPECIAL_BEAM_TIME: _special_swarm()

# ---------------------------------------------------------------- v1.9l: SPECIAL manoeuvres (while the special is locked)
## Owner: "special doesn't do anything until you're in danger": until it arms, a tap of SPECIAL is an evasive move,
## picked by the stick: none or up = climb with a barrel roll (nose up, then level out); forward (left stick) =
## a forward burst with a roll; left / right = a barrel roll to that side; down = a dive with a roll. Tap again
## during a climb or a dive = a U-turn: the ship swings round and the chase camera swings with it.
var man_kind := ""      # "" | climb | dive | fwd | left | right | uturn
var man_t := 0.0
var man_roll := 0.0
var man_dir := 1.0
var man_yaw0 := 0.0
var man_log: Array = []
func man_pick() -> String:
	var a := aim
	var m := move
	if absf(a.x) > 0.5 and absf(a.x) >= absf(a.y): return "left" if a.x < 0.0 else "right"
	if absf(m.x) > 0.5 and absf(m.x) >= absf(m.y) and a.length() < 0.3: return "left" if m.x < 0.0 else "right"
	if a.y > 0.5: return "dive"
	if a.y < -0.5: return "climb"
	if m.y > 0.4: return "fwd"
	if m.y < -0.4: return "dive"
	return "climb"
func _man_press() -> void:
	if GS.form == "mech" or transform_t > 0.0 or not lane.is_empty(): return
	if man_kind == "climb" or man_kind == "dive":
		_man_start("uturn")
		return
	if man_kind != "" and man_kind != "uturn" and man_t < Data.MAN_TIME * 0.5: return
	_man_start(man_pick())
func _man_start(k: String) -> void:
	man_kind = k
	man_t = 0.0
	man_dir = -1.0 if k == "left" else 1.0
	man_yaw0 = yaw
	autopilot = null   # (your hands are on it)
	man_log.append(k)
	Sfx.play("warp_go", -10.0)
	message.emit({"climb": "CLIMB!", "dive": "DIVE!", "fwd": "BURST!", "left": "ROLL LEFT!", "right": "ROLL RIGHT!", "uturn": "U-TURN!"}[k])
func _man_update(dt: float) -> void:
	man_t += dt
	var d: float = Data.MAN_UTURN_TIME if man_kind == "uturn" else Data.MAN_TIME
	var k := clampf(man_t / d, 0.0, 1.0)
	var e := k * k * (3.0 - 2.0 * k)
	var b := player.global_basis
	var acc: float = Data.MAN_BOOST / d * 2.0 * (1.0 - k)   # (a burst that fades out)
	match man_kind:
		"climb", "dive":
			var sgn := 1.0 if man_kind == "climb" else -1.0
			if k < 0.55: pitch = clampf(pitch + sgn * deg_to_rad(Data.MAN_PITCH_DEG) / (0.55 * d) * dt, -PI * 0.45, PI * 0.45)
			else: pitch = lerp_angle(pitch, 0.0, minf(1.0, dt * Data.MAN_SETTLE))   # then it levels out, facing forward
			vel += Vector3.UP * sgn * acc * dt
		"fwd": vel += -b.z * acc * dt
		"left", "right": vel += b.x * man_dir * acc * dt
		"uturn":
			yaw = man_yaw0 + PI * e   # (exactly half a turn)
			pitch = lerp_angle(pitch, 0.0, minf(1.0, dt * Data.MAN_SETTLE))
			vel = vel.lerp(-player.global_basis.z * vel.length(), minf(1.0, dt * 4.0))
	man_roll = -man_dir * TAU * e
	if k >= 1.0:
		man_kind = ""
		man_roll = 0.0

func _special_end(said: String) -> void:
	special_state = "idle"
	special_t = 0.0
	special_roll = 0.0
	_special_lock_t = 0.0
	if said != "": message.emit(said)

## Lock complete and released: the special is spent; the cut-in plays (the game keeps running under it).
func _special_fire() -> void:
	GS.special_used[special_which] = true
	special_state = "cutin"
	special_t = 0.0
	special_roll = 0.0
	special_log.append("cutin")
	Sfx.play("warp_go", -3.0)

## The energy blast: unavoidable once the lock is complete. Shields stripped, overflow into the hull; a hard side
## hit takes that wing off.
func _special_beam() -> void:
	special_state = "beam"
	special_t = 0.0
	special_log.append("beam")
	if not is_instance_valid(special_target):
		return
	_beam = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = Data.SPECIAL_BEAM_WIDTH
	cm.bottom_radius = Data.SPECIAL_BEAM_WIDTH * 0.6
	cm.height = 1.0
	_beam.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(0.55, 0.85, 1.0, 1.0)
	_beam.material_override = mat
	add_child(_beam)
	_aim_beam(special_target.global_position)
	Sfx.play("explosion", -2.0)
	var rbs := _ray_blocks(player.global_position, special_target.global_position) if surface_mode else [null, Vector3.INF]
	var bfs: BlockField = rbs[0]
	var dig: Vector3 = rbs[1]
	if dig != Vector3.INF:   # EXPERIMENT (v1.5t): a beam through the block ground blows a crater you can fly into
		_blast_blocks(dig, "special", bfs)
		_blast(dig, Data.BLAST_DEATH, "ground")
	var e := _enemy_entry(special_target)
	if e.is_empty(): return
	var dir := (special_target.global_position - player.global_position).normalized()
	var side_dot := dir.dot(special_target.global_basis.x)
	var hit_side := ""
	if absf(side_dot) > Data.SPECIAL_SIDE_HIT: hit_side = "l" if side_dot > 0.0 else "r"   # struck from the right = the beam lands on its right... (it enters the side facing you)
	var dmg: float = float(e["sh"]) + float(e["max"]) * Data.SPECIAL_BEAM_OVERFLOW * special_factor()   # v1.9c: shields always go; the hull damage grows with the charge
	if e["def"].get("capital", false): dmg = float(e["sh"]) + Data.CAPITAL_SPECIAL_DAMAGE * special_factor()   # v1.9n: a set amount on a capital ship
	e["sh_cd"] = 6.0   # the shield stays down for a while
	_damage_enemy(e, dmg)
	if hit_side != "" and e in enemies and float(e[hit_side]) > 0.0:
		_break_section(e, hit_side)
		special_log.append("wing_" + hit_side)
	_spark(special_target.global_position, Color(0.7, 0.95, 1.0), 40.0, 0.5)

## v1.9b: stick input that swings the nose onto the special's target (full rate until close, then eases in).
func _aim_beam(to: Vector3) -> void:
	if not is_instance_valid(_beam): return
	var from := player.global_position - player.global_basis.z * 6.0
	var mid := (from + to) * 0.5
	var len := from.distance_to(to)
	var up := (to - from).normalized()
	var side := up.cross(Vector3.UP if absf(up.y) < 0.95 else Vector3.RIGHT).normalized()
	_beam.global_transform = Transform3D(Basis(side, up, side.cross(up)).scaled(Vector3(1.0, len, 1.0)), mid)

## The swarm right after the beam: your real light missiles, locks x identical launchers (the twin-launcher rule).
func _special_swarm() -> void:
	if is_instance_valid(_beam): _beam.queue_free()
	_beam = null
	special_log.append("swarm")
	var n: int = mini(maxi(special_locks, 1) * Data.SPECIAL_LAUNCHERS, GS.missiles)   # v1.9b: the locks you built
	if n > 0 and is_instance_valid(special_target) and special_target in enemies.map(func(o): return o["node"]):
		var keep_t := target
		target = special_target
		_special_left = n
		fire_volley(false, n)
		target = keep_t if is_instance_valid(keep_t) else special_target
		message.emit("SPECIAL: beam hit, %d missiles away." % n)
	elif n <= 0: message.emit("SPECIAL: beam hit. No missiles left for the swarm.")
	_special_end("")

## A missile out of life bursts into a round explosion zone.
## v1.7u (owner): a missile's blast: its radius shows as a white see-through shape (sphere; six-pointed star for the
## super missile), and every enemy inside takes splash, falling off to the edge (the one it hit already took full).
var blast_shapes := 0   # (tests) blast shapes shown
var blast_log: Array = []   # (tests) [radius, star, enemies splashed]
func missile_blast(at: Vector3, m: Dictionary, hit: Node3D) -> void:
	var heavy: bool = m.get("heavy", false)
	var r: float = Data.HEAVY_MISSILE_BLAST_RADIUS if heavy else Data.MISSILE_BLAST_RADIUS
	_blast_shape(at, r, heavy)
	var n := 0
	for e in enemies.duplicate():
		var en: Node3D = e["node"]
		if en == hit or not is_instance_valid(en): continue
		var d := en.global_position.distance_to(at)
		if d >= r: continue
		_damage_enemy(e, missile_damage(e, heavy, float(m.get("scale", 1.0))) * Data.MISSILE_SPLASH * (1.0 - d / r))
		n += 1
	blast_log.append([r, heavy, n])
	if blast_log.size() > 20: blast_log.pop_front()

var _blast_mat: StandardMaterial3D = null
func _blast_shape(at: Vector3, r: float, star: bool) -> void:
	if _blast_mat == null:
		_blast_mat = StandardMaterial3D.new()
		_blast_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_blast_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_blast_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_blast_mat.no_depth_test = false
		_blast_mat.albedo_color = Data.BLAST_SHAPE_COLOR
	var root := Node3D.new()
	root.name = "BlastShape"
	var mat := _blast_mat.duplicate() as StandardMaterial3D   # (each fades on its own)
	var core := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0 if not star else 0.55
	sm.height = sm.radius * 2.0
	sm.radial_segments = 24
	sm.rings = 12
	core.mesh = sm
	core.material_override = mat
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(core)
	if star:   # six spikes, one each way along three axes, the whole burst turned at random
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.38
		cone.height = 0.75
		cone.radial_segments = 12
		var dirs := [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]
		for k in mini(Data.BLAST_STAR_POINTS, dirs.size()):
			var sp := MeshInstance3D.new()
			sp.mesh = cone
			sp.material_override = mat
			sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var dv: Vector3 = dirs[k]
			var b := Basis.looking_at(dv, Vector3.FORWARD if absf(dv.y) > 0.9 else Vector3.UP) * Basis(Vector3.RIGHT, -PI * 0.5)
			sp.transform = Transform3D(b, dv * (0.55 + 0.75 * 0.5 - 0.05))
			root.add_child(sp)
		root.rotation = Vector3(_rng.randf() * TAU, _rng.randf() * TAU, _rng.randf() * TAU)
	add_child(root)
	root.global_position = at
	root.scale = Vector3.ONE * r * 0.15
	blast_shapes += 1
	var tw := root.create_tween()
	tw.tween_property(root, "scale", Vector3.ONE * r * (0.8 if star else 1.0), Data.BLAST_SHAPE_TIME * 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(mat, "albedo_color:a", 0.0, Data.BLAST_SHAPE_TIME).set_delay(Data.BLAST_SHAPE_TIME * 0.25)
	tw.tween_callback(root.queue_free)

func _expire_burst(at: Vector3) -> void:
	_spark(at, Color(1.0, 0.7, 0.3), 22.0, 0.45)
	_spark(at, Color(1.0, 0.95, 0.8), 10.0, 0.25)

var waypoint: Node3D = null   # the player's own map waypoint (radar map -> tap anywhere -> SET COURSE)

## Put the custom waypoint at a point in this system (one at a time) and return it.
func waypoint_at(p: Vector3) -> Node3D:
	if not is_instance_valid(waypoint):
		waypoint = Node3D.new()
		waypoint.name = "Waypoint"
		waypoint.set_meta("kind", "waypoint")
		waypoint.set_meta("radius", 30.0)
		add_child(waypoint)
	waypoint.global_position = p
	return waypoint

var corner_haze := 0.0   # 0..1 inside the wrap-corner cloud bank

## EXPERIMENT (v1.5v, changed v1.9b): the mech meets a block wall ahead (higher than a step). It can't walk into the
## wall, and (v1.9b) pushing no longer digs it. Before v1.9b the push dug it by the same rules as a shot: sand and dirt give way steadily (it plows on), stone breaks
## a hit at a time and shoves the mech back each push, obsidian doesn't break and just bounces it off. No damage, ever.
var _lava_t := 0.0
var _dig_cd := 0.0
var dig_log := {"soft": 0, "stone": 0, "bounce": 0, "blocked": 0}   # (tests)
func _mech_dig(dt: float) -> void:
	_dig_cd = maxf(0.0, _dig_cd - dt)
	if not is_instance_valid(player): return
	var hv := Vector3(vel.x, 0.0, vel.z)
	if hv.length() < 2.0: return
	var dir := hv.normalized()
	var p := player.global_position
	var q := p + dir * Data.MECH_DIG_REACH
	var bf := _block_field_at(q.x, q.z)   # (v1.7a: the region ahead)
	if bf == null: return
	var feet := p.y - 6.0   # (the ground keeps the player 6 m up)
	var body := feet + Data.MECH_DIG_STEP + 0.5
	if not (bf.is_solid(q.x, body, q.z) or bf.is_solid(q.x, p.y + 1.0, q.z)): return   # open ahead, or a step it walks up
	var into := hv.dot(dir)
	vel -= dir * into   # it can't walk into the wall
	if bf.is_solid(p.x, body, p.z):
		player.global_position -= dir * (into * dt + 0.5)   # already in it this frame: step back out
	# v1.9b (owner: "I'm just walking and breaking through the floor"): walking never breaks blocks any more. The wall
	# just stops you; the only way to break blocks is shooting them.
	if _dig_cd <= 0.0:
		dig_log["blocked"] = int(dig_log.get("blocked", 0)) + 1
		_dig_cd = Data.MECH_DIG_STONE_TICK

## EXPERIMENT: the block ground patch on this tile, if there is one (the route test's old 800 m patch).
func _block_field() -> BlockField:
	return tile_root.get_node_or_null("BlockField") as BlockField if is_instance_valid(tile_root) else null

## Every block field standing on this tile: the test patch, or (v1.7a) the regions built round you.
func _fields() -> Array:
	var out: Array = []
	if not is_instance_valid(tile_root): return out
	var tp := _block_field()
	if tp: out.append(tp)
	for r in _regions:
		var f: BlockField = _regions[r]
		if is_instance_valid(f): out.append(f)
	return out

## The block field under a tile-local point (null where the ground is the smooth sheet).
func _block_field_at(x: float, z: float) -> BlockField:
	if not is_instance_valid(tile_root): return null
	var tp := _block_field()
	if tp and tp.covers(x, z): return tp
	var f: BlockField = _regions.get(_region_key_at(x, z))
	return f if is_instance_valid(f) and f.covers(x, z) else null

## v1.7d: regions are keyed by which tile they belong to (relative to this one: -1, 0, 1 each way) and which square of
## it, so the blocks run on across a tile border: a neighbour's regions are built in this tile's frame.
func _region_key_at(x: float, z: float) -> Vector4i:
	var tdx := clampi(floori((x + Surface.EDGE) / Surface.TILE), -1, 1)
	var tdz := clampi(floori((z + Surface.EDGE) / Surface.TILE), -1, 1)
	var r := BlockField.region_of(x - tdx * Surface.TILE, z - tdz * Surface.TILE)
	return Vector4i(tdx, tdz, r.x, r.y)

func _key_tile(k: Vector4i) -> int:
	return tile if k.x == 0 and k.y == 0 else Surface.neighbour(planet_id, tile, Vector2i(k.x, k.y))

func _key_centre(k: Vector4i) -> Vector2:
	return BlockField.region_centre(Vector2i(k.z, k.w)) + Vector2(k.x, k.y) * Surface.TILE

## Where a shot from a to b first meets block ground: [field, point] ([null, INF] if it doesn't).
func _ray_blocks(a: Vector3, b: Vector3) -> Array:
	var best: BlockField = null
	var at := Vector3.INF
	var bd := INF
	for f in _fields():
		var hp: Vector3 = (f as BlockField).ray_hit(a, b)
		if hp != Vector3.INF and a.distance_to(hp) < bd:
			bd = a.distance_to(hp)
			best = f
			at = hp
	return [best, at]

## v1.7d: a blast digs every region it reaches (one right on a region edge digs both sides). Returns what the region
## that was hit broke (for sparks and sounds).
func _blast_blocks(at: Vector3, kind: String, hit: BlockField) -> Dictionary:
	var res: Dictionary = hit.blast(at, kind)
	var r: float = (Data.BLOCK_BLAST.get(kind, Data.BLOCK_BLAST["gun"]) as Array)[0]
	for f in _fields():
		var bf: BlockField = f
		if bf == hit: continue
		var half := bf.cols * Data.BLOCK_BIG * 0.5
		if absf(at.x - bf.center.x) < half + r and absf(at.z - bf.center.y) < half + r: bf.blast(at, kind)
	return res

func _over_blocks() -> bool:
	return is_instance_valid(player) and _block_field_at(player.global_position.x, player.global_position.z) != null

## v1.7a, step 9: the whole planet is blocks. The 500 m regions round you are built from the seed as you fly (the
## nearest missing one each frame) and freed once you are well away; the smooth sheet is cut out under each one, so
## from far off you see the smooth ground and close up you stand on blocks. Blasts and digging are kept per region.
var _regions := {}       # Vector4i(tile dx, tile dz, rx, rz) -> BlockField
## v1.7m underground light: the ship's flashlight (on under cover) and a few real lights at the nearest glowing things.
var flashlight: SpotLight3D
var flare: MeshInstance3D = null   # v1.8j: the lamp's glare
var underwater := false            # v1.8j: the camera is in water
var glow_lights: Array = []   # OmniLight3D pool
var _glow_t := 0.0
func _update_light(dt: float, bf: BlockField, p: Vector3) -> void:
	if flashlight == null and is_instance_valid(player):
		flashlight = SpotLight3D.new()
		flashlight.name = "Flashlight"
		var fl: Array = Data.FLASHLIGHT
		flashlight.light_color = fl[0]
		flashlight.light_energy = fl[1]
		flashlight.spot_range = fl[2]
		flashlight.spot_angle = fl[3]
		flashlight.shadow_enabled = false
		flashlight.visible = false
		player.add_child(flashlight)
		flashlight.position = Vector3(0, 0, -3)
	if flashlight:
		# v1.8j: under water (the camera in the blocks' water, or below the sea) the lamp is on, sea-green and shorter
		var cp: Vector3 = cam.global_position if is_instance_valid(cam) else p
		var cbf: BlockField = _block_field_at(cp.x, cp.z)
		underwater = (cbf != null and cbf.fluid_at(cp.x, cp.y, cp.z) == "water") or (_water and cp.y < -1.0 and Surface.height(planet_id, tile, cp.x, cp.z) < cp.y and (cbf == null or cbf.top_at(cp.x, cp.z) < cp.y))
		var fl: Array = Data.FLASHLIGHT_WATER if underwater else Data.FLASHLIGHT
		flashlight.light_color = fl[0]
		flashlight.light_energy = fl[1]
		flashlight.spot_range = fl[2]
		flashlight.spot_angle = fl[3]
		flashlight.visible = underwater or (bf != null and bf.ceiling_above(p.x, p.y - 6.0, p.z) < INF)   # under a roof: it comes on
		if flare == null:   # the glare at the lamp
			flare = MeshInstance3D.new()
			var q := QuadMesh.new()
			q.size = Vector2.ONE * float(Data.FLASHLIGHT_FLARE[1])
			flare.mesh = q
			var fm := _glow_mat(Data.FLASHLIGHT_FLARE[0]).duplicate() as StandardMaterial3D
			fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
			flare.material_override = fm
			flare.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			flashlight.add_child(flare)
			flare.position = Vector3(0, 0, -0.6)
		flare.visible = flashlight.visible and not (GS.view == "cockpit")
	_glow_t -= dt
	if _glow_t > 0.0: return
	_glow_t = 0.3
	var pts: Array = []
	for f in _fields():
		var bfg: BlockField = f
		if Vector2(bfg.center.x - p.x, bfg.center.y - p.z).length() > Data.GLOW_REACH + Data.BLOCK_REGION: continue   # (v1.7q: only the near ones)
		pts.append_array(bfg.glow_points(p, Data.GLOW_REACH))
	pts.sort_custom(func(a, b): return p.distance_squared_to(a[0]) < p.distance_squared_to(b[0]))
	while glow_lights.size() < Data.GLOW_LIGHTS and not pts.is_empty():
		var ol := OmniLight3D.new()
		ol.shadow_enabled = false
		ol.visible = false
		add_child(ol)
		glow_lights.append(ol)
	for i in glow_lights.size():
		var ol: OmniLight3D = glow_lights[i]
		if i >= pts.size():
			ol.visible = false
			continue
		var spec: Array = Data.GLOW_LIGHT.get(str(pts[i][1]), Data.GLOW_LIGHT["lava"])
		ol.global_position = pts[i][0]
		ol.light_color = spec[0]
		ol.light_energy = spec[1]
		ol.omni_range = spec[2]
		ol.set_meta("kind", pts[i][1])
		ol.visible = true
var region_ms := 0.0     # how long the last region took to build (ms, tests)
var regions_built := 0   # (tests)
var _building: BlockField = null   # the region being built now (outside the tree until it's done)
var _building_key := Vector4i.ZERO
var _build_t0 := 0
func _update_regions() -> void:
	if not BlockField.regions_on() or sun_surface or not is_instance_valid(tile_root) or not is_instance_valid(player): return
	var p := player.global_position
	var pp := Vector2(p.x, p.z)
	var changed := false
	var reach := (Data.BLOCK_REGION_KEEP + 0.5) * Data.BLOCK_REGION
	for k in _regions.keys():
		var c := _key_centre(k)
		if maxf(absf(c.x - pp.x), absf(c.y - pp.y)) > reach or not is_instance_valid(_regions[k]):
			if is_instance_valid(_regions[k]): (_regions[k] as Node).queue_free()
			_regions.erase(k)
			changed = true
	var best := Vector4i.ZERO
	var found := false
	var bd := 1e18
	for dz in range(-Data.BLOCK_REGION_REACH, Data.BLOCK_REGION_REACH + 1):
		for dx in range(-Data.BLOCK_REGION_REACH, Data.BLOCK_REGION_REACH + 1):
			var k := _region_key_at(p.x + dx * Data.BLOCK_REGION, p.z + dz * Data.BLOCK_REGION)
			if _regions.has(k): continue
			var d := _key_centre(k).distance_squared_to(pp)
			if d < bd:
				bd = d
				best = k
				found = true
	if _building != null:   # one region at a time, built a little each frame
		if _building.built:
			tile_root.add_child(_building)
			_building.mined.connect(_on_mined)
			_regions[_building_key] = _building
			region_ms = (Time.get_ticks_usec() - _build_t0) / 1000.0
			regions_built += 1
			_building = null
			changed = true
	elif found:
		_building = BlockField.new()
		_building_key = best
		_build_t0 = Time.get_ticks_usec()
		_building.build(planet_id, _key_tile(best), Vector2i(best.z, best.w), true, Vector2(best.x, best.y) * Surface.TILE)
	if changed: _set_cuts()

## Build one of this tile's regions now, all at once (tests).
func _build_region(r: Vector2i) -> BlockField:
	var t0 := Time.get_ticks_usec()
	var bf := BlockField.new()
	bf.build(planet_id, tile, r)
	tile_root.add_child(bf)
	bf.mined.connect(_on_mined)
	_regions[Vector4i(0, 0, r.x, r.y)] = bf
	region_ms = (Time.get_ticks_usec() - t0) / 1000.0
	regions_built += 1
	return bf

## Tell the tile's smooth ground where not to draw (under every region standing now): a small mask, one texel per
## 500 m region over this tile and its eight neighbours (v1.7q).
var cut_count := 0   # (tests)
func _set_cuts() -> void:
	var terr := tile_root.get_node_or_null("Terrain") as MeshInstance3D if is_instance_valid(tile_root) else null
	var sm := terr.material_override as ShaderMaterial if terr else null
	if sm == null: return
	var nr := int(round(Surface.TILE / Data.BLOCK_REGION))
	var side := nr * 3
	var img := Image.create(side, side, false, Image.FORMAT_L8)
	img.fill(Color(0, 0, 0))
	cut_count = 0
	for k in _regions:
		if not is_instance_valid(_regions[k]): continue
		var kv: Vector4i = k
		img.set_pixel((kv.x + 1) * nr + kv.z, (kv.y + 1) * nr + kv.w, Color(1, 1, 1))
		cut_count += 1
	sm.set_shader_parameter("cut_mask", ImageTexture.create_from_image(img))
	sm.set_shader_parameter("cut_area", Vector4(-Surface.EDGE - Surface.TILE, -Surface.EDGE - Surface.TILE, Data.BLOCK_REGION, side))

func _ground(x: float, z: float) -> float:
	var h := Surface.height(planet_id, tile, x, z)
	if _water: h = maxf(h, 0.0)
	var bf := _block_field_at(x, z)
	if bf: h = bf.top_at(x, z)
	var isl := Surface.island_at(planet_id, tile, x, z)   # v1.7c: the floating pad island
	if not isl.is_empty(): h = maxf(h, float(isl[0]))   # EXPERIMENT: the big blocks are the ground there
	return h

## Ground contact, tile edges (wrap to the next tile) and the ceiling (back to orbit).
func _surface_update(_dt: float) -> void:
	_place_surface_goal()   # v1.8y
	if GS.form == "mech": _mech_dig(_dt)   # EXPERIMENT (v1.5v): the mech digs into block walls by pushing
	var p := player.global_position
	_update_regions()
	var bfp := _block_field_at(p.x, p.z)
	var on_blocks := bfp != null
	var floor_y := (bfp.ground_for(p.x, p.y - 6.0, p.z) if on_blocks else _ground(p.x, p.z)) + 6.0   # v1.5y: tunnel floors
	var isl := Surface.island_at(planet_id, tile, p.x, p.z)   # v1.7c: land on the pad island from above; under it, it's a roof
	if not isl.is_empty():
		if p.y - 6.0 > (float(isl[0]) + float(isl[1])) * 0.5: floor_y = maxf(floor_y, float(isl[0]) + 6.0)
		elif p.y > float(isl[1]) - 1.5:
			player.global_position.y = float(isl[1]) - 1.5
			p = player.global_position
			if vel.y > 0.0: vel.y = 0.0
	altitude = p.y - floor_y + 6.0
	if ground_mode and grounded and vel.y <= 0.5 and p.y > floor_y and p.y - floor_y < Data.GROUND_STICK:   # v1.8r: walking downhill it keeps its feet on the ground
		player.global_position.y = floor_y
		p = player.global_position
		vel.y = 0.0
	grounded = ground_mode and p.y <= floor_y + 0.6 and vel.y <= 0.5   # v1.8r
	if p.y < floor_y:
		var impact := -vel.y
		player.global_position.y = floor_y
		if vel.y < 0.0: vel.y = 0.0
		if not ground_mode: collision_damage("ground", impact)   # Job L (was: > 20 m/s, 0.25 x impact through the shields); v1.8r: GROUND mode lands without a scratch
	for bx: Array in surf_boxes:   # v1.9q: the faction buildings are solid
		if is_instance_valid(bx[0]): _push_out_box(bx[0], bx[1], "ground")
	for fl in _fields(): (fl as BlockField).fluid_update(_dt, player.global_position)   # v1.6b: water and lava move near you
	_update_light(_dt, bfp, p)   # v1.7m
	if bfp:   # lava burns
		if on_blocks and controls and bfp.fluid_at(p.x, p.y, p.z) == "lava":
			_lava_t += _dt
			if _lava_t >= 0.5:
				_lava_t = 0.0
				_player_hit(Data.LAVA_DPS * 0.5, p)
				message.emit("LAVA! Get out!")
	if on_blocks and controls and bfp.touches_kill(player.global_position - Vector3(0, 6.0, 0)):   # v1.6d: the kill floor
		message.emit("You touched the kill floor.")
		GS.hull = 0.0
		_explode(player.global_position)
		controls = false
		_die()
		return
	if on_blocks:   # v1.5y: the roof of a tunnel or cave holds you down
		var roof := bfp.ceiling_above(p.x, player.global_position.y - 6.0, p.z)
		if player.global_position.y > roof - 1.5:
			player.global_position.y = maxf(floor_y, roof - 1.5)
			if vel.y > 0.0: vel.y = 0.0
	for e in enemies:
		if e.get("walker", false): continue   # v1.8n: mechs on foot keep to the ground themselves
		var n: Node3D = e["node"]
		var ef := _ground(n.global_position.x, n.global_position.z) + 30.0
		if n.global_position.y < ef: n.global_position.y = ef
	# build the sector(s) ahead a few rows per frame, so crossing the border needs no loading pause
	var ahead: Array = []
	if p.x > Surface.EDGE - 1600.0: ahead.append(Vector2i(1, 0))
	if p.x < -Surface.EDGE + 1600.0: ahead.append(Vector2i(-1, 0))
	if p.z > Surface.EDGE - 1600.0: ahead.append(Vector2i(0, 1))
	if p.z < -Surface.EDGE + 1600.0: ahead.append(Vector2i(0, -1))
	if ahead.size() == 2: ahead.append(ahead[0] + ahead[1])
	for d in ahead:
		var nt := Surface.neighbour(planet_id, tile, d)
		if not _prepared.get(nt, false):
			_prepared[nt] = Surface.prepare(planet_id, nt, 6)
			break   # one sector's rows per frame
	# the wrap-corner cloud bank: haze when you fly into it
	corner_haze = 0.0
	for c in _corners:
		corner_haze = maxf(corner_haze, clampf((1100.0 - Vector2(p.x, p.z).distance_to(c)) / 600.0, 0.0, 1.0))
	if surf_busy or not controls: return
	if p.x > Surface.EDGE: tile_edge.emit(Vector2i(1, 0))
	elif p.x < -Surface.EDGE: tile_edge.emit(Vector2i(-1, 0))
	elif p.z > Surface.EDGE: tile_edge.emit(Vector2i(0, 1))
	elif p.z < -Surface.EDGE: tile_edge.emit(Vector2i(0, -1))
	elif p.y > Surface.CEILING: leave_atmosphere.emit()

## Cross into the neighbouring tile and move the player to the opposite edge, keeping heading and speed. The ground
## is continuous across borders, so with the next sector already built this is seamless: nearby ships, shots and
## loot come along, and the camera moves with the player instead of jumping.
func shift_tile(dir: Vector2i) -> void:
	var t := Surface.neighbour(planet_id, tile, dir)
	var off := Vector3(dir.x, 0, dir.y) * Surface.TILE
	load_tile(t, off)
	player.global_position -= off
	cam.global_position -= off

func pulse_lights(t: float) -> void:
	pass

# ---------------------------------------------------------------- v1.9n SILVER: the enemy faction's fleet invasion
## Owner: "it should feel like an actual war, where players need allies and coordinated attacks to win." Solo for now
## with AI allies (no game server yet); built so other players' ships could later join as more allies.
var allies: Array = []        # {node, model, hp, max, vel, cd, kind ("fighter"/"frigate"), hit_r, foe (enemy dict), strafe}
var _inv_wave_t := 0.0
var inv_here := false         # the fleet was brought in in THIS system visit
var inv_log: Array = []       # (tests) what the invasion did: "spawn", "wave", "station_down", "won"

## The enemy pieces of the invasion still flying, by role ("battleship", "warship", "destroyer", "command", "fighter").
func invasion_units(role := "") -> Array:
	return enemies.filter(func(o): return o.get("invasion", false) and is_instance_valid(o["node"]) and (role == "" or str(o.get("inv_role", "")) == role))

## Bring the fleet in at `at`: the big ships spread round the point, the station behind them, the first fighters, and
## your allies beside you. `left` = how many battleships are still to kill (a fleet you flew away from comes back as it was).
func spawn_invasion(at: Vector3, faction: String, left: int, station_up: bool) -> void:
	var cfg: Dictionary = Data.INVASION
	var spread: float = cfg["spread"]
	var roles: Array = []
	for i in left: roles.append(["battleship", "inv_battleship"])
	for i in int(cfg["warships"]): roles.append(["warship", "inv_warship"])
	for i in int(cfg["destroyers"]): roles.append(["destroyer", "inv_destroyer"])
	var k := 0
	for r in roles:
		var ang := TAU * float(k) / float(roles.size())
		var p: Vector3 = at + Vector3(cos(ang) * spread * (0.5 if r[0] == "battleship" else 0.9), _rng.randf_range(-80, 80), sin(ang) * spread * (0.5 if r[0] == "battleship" else 0.9))
		_spawn_capital(r[1], r[0], p, at, faction)
		k += 1
	if station_up: _spawn_capital("inv_command", "command", at + (at - player.global_position).normalized() * spread * 1.3, at, faction)
	_inv_fighters(at, faction, int(cfg["fighters"]))
	_spawn_allies(faction)
	_inv_wave_t = float(cfg["wave_every"])
	inv_here = true
	inv_log.append("spawn")

func _spawn_capital(kind: String, role: String, p: Vector3, home: Vector3, faction: String) -> Dictionary:
	var d: Dictionary = Data.ENEMIES[kind]
	var e := spawn_unit(kind, p, home, str(d["model"]), float(d.get("scale", 1.0)))
	e["invasion"] = true
	e["inv_role"] = role
	e["provoked"] = true
	e["aggro"] = true
	e["l"] = 0.0   # (no wing sections: a hit goes to the hull)
	e["r"] = 0.0
	e["node"].name = "%s %s %d" % [faction if faction != "" else "Enemy", d["name"], _enemy_serial]
	e["node"].look_at(home + Vector3(0.01, 0, 0), Vector3.UP)
	if faction != "": e["faction"] = faction
	_light_model(e["model"], Data.INVASION_DRAW["capital"], Data.INVASION_DRAW["capital_lod_bias"])
	return e

## v1.9n (phones): a war has many ships. No shadows from them, and small ships are not drawn far away (a dot you
## could not see anyway); the big ones carry further.
func _light_model(m: Node, draw_to: float, bias := -1.0) -> void:
	for c in m.find_children("*", "GeometryInstance3D", true, false):
		var g := c as GeometryInstance3D
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.visibility_range_end = draw_to
		g.lod_bias = Data.INVASION_DRAW["lod_bias"] if bias < 0.0 else bias

func _inv_fighters(at: Vector3, faction: String, count: int) -> void:
	if count <= 0: return
	for e in spawn_mission_group(at, faction, count, Data.PATROL_MAX_SLOT, "", -9):
		e["invasion"] = true
		e["inv_role"] = "fighter"
		e["aggro"] = true
		_light_model(e["model"], Data.INVASION_DRAW["fighter"])

## Your side: the giver's faction's fighters and a frigate, flying with you.
func _spawn_allies(enemy_faction: String) -> void:
	for a in allies:
		if is_instance_valid(a["node"]): a["node"].queue_free()
	allies = []
	var own: String = str(Data.SYSTEMS[str(GS.mission.get("giver_sys", sys_id))].get("faction", sys.get("faction", "")))
	var pool: Array = Factions.DEFS.get(own, {}).get("fighter_pool", [])
	var fk: String = str(Data.ENEMIES.get(str(pool[0]) if not pool.is_empty() else "", {}).get("model", "enemy"))
	for i in int(Data.INVASION["ally_fighters"]):
		_spawn_ally("fighter", fk, player.global_position + player.global_basis.x * (40.0 + 25.0 * i) * (1.0 if i % 2 == 0 else -1.0) + player.global_basis.z * 30.0, own)
	for i in int(Data.INVASION["ally_frigates"]):
		_spawn_ally("frigate", "carrier", player.global_position + player.global_basis.z * 260.0 + Vector3(0, 60, 0), own)

func _spawn_ally(kind: String, model_key: String, p: Vector3, faction: String) -> void:
	var cfg: Dictionary = Data.ALLY_FIGHTER if kind == "fighter" else Data.ALLY_FRIGATE
	var node := Node3D.new()
	node.name = "%s %s %d" % [faction if faction != "" else "Allied", "fighter" if kind == "fighter" else "frigate", allies.size() + 1]
	var mdl := ShipFactory.build(model_key if ShipFactory.has_real_model(model_key) else "enemy")
	node.add_child(mdl)
	_light_model(mdl, Data.INVASION_DRAW["fighter" if kind == "fighter" else "capital"])
	node.set_meta("kind", "ally")
	node.set_meta("radius", float(cfg["hit_r"]))
	add_child(node)
	node.global_position = p
	node.look_at(p - player.global_basis.z, Vector3.UP)
	allies.append({"node": node, "model": mdl, "hp": float(cfg["hull"]), "max": float(cfg["hull"]), "vel": Vector3.ZERO, "cd": _rng.randf_range(0.3, 1.5),
		"kind": kind, "hit_r": float(cfg["hit_r"]), "foe": {}, "strafe": _rng.randf_range(-1, 1), "re_t": 0.0})

func _damage_ally(a: Dictionary, dmg: float) -> void:
	a["hp"] = float(a["hp"]) - dmg
	_spark(a["node"].global_position, Color(1.0, 0.6, 0.25), 3.0, 0.25)
	if float(a["hp"]) <= 0.0:
		_explode(a["node"].global_position)
		message.emit("%s is down." % a["node"].name)
		a["node"].queue_free()
		allies.erase(a)

## An enemy fighter's foe: the nearest ally when one is clearly nearer than you (re-picked about once a second).
func _enemy_foe(e: Dictionary, dt: float) -> Dictionary:
	if allies.is_empty(): return {}
	e["foe_t"] = float(e.get("foe_t", 0.0)) - dt
	var cur = e.get("foe_ally", {})
	if float(e["foe_t"]) > 0.0 and cur is Dictionary and not cur.is_empty() and allies.has(cur) and is_instance_valid(cur["node"]): return cur
	e["foe_t"] = _rng.randf_range(0.8, 1.4)
	var p: Vector3 = e["node"].global_position
	var best: Dictionary = {}
	var bd: float = p.distance_to(player.global_position) * 0.8
	for a in allies:
		if not is_instance_valid(a["node"]): continue
		var dd: float = p.distance_to(a["node"].global_position)
		if dd < bd:
			bd = dd
			best = a
	e["foe_ally"] = best
	return best

## A capital ship: drifts slowly round the fleet's point and fires its turrets at whoever is in range (you or allies).
func _update_capital(e: Dictionary, dt: float) -> void:
	var n: Node3D = e["node"]
	var d: Dictionary = e["def"]
	if float(d["speed"]) > 0.0:
		e["orbit"] = float(e["orbit"]) + dt * 0.02
		var goal: Vector3 = (e["home"] as Vector3) + Vector3(cos(e["orbit"]), 0.0, sin(e["orbit"])) * Data.INVASION["spread"] * 0.6
		var want := (goal - n.global_position)
		if want.length() > 20.0:
			var fwd := -n.global_basis.z
			var nf := fwd.slerp(want.normalized(), minf(1.0, dt * float(d["turn"])))
			if nf.length() > 0.01: n.look_at(n.global_position + nf, Vector3.UP)
			n.global_position += -n.global_basis.z * float(d["speed"]) * dt
	e["cd"] = float(e["cd"]) - dt
	if float(e["cd"]) > 0.0 or not controls: return
	e["cd"] = 1.0 / float(d["rate"]) * _rng.randf_range(0.7, 1.3)
	var rng_m: float = d["range"]
	var cands: Array = [[player.global_position, vel]]
	for a in allies:
		if is_instance_valid(a["node"]): cands.append([a["node"].global_position, a["vel"]])
	var pick: Array = []
	var best := rng_m
	for c in cands:
		var dd: float = n.global_position.distance_to(c[0])
		if dd < best:
			best = dd
			pick = c
	if pick.is_empty(): return
	var hr: float = float(d.get("hit_r", 30.0))
	var from: Vector3 = n.global_position + Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.3, 0.6), _rng.randf_range(-1, 1)) * hr * 0.7
	var lead: Vector3 = (pick[0] as Vector3) + (pick[1] as Vector3) * (best / 320.0) + Vector3(_rng.randfn(0, 6), _rng.randfn(0, 6), _rng.randfn(0, 6))
	_spawn_bolt(from, (lead - from).normalized() * 320.0, float(d["damage"]), Color(1.0, 0.3, 0.2), "enemy", best / 300.0 + 0.6)
	if best < 600.0: Sfx.play("laser_enemy", -14.0 - best / 80.0, 0.6)

## Allies: each fighter takes the nearest enemy fighter (the frigate the nearest big ship), makes attack runs and
## fires; with nothing in reach they form up on you.
func _update_allies(dt: float) -> void:
	for i in range(allies.size() - 1, -1, -1):
		var a: Dictionary = allies[i]
		var n: Node3D = a["node"]
		if not is_instance_valid(n):
			allies.remove_at(i)
			continue
		var cfg: Dictionary = Data.ALLY_FIGHTER if a["kind"] == "fighter" else Data.ALLY_FRIGATE
		a["re_t"] = float(a["re_t"]) - dt
		var foe = a["foe"]
		if float(a["re_t"]) <= 0.0 or not (foe is Dictionary) or foe.is_empty() or not enemies.has(foe) or not is_instance_valid(foe["node"]):
			a["re_t"] = _rng.randf_range(1.0, 2.0)
			a["foe"] = _ally_pick(a)
			foe = a["foe"]
		var goal: Vector3
		var tp := Vector3.INF
		if not foe.is_empty():
			tp = foe["node"].global_position
			var to: Vector3 = tp - n.global_position
			var side: Vector3 = n.global_basis.x * float(a["strafe"]) * 80.0
			var keep: float = float(foe["def"].get("hit_r", 7.5)) + (140.0 if a["kind"] == "fighter" else 600.0)
			goal = tp + side if to.length() > keep else n.global_position - to.normalized() * 220.0 + side
		else:
			goal = player.global_position + player.global_basis.x * (60.0 * float(a["strafe"])) + player.global_basis.z * 50.0
		var want := goal - n.global_position
		if want.length() > 5.0 and float(cfg["speed"]) > 0.0:
			var fwd := -n.global_basis.z
			var nf := fwd.slerp(want.normalized(), minf(1.0, dt * float(cfg.get("turn", 0.3))))
			if nf.length() > 0.01: n.look_at(n.global_position + nf, Vector3.UP)
		var sp: float = float(cfg["speed"]) * (1.0 if not foe.is_empty() or want.length() > 120.0 else 0.4)
		a["vel"] = (a["vel"] as Vector3).lerp(-n.global_basis.z * sp, minf(1.0, dt * 1.5))
		n.global_position += a["vel"] * dt
		if tp == Vector3.INF or not controls: continue
		a["cd"] = float(a["cd"]) - dt
		var dist: float = n.global_position.distance_to(tp)
		if float(a["cd"]) > 0.0 or dist > float(cfg["range"]) + float(foe["def"].get("hit_r", 7.5)): continue
		var facing: bool = a["kind"] == "frigate" or (-n.global_basis.z).dot((tp - n.global_position).normalized()) > 0.97
		if not facing: continue
		a["cd"] = 1.0 / float(cfg["rate"]) * _rng.randf_range(0.8, 1.2)
		var from: Vector3 = n.global_position - n.global_basis.z * (5.0 if a["kind"] == "fighter" else 40.0)
		var lead: Vector3 = tp + (foe["vel"] as Vector3) * (dist / 300.0) + Vector3(_rng.randfn(0, 3), _rng.randfn(0, 3), _rng.randfn(0, 3))
		_spawn_bolt(from, (lead - from).normalized() * 300.0, float(cfg["damage"]), Color(0.35, 0.8, 1.0), "ally", dist / 280.0 + 0.5)

func _ally_pick(a: Dictionary) -> Dictionary:
	var p: Vector3 = a["node"].global_position
	var best: Dictionary = {}
	var bd := 3000.0
	for e in enemies:
		if not is_instance_valid(e["node"]) or not (e.get("aggro", false) or e.get("invasion", false)): continue
		var cap: bool = e["def"].get("capital", false)
		var dd: float = p.distance_to(e["node"].global_position) * (1.0 if (a["kind"] == "frigate") == cap else 3.0)   # fighters take fighters first, the frigate the big ships
		if dd < bd:
			bd = dd
			best = e
	return best

## The invasion, every frame (from Missions.tick): bring it in when you arrive, keep its fighters topped up from the
## command station (slowly once it is down), and win when the last battleship goes.
func invasion_tick(dt: float, m: Dictionary) -> void:
	var at := Missions.point_pos(self, 0)
	if at == Vector3.INF: return
	var cfg: Dictionary = Data.INVASION
	if int(m.get("spawned", -1)) < 0:
		if player.global_position.distance_to(at) < float(cfg["arrive"]):
			spawn_invasion(at, str(m["faction"]), int(m.get("left", cfg["battleships"])), not bool(m.get("station_down", false)))
			m["spawned"] = 0
			message.emit("SILVER: the %s fleet is here. Destroy the three battleships; your wing is with you." % (str(m["faction"]) if str(m["faction"]) != "" else "enemy"))
		return
	if not inv_here:
		m["spawned"] = -1   # (the fleet was left behind when you went: it is back, as it was, when you return)
		return
	var bs := invasion_units("battleship").size()
	m["left"] = bs
	if bs == 0:
		inv_log.append("won")
		for e in invasion_units():   # what is left of the fleet jumps out
			if e["def"].get("capital", false):
				_spark(e["node"].global_position, Color(0.7, 0.85, 1.0), 60.0, 0.5)
				e["node"].queue_free()
				enemies.erase(e)
			else: e["retreat"] = 30.0
		for a in allies:
			if is_instance_valid(a["node"]): a["node"].queue_free()
		allies = []
		Missions._pay(self, "SILVER: the invasion is broken: the last battleship is down. %s pays %d cr." % [Missions.giver_name(m), int(m["pay"])])
		return
	if not bool(m.get("station_down", false)) and invasion_units("command").is_empty():
		m["station_down"] = true
		inv_log.append("station_down")
		message.emit("The Star Command Station is down: their fighters come slower now.")
	_inv_wave_t -= dt
	if _inv_wave_t <= 0.0:
		_inv_wave_t = float(cfg["wave_every"]) * (float(cfg["station_down_slow"]) if bool(m.get("station_down", false)) else 1.0)
		var room: int = int(cfg["fighters"]) - invasion_units("fighter").size()
		var n: int = mini(room, int(cfg["wave"]))
		if n > 0:
			var st: Array = invasion_units("command")
			var from: Vector3 = (st[0]["node"].global_position if not st.is_empty() else invasion_units("battleship")[0]["node"].global_position)
			_inv_fighters(from, str(m["faction"]), n)
			inv_log.append("wave")


## v1.9o: a prisoner freed by their own people comes after you on launch, with a wing.
func spawn_chaser(id: String) -> Array:
	var p: Dictionary = Data.roster_pilot(id)
	if p.is_empty() or not is_instance_valid(player): return []
	var at: Vector3 = player.global_position + player.global_basis.z * 700.0 + Vector3(0, 80, 0)
	var grp := spawn_mission_group(at, str(p["faction"]), Data.CHASER_WING, int(p.get("slot", 2)), "", -8)
	if grp.is_empty(): return grp
	assign_roster(grp[0], p)
	for e in grp:
		e["aggro"] = true
		e["provoked"] = true
	grp[0]["node"].name = "%s (freed)" % str(p["name"])
	message.emit("%s is free and coming for you, with a wing." % str(p["name"]))
	return grp
