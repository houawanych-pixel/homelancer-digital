class_name ShipFactory
extends RefCounted
## Builds ship visuals. Real GLB models are used when present in assets/ships/; otherwise a clearly labelled,
## original low-poly stand-in is built from primitives. Every visual faces -Z and is about `length` units long.

# key -> [glb path, target length, extra yaw degrees applied after import]
const GLB := {
	"cadet": ["res://assets/ships/player/cadet_v2.glb", 9.0, 0.0],   # v9.8 (owner): the remodelled Cadet (laptop Blender build, 9 m, nose -Z, level 1: 4 core + 1 per wing mounts, tilting nacelles)
	"ranger": ["res://assets/ships/player/ranger.glb", 10.5, 0.0],
	"lancer": ["res://assets/ships/player/lancer.glb", 12.0, 0.0],
	"bulk_empty": ["res://assets/ships/player/bulk_empty.glb", 19.0, 0.0],
	"bulk": ["res://assets/ships/player/bulk.glb", 19.0, 0.0],
	"hauler": ["res://assets/ships/player/hauler.glb", 15.0, 0.0],
	# v1.4q: the owner's true Savagers set (split from hl_SAVAGERS_ship_set) replaces the old raider and corsair models
	"enemy": ["res://assets/ships/enemy/savager_skirmish.glb", Data.SAVAGER_SKIRMISH_LEN, Data.SAVAGER_SKIRMISH_YAW],
	"enemy2": ["res://assets/ships/enemy/savager_gunboat.glb", Data.SAVAGER_GUNBOAT_LEN, Data.SAVAGER_GUNBOAT_YAW],
	"savager_scrapfang": ["res://assets/ships/enemy/savager_scrapfang.glb", Data.SCRAPFANG_LEN, 0.0],   # v1.4r fighter ladder (stand-ins from the owner's set until
	"savager_redclaw": ["res://assets/ships/enemy/savager_redclaw.glb", Data.REDCLAW_LEN, 0.0],         #  each named fighter design is delivered)
	"savager_ironhowl": ["res://assets/ships/enemy/savager_skirmish.glb", Data.IRONHOWL_LEN, Data.SAVAGER_SKIRMISH_YAW],
	"savager_warboar": ["res://assets/ships/enemy/savager_gunboat.glb", Data.WARBOAR_LEN, Data.SAVAGER_GUNBOAT_YAW],
	"imperium_fighter": ["res://assets/ships/enemy/imperium_fighter.glb", Data.IMPERIUM_FIGHTER_LEN, 0.0],   # v1.4w (facing checked from above)
	"imperium_gunship": ["res://assets/ships/enemy/imperium_gunship.glb", Data.IMPERIUM_GUNSHIP_LEN, 0.0],
	"liberator_fighter": ["res://assets/ships/enemy/liberator_fighter.glb", Data.LIBERATOR_FIGHTER_LEN, Data.LIBERATOR_YAW],
	"liberator_heavy": ["res://assets/ships/enemy/liberator_heavy.glb", Data.LIBERATOR_HEAVY_LEN, Data.LIBERATOR_YAW],
	# v1.4y: the owner's Kaijurai and Phenom sets (facing checked from above: nose at -Z)
	"kaijurai_dart": ["res://assets/ships/enemy/kaijurai_dart.glb", Data.KAIJURAI_DART_LEN, Data.ALIEN_SHIP_YAW],
	"kaijurai_heavy": ["res://assets/ships/enemy/kaijurai_heavy.glb", Data.KAIJURAI_HEAVY_LEN, Data.ALIEN_SHIP_YAW],
	"kaijurai_gunship": ["res://assets/ships/enemy/kaijurai_gunship.glb", Data.KAIJURAI_GUNSHIP_LEN, Data.ALIEN_SHIP_YAW],
	# v6.2: the second Kaijurai set (own pack "kaijurai_fleet", fetched once you fly)
	"kaijurai_fang": ["res://assets/ships/kaijurai/kaijurai_fang.glb", Data.KAIJURAI_FANG_LEN, Data.KAIJURAI_FANG_YAW],
	"kaijurai_ravager": ["res://assets/ships/kaijurai/kaijurai_ravager.glb", Data.KAIJURAI_RAVAGER_LEN, Data.KAIJURAI_RAVAGER_YAW],
	"kaijurai_stalker": ["res://assets/ships/kaijurai/kaijurai_stalker.glb", Data.KAIJURAI_STALKER_LEN, Data.ALIEN_SHIP_YAW],
	"kaijurai_hound": ["res://assets/ships/kaijurai/kaijurai_hound.glb", Data.KAIJURAI_HOUND_LEN, Data.ALIEN_SHIP_YAW],
	"kaijurai_reaper": ["res://assets/ships/kaijurai/kaijurai_reaper.glb", Data.KAIJURAI_REAPER_LEN, Data.KAIJURAI_REAPER_YAW],
	"phenom_fighter": ["res://assets/ships/enemy/phenom_fighter.glb", Data.PHENOM_FIGHTER_LEN, Data.ALIEN_SHIP_YAW],
	"phenom_interceptor": ["res://assets/ships/enemy/phenom_interceptor.glb", Data.PHENOM_INTERCEPTOR_LEN, Data.ALIEN_SHIP_YAW],
	"phenom_scout": ["res://assets/ships/enemy/phenom_scout.glb", Data.PHENOM_SCOUT_LEN, Data.ALIEN_SHIP_YAW],
	"phenom_heavy": ["res://assets/ships/enemy/phenom_heavy.glb", Data.PHENOM_HEAVY_LEN, Data.ALIEN_SHIP_YAW],
	"covenant_fighter": ["res://assets/ships/enemy/covenant_fighter.glb", Data.COVENANT_FIGHTER_LEN, Data.ALIEN_SHIP_YAW],   # v1.5c
	"covenant_interceptor": ["res://assets/ships/enemy/covenant_interceptor.glb", Data.COVENANT_INTERCEPTOR_LEN, Data.ALIEN_SHIP_YAW],
	"covenant_lance": ["res://assets/ships/enemy/covenant_lance.glb", Data.COVENANT_LANCE_LEN, Data.ALIEN_SHIP_YAW],
	"cybermorph_fighter": ["res://assets/ships/enemy/cybermorph_fighter.glb", Data.CYBERMORPH_FIGHTER_LEN, Data.ALIEN_SHIP_YAW],
	"cybermorph_star": ["res://assets/ships/enemy/cybermorph_star.glb", Data.CYBERMORPH_STAR_LEN, Data.ALIEN_SHIP_YAW],
	"solrath_blade_a": ["res://assets/ships/enemy/solrath_blade_a.glb", Data.SOLRATH_BLADE_LEN, Data.ALIEN_SHIP_YAW],
	"solrath_blade_b": ["res://assets/ships/enemy/solrath_blade_b.glb", Data.SOLRATH_BLADE_LEN, Data.ALIEN_SHIP_YAW],
	"solrath_batwing": ["res://assets/ships/enemy/solrath_batwing.glb", Data.SOLRATH_BATWING_LEN, Data.ALIEN_SHIP_YAW],
	"solrath_spire": ["res://assets/ships/enemy/solrath_spire.glb", Data.SOLRATH_SPIRE_LEN, Data.ALIEN_SHIP_YAW],
	"elyza_fighter": ["res://assets/ships/enemy/elyza_fighter.glb", Data.ELYZA_FIGHTER_LEN, Data.ALIEN_SHIP_YAW],   # v1.5p: folding wings (Body / WingL / WingR)
	# v1.5q: the owner's placeholder fighters, one per faction in its own colour (until each faction's real ships come)
	"placeholder_savagers": ["res://assets/ships/enemy/placeholder_savagers.glb", Data.PLACEHOLDER_SHIP_LEN, 0.0],
	"placeholder_liberator": ["res://assets/ships/enemy/placeholder_liberator.glb", Data.PLACEHOLDER_SHIP_LEN, 0.0],
	"placeholder_unity": ["res://assets/ships/enemy/placeholder_unity.glb", Data.PLACEHOLDER_SHIP_LEN, 0.0],
	"placeholder_imperium": ["res://assets/ships/enemy/placeholder_imperium.glb", Data.PLACEHOLDER_SHIP_LEN, 0.0],
	"placeholder_elyza": ["res://assets/ships/enemy/placeholder_elyza.glb", Data.PLACEHOLDER_SHIP_LEN, 0.0],
	"placeholder_covenant": ["res://assets/ships/enemy/placeholder_covenant.glb", Data.PLACEHOLDER_SHIP_LEN, 0.0],
	"placeholder_solarion": ["res://assets/ships/enemy/placeholder_solarion.glb", Data.PLACEHOLDER_SHIP_LEN, 0.0],
	"placeholder_orion": ["res://assets/ships/enemy/placeholder_orion.glb", Data.PLACEHOLDER_SHIP_LEN, 0.0],
	"placeholder_cybermorph": ["res://assets/ships/enemy/placeholder_cybermorph.glb", Data.PLACEHOLDER_SHIP_LEN, 0.0],
	"placeholder_solrath": ["res://assets/ships/enemy/placeholder_solrath.glb", Data.PLACEHOLDER_SHIP_LEN, 0.0],
	"placeholder_gadversee": ["res://assets/ships/enemy/placeholder_gadversee.glb", Data.PLACEHOLDER_SHIP_LEN, 0.0],
	"placeholder_arctides": ["res://assets/ships/enemy/placeholder_arctides.glb", Data.PLACEHOLDER_SHIP_LEN, 0.0],
	"placeholder_phenom": ["res://assets/ships/enemy/placeholder_phenom.glb", Data.PLACEHOLDER_SHIP_LEN, 0.0],
	"placeholder_kaijurai": ["res://assets/ships/enemy/placeholder_kaijurai.glb", Data.PLACEHOLDER_SHIP_LEN, 0.0],
	"liberator_cross": ["res://assets/ships/enemy/liberator_cross.glb", Data.LIBERATOR_CROSS_LEN, Data.LIBERATOR_YAW],
	"savager_cruiser": ["res://assets/ships/enemy/savager_cruiser.glb", Data.SAVAGER_CRUISER_LEN, Data.SAVAGER_CRUISER_YAW],
	"pilot_pod": ["res://assets/cargo/spacesuit_pilot.glb", 4.0, 0.0],   # stand-in: the soldier in the space suit
	"savager_carrier": ["res://assets/ships/enemy/savager_carrier.glb", Data.SAVAGER_CARRIER_LEN, Data.SAVAGER_CARRIER_YAW],
	"fleet": ["res://assets/ships/civilian/cargo_ship.glb", 16.0, 0.0],
	"fleet2": ["res://assets/ships/civilian/freighter.glb", 20.0, 0.0],
	"fleet3": ["res://assets/ships/civilian/tanker.glb", 34.0, 0.0],
	"crate_a": ["res://assets/cargo/crate_a.glb", 3.4, 0.0],
	"crate_b": ["res://assets/cargo/crate_b.glb", 3.4, 0.0],
	"crate_c": ["res://assets/cargo/crate_c.glb", 3.4, 0.0],
	"tanker": ["res://assets/ships/civilian/big_tanker.glb", 110.0, 0.0],
	"carrier": ["res://assets/ships/civilian/carrier.glb", 130.0, 0.0],
	"station": ["res://assets/stations/station.glb", 150.0, 0.0],
	"missile": ["res://assets/weapons/missile.glb", 3.4, 0.0],
	"mine": ["res://assets/weapons/mine.glb", 3.2, 0.0],
	"gatling": ["res://assets/weapons/gatling.glb", 3.0, 0.0],
	"rocket_pod": ["res://assets/weapons/rocket_pod.glb", 3.0, 0.0],
	"wpn_shell_smg": ["res://assets/wing_guns/wpn_shell_smg.glb", Data.WING_GUN_LEN, 0.0],   # v1.9g: the owner's wing guns (pack "wing_guns")
	"wpn_gunnar_rifle": ["res://assets/wing_guns/wpn_gunnar_rifle.glb", Data.WING_GUN_LEN, 0.0],   # v1.9g: the owner's wing guns (pack "wing_guns")
	"wpn_teal_gatling": ["res://assets/wing_guns/wpn_teal_gatling.glb", Data.WING_GUN_LEN, 0.0],   # v1.9g: the owner's wing guns (pack "wing_guns")
	"wpn_blue_quad_cannon": ["res://assets/wing_guns/wpn_blue_quad_cannon.glb", Data.WING_GUN_LEN, 0.0],   # v1.9g: the owner's wing guns (pack "wing_guns")
	"wpn_warden_gun": ["res://assets/wing_guns/wpn_warden_gun.glb", Data.WING_GUN_LEN, 0.0],   # v1.9g: the owner's wing guns (pack "wing_guns")
	"wpn_crystal_bone_rifle": ["res://assets/wing_guns/wpn_crystal_bone_rifle.glb", Data.WING_GUN_LEN, 0.0],   # v1.9g: the owner's wing guns (pack "wing_guns")
	"wpn_mech_arm_cannon": ["res://assets/wing_guns/wpn_mech_arm_cannon.glb", Data.WING_GUN_LEN, 0.0],   # v1.9g: the owner's wing guns (pack "wing_guns")
	"wpn_missile_pod": ["res://assets/wing_guns/wpn_missile_pod.glb", Data.WING_GUN_LEN, 0.0],   # v1.9g: the owner's wing guns (pack "wing_guns")
	"wpn_rocket_rack": ["res://assets/wing_guns/wpn_rocket_rack.glb", Data.WING_GUN_LEN, 0.0],   # v1.9h: the owner's rail / heavy mounts
	"wpn_rail_lance": ["res://assets/wing_guns/wpn_rail_lance.glb", Data.WING_GUN_LEN, 0.0],   # v1.9h: the owner's rail / heavy mounts
	"wpn_rail_rifle": ["res://assets/wing_guns/wpn_rail_rifle.glb", Data.WING_GUN_LEN, 0.0],   # v1.9h: the owner's rail / heavy mounts
	"wpn_rail_carbine": ["res://assets/wing_guns/wpn_rail_carbine.glb", Data.WING_GUN_LEN, 0.0],   # v1.9h: the owner's rail / heavy mounts
	"wpn_twin_cannon": ["res://assets/wing_guns/wpn_twin_cannon.glb", Data.WING_GUN_LEN, 0.0],   # v1.9h: the owner's rail / heavy mounts
	"wpn_charge_cannon": ["res://assets/wing_guns/wpn_charge_cannon.glb", Data.WING_GUN_LEN, 0.0],   # v1.9h: the owner's rail / heavy mounts
	"wpn_hv_missile_turret": ["res://assets/wing_guns/wpn_hv_missile_turret.glb", Data.WING_GUN_LEN, 0.0],   # v1.9h: the owner's rail / heavy mounts
	"wpn_hv_quad_launcher": ["res://assets/wing_guns/wpn_hv_quad_launcher.glb", Data.WING_GUN_LEN, 0.0],   # v1.9h: the owner's rail / heavy mounts
	"wpn_hv_cannon_turret": ["res://assets/wing_guns/wpn_hv_cannon_turret.glb", Data.WING_GUN_LEN, 0.0],   # v1.9h: the owner's rail / heavy mounts
	"wpn_hv_rocket_arm": ["res://assets/wing_guns/wpn_hv_rocket_arm.glb", Data.WING_GUN_LEN, 0.0],   # v1.9h: the owner's rail / heavy mounts
	"wpn_hv_rail_launcher": ["res://assets/wing_guns/wpn_hv_rail_launcher.glb", Data.WING_GUN_LEN, 0.0],   # v1.9h: the owner's rail / heavy mounts
	"wpn_hv_missile_box": ["res://assets/wing_guns/wpn_hv_missile_box.glb", Data.WING_GUN_LEN, 0.0],   # v1.9h: the owner's rail / heavy mounts
	# mechs: rigged 3 m models scaled to small-ship size; yaw 180 so the mech faces -Z like the ships
	"mech_tan": ["res://assets/mechs/tan_navy_mecha.scn", 11.0, 180.0],
	"mech_player": ["res://assets/mechs/black_gold_mecha.scn", 9.5, 180.0],   # the player's ship <-> mech frame
	"mf_orange": ["res://assets/mech_frames/mf_orange.scn", 9.5, 180.0],   # v1.9i: a mech frame (pack "mf_orange")
	"mf_rifle": ["res://assets/mech_frames/mf_rifle.scn", 9.5, 180.0],   # v1.9i: a mech frame (pack "mf_rifle")
	"mf_minigun_a": ["res://assets/mech_frames/mf_minigun_a.scn", 9.5, 180.0],   # v1.9i: a mech frame (pack "mf_minigun_a")
	"mf_minigun_b": ["res://assets/mech_frames/mf_minigun_b.scn", 9.5, 180.0],   # v1.9i: a mech frame (pack "mf_minigun_b")
	"mf_teal": ["res://assets/mech_frames/mf_teal.scn", 9.5, 180.0],   # v1.9i: a mech frame (pack "mf_teal")
	"mf_white": ["res://assets/mech_frames/mf_white.scn", 9.5, 180.0],   # v1.9i: a mech frame (pack "mf_white")
	"mf_headless": ["res://assets/mech_frames/mf_headless.scn", 9.5, 180.0],   # v1.9i: a mech frame (pack "mf_headless")
	"mf_mecblu": ["res://assets/mech_frames/mf_mecblu.scn", 9.5, 180.0],   # v1.9i: a mech frame (pack "mf_mecblu")
	"mf_acmec": ["res://assets/mech_frames/mf_acmec.scn", 9.5, 180.0],   # v1.9i: a mech frame (pack "mf_acmec")
	"mf_mecbrn": ["res://assets/mech_frames/mf_mecbrn.scn", 9.5, 180.0],   # v1.9i: a mech frame (pack "mf_mecbrn")
}

