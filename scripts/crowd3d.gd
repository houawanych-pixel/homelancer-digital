extends Control
class_name Crowd3D
## v11.84 (owner: "in Freelancer they use GLB characters ... we have GLB characters and rigs, we just need a toon shader"):
## a crowd of the rigged 3D characters walking and standing on a room's floor, drawn with an anime toon shader and an
## ink outline so they sit in the painted 360 rooms. The rooms are flat 360 strips, so each character (model + move)
## is drawn once into a small transparent SubViewport, and every person in the crowd is a picture of one of those,
## placed on the floor at its depth (smaller further back) and slid with the view as you look round.
## One walk + one idle viewport per model serves any number of people: a big crowd costs almost nothing extra.

const MODELS := ["future_soldier", "phenom_ascendant_guard", "phenom_aurelian_guard", "phenom_isara", "phenom_thalen", "phenom_vyrela", "phenom_xerathion"]
const PACK := "crowd3d"
const VP_SIZE := Vector2i(320, 512)
const FRAME_LO := 0.03     # the viewport shows from 3 % of the body below the feet ...
const FRAME_HI := 1.07     # ... to 7 % above the head

const TOON := """
shader_type spatial;
render_mode diffuse_toon, specular_disabled;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec4 shade : source_color = vec4(0.7, 0.64, 0.78, 1.0);
uniform vec4 rim_col : source_color = vec4(1.0, 0.78, 0.55, 1.0);
void fragment() {
	vec3 c = texture(albedo_tex, UV).rgb * tint.rgb;
	float g = dot(c, vec3(0.299, 0.587, 0.114));
	ALBEDO = clamp(mix(vec3(g), c, 1.3) * 1.08, 0.0, 1.0);   // anime: richer colour
	ROUGHNESS = 1.0;
}
void light() {
	float n = dot(NORMAL, LIGHT);
	float band = n > 0.45 ? 1.0 : (n > 0.0 ? 0.72 : 0.0);   // anime cel bands: lit, half, shadow
	vec3 lit = mix(shade.rgb, vec3(1.0), band);
	DIFFUSE_LIGHT += ALBEDO * lit * LIGHT_COLOR * ATTENUATION / PI;
	float rim = smoothstep(0.62, 0.72, 1.0 - max(dot(NORMAL, VIEW), 0.0)) * step(0.0, n);
	DIFFUSE_LIGHT += rim * rim_col.rgb * 0.35;
}
"""

const INK := """
shader_type spatial;
render_mode unshaded, cull_front;
uniform float width = 0.012;
uniform vec4 ink : source_color = vec4(0.07, 0.05, 0.08, 1.0);
void vertex() { VERTEX += NORMAL * width; }
void fragment() { ALBEDO = ink.rgb; }
"""

var hub: Node
var room := ""                 # the room file the crowd is in ("" = no crowd)
var cfg: Dictionary = {}       # Data.CROWD3D_ROOMS[room]
var views := {}                # "<model>:<move>" -> SubViewport
var heights := {}              # model -> body height (model units)
var people: Array = []         # {model, x, d, dir, state, t, node}
var holder: Control
var crowd_log: Array = []      # (tests)
var _toon: Shader
var _ink: Shader
# v12.11 (owner): the in-game Crowd Edit tool (scripts/crowd_editor.gd, a dev tool: off before launch)
var full := ""                 # "<faction>/<room file>": the room's key for placements (set by the hub)
var edit_on := false           # editing: placed people stand still where they are put
var preview := false           # (editing, but let them walk to check their boxes)
static var edits := {}         # full -> placed list edited this session (copied out with COPY ALL)

func setup(h: Node) -> void:
	hub = h
	name = "Crowd3D"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder = Control.new()
	holder.name = "People"
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	_toon = Shader.new()
	_toon.code = TOON
	_ink = Shader.new()
	_ink.code = INK

func room_changed(file: String) -> void:
	if file == room: return
	_clear()
	room = file
	cfg = Data.CROWD3D_ROOMS.get(file, {}).duplicate()
	if file != "" and (edit_on or not placed_list().is_empty()) and not Data.CROWD3D_CREWS.has(str(cfg.get("crew", ""))): cfg["crew"] = "orion"   # (placing works in any room)
	if cfg.is_empty(): return
	var pk := _pack()
	if not Packs.is_ready(pk):
		Packs.request(pk)
		if not Packs.pack_ready.is_connected(_on_pack): Packs.pack_ready.connect(_on_pack)
		return
	_build()

