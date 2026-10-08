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
var braking := false
var thrust_held := false
var boosting := false
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
	for p in sys["patrols"]: _spawn_group(p, Data.ROSTER_PATROL_SIZE if Factions.replaces_patrols(str(sys.get("faction", ""))) else 2)
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
	else:
		at = dock_point(station) + Vector3(0, 0, 30)
		face = Vector3(0, 0, 1)
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
	cam.far = 14000.0
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
var extra_worlds: Array = []    # [MeshInstance3D, data] waiting for / wearing the real map
func _build_extras() -> void:
	if surface_mode or not extras.is_empty() or not is_inside_tree(): return
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
	if beacon == null or not Packs.is_ready("structures") or not ResourceLoader.exists("res://assets/structures/dock_arch.glb"): return
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
	_planet_real()
	_dock_gate()
	# placeholders are built a moment after arrival, so they never add to the load hitch of a jump
	get_tree().create_timer(Data.PH_BUILD_DELAY).timeout.connect(_build_extras)
	if not Packs.pack_ready.is_connected(_on_world_pack): Packs.pack_ready.connect(_on_world_pack)
	Packs.request("worlds")

func _on_world_pack(pk: String) -> void:
	if pk == "worlds":
		_planet_real()
		_extra_worlds_real()
	if pk == "structures": _dock_gate()

func dock_point(n: Node3D) -> Vector3:
	if n.get_meta("kind", "") == "waypoint": return n.global_position
	if surface_mode and n == station: return station.global_position + Vector3(0, 90, 160)
	if n == planet:
		var toward: Vector3 = (station.global_position - planet.global_position).normalized()
		return planet.global_position + toward * (float(planet.get_meta("radius")) + 60.0)
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

## The owner's jump gate ring replaces the code-made ring once the "structures" pack is in.
func _gate_model() -> void:
	if gate_model != null or gates.is_empty() or not is_instance_valid(gate_standin): return
	if not (Packs.is_ready("structures") and ResourceLoader.exists(GATE_RING_PATH)): return
	var sc := (load(GATE_RING_PATH) as PackedScene).instantiate()
	var found := sc.find_children("*", "MeshInstance3D", true, false)
	if not found.is_empty():
		for g in gates:
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
	if pk == "structures" and not surface_mode:
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

func _build_nebula(d: Dictionary) -> void:
	nebula_center = d["center"]
	nebula_radius = d["radius"]
	nebula_color = d["color"]
	var tex := [_cloud_texture(nebula_color, hash(sys_id)), _cloud_texture(nebula_color.lightened(0.2), hash(sys_id) + 3)]
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var holder := Node3D.new()
	holder.name = "Nebula"
	add_child(holder)
	for i in 26:
		var mi := MeshInstance3D.new()
		mi.mesh = q
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.albedo_texture = tex[i % 2]
		m.albedo_color = Color(1, 1, 1, 0.55)
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		mi.material_override = m
		var dir := Vector3(_rng.randfn(0, 1), _rng.randfn(0, 0.5), _rng.randfn(0, 1)).normalized()
		mi.position = nebula_center + dir * _rng.randf_range(0.0, nebula_radius * 0.85)
		var s := _rng.randf_range(260.0, 460.0)
		mi.scale = Vector3(s, s, s)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mi)

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

func set_player_model() -> void:
	if is_instance_valid(model): model.queue_free()
	if GS.form == "mech" and not Packs.is_ready("mechs"): GS.form = "ship"
	var mech := GS.form == "mech"
	model = ShipFactory.build("mech_player" if mech else Data.SHIPS[GS.ship_id]["model"])
	player.add_child(model)
	model.visible = GS.view != "cockpit"
	# damage maps between forms: left wing = left arm, right wing = right arm, hull = core
	player_vis = Sections.setup(model, mech)
	Sections.set_side_visible(player_vis, "l", GS.wing_l > 0.0)
	Sections.set_side_visible(player_vis, "r", GS.wing_r > 0.0)

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