static var _cache := {}
static var _mats := {}

## v8.8 (owner: rebuilt Cadet): a model may carry named weapon mounts (empties "mount_<name>"). The game uses them when
## present, else the old rule (share of the half span). Slots: -1 / -5 front guns, -6 belly, 0-5 wing slots.
static func mount_name(g: int) -> String:
	match g:
		-1: return "gun_front_L"
		-5: return "gun_front_R"
		-6: return "gun_belly"
	if g < 0: return ""
	var sd := "R" if GS.mount_side(g) > 0.0 else "L"
	var spot := "tip_bot" if GS.is_tip(g) else ("mid_top" if g >= 4 else "root_top")
	return "wing_%s_%s" % [sd, spot]

static func mount_node(model: Node, g: int) -> Node3D:
	if model == null: return null
	# v9.8 (owner: the Cadet is level 1 = 4 core mounts + 1 per wing): a level-1 ship's single core gun sits on the
	# nose centre ("mount_gun_nose"); its built-in bays are "mount_missile_light" (-2), "mount_missile_super" (-3)
	# and "mount_mine" (-4). Models without them keep the old names / the spacing rule.
	if g == -1:
		var nose := model.find_child("mount_gun_nose", true, false) as Node3D
		if nose != null: return nose
	var bay: String = {-2: "missile_light", -3: "missile_super", -4: "mine"}.get(g, "")
	if bay != "": return model.find_child("mount_" + bay, true, false) as Node3D
	var nm := mount_name(g)
	if nm == "": return null
	return model.find_child("mount_" + nm, true, false) as Node3D