func _on_pack(pk: String) -> void:
	if pk == _pack() and not cfg.is_empty() and people.is_empty(): _build()

## v12.9: the room's crowd: a faction crew (Data.CROWD3D_CREWS, its own pack) or the mixed crowd; at most
## CROWD3D_MAX_MODELS different people, picked the same way each visit.
func _pack() -> String:
	var c := str(cfg.get("crew", ""))
	return str(Data.CROWD3D_CREWS[c]["pack"]) if Data.CROWD3D_CREWS.has(c) else PACK

func _models() -> Array:
	var c := str(cfg.get("crew", ""))
	var out: Array = []
	var placed: Array = placed_list()
	if (not placed.is_empty() or edit_on) and Data.CROWD3D_CREWS.has(c):   # v12.11: the owner's own placement (Crowd Placer tool)
		var cr0: Dictionary = Data.CROWD3D_CREWS[c]
		for pl in placed:
			var path0 := "%s/HL_Orion_%s%s.glb" % [cr0["folder"], _crew_num(str(pl["model"]), cr0), cr0["suffix"]]
			if not (path0 in out): out.append(path0)
		return out
	if Data.CROWD3D_CREWS.has(c):
		var cr: Dictionary = Data.CROWD3D_CREWS[c]
		for m in cr["models"]: out.append("%s/%s%s.glb" % [cr["folder"], m, cr["suffix"]])
	else:
		for m in MODELS: out.append("res://assets/crowd3d/%s.glb" % m)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(room)
	for i in range(out.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = out[i]; out[i] = out[j]; out[j] = t
	return out.slice(0, Data.CROWD3D_MAX_MODELS)

func _clear() -> void:
	for p in people: (p["node"] as Node).queue_free()
	people.clear()
	for k in views: (views[k] as Node).queue_free()
	views.clear()

## The room's light: the still's average colour lights the crowd, so they take on the room's tint.
func _room_light() -> Color:
	var f := room.get_slice("_", 0)
	for fac in ["orion", "liberator", "unity", "covenant", "savagers", "solarion", "imperium", "elyza"]:
		var p := "res://assets/rooms/%s/%s.jpg" % [fac, room]
		if ResourceLoader.exists(p):
			var im := (load(p) as Texture2D).get_image()
			if im == null: break
			if im.is_compressed(): im.decompress()
			im.resize(1, 1)
			return im.get_pixel(0, 0)
	return Color(0.8, 0.75, 0.7)

func _build() -> void:
	var lc := _room_light()
	var paths := _models()
	for path in paths:
		var m := str(path).get_file().get_basename()
		if not ResourceLoader.exists(path): continue
		for move in ["Walk", "Walk2", "Idle"]:   # (two walks at different points in the step: copies don't march in step)
			views["%s:%s" % [m, move]] = _make_view(path, m, move, lc)
	if views.is_empty(): return
	var have: Array = []
	for path in paths:
		var m := str(path).get_file().get_basename()
		if views.has(m + ":Walk"): have.append(m)
	var placed: Array = placed_list()
	if not placed.is_empty() or edit_on:
		_build_placed(placed, have)
		return
	var n: int = int(cfg.get("count", 20))
	for i in n:
		var walking := randf() < float(cfg.get("walkers", 0.7))
		var p := {"model": have[i % have.size()], "v": 1 + (i / have.size()) % 2, "x": randf(), "d": randf(), "dir": 1.0 if randf() < 0.5 else -1.0,
			"state": "walk" if walking else "idle", "t": randf_range(3.0, 12.0)}
		var tr := TextureRect.new()
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		holder.add_child(tr)
		p["node"] = tr
		_set_tex(p)
		people.append(p)
	crowd_log.append("built:%d people, %d models" % [people.size(), have.size()])

func _make_view(path: String, model: String, move: String, lc: Color) -> SubViewport:
	var vp := SubViewport.new()
	vp.name = "%s_%s" % [model, move]
	vp.size = VP_SIZE
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_2X
	add_child(vp)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = lc.lerp(Color(1, 1, 1), 0.35)
	env.ambient_light_energy = 0.85
	we.environment = env
	vp.add_child(we)
	var key := DirectionalLight3D.new()   # the room's light from the front, high and to the side
	key.light_color = lc.lerp(Color(1, 0.95, 0.88), 0.6)
	key.light_energy = 2.1
	key.rotation_degrees = Vector3(-35, -30, 0)
	vp.add_child(key)
	var inst: Node3D = (load(path) as PackedScene).instantiate()
	vp.add_child(inst)
	var mv := move.trim_suffix("2")
	inst.rotation_degrees.y = 90.0 if mv == "Walk" else 25.0   # walking: side on, heading screen right; standing: turned a little to you
	var box := _toon_up(inst)
	var h := maxf(box.size.y, 0.1)
	heights[model] = h
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = h * (FRAME_HI + FRAME_LO)
	cam.position = Vector3(0, box.position.y + h * (FRAME_HI - FRAME_LO) * 0.5, 50.0)
	cam.far = 200.0
	vp.add_child(cam)
	cam.current = true
	var ap := _find_player(inst)
	if ap != null:
		var an := ap.get_animation_list()
		var pick := ""
		for a in an: if str(a).to_lower().ends_with(mv.to_lower()): pick = a
		if pick != "":
			ap.get_animation(pick).loop_mode = Animation.LOOP_LINEAR
			ap.play(pick)
			ap.seek(ap.current_animation_length * (0.5 if move.ends_with("2") else 0.0), true)
	return vp

## Toon + ink on every mesh; returns the body's box (model space, rest pose).
func _toon_up(inst: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in inst.find_children("*", "MeshInstance3D", true, false):
		var xf := inst.global_transform.affine_inverse() * mi.global_transform if inst.is_inside_tree() else mi.transform
		var b := xf * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
		for si in mi.mesh.get_surface_count():
			var src := mi.get_active_material(si)
			var m := ShaderMaterial.new()
			m.shader = _toon
			if src is BaseMaterial3D and (src as BaseMaterial3D).albedo_texture != null:
				m.set_shader_parameter("albedo_tex", (src as BaseMaterial3D).albedo_texture)
				m.set_shader_parameter("tint", (src as BaseMaterial3D).albedo_color)
			var ink := ShaderMaterial.new()
			ink.shader = _ink
			m.next_pass = ink
			mi.set_surface_override_material(si, m)
	# (the box is in the rotated instance's space; height is what matters, and rotation is about Y)
	for mi: MeshInstance3D in inst.find_children("*", "MeshInstance3D", true, false):
		for si in mi.mesh.get_surface_count():
			((mi.get_surface_override_material(si) as ShaderMaterial).next_pass as ShaderMaterial).set_shader_parameter("width", box.size.y * 0.0065)
	return box

func _find_player(n: Node) -> AnimationPlayer:
	for c in n.find_children("*", "AnimationPlayer", true, false): return c
	return null

func _set_tex(p: Dictionary) -> void:
	var vp: SubViewport = views.get("%s:%s" % [p["model"], ("Walk" if int(p.get("v", 1)) == 1 else "Walk2") if p["state"] == "walk" else "Idle"])
	if vp == null: vp = views.get(str(p["model"]) + ":Idle")
	(p["node"] as TextureRect).texture = vp.get_texture()

## v12.10 (owner: "match size more accurate"): people are not all one height: a share of the room's height for this
## model (Data.CROWD3D_TALL, by name; 1.0 = a tall man).
var _tall_cache := {}
func _tall(model: String) -> float:
	if not _tall_cache.has(model):
		var k := 1.0
		for key in Data.CROWD3D_TALL: if model.contains(key): k = float(Data.CROWD3D_TALL[key])
		_tall_cache[model] = k
	return float(_tall_cache[model])

## v12.11 (owner: "a tool to scale and set characters in place ... a square block of movement area per character, so
## they don't break the illusion walking over things"): people from the Crowd Placer's copied block
## (Data.CROWD3D_PLACED[room]): each stands where it was put, at its size, and walks only inside its box (its whole
## body stays in the box; it turns round at the box's sides and drifts a little deeper or nearer, growing and
## shrinking with the floor).
func placed_list() -> Array:
	if edits.has(full): return edits[full]
	return Data.CROWD3D_PLACED.get(full, Data.CROWD3D_PLACED.get(room, []))

func rebuild() -> void:
	var f := room
	room = ""
	room_changed(f)

## Screen point of a strip point (x along the loop, y down the strip), and back (the same maths as tick).
func _xf() -> Dictionary:
	var rv: Control = hub.room_view
	var mat := rv.material as ShaderMaterial
	var tex: Texture2D = mat.get_shader_parameter("strip")
	var S := get_viewport_rect().size
	var zm := Data.ROOM_ZOOM
	return {"S": S, "vw": float(mat.get_shader_parameter("vis_w")), "zm": zm, "sh": float(tex.get_height()) / float(tex.get_width()) if tex != null else 0.15,
		"shift": float(hub.room_pitch) * 0.5 * (1.0 - 1.0 / zm) * zm * S.y, "yaw": float(hub.room_yaw)}
func to_screen(x: float, y: float) -> Vector2:
	var t := _xf()
	var dx := fposmod(x - float(t["yaw"]) + 0.5, 1.0) - 0.5
	return Vector2(t["S"].x * 0.5 + dx / maxf(float(t["vw"]), 0.01) * t["S"].x, t["S"].y * (0.5 + (y - 0.5) * float(t["zm"])) - float(t["shift"]))
func from_screen(pos: Vector2) -> Vector2:
	var t := _xf()
	var x := fposmod(float(t["yaw"]) + (pos.x - t["S"].x * 0.5) / t["S"].x * float(t["vw"]), 1.0)
	return Vector2(x, ((pos.y + float(t["shift"])) / t["S"].y - 0.5) / float(t["zm"]) + 0.5)
func screen_per_strip() -> Vector2:   # pixels per 1.0 of x and of y
	var t := _xf()
	return Vector2(t["S"].x / maxf(float(t["vw"]), 0.01), t["S"].y * float(t["zm"]))
## A person after the editor changed their source entry.
func sync(p: Dictionary) -> void:
	var pl: Dictionary = p["src"]
	p["x"] = float(pl["x"]); p["feet"] = float(pl["feet"]); p["feet0"] = float(pl["feet"]); p["h0"] = float(pl["h"]); p["zone"] = pl["zone"]; p["dir"] = float(pl.get("face", 1))
	p["walker"] = bool(pl.get("walk", true))
	_set_tex(p)

func _crew_num(model: String, cr: Dictionary) -> String:
	for m in cr["models"]:
		if str(m).ends_with("_" + model): return str(m).substr(9)
	return model

func _build_placed(placed: Array, have: Array) -> void:
	for i in placed.size():
		var pl: Dictionary = placed[i]
		var key := ""
		for m in have: if str(m).contains("_" + str(pl["model"]) + "_"): key = m
		if key == "": continue
		var walking := bool(pl.get("walk", true))
		var p := {"model": key, "v": 1 + i % 2, "x": float(pl["x"]), "feet": float(pl["feet"]), "feet0": float(pl["feet"]), "h0": float(pl["h"]),
			"zone": pl.get("zone", []), "dir": float(pl.get("face", 1)), "state": "walk" if walking else "idle", "walker": walking,
			"fz": randf_range(-1.0, 1.0), "t": randf_range(3.0, 12.0), "d": clampf((float(pl["feet"]) - 0.66) / 0.22, 0.0, 1.0), "src": pl}
		if edit_on and not preview: p["state"] = "idle"
		var tr := TextureRect.new()
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		holder.add_child(tr)
		p["node"] = tr
		_set_tex(p)
		people.append(p)
	crowd_log.append("placed:%d people" % people.size())

## The placed person's floor point and height now (their box keeps them in).
func _placed_floor(p: Dictionary, dt: float, strip_h: float) -> Vector2:
	var z: Array = p["zone"]
	var fit: Array = Data.CROWD3D_PLACED_FIT.get(room, [1.0, -0.44])
	var hz := -float(fit[1]) / float(fit[0])   # (where a person would shrink to nothing: the horizon)
	var hk := func(f: float) -> float: return float(p["h0"]) * maxf(0.05, (f - hz) / maxf(0.01, float(p["feet0"]) - hz))
	if p["state"] == "walk" and z.size() == 4:
		var h: float = hk.call(float(p["feet"]))
		var half: float = h * 0.28 * strip_h   # (half a body's width, in strip widths)
		p["x"] = float(p["x"]) + float(p["dir"]) * h * strip_h * (Data.CROWD3D_WALK / 1.8) * dt
		if float(p["x"]) > float(z[2]) - half: p["x"] = float(z[2]) - half; p["dir"] = -1.0; _set_tex(p)
		if float(p["x"]) < float(z[0]) + half: p["x"] = float(z[0]) + half; p["dir"] = 1.0; _set_tex(p)
		var lo: float = float(z[1]) + h   # feet low enough that the head stays in the box ...
		var hi: float = float(z[3])       # ... and the feet stay in it
		p["feet"] = clampf(float(p["feet"]) + float(p["fz"]) * 0.004 * dt, minf(lo, hi), hi)
		if float(p["feet"]) <= minf(lo, hi) + 0.0001 or float(p["feet"]) >= hi - 0.0001: p["fz"] = -float(p["fz"])
	return Vector2(float(p["feet"]), hk.call(float(p["feet"])))

## The floor line and body height at depth d (0 = the back of the room, 1 = the front), as shares of the strip's height.
func _floor(d: float) -> Vector2:
	var b: Array = cfg.get("back", [0.68, 0.14])
	var f: Array = cfg.get("front", [0.86, 0.34])
	return Vector2(lerpf(float(b[0]), float(f[0]), d), lerpf(float(b[1]), float(f[1]), d))

func tick(dt: float) -> void:
	if people.is_empty(): return
	var rv: Control = hub.room_view
	visible = rv.visible
	if not visible: return
	var mat := rv.material as ShaderMaterial
	var tex: Texture2D = mat.get_shader_parameter("strip")
	if tex == null: return
	var S := get_viewport_rect().size
	var vw := float(mat.get_shader_parameter("vis_w"))
	var strip_h := float(tex.get_height()) / float(tex.get_width())   # the strip's height in strip widths
	var zm := Data.ROOM_ZOOM
	var shift := float(hub.room_pitch) * 0.5 * (1.0 - 1.0 / zm) * zm * S.y
	for p in people:
		var fl := _floor(float(p["d"]))
		p["t"] = float(p["t"]) - dt
		if p.has("feet") and edit_on and not preview:   # (being placed: stand still where put)
			fl = Vector2(float(p["feet"]), float(p["h0"]))
		elif p.has("feet"):   # v12.11: placed by the owner: their box, their own rhythm of walking and stopping
			fl = _placed_floor(p, dt, strip_h)
			if bool(p["walker"]) and float(p["t"]) <= 0.0:
				p["state"] = "idle" if p["state"] == "walk" else "walk"
				p["t"] = randf_range(2.5, 6.0) if p["state"] == "idle" else randf_range(6.0, 14.0)
				_set_tex(p)
		elif p["state"] == "walk":
			# normal walking speed: 1.3 m/s for a 1.8 m person, in strip widths
			p["x"] = fposmod(float(p["x"]) + float(p["dir"]) * fl.y * strip_h * (Data.CROWD3D_WALK / 1.8) * dt, 1.0)
			if float(p["t"]) <= 0.0:
				p["state"] = "idle"
				p["t"] = randf_range(2.5, 7.0)
				_set_tex(p)
		elif float(p["t"]) <= 0.0:
			p["state"] = "walk"
			p["t"] = randf_range(6.0, 16.0)
			if randf() < 0.4: p["dir"] = -float(p["dir"])
			_set_tex(p)
		var tr: TextureRect = p["node"]
		var dx := fposmod(float(p["x"]) - float(hub.room_yaw) + 0.5, 1.0) - 0.5
		var sx := S.x * 0.5 + dx / maxf(vw, 0.01) * S.x
		var body := fl.y * zm * S.y * _tall(str(p["model"]))
		var feet := S.y * (0.5 + (fl.x - 0.5) * zm) - shift
		var fh := body * (FRAME_HI + FRAME_LO)
		var fw := fh * float(VP_SIZE.x) / float(VP_SIZE.y)
		tr.size = Vector2(fw, fh)
		tr.position = Vector2(sx - fw * 0.5, feet + body * FRAME_LO - fh)
		tr.flip_h = (p["state"] == "walk" or p.has("feet")) and float(p["dir"]) < 0.0
		tr.visible = sx > -fw and sx < S.x + fw
	# nearer people in front of those further back
	people.sort_custom(func(a, b): return float(a["d"]) < float(b["d"]))
	for i in people.size(): holder.move_child(people[i]["node"], i)