func _mech_move(dt: float, thrust: Vector2, base_speed: float) -> void:
	var fwd := -player.global_basis.z
	var right := player.global_basis.x
	var sp := base_speed * 0.85
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
		var soldier: Dictionary = roster_pick(own, _guard_slot) if (Factions.replaces_patrols(own) or _guard_spawn) else {}
		# v1.4z: an enemy home system whose faction has a roster and ships (Phenom, Kaijurai): its own people fly the patrols
		if soldier.is_empty() and not _guard_spawn and str(sys.get("enemy_faction", "")) != "": soldier = roster_pick(str(sys["enemy_faction"]))
		if soldier.is_empty() and _incursion != "" and not _guard_spawn:   # a rival's raiding party: common soldiers, now and then led by slot 02
			soldier = roster_pick(_incursion, 2 if (i == 0 and randf() < Data.INCURSION_NAMED_CHANCE) else 1)
			if i == count - 1 or count > Data.INCURSION_SIZE: _incursion_done = true
		if not soldier.is_empty(): kind = roster_fighter(soldier)
		# v1.4y: an enemy home system with its own ships (Kaijurai, Phenom) flies them, taken from its list in turn
		var fleet: Array = sys.get("enemy_ships", []) if soldier.is_empty() and not _guard_spawn else []
		if not fleet.is_empty(): kind = fleet[(_fleet_serial + i) % fleet.size()]
		if fleet.is_empty() and soldier.is_empty() and count >= 2 and i == count - 1 and _rng.randf() < 0.5 and Packs.is_ready("mechs"): kind = "mech"
		var e := spawn_unit(kind, center + Vector3(_rng.randf_range(-60, 60), _rng.randf_range(-20, 20), _rng.randf_range(-60, 60)), center)
		e["group"] = _group_serial
		# the first ship flies under a NAMED squad leader (Scar Jackal, Iron Revenant...); everyone else is a generic
		# pilot in that leader's wing
		if not soldier.is_empty(): assign_roster(e, soldier)
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
	var e := spawn_unit(p["fighter_primary"], at, at)
	assign_roster(e, p)
	e["bounty"] = p["id"]
	e["node"].name = "%s (bounty)" % p["name"]
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
func spawn_unit(kind: String, pos: Vector3, home: Vector3) -> Dictionary:
	var e: Dictionary = Data.ENEMIES[kind]
	var is_mech: bool = e.get("mech", false)
	var mk: String = e.get("model", "enemy")
	if not (ShipFactory.has_real_model(mk) or mk.begins_with("mech")): mk = "enemy"
	var n := ShipFactory.build(mk)
	var node := Node3D.new()
	_enemy_serial += 1
	node.name = "%s %d" % [e["name"], _enemy_serial]
	node.add_child(n)
	node.position = pos
	node.set_meta("kind", "enemy")
	node.set_meta("radius", float(e.get("radius", 7.0)))
	var pilots: Array = Data.PILOTS.get(sys["enemy"], [])
	if not pilots.is_empty() and not is_mech: node.set_meta("pilot", pilots[_enemy_serial % pilots.size()])
	add_child(node, true)
	var side_hp: float = float(e["hull"]) * Data.SECTION_SHARE
	var ent := {"node": node, "model": n, "hp": e["hull"], "max": e["hull"], "sh": e.get("shield", 0.0), "sh_max": e.get("shield", 0.0), "sh_cd": 0.0,
		"def": e, "vel": Vector3.ZERO, "home": home, "mech": is_mech,
		"l": side_hp, "r": side_hp, "side_max": side_hp, "vis": Sections.setup(n, is_mech),
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
		for k in 3:      # a cargo hauler, a freighter and a liquid tanker (water, fuel) on each run
			var mk: String = ["fleet", "fleet2", "fleet3"][k]
			if not ShipFactory.has_real_model(mk): mk = "fleet"
			var node := Node3D.new()
			node.name = ("Tanker %s-%d" if mk == "fleet3" else "Freighter %s-%d") % [sys["name"], k + 1]
			node.add_child(ShipFactory.build(mk))
			node.set_meta("kind", "traffic")
			node.set_meta("radius", 12.0)
			add_child(node)
			traffic.append({"node": node, "t": float(k) / 3.0, "dir": 1.0 if k != 1 else -1.0})

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
	if not _mem_reported and time > 3.0:
		_mem_reported = true
		if OS.has_feature("web") or OS.get_environment("HL_PROFILE") != "": print(memory_report())
	if not is_instance_valid(player): return
	_update_player(dt)
	Missions.tick(self, dt)   # v1.5f
	_update_beacon()
	_update_enemies(dt)
	_update_traffic(dt)
	_update_bolts(dt)
	_update_missiles(dt)
	_update_trails(dt)
	_update_blasts(dt)
	_update_mines(dt)
	_update_loot(dt)
	_update_effects(dt)
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
			for p in sys["patrols"]:
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
	var turn: float = s["turn"]
	gun_cd = maxf(0.0, gun_cd - dt)
	shield_delay = maxf(0.0, shield_delay - dt)
	hit_shake = maxf(0.0, hit_shake - dt * 2.5)
	call_cd = maxf(0.0, call_cd - dt)
	chatter_cd = maxf(0.0, chatter_cd - dt)
	GS.energy = minf(Data.ENERGY_MAX, GS.energy + Data.ENERGY_REGEN * dt)
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
	if warp_state == "on": steer *= 0.35 # heavy steering at warp speed
	# full loops: pitch is not capped. Upside down, left/right steering is mirrored so it still turns the way the
	# stick points on screen (the camera rolls over with the ship).
	yaw -= steer.x * turn * dt * (1.0 if cos(pitch) >= 0.0 else -1.0)
	pitch = wrapf(pitch - steer.y * turn * 0.8 * dt, -PI, PI)
	player.basis = Basis.from_euler(Vector3(pitch, yaw, 0))
	if is_instance_valid(model) and GS.form != "mech" and transform_t <= 0.0:
		model.rotation.z = lerpf(model.rotation.z, -steer.x * 0.55, minf(1.0, dt * 4.0))
		model.rotation.x = lerpf(model.rotation.x, -steer.y * 0.12, minf(1.0, dt * 4.0))
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
	if GS.form == "mech" and warp_state == "off":
		_mech_move(dt, thrust, base_speed)
	elif warp_state == "on":
		vel = vel.lerp(fwd * base_speed * Data.WARP_MULT, minf(1.0, dt * 1.2))
		_booster_particles(dt, 0.5)
	elif engine_kill:
		pass # engines off: keep drifting on the current vector while the nose turns freely
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
		var cost := Data.ENERGY_PER_GUN * float(GS.ship()["guns"])
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
	if warp_state == "on" or GS.form == "mech": return false
	engine_kill = not engine_kill
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

func _in_fire_cone(t: Node3D) -> bool:
	if t == null or not is_instance_valid(t) or t.get_meta("kind", "") != "enemy": return false
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
	for g in guns:
		var off := (g - (guns - 1) / 2.0) * 2.4
		if off < -0.1 and GS.wing_l <= 0.0: continue   # left wing gone: its guns are gone
		if off > 0.1 and GS.wing_r <= 0.0: continue
		var from := player.global_position + player.global_basis.x * off + fwd * 5.0
		_spawn_bolt(from, aim_dir * float(w["speed"]) + vel, float(w["damage"]), w["color"], "player", float(w["range"]) / float(w["speed"]))
		_spark(from + fwd * 1.5, (w["color"] as Color).lightened(0.4), 3.2, 0.09)
	if _laser_sfx_cd <= 0.0:
		Sfx.play("laser", -9.0)
		_laser_sfx_cd = 0.07

func _spawn_bolt(from: Vector3, v: Vector3, dmg: float, col: Color, owner: String, life: float) -> void:
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
	bolts.append({"node": mi, "vel": v, "life": life, "dmg": dmg, "owner": owner})

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
	return mini(mini(GS.max_locks(item), int(lock_time / Data.LOCK_STEP)), ammo)

## Fire `count` missiles at the target: the first now, the rest VOLLEY_GAP apart, fanned out.
func fire_volley(heavy: bool, count: int) -> int:
	count = clampi(count, 1, GS.heavy_missiles if heavy else GS.missiles)
	var scale := 1.0 if heavy else float(Data.MISSILE_RACKS.get(GS.rack, Data.MISSILE_RACKS["triple"])["damage"])
	if count <= 1 and not heavy: scale = 1.0   # a single shot without locks is a full-strength missile
	if not fire_missile(heavy, 0, count, scale): return 0
	var t = missiles_live[-1]["target"]
	for k in range(1, count):
		volley_queue.append({"t": Data.VOLLEY_GAP * k, "heavy": heavy, "k": k, "n": count, "scale": scale, "target": t})
	lock_time = 0.0
	return count

func fire_missile(heavy := false, k := 0, n := 1, scale := 1.0, forced: Node3D = null) -> bool:
	if (GS.heavy_missiles if heavy else GS.missiles) <= 0: return false
	var t := target if (target and is_instance_valid(target) and target.get_meta("kind", "") == "enemy") else null
	if forced != null and is_instance_valid(forced): t = forced
	if t == null: t = _nearest_enemy(900.0)
	if t == null:
		message.emit("No hostile target for missile lock.")
		return false
	if heavy: GS.heavy_missiles -= 1
	else: GS.missiles -= 1
	var te := _enemy_entry(t)
	if te.has("pilot"): _chatter(te, "missile_incoming", true)
	# v1.4m: a launch is noticed. The target and its wing turn on you.
	for ae in enemies:
		if ae["node"] == t or (ae["node"] as Node3D).global_position.distance_to(t.global_position) < Data.MISSILE_ALERT: ae["aggro"] = true
	GS.changed.emit()
	var mi := _missile_node(heavy)
	add_child(mi)
	mi.global_position = player.global_position - player.global_basis.y * 1.5
	var fan := Vector3.ZERO   # a volley fans out left/right and a little up
	if n > 1:
		var a := (float(k) / float(n - 1) - 0.5) * 2.0
		fan = (player.global_basis.x * a + player.global_basis.y * (1.0 - absf(a)) * 0.5) * Data.VOLLEY_SPREAD
	missiles_live.append({"node": mi, "vel": -player.global_basis.z * 90.0 + vel + fan, "target": t, "life": 7.0, "heavy": heavy, "scale": scale,
		"wp": _rng.randf() * TAU, "wf": _rng.randf_range(Data.WEAVE_HZ[0], Data.WEAVE_HZ[1]), "wo": _rng.randf() * TAU})
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
		flare.material_override = ShipFactory.mat(Color(1.0, 0.85, 0.55), true)
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
		if b["owner"] == "player":
			for e in enemies:
				if _seg_hit(from, to, e["node"].global_position, 7.5):
					_damage_enemy(e, b["dmg"], _seg_closest(from, to, e["node"].global_position))
					hit = true
					break
		else:
			if _seg_hit(from, to, player.global_position, 5.0):
				_player_hit(b["dmg"], _seg_closest(from, to, player.global_position))
				hit = true
		if not hit and in_belt_region(to):
			for r in rocks:
				if _seg_hit(from, to, r[0], r[1]):
					_spark(to, Color(1, 0.8, 0.5), 3.0)
					hit = true
					break
		if hit or b["life"] <= 0.0:
			n.queue_free()
			bolts.remove_at(i)

func in_belt_region(p: Vector3) -> bool:
	return p.distance_to(belt_center) < belt_radius + 60.0

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
			v = v.lerp(rel.normalized() * Data.MISSILE_SPEED, minf(1.0, dt * Data.MISSILE_TURN))
			var te := _enemy_entry(t)
			if not te.is_empty():
				# the enemy may try a side-boost as the missile closes in; moving sideways fast enough shakes it off
				if rel.length() < Data.DODGE_RANGE and not m.get("rolled", false):
					m["rolled"] = true
					if float(te.get("dodge_t", 0.0)) <= 0.0 and _rng.randf() < enemy_dodge_chance:
						var sd := v.cross(Vector3.UP).normalized() * (1.0 if _rng.randf() < 0.5 else -1.0)
						te["dodge_t"] = Data.ENEMY_DODGE_TIME
						te["dodge_dir"] = sd if sd.length() > 0.5 else Vector3.RIGHT
				if rel.length() < Data.DODGE_RANGE and side_speed(te["vel"], rel) > Data.DODGE_SIDE_FRAC * float(te["def"]["speed"]):
					m["target"] = null
					m["shaken"] = true   # dodged: it does not get a second go
					t = null
					enemy_evades += 1
					_popup(te["node"].global_position, "EVADED", Color(0.7, 0.9, 1.0))
		m["vel"] = v
		var wv2 := weave(m, v, n.global_position.distance_to(t.global_position), dt) if is_instance_valid(t) else Vector3.ZERO
		n.global_position += (v + wv2) * dt
		if v.length() > 0.1: n.look_at(n.global_position + v + wv2, Vector3.UP)
		m["life"] -= dt
		_missile_trail(n)
		var done: bool = m["life"] <= 0.0
		if is_instance_valid(t) and n.global_position.distance_to(t.global_position) < 9.0:
			var e := _enemy_entry(t)
			if not e.is_empty():
				_damage_enemy(e, missile_damage(e, m.get("heavy", false), float(m.get("scale", 1.0))))
			_spark(n.global_position, Color(1, 0.6, 0.2), 12.0 if m.get("heavy", false) else 8.0)
			done = true
		if done:
			n.queue_free()
			missiles_live.remove_at(i)

## Heavy: hits hard (at least HEAVY_MISSILE_HULL_FRAC of the hull). Light: MISSILE_DAMAGE or 30 % of the hull,
## times the rack's damage share (a swarm missile is lighter).
func missile_damage(e: Dictionary, heavy: bool, scale := 1.0) -> float:
	if heavy: return maxf(Data.HEAVY_MISSILE_DAMAGE, float(e["max"]) * Data.HEAVY_MISSILE_HULL_FRAC)
	return maxf(Data.MISSILE_DAMAGE, float(e["max"]) * Data.LIGHT_MISSILE_HULL_FRAC) * scale

func _enemy_entry(n: Node3D) -> Dictionary:
	for e in enemies:
		if e["node"] == n: return e
	return {}

## Shields soak damage first. What gets through hits the section under the hit point: a wing/arm if the shot
## landed on that side (and it is still there), otherwise the core. Missiles and mines (no hit point) hit the core.
func _damage_enemy(e: Dictionary, dmg: float, hit := Vector3.INF) -> void:
	e["aggro"] = true
	e["provoked"] = true
	e["sh_cd"] = 4.0
	var at: Vector3 = e["node"].global_position if hit == Vector3.INF else hit
	var had_shield := float(e["sh"]) > 0.0
	var to_shield := minf(dmg, float(e["sh"]))
	e["sh"] = float(e["sh"]) - to_shield
	var to_hull := dmg - to_shield
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
		if e["sh_cd"] <= 0.0: e["sh"] = minf(float(e["sh_max"]), float(e["sh"]) + float(e["sh_max"]) * 0.15 * dt)
		var to := ppos - n.global_position
		var dist := to.length()
		var was: bool = e["aggro"]
		var spotting := warp_state == "charging" and dist < 1600.0   # they see the warp charge and come to stop you
		# v1.4r: a faction you are on speaking terms with (yellow or better) leaves you alone until you shoot at it
		var peaceful: bool = e.has("faction") and not e.get("provoked", false) and not Factions.hostile(e["faction"])
		if e.has("faction"): n.set_meta("kind", "patrol" if peaceful else "enemy")   # v1.4w: a peaceful faction ship is not a hostile contact
		if peaceful: e["aggro"] = false
		elif dist < 650.0 or e["aggro"] or spotting: e["aggro"] = dist < (1600.0 if spotting else 1400.0)
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
			goal = ppos + side if dist > 140.0 else n.global_position - to.normalized() * 200.0 + side
		else:
			e["orbit"] += dt * 0.25
			goal = e["home"] + Vector3(cos(e["orbit"]) * 120.0, sin(e["orbit"] * 0.7) * 25.0, sin(e["orbit"]) * 120.0)
		var fwd := -n.global_basis.z
		var want := (goal - n.global_position).normalized()
		var new_fwd := fwd.slerp(want, minf(1.0, dt * float(d["turn"])))
		if new_fwd.length() > 0.01:
			n.look_at(n.global_position + new_fwd, Vector3.UP)
		var sp: float = d["speed"] * (1.0 if e["aggro"] else 0.5) * (1.4 if warp_state == "charging" else 1.0)
		e["vel"] = (e["vel"] as Vector3).lerp(-n.global_basis.z * sp, minf(1.0, dt * 1.5))
		if float(e.get("dodge_t", 0.0)) > 0.0:   # Job M: side-boost out of a missile's path
			e["dodge_t"] = float(e["dodge_t"]) - dt
			e["vel"] = (e["dodge_dir"] as Vector3) * float(d["speed"]) * Data.ENEMY_DODGE_BOOST
		n.global_position += e["vel"] * dt
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
		if e["aggro"] and controls and dist < 420.0 and facing:
			var lead := ppos + vel * (dist / 300.0)
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
	if in_belt:
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
			if atmo_depth > 0.0:
				Packs.request("planets")
				Packs.request("city")    # small; city blocks upgrade to the full capital material when it lands
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
		if d2 < hitr:
			var n2 := (player.global_position - body.global_position).normalized()
			player.global_position = body.global_position + n2 * hitr
			collision_damage("station" if (body == station or not body.get_meta("info", {}).has("palette")) else "ground", -vel.dot(n2))   # Job L (a planet without a surface is ground)
			vel = vel - n2 * vel.dot(n2) * 1.5
	var nd := p.distance_to(nebula_center)
	in_nebula = 0.0 if nebula_radius <= 1.0 else clampf((nebula_radius - nd) / (nebula_radius * 0.35), 0.0, 1.0)

var look := Vector2.ZERO   # cockpit free-look (-1..1): the pilot's head turns toward where you steer
const LOOK_YAW := 0.5      # radians at full look left/right
const LOOK_PITCH := 0.22   # radians at full look up/down (less: you shouldn't see past the canopy art)

func _update_camera(dt: float, snap: bool) -> void:
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
	var look := player.global_position - player.global_basis.z * 30.0 + player.global_basis.y * 2.6
	if hit_shake > 0.0: look += Vector3(_rng.randfn(0, 1), _rng.randfn(0, 1), 0) * hit_shake * 0.8
	cam.look_at(look, player.global_basis.y)
	cam.fov = lerpf(cam.fov, 88.0 if warp_state == "on" else (76.0 if boosting else 70.0), minf(1.0, dt * 2.0))

func _ambient_anim(dt: float) -> void:
	if is_instance_valid(planet_clouds): planet_clouds.rotate_y(dt * 0.006)
	for gp in gate_portals:
		if not is_instance_valid(gp): continue
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
			var shots := fire_volley(heavy, maxi(1, lock_count("heavy_missile" if heavy else "light_missile")))
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
	mines_live.append({"node": mi, "arm": 1.0, "life": 60.0, "vel": vel * 0.2})
	system_used.emit("mine", "Mine deployed. %d left." % GS.mines)
	return true

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
				if d < Data.MINE_RADIUS: _damage_enemy(e, Data.MINE_DAMAGE * (1.0 - d / Data.MINE_RADIUS * 0.5))
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
				if m0.get("kind", "") == "bounty": message.emit("%s is in your hold. Bring them back to %s for the %d cr bounty." % [who.get("name", "The pilot"), Data.SYSTEMS[m0["giver_sys"]]["station"]["name"], Data.bounty_reward(l["bounty"])])
				else: message.emit("%s is in your hold. Dock at any station for the %d cr bounty." % [who.get("name", "The pilot"), Data.bounty_reward(l["bounty"])])
			Sfx.play("pickup", -6.0)
			n.queue_free()
			loot.remove_at(i)
		elif d < 14.0:
			GS.add_credits(int(l["value"]))
			_popup(n.global_position, "+%d cr" % int(l["value"]), Color(1.0, 0.85, 0.35))
			Sfx.play("pickup", -6.0)
			n.queue_free()
			loot.remove_at(i)
		elif l["life"] <= 0.0:
			n.queue_free()
			loot.remove_at(i)

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
	# keep a manually chosen non-enemy target; otherwise pick the nearest hostile ahead
	if target != null and target.get_meta("kind", "") != "enemy": return
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
	target = best

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
	Packs.request("city")
	if not Packs.pack_ready.is_connected(_on_pack_ready): Packs.pack_ready.connect(_on_pack_ready)
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
	if is_instance_valid(tile_root): tile_root.queue_free()
	tile_root = Surface.build_tile(planet_id, t)
	_water = Surface.has_water(planet_id, t)
	_edge_warned = false
	add_child(tile_root)
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
		station.global_position = Vector3(l["pos"].x, Surface.pad_height(planet_id, t) + 20.0, l["pos"].y)
	# a patrol over this tile (ships, sometimes a mech)
	var prng := RandomNumberGenerator.new()
	prng.seed = hash("%s%d" % [planet_id, t])
	var c := Vector3(prng.randf_range(-1400, 1400), 0, prng.randf_range(-1400, 1400))
	c.y = _ground(c.x, c.z) + 260.0
	if enemies.size() < 4: _spawn_group(c, 2)
	if keep == Vector3.INF: _update_camera(1.0, true)
	_corners = Surface.wrap_corners(planet_id, t)
	_prepared.clear()
	# city blocks: simple box collision (decks, pillars, tower blocks) in this tile's space
	city_solids.clear()
	city_bounds = AABB()
	var all: Array = []
	var cb := tile_root.get_node_or_null("CapitalBlock")
	if cb:
		for a: AABB in cb.get_meta("solids"): all.append(AABB(a.position + cb.position, a.size))
	for a: AABB in tile_root.get_meta("solids", []): all.append(a)   # town buildings
	for w: AABB in all:
		city_solids.append(w)
		city_bounds = w if city_bounds.size == Vector3.ZERO else city_bounds.merge(w)

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
func spawn_mission_group(at: Vector3, faction: String, count: int, max_slot: int, boss_id: String, stage: int) -> Array:
	_group_serial += 1
	var out: Array = []
	var pool: Array = Factions.DEFS.get(faction, {}).get("fighter_pool", [])
	for i in count:
		var soldier: Dictionary = {}
		if i == 0 and boss_id != "": soldier = Data.roster_pilot(boss_id)
		else: soldier = _pick_senior(faction, max_slot, max_slot if i == 0 else mini(max_slot, 2))
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

## v1.5f: the most senior pick a few draws give (roster_pick leans to slot 01; a senior job wants the slot asked for).
func _pick_senior(faction: String, max_slot: int, want: int) -> Dictionary:
	var best: Dictionary = {}
	for k in 14:
		var p := roster_pick(faction, max_slot)
		if p.is_empty(): break
		if best.is_empty() or int(p.get("slot", 0)) > int(best.get("slot", 0)): best = p
		if int(best.get("slot", 0)) >= want: break
	return best

## v1.5f: the escort mission's freighter, at the station's dock point, heading for the planet.
func make_escort() -> void:
	if is_instance_valid(escort_node) or not is_instance_valid(station) or not is_instance_valid(planet): return
	var node := Node3D.new()
	node.name = "Freighter %s (escort)" % sys["name"]
	node.add_child(ShipFactory.build("fleet" if ShipFactory.has_real_model("fleet") else "enemy"))
	node.set_meta("kind", "traffic")
	node.set_meta("radius", 12.0)
	add_child(node)
	var a := dock_point(station) + Vector3(0, 60, 0)
	node.global_position = a
	node.set_meta("trip", a.distance_to(planet_dock_point()))
	escort_node = node

func planet_dock_point() -> Vector3:
	return dock_point(planet) + Vector3(0, 60, 0)

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

var city_solids: Array = []   # AABBs of the city block in this tile (see City)

## The city pack arrived after the block was built: swap its flat colours for the shared capital material.
func _on_pack_ready(pk: String) -> void:
	if pk != "city" or not is_instance_valid(tile_root): return
	var cb := tile_root.get_node_or_null("CapitalBlock")
	if cb: City.refresh(cb)
var city_bounds := AABB()

## Keep a body of radius r out of the city's solid boxes. Landing on top of a box (a deck, the plaza, a roof)
## works like the ground; hitting a side pushes you back out. Returns the push applied.
func city_push(p: Vector3, r: float) -> Vector3:
	if city_solids.is_empty() or not city_bounds.grow(r).has_point(p): return Vector3.ZERO
	var push := Vector3.ZERO
	for a: AABB in city_solids:
		var g := a.grow(r)
		if not g.has_point(p + push): continue
		var q := p + push
		var opts := [[g.end.y - q.y, Vector3.UP], [q.x - g.position.x, Vector3.LEFT], [g.end.x - q.x, Vector3.RIGHT],
			[q.z - g.position.z, Vector3.FORWARD], [g.end.z - q.z, Vector3.BACK], [q.y - g.position.y, Vector3.DOWN]]
		var best: Array = opts[0]
		if best[0] > 3.0:   # well below the top: push out sideways (or down) the shortest way instead
			for o in opts.slice(1):
				if o[0] < best[0]: best = o
		push += (best[1] as Vector3) * best[0]
	return push
var corner_haze := 0.0   # 0..1 inside the wrap-corner cloud bank

func _ground(x: float, z: float) -> float:
	var h := Surface.height(planet_id, tile, x, z)
	if _water: h = maxf(h, 0.0)
	return h

## Ground contact, tile edges (wrap to the next tile) and the ceiling (back to orbit).
func _surface_update(_dt: float) -> void:
	var p := player.global_position
	var floor_y := _ground(p.x, p.z) + 6.0
	altitude = p.y - floor_y + 6.0
	if p.y < floor_y:
		var impact := -vel.y
		player.global_position.y = floor_y
		if vel.y < 0.0: vel.y = 0.0
		collision_damage("ground", impact)   # Job L (was: > 20 m/s, 0.25 x impact through the shields)
	var cp := city_push(player.global_position, 6.0)
	if cp != Vector3.ZERO:
		player.global_position += cp
		var nrm := cp.normalized()
		var into := vel.dot(nrm)
		collision_damage("building", -into)   # Job L: town / city buildings
		if into < 0.0: vel -= nrm * into   # stop moving into the wall / deck
		if nrm.y > 0.7: altitude = 0.0
	for e in enemies:
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