static func has_real_model(key: String) -> bool:
	return GLB.has(key) and ResourceLoader.exists(GLB[key][0])

## keep = false: don't hold the model in memory after this copy is gone (hangar previews of ships you don't fly).
static func build(key: String, keep := true) -> Node3D:
	var root := Node3D.new()
	root.name = "Model_" + key
	if has_real_model(key):
		var scene: PackedScene = _cache.get(key)
		if scene == null:
			scene = load(GLB[key][0])
			if keep: _cache[key] = scene
		var inst: Node3D = scene.instantiate()
		inst.rotation_degrees.y = GLB[key][2]
		root.add_child(inst)
		_fit(root, inst, GLB[key][1])
		root.set_meta("placeholder", false)
		if Data.SHIP_FLOW.has(key): _flow(inst, Data.SHIP_FLOW[key])
		if Data.SHIP_WINGS.has(key):   # v1.5p: folding wings start folded (the open form is only for the SPECIAL)
			root.set_meta("wings_key", key)
			set_wings(root, 0.0)
		return root
	root.set_meta("placeholder", true)
	match key:
		"cadet": _fighter(root, Color(0.86, 0.9, 0.95), Color(0.2, 0.75, 1.0), 1.0, 2)
		"ranger": _fighter(root, Color(0.42, 0.47, 0.55), Color(1.0, 0.72, 0.25), 1.15, 2)
		"lancer": _heavy(root, Color(0.3, 0.32, 0.36), Color(1.0, 0.35, 0.3))
		"enemy": _raider(root, Color(0.35, 0.08, 0.08), Color(1.0, 0.3, 0.15))
		"fleet": _freighter(root, Color(0.6, 0.64, 0.7), Color(0.4, 0.8, 1.0))
		"carrier": _carrier(root, Color(0.62, 0.66, 0.72), Color(0.35, 0.8, 1.0))
		_: _fighter(root, Color.WHITE, Color.CYAN, 1.0, 2)
	return root

