extends Control
class_name StationCrew
## v11.14 (owner: "they should appear just like Evee, they're in the game somewhere"): a faction's crew stand in its
## station rooms as moving people (magenta-screen clips keyed in the game): they walk in, stand idle, now and then
## walk a few steps to the side, and talk when you tap them (their own voice for the hello, then the call on the
## right like everyone on your side). They move between their faction's rooms over time (Data.CREW).

const KEY_SHADER := """
shader_type canvas_item;
uniform bool flip = false;
void fragment() {
	vec2 uv = UV;
	if (flip) uv.x = 1.0 - uv.x;
	vec4 c = texture(TEXTURE, uv);
	float m = min(c.r, c.b) - c.g;          // how magenta it is beyond green
	float a = 1.0 - smoothstep(0.12, 0.30, m);
	float sp = clamp(m, 0.0, 1.0);          // no pink fringe
	c.r -= sp * 0.6;
	c.b -= sp * 0.6;
	COLOR = vec4(c.rgb, c.a * a);
}
"""

var hub: Node
var who: Dictionary = {}       # the crew member in this room ({} = nobody)
var vid: VideoStreamPlayer
var hit: Control
var voice: AudioStreamPlayer
var yaw := -1.0                # where they stand in the room (share of the 360 loop)
var state := ""                # "in" (walking forward), "idle", "walk", "talk"
var state_t := 0.0
var next_walk := 0.0
var walk_from := 0.0
var walk_to := 0.0
var shown_key := ""
var crew_log: Array = []       # (tests) what they did
var force := {}               # (tests) this crew member in whatever room
var scale_ref := {}            # v11.60: the biggest person on the floor ({top, feet}: shares of the panorama)
var body_px := 0.0             # (tests) their drawn body height

func setup(h: Node) -> void:
	hub = h
	name = "Crew"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	vid = VideoStreamPlayer.new()
	vid.name = "CrewVideo"
	vid.expand = true
	vid.volume_db = -80.0
	vid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = Shader.new()
	m.shader.code = KEY_SHADER
	vid.material = m
	vid.visible = false
	vid.finished.connect(_clip_done)
	add_child(vid)
	hit = Control.new()
	hit.name = "CrewHit"
	hit.mouse_filter = Control.MOUSE_FILTER_STOP
	hit.visible = false
	hit.gui_input.connect(func(e: InputEvent):
		if (e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and not (e as InputEventMouseButton).pressed) \
				or (e is InputEventScreenTouch and not (e as InputEventScreenTouch).pressed): tap())
	add_child(hit)
	voice = AudioStreamPlayer.new()
	voice.bus = "Master"
	add_child(voice)

## Who of the faction stands in `room` right now: each one is in their home room most of the time and visits the
## others in turn (the turn changes every Data.CREW_VISIT_S seconds of real time).
static func in_room(faction: String, room: String, now := -1.0) -> Dictionary:
	var list: Array = Data.CREW.get(faction, [])
	if now < 0.0: now = Time.get_unix_time_from_system()
	var turn := int(now / Data.CREW_VISIT_S)
	for i in list.size():
		var c: Dictionary = list[i]
		if room_of(c, turn + i) == room: return c
	return {}

static func room_of(c: Dictionary, turn: int) -> String:
	var also: Array = c.get("also", [])
	var k := posmod(turn, also.size() + 2)   # (home twice as often as any one visit)
	return str(also[k]) if k < also.size() else str(c["home"])

func clip_path(clip: String) -> String:
	return "res://assets/crew/%s/%s_%s.ogv" % [str(who["faction"]), str(who["file"]), clip]

func pack_name(c: Dictionary) -> String:
	return "crew_%s_%s" % [str(c["faction"]), str(c["file"])]

## The room on screen changed (hub._show_room): the crew member here walks in, or whoever was here goes.
func room_changed(key: String) -> void:
	if key == shown_key: return
	shown_key = key
	who = {}
	vid.stop()
	vid.visible = false
	hit.visible = false
	if key == "" or not ("_" in key): return
	var f := key.get_slice("_", 0)
	var c := in_room(f, key.substr(f.length() + 1)) if force.is_empty() else force.duplicate()
	if c.is_empty(): return
	c = c.duplicate()
	c["faction"] = f
	var pk := pack_name(c)
	if not Packs.is_ready(pk):
		Packs.request(pk)
		if not Packs.pack_ready.is_connected(_on_pack): Packs.pack_ready.connect(_on_pack)
		return
	who = c
	if not ResourceLoader.exists(clip_path("idle")):
		who = {}
		return
	# v11.60 (owner: "use them to cover the seams ... in good spots"): they stand on a seam of the moving room (the
	# second worst one; Evee covers the worst), sized to the biggest people in the picture
	yaw = -1.0
	var sm: Array = hub.seams_by_badness(key)
	if sm.size() >= 2: yaw = float(sm[1])
	elif sm.size() == 1 and not hub.asst_seam: yaw = float(sm[0])
	if yaw >= 0.0: who["_home_yaw"] = yaw
	scale_ref = hub.biggest_person(key)
	_play("walk_fwd" if ResourceLoader.exists(clip_path("walk_fwd")) else "idle")
	state = "in"
	next_walk = randf_range(Data.CREW_WALK_EVERY[0], Data.CREW_WALK_EVERY[1])
	crew_log.append("in:" + str(c["id"]))