## v9.8 (owner: Harrier-style engines): the remodelled Cadet's two side engines (with their wings) are their own nodes
## "Nacelle_L" / "Nacelle_R", pivoted on the engine centre. They only turn about the left-right axis (pitch), never
## sideways: 0 = nozzles back (flying forward), 90 = nozzles down (going up), 180 = nozzles forward (backing up),
## -90 = nozzles up (going down). Returns the nacelle nodes (empty for ships without them).
static func nacelles(root: Node) -> Array:
	if root == null: return []
	var out: Array = []
	for nm in ["Nacelle_L", "Nacelle_R"]:
		var n := root.find_child(nm, true, false) as Node3D
		if n != null: out.append(n)
	return out

static func set_nacelle_tilt(nodes: Array, deg: float) -> void:
	for n in nodes:
		if is_instance_valid(n): (n as Node3D).rotation.x = deg_to_rad(deg)

## v1.5p folding wings: k = 0 folded in (how it flies), 1 = swung out (the SPECIAL). No-op for other ships.
static func set_wings(root: Node3D, k: float) -> void:
	if root == null or not root.has_meta("wings_key"): return
	var tuck: float = float(Data.SHIP_WINGS[root.get_meta("wings_key")]) * (1.0 - clampf(k, 0.0, 1.0))
	var wl := root.find_child("WingL", true, false) as Node3D
	var wr := root.find_child("WingR", true, false) as Node3D
	if wl: wl.position.x = tuck
	if wr: wr.position.x = -tuck
	root.set_meta("wings_open", clampf(k, 0.0, 1.0))

static func wings_open(root: Node3D) -> float:
	return float(root.get_meta("wings_open", 1.0)) if root and root.has_meta("wings_key") else -1.0

## v1.9i: an unfitted copy of a model's GLB (a mech's arms or legs are borrowed from it; never shown on its own).
static func raw(key: String) -> Node3D:
	if not has_real_model(key): return null
	var scene: PackedScene = _cache.get(key)
	if scene == null:
		scene = load(GLB[key][0])
		_cache[key] = scene
	return scene.instantiate()

## v1.9i: the pack a model's files come in ("" = always there or the shared mechs pack).
static func pack_of(key: String) -> String:
	if key.begins_with("mf_"): return key
	if key.begins_with("mech_"): return "mechs"
	return ""

## v1.9i: a mech built from three frames' parts: the core's body and skeleton, the arms' and legs' meshes on it.
static func build_mech(core_key: String, arms_key: String, legs_key: String) -> Node3D:
	var m := build(core_key)
	var arms_src: Node3D = raw(arms_key) if arms_key != core_key else null
	var legs_src: Node3D = raw(legs_key) if legs_key != core_key else null
	if arms_src != null or legs_src != null: MechParts.assemble(m, arms_src, legs_src)
	for n in [arms_src, legs_src]:
		if n != null: n.free()
	m.set_meta("mech_keys", [core_key, arms_key, legs_key])
	return m