func _on_pack(pk: String) -> void:
	if shown_key != "" and pk.begins_with("crew_"):
		var k := shown_key
		shown_key = ""
		room_changed(k)

func _play(clip: String) -> void:
	vid.stream = load(clip_path(clip))
	vid.loop = clip == "idle"
	vid.set_meta("clip", clip)
	vid.play()
	vid.visible = true
	state_t = 0.0

func _clip_done() -> void:
	if who.is_empty(): return
	if state == "walk":
		yaw = walk_to
	state = "idle"
	(vid.material as ShaderMaterial).set_shader_parameter("flip", false)
	_play("idle")

func tick(dt: float) -> void:
	if who.is_empty() or not vid.visible: return
	state_t += dt
	if state == "idle":
		next_walk -= dt
		if next_walk <= 0.0 and ResourceLoader.exists(clip_path("walk_side")):
			# a few steps to one side and back over time (never far from their spot)
			var span: float = Data.CREW_WALK_SPAN
			var home := float(who.get("_home_yaw", yaw))
			walk_from = yaw
			walk_to = home + span * (1.0 if randf() < 0.5 else -1.0) if absf(yaw - home) < 0.001 else home   # (out a few steps, then back)
			(vid.material as ShaderMaterial).set_shader_parameter("flip", walk_to < walk_from)   # (the clip walks right)
			_play("walk_side")
			state = "walk"
			next_walk = randf_range(Data.CREW_WALK_EVERY[0], Data.CREW_WALK_EVERY[1])
			crew_log.append("walk")
	_place()

func _place() -> void:
	var S := get_viewport_rect().size
	var rv: Control = hub.room_view
	if not rv.visible:
		vid.visible = false
		hit.visible = false
		return
	var vw: float = float((rv.material as ShaderMaterial).get_shader_parameter("vis_w"))
	if yaw < 0.0:
		yaw = fposmod(float(hub.room_yaw) + (Data.CREW_SCREEN_X - 0.5) * vw, 1.0)
		who["_home_yaw"] = yaw
	var y_now := yaw
	if state == "walk":
		var k := clampf(state_t / maxf(0.1, Data.CREW_WALK_TIME), 0.0, 1.0)
		y_now = lerpf(walk_from, walk_to, k)
	var d := fposmod(y_now - float(hub.room_yaw) + 0.5, 1.0) - 0.5
	var x := S.x * 0.5 + d / maxf(vw, 0.01) * S.x
	var zm := Data.ROOM_ZOOM
	var shift := float(hub.room_pitch) * 0.5 * (1.0 - 1.0 / zm) * zm * S.y
	var h := S.y * Data.CREW_HEIGHT
	var feet := S.y * Data.CREW_FEET - shift
	if not scale_ref.is_empty():   # v11.60: the same head and floor lines as the biggest person in the room
		var yh := S.y * (0.5 + (float(scale_ref["top"]) - 0.5) * zm) - shift
		var yf := S.y * (0.5 + (float(scale_ref["feet"]) - 0.5) * zm) - shift
		var body := yf - yh
		if body > S.y * 0.25 and body < S.y * 1.6:
			h = body / Data.CREW_BODY_SHARE
			feet = yf + h * Data.CREW_FOOT_PAD
	if state == "in":   # walking in: they come a little closer as they arrive
		h *= lerpf(0.86, 1.0, clampf(state_t / 4.0, 0.0, 1.0))
	body_px = h * Data.CREW_BODY_SHARE
	var w := h * Data.CREW_ASPECT
	vid.size = Vector2(w, h)
	vid.position = Vector2(x - w * 0.5, feet - h)
	vid.visible = x > -w and x < S.x + w
	hit.visible = vid.visible
	hit.size = Vector2(w * 0.45, h * 0.85)
	hit.position = Vector2(x - w * 0.225, feet - h * 0.92)

## Tap: they turn to you and talk (their own voice), and their call opens on the right.
func tap() -> void:
	if who.is_empty(): return
	(vid.material as ShaderMaterial).set_shader_parameter("flip", false)
	if state == "walk": yaw = lerpf(walk_from, walk_to, clampf(state_t / Data.CREW_WALK_TIME, 0.0, 1.0))
	if ResourceLoader.exists(clip_path("talk")):
		_play("talk")
		state = "talk"
	var g := "res://assets/crew/%s/%s_greet.mp3" % [str(who["faction"]), str(who["file"])]
	if ResourceLoader.exists(g):
		Sfx.stop_voice()
		voice.stream = load(g)
		voice.play()
	var face := "res://assets/crew/%s/%s_face.png" % [str(who["faction"]), str(who["file"])]
	hub.open_call("r", str(who["name"]), "%s · %s" % [str(who["faction"]).to_upper(), str(who["role"])], str(who["line"]), face, 0.0, {"id": str(who["id"])})
	crew_log.append("talk:" + str(who["id"]))