## v6.2 (owner): a creature ship's back half waves (tentacles, tails): the model's own texture on a material whose
## vertex step bends it along the tail, more the farther back. Each ship gets its own phase so a pack never moves as one.
const FLOW_SHADER := """
shader_type spatial;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap;
uniform bool has_orm = false;
uniform vec3 tail = vec3(0.0, 0.0, 1.0);
uniform float half_len = 0.5;
uniform float amp = 0.05;
uniform float freq = 5.0;
uniform float speed = 2.0;
uniform float phase = 0.0;
void vertex() {
	float t = dot(VERTEX, tail) / half_len;            // -1 at the nose .. +1 at the tail tip
	float k = smoothstep(-0.2, 1.0, t);
	k *= k;
	vec3 side = normalize(cross(tail, vec3(0.0, 1.0, 0.0)) + vec3(0.0001));
	float w1 = sin(TIME * speed - t * freq + phase);
	float w2 = sin(TIME * speed * 0.63 - t * freq * 1.7 + phase * 1.9 + 1.3);
	VERTEX += (side * w1 + vec3(0.0, 1.0, 0.0) * w2 * 0.6) * amp * half_len * 2.0 * k;
}
void fragment() {
	vec4 c = texture(albedo_tex, UV);
	ALBEDO = c.rgb;
	if (has_orm) {
		vec3 o = texture(orm_tex, UV).rgb;
		ROUGHNESS = o.g;
		METALLIC = o.b;
	} else {
		ROUGHNESS = 0.6;
		METALLIC = 0.4;
	}
}
"""
static var _flow_shader: Shader
static func _flow(inst: Node3D, cfg: Array) -> void:
	if _flow_shader == null:
		_flow_shader = Shader.new()
		_flow_shader.code = FLOW_SHADER
	for mi: MeshInstance3D in inst.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null: continue
		var src := mi.mesh.surface_get_material(0) as BaseMaterial3D
		var box: AABB = mi.mesh.get_aabb()
		var tail: Vector3 = cfg[0]
		var m := ShaderMaterial.new()
		m.shader = _flow_shader
		if src != null and src.albedo_texture != null: m.set_shader_parameter("albedo_tex", src.albedo_texture)
		if src != null and src.metallic_texture != null:
			m.set_shader_parameter("orm_tex", src.metallic_texture)
			m.set_shader_parameter("has_orm", true)
		m.set_shader_parameter("tail", tail)
		m.set_shader_parameter("half_len", maxf(absf(box.size.dot(tail)) * 0.5, 0.001))
		m.set_shader_parameter("amp", float(cfg[1]))
		m.set_shader_parameter("freq", float(cfg[2]))
		m.set_shader_parameter("speed", float(cfg[3]))
		m.set_shader_parameter("phase", randf() * TAU)
		mi.material_override = m
		mi.set_meta("flow", true)

## Scale and centre an imported model once (never re-scaled at runtime).
static func _fit(root: Node3D, inst: Node3D, length: float) -> void:
	var box := _aabb(inst, Transform3D.IDENTITY)
	if box.size == Vector3.ZERO: return
	var longest := maxf(box.size.x, maxf(box.size.y, box.size.z))
	var s := length / longest
	inst.scale = Vector3.ONE * s
	inst.position = -box.get_center() * s

static func _aabb(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	if n is Node3D: xf = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var b: AABB = xf * (n as MeshInstance3D).mesh.get_aabb()
		out = b
		first = false
	for c in n.get_children():
		var cb := _aabb(c, xf)
		if cb.size == Vector3.ZERO: continue
		if first:
			out = cb
			first = false
		else:
			out = out.merge(cb)
	return out

static func mat(col: Color, emissive := false, metal := 0.4) -> StandardMaterial3D:
	var k := "%s|%s|%s" % [col.to_html(), emissive, metal]
	if _mats.has(k): return _mats[k]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = metal
	m.roughness = 0.45
	if emissive:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mats[k] = m
	return m

static func _part(parent: Node3D, mesh: Mesh, pos: Vector3, scl: Vector3, col: Color, rot := Vector3.ZERO, emissive := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.scale = scl
	mi.rotation_degrees = rot
	mi.material_override = mat(col, emissive)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

static var _box: BoxMesh
static var _prism: PrismMesh
static var _cyl: CylinderMesh
static var _sph: SphereMesh

static func _meshes() -> void:
	if _box: return
	_box = BoxMesh.new()
	_prism = PrismMesh.new()
	_cyl = CylinderMesh.new()
	_cyl.radial_segments = 10
	_cyl.rings = 1
	_sph = SphereMesh.new()
	_sph.radial_segments = 12
	_sph.rings = 6

static func _engine(root: Node3D, pos: Vector3, r: float, glow: Color) -> void:
	_part(root, _cyl, pos, Vector3(r, 0.5, r), Color(0.18, 0.2, 0.24), Vector3(90, 0, 0))
	var g := _part(root, _cyl, pos + Vector3(0, 0, 0.55), Vector3(r * 0.8, 0.06, r * 0.8), glow, Vector3(90, 0, 0), true)
	g.name = "EngineGlow"

static func _fighter(root: Node3D, body: Color, accent: Color, size: float, engines: int) -> void:
	_meshes()
	var s := size
	# fuselage: long nose prism + body block
	_part(root, _prism, Vector3(0, 0, -3.2 * s), Vector3(1.4 * s, 3.4 * s, 0.9 * s), body, Vector3(-90, 0, 0))
	_part(root, _box, Vector3(0, 0, 0.4 * s), Vector3(1.7 * s, 0.95 * s, 4.0 * s), body)
	_part(root, _sph, Vector3(0, 0.55 * s, -1.2 * s), Vector3(0.9 * s, 0.6 * s, 1.8 * s), Color(0.1, 0.22, 0.35))
	# swept wings
	for side in [-1.0, 1.0]:
		_part(root, _box, Vector3(side * 2.4 * s, -0.1 * s, 1.0 * s), Vector3(3.4 * s, 0.14 * s, 2.0 * s), body, Vector3(0, side * -24.0, side * -4.0))
		_part(root, _box, Vector3(side * 3.9 * s, 0.35 * s, 1.7 * s), Vector3(0.18 * s, 1.1 * s, 1.4 * s), accent)
		_part(root, _box, Vector3(side * 1.25 * s, 0.1 * s, -1.4 * s), Vector3(0.25 * s, 0.25 * s, 2.6 * s), Color(0.2, 0.22, 0.25))
	_part(root, _box, Vector3(0, 0.5 * s, 1.4 * s), Vector3(0.12 * s, 1.0 * s, 1.6 * s), accent)
	if engines == 2:
		for side in [-0.55, 0.55]: _engine(root, Vector3(side * s, 0, 2.6 * s), 0.55 * s, accent)
	else:
		_engine(root, Vector3(0, 0, 2.6 * s), 0.75 * s, accent)

static func _heavy(root: Node3D, body: Color, accent: Color) -> void:
	_meshes()
	_part(root, _prism, Vector3(0, 0, -3.8), Vector3(2.2, 3.2, 1.3), body, Vector3(-90, 0, 0))
	_part(root, _box, Vector3(0, 0, 0.6), Vector3(2.6, 1.4, 5.2), body)
	_part(root, _sph, Vector3(0, 0.8, -1.6), Vector3(1.1, 0.7, 2.0), Color(0.12, 0.16, 0.22))
	for side in [-1.0, 1.0]:
		_part(root, _box, Vector3(side * 2.7, -0.2, 1.2), Vector3(3.2, 0.3, 3.0), body, Vector3(0, side * -12.0, 0))
		_part(root, _box, Vector3(side * 4.2, -0.2, 0.2), Vector3(0.5, 0.5, 4.2), Color(0.22, 0.23, 0.26))
		_part(root, _box, Vector3(side * 4.2, 0.55, 1.8), Vector3(0.2, 1.0, 1.6), accent)
		_engine(root, Vector3(side * 1.0, 0, 3.4), 0.7, accent)
	_part(root, _box, Vector3(0, -0.85, -0.4), Vector3(0.45, 0.45, 3.6), Color(0.22, 0.23, 0.26))

static func _raider(root: Node3D, body: Color, accent: Color) -> void:
	_meshes()
	_part(root, _prism, Vector3(0, 0, -3.0), Vector3(1.2, 3.8, 0.7), body, Vector3(-90, 0, 0))
	_part(root, _box, Vector3(0, 0, 0.5), Vector3(1.5, 0.8, 3.4), Color(0.12, 0.1, 0.1))
	for side in [-1.0, 1.0]:
		_part(root, _prism, Vector3(side * 2.6, 0, 0.3), Vector3(1.4, 4.4, 0.25), body, Vector3(-90, 0, side * 90.0 + side * 18.0))
		_part(root, _box, Vector3(side * 4.2, 0, -1.3), Vector3(0.2, 0.2, 2.6), accent, Vector3.ZERO, true)
	_part(root, _prism, Vector3(0, 0.9, 1.2), Vector3(0.2, 1.4, 1.8), body)
	_engine(root, Vector3(0, 0, 2.3), 0.6, accent)

static func _freighter(root: Node3D, body: Color, accent: Color) -> void:
	_meshes()
	_part(root, _box, Vector3(0, 0, 0), Vector3(3.0, 2.4, 11.0), body)
	_part(root, _prism, Vector3(0, 0, -6.6), Vector3(3.0, 2.2, 2.4), body, Vector3(-90, 0, 0))
	for i in 3:
		_part(root, _box, Vector3(0, -1.9, -2.5 + i * 3.0), Vector3(3.6, 1.4, 2.4), Color(0.55, 0.42, 0.25))
	_part(root, _box, Vector3(0, 1.6, -4.2), Vector3(1.6, 0.8, 1.8), Color(0.1, 0.2, 0.3))
	for side in [-1.0, 1.0]: _engine(root, Vector3(side * 0.9, 0, 5.8), 0.8, accent)

static func _carrier(root: Node3D, body: Color, accent: Color) -> void:
	_meshes()
	var dark := Color(0.25, 0.28, 0.33)
	_part(root, _box, Vector3(0, 0, 0), Vector3(26, 12, 110), body)
	_part(root, _prism, Vector3(0, -1, -66), Vector3(26, 22, 12), body, Vector3(-90, 0, 0))
	_part(root, _box, Vector3(0, 8, 10), Vector3(34, 3, 86), dark) # flight deck
	for i in 8:
		_part(root, _box, Vector3(0, 9.7, -28 + i * 10), Vector3(1.5, 0.4, 5), accent, Vector3.ZERO, true)
	_part(root, _box, Vector3(12, 18, 22), Vector3(7, 16, 18), body) # island tower
	_part(root, _box, Vector3(12, 27, 20), Vector3(5, 3, 10), Color(0.1, 0.2, 0.3))
	for side in [-1.0, 1.0]:
		_part(root, _box, Vector3(side * 16, -2, 8), Vector3(8, 9, 70), dark)
		for j in 3:
			_engine(root, Vector3(side * (4 + j * 5.5), -1, 57), 2.4, accent)
