extends Control
## Docked base screens: Hub, Equipment Dealer, Ship Dealer, Repair/Resupply. Map and Launch are handled by main.

signal launch_requested
signal map_requested
signal galaxy_requested   # v3.1: the GALAXY MAP tile on HOME
signal descend_requested(planet_id: String, location_id: String)

const CYAN := Color(0.4, 0.86, 1.0)
const GOLD := Color(1.0, 0.82, 0.4)
const INK := Color(0.03, 0.07, 0.12, 0.74)
const TAB_H := 54.0        # v3.1: the tab bar
const TOP_Y := 68.0        # v3.1: station name, credits and LAUNCH sit under the tabs
const CONTENT_Y := 140.0   # v3.1: where the page starts
const TILE_H := 150.0      # v3.1: the picture tiles along the bottom of HOME

var base: Dictionary = {} # station or planet info from Data
var kind := "station"
var screen := "hub"
var font: Font = ThemeDB.fallback_font
var theme_obj: Theme
var left: BoxContainer   # v3.1: the tab bar along the top (was the menu column)
var content: Control
var status: Label
var header: Label
var subheader: Label
var credits_label: Label
var launch_btn: Button   # v1.5k: always there, upper right
var board_tab := "missions"   # v1.5k: the MISSION BOARD's open tab: "missions" | "bounty"
var preview_vp: SubViewport
var preview_pivot: Node3D
var _bay_art_node: Control
var _bay_node: Control
var bay_yaw := 0.0    # v2.6: the hangar turntable's turn
var bay_hold := 0.0   # s the turntable waits after you drag it or pick a slot
var preview_key := ""
var t := 0.0
# ship inspector: tap the showroom (or VIEW) to look the ship over: drag to turn it, pinch / wheel to zoom, full stats
var asst: VideoStreamPlayer   # v3.7 (owner): the station assistant, standing in the HOME room
var asst_chat: Panel
var asst_greeted := false
var asst_idle := 0
var room_view: ColorRect   # v3.5 (owner): the 360 room you stand in
var leftwin: Panel         # v3.5: the left digital window
var show_btn: Button       # v3.5: brings the folded windows back
var panels_hidden := false # v3.5: both windows folded away (only the top bar stays)
var look_motion := false   # v3.5: false = drag / stick to look; true = turn the phone
var room_override := ""    # (tests) pretend the station's faction has rooms
var room_yaw := 0.0
var room_pitch := 0.0
var room_idle := 0.0
var room_key := ""
var _motion0 := -999.0
var _motion_yaw0 := 0.0
var bg_tex: Texture2D     # v1.4s: ONE static picture behind the interface (station's own > faction's > none)
var bg := {}              # Factions.hub_background() of the place you are docked at
var inspect: Control = null
var insp_id := ""
var insp_pivot: Node3D
var insp_cam: Camera3D
var insp_yaw := 0.7
var insp_pitch := 0.25
var insp_dist := 18.0
var insp_stats: RichTextLabel
var _touches := {}   # index -> position (for pinch)
var _pinch0 := 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme_obj = _make_theme()
	theme = theme_obj
	room_view = ColorRect.new()
	room_view.name = "RoomView"
	room_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	room_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rm := ShaderMaterial.new()
	rm.shader = Shader.new()
	rm.shader.code = ROOM_SHADER
	room_view.material = rm
	room_view.visible = false
	add_child(room_view)
	asst = VideoStreamPlayer.new()   # v3.7: in front of the room, behind the windows
	asst.name = "Assistant"
	asst.expand = true
	asst.volume_db = -80.0
	asst.visible = false
	var am := ShaderMaterial.new()
	am.shader = Shader.new()
	am.shader.code = ASST_SHADER
	am.set_shader_parameter("key", Data.ASST_KEY)
	asst.material = am
	asst.finished.connect(_asst_next)
	asst.gui_input.connect(func(e: InputEvent):
		if (e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and not (e as InputEventMouseButton).pressed) \
				or (e is InputEventScreenTouch and not (e as InputEventScreenTouch).pressed): asst_tap())
	add_child(asst)
	header = _label(32, Color(1, 1, 1))
	header.position = Vector2(28, TOP_Y)
	add_child(header)
	subheader = _label(15, CYAN)
	subheader.position = Vector2(30, TOP_Y + 44)
	add_child(subheader)
	credits_label = _label(22, GOLD)
	credits_label.anchor_left = 1.0
	credits_label.anchor_right = 1.0
	credits_label.offset_left = -760
	credits_label.offset_right = -36 - Data.HUB_LAUNCH_SIZE.x - 20
	credits_label.offset_top = TOP_Y + 14
	credits_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(credits_label)
	# v1.5k: LAUNCH is always on screen (upper right, under the credits), on every page: you can never be stuck here
	launch_btn = Button.new()
	launch_btn.name = "LaunchButton"
	launch_btn.text = "LAUNCH"
	launch_btn.anchor_left = 1.0
	launch_btn.anchor_right = 1.0
	launch_btn.offset_left = -36 - Data.HUB_LAUNCH_SIZE.x
	launch_btn.offset_right = -36
	launch_btn.offset_top = TOP_Y
	launch_btn.offset_bottom = TOP_Y + Data.HUB_LAUNCH_SIZE.y
	launch_btn.add_theme_font_size_override("font_size", Data.ts(26))
	launch_btn.add_theme_color_override("font_color", Color(1, 1, 1))
	launch_btn.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	var lsb := StyleBoxFlat.new()
	lsb.bg_color = Color(0.12, 0.62, 0.28)
	lsb.border_color = Color(0.55, 1.0, 0.65)
	lsb.set_border_width_all(3)
	lsb.set_corner_radius_all(10)
	launch_btn.add_theme_stylebox_override("normal", lsb)
	var lsh := lsb.duplicate() as StyleBoxFlat
	lsh.bg_color = Color(0.18, 0.75, 0.36)
	launch_btn.add_theme_stylebox_override("hover", lsh)
	launch_btn.add_theme_stylebox_override("pressed", lsh)
	launch_btn.pressed.connect(func(): launch_requested.emit())
	# v3.1 (owner's concept art): the station's services as a tab bar along the top
	left = HBoxContainer.new()
	left.name = "Tabs"
	left.anchor_right = 1.0
	left.offset_left = 10
	left.offset_right = -10
	left.offset_top = 6
	left.offset_bottom = 6 + TAB_H
	left.add_theme_constant_override("separation", 4)
	add_child(left)
	content = Panel.new()
	content.anchor_left = 0.0
	content.anchor_right = 1.0
	content.anchor_bottom = 1.0
	content.offset_left = 24
	content.offset_top = CONTENT_Y
	content.offset_right = -24
	content.offset_bottom = -66
	add_child(content)
	leftwin = Panel.new()   # v3.5: the left digital window (where you are, your ship, the view buttons)
	leftwin.name = "LeftWindow"
	leftwin.offset_left = 24
	leftwin.offset_top = CONTENT_Y
	leftwin.anchor_right = Data.ROOM_SPLIT
	leftwin.offset_right = -6
	leftwin.anchor_bottom = 1.0
	leftwin.offset_bottom = -66
	leftwin.visible = false
	add_child(leftwin)
	asst_chat = Panel.new()   # v3.7: what she says, and a line to type to her
	asst_chat.name = "AssistantChat"
	asst_chat.anchor_left = 0.5
	asst_chat.anchor_right = 0.5
	asst_chat.offset_left = -240
	asst_chat.offset_right = 240
	asst_chat.offset_top = CONTENT_Y
	asst_chat.offset_bottom = CONTENT_Y + 150
	asst_chat.visible = false
	var cv := VBoxContainer.new()
	cv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cv.offset_left = 14
	cv.offset_top = 10
	cv.offset_right = -10
	cv.offset_bottom = -10
	asst_chat.add_child(cv)
	var said := _label(16, Color.WHITE)
	said.name = "Said"
	said.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	said.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cv.add_child(said)
	var row := HBoxContainer.new()
	cv.add_child(row)
	var ed := LineEdit.new()
	ed.name = "AskLine"
	ed.placeholder_text = "Ask her something..."
	ed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ed.text_submitted.connect(func(t: String): asst_ask(t))
	row.add_child(ed)
	var sb := Button.new()
	sb.name = "AskSend"
	sb.text = "SEND"
	sb.pressed.connect(func(): asst_ask(ed.text))
	row.add_child(sb)
	var xb := Button.new()
	xb.text = "X"
	xb.pressed.connect(func(): asst_chat.visible = false)
	row.add_child(xb)
	add_child(asst_chat)
	show_btn = Button.new()
	show_btn.name = "ShowPanels"
	show_btn.text = "HIDE PANELS"
	show_btn.anchor_top = 1.0
	show_btn.anchor_bottom = 1.0
	show_btn.offset_left = 24
	show_btn.offset_right = 214
	show_btn.offset_top = -64
	show_btn.offset_bottom = -12
	show_btn.add_theme_font_size_override("font_size", Data.ts(16))
	show_btn.visible = false
	show_btn.pressed.connect(func(): set_panels_hidden(not panels_hidden))
	add_child(show_btn)
	status = _label(17, GOLD)
	status.anchor_top = 1.0
	status.anchor_bottom = 1.0
	status.anchor_right = 1.0
	status.offset_left = 230
	status.offset_top = -60
	status.offset_bottom = -10
	status.offset_right = -24
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status)
	add_child(launch_btn)   # last child: drawn over everything, nothing can cover it
	GS.changed.connect(_refresh_credits)
	Packs.pack_ready.connect(func(pk: String):
		if visible and pk == bg.get("pack", "-"): _load_background())
	visibility_changed.connect(func():
		if not visible: bg_tex = null)   # leaving the station lets the picture go
	visible = false

## The static faction picture for this station: asked for when you dock, shown as soon as it is in.
func _load_background() -> void:
	bg = Factions.hub_background(base, Data.SYSTEMS[GS.system_id])
	bg_tex = null
	if bg["path"] != "":
		Packs.request(bg["pack"])
		if ResourceLoader.exists(bg["path"]): bg_tex = load(bg["path"])
	queue_redraw()

func _label(size: int, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", Data.ts(size))
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 5)
	return l

func _make_theme() -> Theme:
	var th := Theme.new()
	var mk := func(bg: Color, edge: Color) -> StyleBoxFlat:
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg
		sb.border_color = edge
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(10)
		sb.content_margin_left = 16
		sb.content_margin_right = 16
		sb.content_margin_top = 10
		sb.content_margin_bottom = 10
		return sb
	th.set_stylebox("normal", "Button", mk.call(Color(0.03, 0.08, 0.14, Data.HUB_BUTTON_ALPHA), Color(CYAN, 0.6)))
	th.set_stylebox("hover", "Button", mk.call(Color(0.08, 0.2, 0.32, 0.9), CYAN))
	th.set_stylebox("pressed", "Button", mk.call(Color(0.15, 0.35, 0.5, 0.98), CYAN))
	th.set_stylebox("focus", "Button", mk.call(Color(0, 0, 0, 0), Color(0, 0, 0, 0)))
	th.set_stylebox("disabled", "Button", mk.call(Color(0.03, 0.05, 0.08, Data.HUB_BUTTON_ALPHA * 0.85), Color(1, 1, 1, 0.15)))
	th.set_font_size("font_size", "Button", Data.ts(21))
	th.set_color("font_color", "Button", Color(0.93, 0.97, 1.0))
	th.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.35))
	th.set_stylebox("panel", "Panel", mk.call(Color(INK, Data.HUB_PANEL_ALPHA), Color(CYAN, 0.35)))
	# v3.1: the top tabs (dark glass, the open one lit blue with a bright edge underneath)
	th.set_type_variation("HubTab", "Button")
	var tab := func(bg: Color, edge: Color, under: int) -> StyleBoxFlat:
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg
		sb.border_color = edge
		sb.set_border_width_all(1)
		sb.border_width_bottom = under
		sb.corner_radius_top_left = 8
		sb.corner_radius_top_right = 8
		sb.content_margin_left = 4
		sb.content_margin_right = 4
		return sb
	th.set_stylebox("normal", "HubTab", tab.call(Color(0.02, 0.05, 0.1, 0.88), Color(CYAN, 0.22), 2))
	th.set_stylebox("hover", "HubTab", tab.call(Color(0.05, 0.14, 0.24, 0.92), Color(CYAN, 0.6), 2))
	th.set_stylebox("pressed", "HubTab", tab.call(Color(0.08, 0.26, 0.44, 0.95), CYAN, 4))
	th.set_stylebox("focus", "HubTab", StyleBoxEmpty.new())
	th.set_font_size("font_size", "HubTab", Data.ts(15))
	th.set_color("font_color", "HubTab", Color(0.8, 0.9, 1.0))
	th.set_color("font_hover_color", "HubTab", Color.WHITE)
	th.set_font_size("font_size", "Label", Data.ts(18))
	return th

func open(station_or_planet: Dictionary) -> void:
	base = station_or_planet
	kind = base.get("kind", "station")
	visible = true
	_load_background()
	show_screen("hub")
	status.text = "Docked at %s. Shields and energy restored. REPAIR and RESTOCK are at Equipment." % base["name"]
	if GS.ore_worth(str(base["name"])) > 0: status.text = "Docked at %s. You carry gold / diamond worth %d cr here: sell it under YOUR SHIP." % [base["name"], GS.ore_worth(str(base["name"]))]

func _refresh_credits() -> void:
	credits_label.text = "CREDITS  %d cr" % GS.credits

func show_screen(s: String) -> void:
	close_inspector()
	_dragged = false   # (a drag left over from the last page must not swallow the next tap)
	screen = s
	_refresh_credits()
	var sysname: String = Data.SYSTEMS[GS.system_id]["name"]
	header.text = base["name"].to_upper() if s == "hub" else {"equipment": "WEAPONS & EQUIPMENT DEALER", "ships": "SHIP DEALER", "mechs": "MECH DEALER", "repair": "REPAIR & RESUPPLY", "bounty": "MISSION BOARD", "missions": "MISSION BOARD", "board": "MISSION BOARD", "ship": "YOUR SHIP", "faction": "FACTION", "surface": "PLANET DESTINATIONS", "lounge": "PILOTS' LOUNGE"}[s]
	subheader.text = "%s  ·  %s SYSTEM  ·  %s" % ["ORBITAL STATION" if kind == "station" else "PLANET SURFACE", sysname.to_upper(), base["name"]]
	for box in [left, content, leftwin]:   # take the old page out at once, so the new buttons keep their own names
		for c in box.get_children():
			box.remove_child(c)
			c.queue_free()
	preview_vp = null
	var hangar := s == "equipment"   # v1.9x: the HANGAR uses the whole width (BACK returns to the station menu)
	left.visible = not hangar
	var top := 22.0 if hangar else TOP_Y   # v3.1: no tabs in the hangar, so the name goes back up
	header.position.y = top
	subheader.position.y = top + 44.0
	content.offset_top = 112 if hangar else CONTENT_Y
	if hangar: header.text = "HANGAR"
	# v3.1: HOME is open glass (the station picture shows through); the other pages keep their panel
	if s == "hub": content.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	else: content.remove_theme_stylebox_override("panel")
	var menu := [["hub", "HOME"], ["equipment", "HANGAR"], ["ships", "SHIPS"], ["mechs", "MECHS"], ["repair", "REPAIR"], ["board", "MISSIONS"], ["lounge", "LOUNGE"], ["ship", "MY SHIP"], ["faction", "FACTION"], ["map", "NAV MAP"]]   # (v1.5k: LAUNCH is its own always-visible button)
	if _surface_planet() != "": menu.insert(5, ["surface", "SURFACE"])
	for m in menu:
		var b := Button.new()
		b.text = m[1]
		b.theme_type_variation = "HubTab"
		b.custom_minimum_size = Vector2(60, TAB_H)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = true
		b.name = "Btn_" + m[0]
		if m[0] == s or (m[0] == "board" and s in ["missions", "bounty"]):
			b.add_theme_stylebox_override("normal", theme_obj.get_stylebox("pressed", "HubTab"))
			b.add_theme_stylebox_override("hover", theme_obj.get_stylebox("pressed", "HubTab"))
			b.add_theme_color_override("font_color", Color.WHITE)
		b.pressed.connect(_menu.bind(m[0]))
		left.add_child(b)
	_layout_windows(s)
	match s:
		"lounge": _lounge_page()
		"hub": _hub_page()
		"equipment": _equipment_page()
		"ships":
			Packs.request("lancer")
			Packs.request("ranger")
			Packs.request("hauler")
			Packs.request("bulk")
			_ships_page()
		"mechs":   # v1.9i: the frames you own come in first (their parts make your mech)
			for fid in GS.owned_mechs:
				var pk := ShipFactory.pack_of(str(Data.MECHS[fid]["model"]))
				if pk != "": Packs.request(pk)
			_mechs_page()
		"repair": _repair_page()
		"board": show_screen(board_tab)
		"bounty":
			board_tab = "bounty"
			_bounty_page()
		"missions":
			board_tab = "missions"
			_missions_page()
		"ship": _ship_page()
		"faction": _faction_page()
		"surface": _surface_page()
	queue_redraw()

## v3.5 (owner): the same frame on every page: the top bar, the left digital window, the room in the middle, the page
## in the right window. HIDE PANELS folds both windows away so you can stand in the room and look round.
const ROOM_SHADER := """
shader_type canvas_item;
uniform sampler2D strip : repeat_enable, filter_linear;
uniform float yaw = 0.0;
uniform float pitch = 0.0;
uniform float vis_w = 0.3;
uniform float zoom = 1.14;
uniform float wash = 0.12;
uniform float band = 0.16;
void fragment() {
	float x = yaw + (UV.x - 0.5) * vis_w;
	float y = 0.5 + (UV.y - 0.5) / zoom + pitch * 0.5 * (1.0 - 1.0 / zoom);
	vec3 c = texture(strip, vec2(x, y)).rgb * (1.0 - wash);
	c *= mix(0.5, 1.0, smoothstep(0.0, band, UV.y));   // the top bar reads over it
	COLOR = vec4(c, 1.0);
}
"""

const ASST_SHADER := """
shader_type canvas_item;
uniform vec4 key : source_color = vec4(0.08, 0.75, 0.1, 1.0);
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float g = c.g - max(c.r, c.b);          // how green it is beyond the other two
	float a = 1.0 - smoothstep(0.12, 0.32, g);
	c.g = min(c.g, max(c.r, c.b) + 0.04);  // no green fringe
	COLOR = vec4(c.rgb, c.a * a);
}
"""

## v3.7: she shows on HOME (when her clips are in) and stands at her spot in the room.
func _asst_show(s: String) -> void:
	var on := s == "hub" and Packs.is_ready("assistant") and ResourceLoader.exists("res://assets/assistant/idle_a.ogv")
	if s == "hub" and not Packs.is_ready("assistant"):
		Packs.request("assistant")
		if not Packs.pack_ready.is_connected(_on_asst_pack): Packs.pack_ready.connect(_on_asst_pack)
	if on and not asst.visible:
		asst.visible = true
		_asst_play("idle_a")
	elif not on:
		asst.visible = false
		asst.stop()
		asst_chat.visible = false

func _on_asst_pack(pk: String) -> void:
	if pk == "assistant" and visible: _asst_show(screen)

func _asst_play(clip: String) -> void:
	asst.stream = load("res://assets/assistant/%s.ogv" % clip)
	asst.set_meta("clip", clip)
	asst.play()

func _asst_next() -> void:
	if not asst.visible: return
	asst_idle += 1
	_asst_play("idle_b" if asst_idle % 3 == 2 else "idle_a")

func _asst_place() -> void:
	if not asst.visible: return
	var S := get_viewport_rect().size
	var h := S.y * Data.ASST_HEIGHT
	var w := h * 320.0 / 486.0
	var x := S.x * 0.5
	if room_view.visible:   # she keeps her spot in the room as you look round
		var vw: float = float((room_view.material as ShaderMaterial).get_shader_parameter("vis_w"))
		var d := fposmod(Data.ASST_YAW - room_yaw + 0.5, 1.0) - 0.5
		x = S.x * 0.5 + d / maxf(vw, 0.01) * S.x
	asst.size = Vector2(w, h)
	asst.position = Vector2(x - w * 0.5, S.y - h - 58.0)

## Tap her: she says hello (her own voice the first time), and the talk line opens.
func asst_tap() -> void:
	asst_chat.visible = true
	_asst_play("talk")
	var said: Label = asst_chat.find_child("Said", true, false)
	if not asst_greeted:
		asst_greeted = true
		_asst_voice()
		said.text = "Hi, pilot. Ask me anything about the station."
	else: said.text = "Yes, pilot?"

func _asst_voice() -> void:
	var ap := AudioStreamPlayer.new()
	ap.stream = load("res://assets/assistant/greet.mp3")
	add_child(ap)
	ap.finished.connect(ap.queue_free)
	ap.play()

## Ask her something: the brain answers (the rule engine for now; Echo Vision's brain plugs in through Brain.responder).
func asst_ask(t: String) -> void:
	if t.strip_edges() == "": return
	var ed: LineEdit = asst_chat.find_child("AskLine", true, false)
	ed.text = ""
	var ctx := {"system": GS.system_id, "hostiles": 0, "kills": GS.kills, "credits": GS.credits, "station": str(base.get("name", ""))}
	Brain.ask("assistant", t, ctx, func(line: String):
		var clean := line
		if clean.begins_with("["): clean = clean.substr(clean.find("]") + 1)
		clean = clean.strip_edges()
		if clean != "": clean = clean[0].to_upper() + clean.substr(1)
		(asst_chat.find_child("Said", true, false) as Label).text = clean
		_asst_play("talk")
		if Sfx.voice_on(): Sfx.read_aloud(clean, "", 1.15, true))

func _room_faction() -> String:
	if room_override != "": return room_override
	var f := str(Factions.owner_of(base, Data.SYSTEMS[GS.system_id])).to_lower()
	if f.begins_with("liberator"): f = "liberator"
	return f if f in Data.ROOM_FACTIONS else ""

## The room for this page: "" when the faction's rooms are not in yet (the station picture shows instead).
func room_for(s: String) -> String:
	var f := _room_faction()
	if f == "" or not Data.ROOM_OF.has(s): return ""
	return "%s_%s" % [f, Data.ROOM_OF[s]]

func _show_room(s: String) -> void:
	var key := room_for(s)
	if key == "":
		room_view.visible = false
		room_key = ""
		return
	var f := key.get_slice("_", 0)
	var rn := key.substr(f.length() + 1)
	var pk := "room_" + key
	var path := "res://assets/rooms/%s/%s.jpg" % [f, rn]
	if not (Packs.is_ready(pk) and ResourceLoader.exists(path)):
		Packs.request(pk)
		if not Packs.pack_ready.is_connected(_on_room_pack): Packs.pack_ready.connect(_on_room_pack)
		room_view.visible = false
		return
	var m := room_view.material as ShaderMaterial
	if key != room_key:   # a new room: face its front, and let the last picture go
		room_key = key
		room_yaw = Data.ROOM_FRONT
		room_pitch = 0.0
		room_idle = 0.0
		m.set_shader_parameter("strip", load(path))
	room_view.visible = true
	_update_room(0.0)

func _on_room_pack(pk: String) -> void:
	if visible and pk.begins_with("room_") and pk == "room_" + room_for(screen): _show_room(screen)

## Look round: drag (in screen pixels), the right stick, or the phone itself.
func look_by(rel: Vector2) -> void:
	var S := get_viewport_rect().size
	var m := room_view.material as ShaderMaterial
	room_yaw = fposmod(room_yaw - rel.x / maxf(S.x, 1.0) * float(m.get_shader_parameter("vis_w")), 1.0)
	room_pitch = clampf(room_pitch - rel.y / maxf(S.y, 1.0) * 2.5, -1.0, 1.0)
	room_idle = 0.0

func _update_room(dt: float) -> void:
	if not room_view.visible: return
	var m := room_view.material as ShaderMaterial
	var tex: Texture2D = m.get_shader_parameter("strip")
	var S := get_viewport_rect().size
	if tex != null and S.y > 0.0:
		m.set_shader_parameter("vis_w", (S.x / S.y) * (float(tex.get_height()) / float(tex.get_width())) / Data.ROOM_ZOOM)
	var sx := Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var sy := Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	if absf(sx) > 0.2 or absf(sy) > 0.2:   # the right stick looks round (the left stick has nothing to walk in a picture)
		room_yaw = fposmod(room_yaw + sx * Data.ROOM_STICK * dt, 1.0)
		room_pitch = clampf(room_pitch + sy * 1.2 * dt, -1.0, 1.0)
		room_idle = 0.0
	if look_motion: _motion_look()
	room_idle += dt
	if room_idle > Data.ROOM_DRIFT_AFTER and not look_motion: room_yaw = fposmod(room_yaw + Data.ROOM_DRIFT * dt, 1.0)
	m.set_shader_parameter("yaw", room_yaw)
	m.set_shader_parameter("pitch", room_pitch)
	m.set_shader_parameter("zoom", Data.ROOM_ZOOM)
	m.set_shader_parameter("wash", Data.ROOM_WASH)
	m.set_shader_parameter("band", 116.0 / maxf(S.y, 1.0))

## v3.5 (owner: "like VR"): with LOOK set to MOTION, turning the phone turns the view (the web page reads the phone's
## heading; iPhones ask for permission on the next tap).
func set_look_motion(on: bool) -> void:
	look_motion = on
	_motion0 = -999.0
	if on and OS.has_feature("web"): JavaScriptBridge.eval("window.hlMotionStart && window.hlMotionStart()")

func _motion_look() -> void:
	var heading := -999.0
	if OS.has_feature("web"):
		var a = JavaScriptBridge.eval("(window.hlMotion && window.hlMotion.on && window.hlMotion.a !== null) ? window.hlMotion.a : -999")
		heading = float(a) if a != null else -999.0
	else:
		var g := Input.get_gyroscope()
		if g != Vector3.ZERO:
			_motion_yaw0 -= g.y * get_process_delta_time() / TAU
			room_yaw = fposmod(_motion_yaw0, 1.0)
		return
	if heading < -900.0: return
	if _motion0 < -900.0:
		_motion0 = heading
		_motion_yaw0 = room_yaw
	room_yaw = fposmod(_motion_yaw0 + (_motion0 - heading) / 360.0, 1.0)
	room_idle = 0.0

func set_panels_hidden(h: bool) -> void:
	panels_hidden = h
	_layout_windows(screen)

## Where the windows sit for this page (the hangar and HOME keep their own layouts).
func _layout_windows(s: String) -> void:
	_show_room(s)
	_asst_show(s)
	var split: bool = not (s in ["hub", "equipment"])
	content.anchor_left = Data.ROOM_SPLIT if split else 0.0
	content.offset_left = 6.0 if split else 24.0
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE if s == "hub" else Control.MOUSE_FILTER_STOP
	var fold: bool = panels_hidden and s != "equipment"
	content.visible = not fold
	leftwin.visible = split and not fold
	show_btn.visible = s != "equipment"
	show_btn.text = "SHOW PANELS" if fold else "HIDE PANELS"
	if leftwin.visible and leftwin.get_child_count() == 0: _left_window(s)

## v3.5: where a page's model goes: the left window when it is open, else the page itself (h).
func _left_slot(h: Control) -> Control:
	var sl: Control = leftwin.find_child("LeftSlot", true, false)
	return sl if sl != null and leftwin.visible else h

func _left_window(s: String) -> void:
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 16
	v.offset_top = 14
	v.offset_right = -14
	v.offset_bottom = -12
	v.add_theme_constant_override("separation", 6)
	leftwin.add_child(v)
	var rn := _label(20, Color.WHITE)
	rn.name = "RoomName"
	rn.text = str(Data.ROOM_OF.get(s, s)).replace("_", " ").to_upper()
	rn.clip_text = true
	v.add_child(rn)
	var at := _label(14, CYAN)
	at.text = "%s  ·  %s" % [str(base.get("name", "")), str(Factions.owner_of(base, Data.SYSTEMS[GS.system_id]))]
	at.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(at)
	var sh := GS.ship()
	var you := _label(14, Color(0.85, 0.92, 1.0))
	you.name = "YouNow"
	you.text = "%s\nHull %d / %d  ·  Shield %d\nMissiles %d / %d  ·  Heavy %d / %d\nMines %d / %d" % [str(sh["name"]).to_upper(), int(GS.hull), int(GS.max_hull()), int(GS.max_shield()),
		GS.missiles, GS.max_missiles(), GS.heavy_missiles, GS.max_heavy(), GS.mines, GS.max_mines()]
	v.add_child(you)
	var slot := VBoxContainer.new()   # a page can put its model here (the ship or mech you are looking at)
	slot.name = "LeftSlot"
	slot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(slot)
	if room_view.visible or room_for(s) != "":
		var lk := Button.new()
		lk.name = "LookMode"
		lk.text = "LOOK: TURN PHONE" if look_motion else "LOOK: DRAG"
		lk.custom_minimum_size = Vector2(0, 44)
		lk.clip_text = true
		lk.add_theme_font_size_override("font_size", Data.ts(15))
		lk.pressed.connect(func():
			set_look_motion(not look_motion)
			lk.text = "LOOK: TURN PHONE" if look_motion else "LOOK: DRAG"
			status.text = "Turn your phone to look round (tap once more if it asks to allow motion)." if look_motion else "Drag the room, or use the right stick, to look round.")
		v.add_child(lk)

## v3.5: the pilots' lounge: who is here to talk to.
func _lounge_page() -> void:
	var v := _page_box()
	var cap := _label(18, GOLD)
	cap.text = "PILOTS' LOUNGE"
	v.add_child(cap)
	_people_rows(v)
	if Factions.people_at(base, Data.SYSTEMS[GS.system_id]).is_empty():
		var none := _label(16, Color(0.8, 0.88, 1.0))
		none.text = "No pilots here right now."
		v.add_child(none)

func _gui_input(e: InputEvent) -> void:
	if not room_view.visible: return
	if e is InputEventScreenDrag:
		look_by((e as InputEventScreenDrag).relative)
		accept_event()
	elif e is InputEventMouseMotion and ((e as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT):
		look_by((e as InputEventMouseMotion).relative)
		accept_event()

func _menu(id: String) -> void:
	if id == "launch": launch_requested.emit()
	elif id == "map": map_requested.emit()
	else: show_screen(id)

## v1.5k: a page that scrolls (the MISSION BOARD's lists can be longer than the panel).
func _scroll_box() -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.name = "Scroll"
	sc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sc.offset_left = 24
	sc.offset_top = 18
	sc.offset_right = -14
	sc.offset_bottom = -12
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.offset_right = -96   # v1.7v (owner: "I can't scroll down"): room for the big UP / DOWN tabs on the right
	content.add_child(sc)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_theme_constant_override("separation", 10)
	sc.add_child(v)
	for d in [-1, 1]:
		var b := Button.new()
		b.name = "ScrollUp" if d < 0 else "ScrollDown"
		b.text = "UP" if d < 0 else "DOWN"   # v1.8y (owner: one was bigger than the other): plain words, one size
		b.custom_minimum_size = Vector2(80, 120)
		b.clip_text = true
		b.add_theme_font_size_override("font_size", 20)
		var tight := (theme_obj.get_stylebox("normal", "Button") as StyleBoxFlat).duplicate() as StyleBoxFlat   # v3.1: "DOWN" fits
		tight.content_margin_left = 4
		tight.content_margin_right = 4
		b.add_theme_stylebox_override("normal", tight)
		b.anchor_left = 1.0
		b.anchor_right = 1.0
		b.anchor_top = 0.0 if d < 0 else 1.0
		b.anchor_bottom = b.anchor_top
		b.offset_left = -88
		b.offset_right = -8
		b.offset_top = 18.0 if d < 0 else -138.0
		b.offset_bottom = b.offset_top + 120.0
		b.pressed.connect(func(): scroll_board(sc, d))
		content.add_child(b)
	return v

## v1.7v: the UP / DOWN tabs move a board list most of a screen at a time.
func scroll_board(sc: ScrollContainer, d: int) -> void:
	var step: float = maxf(160.0, sc.size.y * 0.7)
	var to: float = clampf(sc.scroll_vertical + d * step, 0.0, maxf(0.0, sc.get_v_scroll_bar().max_value - sc.size.y))
	create_tween().tween_property(sc, "scroll_vertical", int(to), 0.25)

func _page_box() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 24
	v.offset_top = 18
	v.offset_right = -24
	v.offset_bottom = -18
	v.add_theme_constant_override("separation", 10)
	content.add_child(v)
	return v

## v1.5l: the people of this station (coordinator; the leader too at a capital): face, name, role, and TALK.
func _people_rows(v: VBoxContainer) -> void:
	var folk: Array = Factions.people_at(base, Data.SYSTEMS[GS.system_id])
	if folk.is_empty(): return
	var head := _label(18, GOLD)
	head.text = "AT THIS STATION"
	v.add_child(head)
	var row := HBoxContainer.new()
	row.name = "People"
	row.add_theme_constant_override("separation", 18)
	for who in folk:
		var p: Dictionary = who["pilot"]
		var card := HBoxContainer.new()
		card.name = "Person_" + str(p["id"])
		card.add_theme_constant_override("separation", 8)
		var pic := TextureRect.new()
		pic.custom_minimum_size = Vector2(72, 72)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		if ResourceLoader.exists(str(p["portrait_clean"])): pic.texture = load(str(p["portrait_clean"]))
		card.add_child(pic)
		var col := VBoxContainer.new()
		var nm := _label(16, Color(1, 1, 1))
		nm.text = "%s\n%s" % [str(p["name"]), "Leader · " + str(p["type"]).trim_prefix("Level 6 ") if who["role"] == "leader" else "Coordinator · " + str(p["type"]).substr(8)]
		col.add_child(nm)
		var tb := Button.new()
		tb.name = "Talk_" + str(p["id"])
		tb.text = "TALK"
		tb.custom_minimum_size = Vector2(110, 38)
		var line := ("%s, %s. Welcome to %s." % [p["name"], str(Data.ROSTERS[p["faction"]].get("title", p["faction"])), base["name"]]) if who["role"] == "leader" else ("%s here. I have work for you on the Mission Board." % p["name"])
		tb.pressed.connect(func():
			status.text = "%s: %s" % [p["name"], line]
			Sfx.play_character_voice(str(p.get("voice_id", p["id"])), "", line, float(p.get("voice", 1.0)), str(p.get("sex", "")) == "female"))
		col.add_child(tb)
		card.add_child(col)
		row.add_child(card)
	v.add_child(row)

func _hub_page() -> void:
	# v3.1 (owner's concept art): HOME = the station card on the left, your pilot and ship on the right, the station
	# picture open in the middle, and picture tiles for the main services along the bottom.
	var lc := _home_card(Rect2(0, 0, 360, 0), "StationCard")
	lc.anchor_bottom = 1.0
	lc.offset_bottom = -TILE_H - 14.0
	var v := lc.get_child(0).get_child(0) as VBoxContainer
	v.add_child(_caption("STATION  ·  " + str(Factions.owner_of(base, Data.SYSTEMS[GS.system_id])).to_upper()))
	var l := _label(15, Color(1, 1, 1))
	l.name = "Lore"
	l.text = base.get("desc", "")
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(l)
	_people_rows(v)
	_standing_rows(v)
	var rc := _home_card(Rect2(0, 0, 380, 0), "ShipCard")
	rc.anchor_left = 1.0
	rc.anchor_right = 1.0
	rc.offset_left = -380
	rc.offset_right = 0
	rc.anchor_bottom = 1.0
	rc.offset_bottom = -TILE_H - 14.0
	var rv := rc.get_child(0).get_child(0) as VBoxContainer
	rv.add_child(_caption("PILOT"))
	var pn := _label(18, Color.WHITE)
	pn.name = "PilotName"
	pn.text = (GS.pilot_name if GS.pilot_name != "" else "Freelancer").to_upper()
	rv.add_child(pn)
	var cr := _label(16, GOLD)
	cr.text = "%s cr" % _thousands(GS.credits)
	rv.add_child(cr)
	var sh := GS.ship()
	rv.add_child(_caption("CURRENT SHIP"))
	var sn := _label(16, Color.WHITE)
	sn.name = "ShipName"
	sn.text = "%s  ·  %s" % [sh["name"], sh["class"]]
	sn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rv.add_child(sn)
	var best := {"speed": 1.0, "hull": 1.0, "shield": 1.0, "guns": 1.0}
	for k in Data.SHIPS:
		for st in best: best[st] = maxf(best[st], float(Data.SHIPS[k][st]))
	for bar in [["SPEED", float(sh["speed"]) / best["speed"]], ["FIREPOWER", float(sh["guns"]) / best["guns"]],
			["SHIELD", GS.max_shield() / best["shield"]], ["HULL", float(GS.hull) / best["hull"]]]:
		rv.add_child(_stat_bar(bar[0], bar[1]))
	var info := _label(13, CYAN)
	info.name = "Loadout"
	info.text = "%s ×%d  ·  Missiles %d/%d  ·  Heavy %d/%d  ·  Mines %d/%d" % [GS.weapon()["name"], sh["guns"], GS.missiles, GS.max_missiles(), GS.heavy_missiles, GS.max_heavy(), GS.mines, GS.max_mines()]
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rv.add_child(info)
	# the picture tiles (each one opens its page)
	var row := HBoxContainer.new()
	row.name = "Tiles"
	row.anchor_top = 1.0
	row.anchor_bottom = 1.0
	row.anchor_right = 1.0
	row.offset_top = -TILE_H
	row.add_theme_constant_override("separation", 10)
	content.add_child(row)
	var lead: Dictionary = Factions.leader(Factions.owner_of(base, Data.SYSTEMS[GS.system_id]))
	for tl in [["equipment", "HANGAR", "Weapons & upgrades", "res://assets/ui/weapons/laser_cannon.png"],
			["ships", "SHIP DEALER", "Buy new ships", "res://assets/ui/ship_lv2.png"],
			["mechs", "MECH DEALER", "Frames & parts", "res://assets/ui/mech_lv2.png"],
			["board", "MISSIONS", "Jobs & bounties", "res://assets/missions/escort.png"],
			["faction", "COMMAND", "Faction & standing", str(lead.get("portrait_clean", ""))],
			["galaxy", "GALAXY MAP", "Explore & travel", "res://assets/nav/nebula.jpg"]]:
		row.add_child(_tile(tl[0], tl[1], tl[2], tl[3], row.get_child_count()))

## v3.1: a dark glass card on the HOME page holding a VBox (child 0).
func _home_card(r: Rect2, nm: String) -> PanelContainer:
	var pc := PanelContainer.new()
	pc.name = nm
	pc.position = r.position
	pc.custom_minimum_size = Vector2(r.size.x, 0)
	pc.offset_right = r.size.x
	pc.add_theme_stylebox_override("panel", _glass())
	var sc := ScrollContainer.new()   # (more lore or people than fit: the card scrolls instead of growing)
	sc.name = "Scroll"
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	pc.add_child(sc)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 4)
	sc.add_child(v)
	content.add_child(pc)
	return pc

func _caption(t: String) -> Label:
	var c := _label(14, CYAN)
	c.text = t
	c.add_theme_constant_override("outline_size", 0)
	return c

func _thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out

## v3.1: a labelled stat bar (0..1) like the concept art's CURRENT SHIP panel.
func _stat_bar(nm: String, k: float) -> Control:
	var h := HBoxContainer.new()
	h.name = "Stat_" + nm
	var lb := _label(12, Color(0.85, 0.92, 1.0))
	lb.text = nm
	lb.custom_minimum_size = Vector2(130, 0)
	lb.add_theme_constant_override("outline_size", 0)
	h.add_child(lb)
	var bar := Control.new()
	bar.custom_minimum_size = Vector2(0, 18)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var kk := clampf(k, 0.04, 1.0)
	bar.draw.connect(func():
		var y := bar.size.y * 0.5 - 4.0
		bar.draw_rect(Rect2(0, y, bar.size.x, 8), Color(1, 1, 1, 0.1))
		bar.draw_rect(Rect2(0, y, bar.size.x * kk, 8), CYAN)
		bar.draw_rect(Rect2(0, y - 2, bar.size.x * kk, 12), Color(CYAN, 0.18)))
	h.add_child(bar)
	return h

## v3.1: a picture tile for HOME: a slice of the station picture behind, the service's own picture on it, the name
## on a dark strip at the foot with an arrow. Tap = open that page.
func _tile(id: String, title: String, sub: String, pic_path: String, idx: int) -> Button:
	var b := Button.new()
	b.name = "Tile_" + id
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(120, TILE_H)
	for st in ["normal", "hover", "pressed", "focus"]: b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	var pic: Texture2D = load(pic_path) if pic_path != "" and ResourceLoader.exists(pic_path) else null
	var hot := [false]
	b.mouse_entered.connect(func(): hot[0] = true; b.queue_redraw())
	b.mouse_exited.connect(func(): hot[0] = false; b.queue_redraw())
	b.draw.connect(func():
		var R := Rect2(Vector2.ZERO, b.size)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.02, 0.05, 0.1, 0.92)
		sb.set_corner_radius_all(8)
		b.draw_style_box(sb, R)
		var art := R.grow(-3)
		art.size.y -= 50.0
		if bg_tex != null:   # a different slice of the station picture for each tile
			var tw := bg_tex.get_width()
			var th := bg_tex.get_height()
			var rw := minf(tw * 0.3, th * art.size.x / art.size.y)
			var rh := rw * art.size.y / art.size.x
			var src := Rect2((tw - rw) * (0.08 + 0.84 * idx / 5.0), th * 0.35, rw, rh)
			b.draw_texture_rect_region(bg_tex, art, src, Color(0.42, 0.5, 0.6))
		if pic != null:
			var ps := pic.get_size()
			if pic_path.ends_with(".jpg") or id == "board":   # a picture: fill the tile
				var k := maxf(art.size.x / ps.x, art.size.y / ps.y)
				var src2 := Rect2((ps - art.size / k) * 0.5, art.size / k)
				b.draw_texture_rect_region(pic, art, src2, Color(1, 1, 1, 0.95))
			else:   # an icon or portrait: stand it in the middle
				var k2 := minf(art.size.x * 0.8 / ps.x, art.size.y * 0.92 / ps.y)
				var sz := ps * k2
				b.draw_texture_rect(pic, Rect2(art.position + (art.size - sz) * Vector2(0.5, 0.55), sz), false)
		var band := Rect2(R.position + Vector2(0, R.size.y - 52), Vector2(R.size.x, 52))
		b.draw_rect(band, Color(0.02, 0.05, 0.1, 0.95))
		b.draw_line(band.position, band.position + Vector2(band.size.x, 0), Color(CYAN, 0.7), 2.0)
		b.draw_string(font, band.position + Vector2(10, 22), title, HORIZONTAL_ALIGNMENT_LEFT, band.size.x - 34, Data.ts(14), Color.WHITE)
		b.draw_string(font, band.position + Vector2(10, 44), sub, HORIZONTAL_ALIGNMENT_LEFT, band.size.x - 34, Data.TEXT_FLOOR, Color(0.7, 0.8, 0.9))
		b.draw_string(font, band.position + Vector2(band.size.x - 24, 36), ">", HORIZONTAL_ALIGNMENT_LEFT, -1, Data.ts(20), CYAN)
		var edge := StyleBoxFlat.new()
		edge.draw_center = false
		edge.border_color = CYAN if hot[0] else Color(CYAN, 0.45)
		edge.set_border_width_all(2)
		edge.set_corner_radius_all(8)
		b.draw_style_box(edge, R))
	b.pressed.connect(func():
		if id == "galaxy": galaxy_requested.emit()
		else: _menu(id))
	return b

func _equipment_page() -> void:
	# v1.9y (owner's hangar layout + bay art): the docking bay fills the screen (the faction's hangar art, a looping clip
	# when there is one), YOUR ship on the pad seen from above with a square on every slot, the menu floating on the
	# left (HANGAR / WEAPON / EQUIPMENT / REPAIR & AMMO), the panel for that section floating on the right.
	bay_yaw = 0.0   # v2.6: each time the page is built it faces you first, then starts turning
	bay_hold = Data.BAY_SPIN_WAIT
	if not GS.level_def()["uv"].has(eq_sel) and eq_sel < 100: eq_sel = -1
	if eq_sel >= 100 and eq_sel - 100 >= GS.module_slots(): eq_sel = -1
	if not (eq_tab in ["hangar", "weapon", "module", "ammo"]): eq_tab = "hangar"
	var root := Control.new()
	root.name = "Hangar"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.clip_contents = true
	content.add_child(root)
	root.draw.connect(func(): root.draw_rect(Rect2(Vector2.ZERO, root.size), Color(0.05, 0.06, 0.08)))
	var art := _bay_art()
	root.add_child(art)
	_bay_art_node = art
	# the bay (middle): the ship and its slot squares
	var bay := Control.new()
	bay.name = "HangarBay"
	bay.anchor_right = 0.6
	bay.anchor_bottom = 1.0
	bay.offset_left = 206
	bay.offset_right = -8
	bay.offset_bottom = -48
	root.add_child(bay)
	root.resized.connect(func(): _place_bay_art(art, bay))
	bay.resized.connect(func(): _place_bay_art(art, bay))
	get_tree().process_frame.connect(func(): _place_bay_art(art, bay), CONNECT_ONE_SHOT)
	_bay_node = bay
	_hangar_bay(bay)
	var mods := Control.new()   # the module slots along the bottom of the bay
	mods.anchor_right = 0.6
	mods.anchor_top = 1.0
	mods.anchor_bottom = 1.0
	mods.offset_left = 206
	mods.offset_right = -8
	mods.offset_top = -44
	root.add_child(mods)
	_module_strip(mods)
	# left: the menu
	var lp := PanelContainer.new()
	lp.name = "HangarMenu"
	lp.add_theme_stylebox_override("panel", _glass())
	lp.anchor_bottom = 1.0
	lp.offset_left = 4
	lp.offset_top = 4
	lp.offset_right = 198
	lp.clip_contents = true
	lp.offset_bottom = -4
	root.add_child(lp)
	var menu := VBoxContainer.new()
	menu.add_theme_constant_override("separation", 6)
	lp.add_child(menu)
	var back := Button.new()
	back.name = "HangarBack"
	back.text = "◀ STATION"
	back.clip_text = true
	back.add_theme_font_size_override("font_size", Data.ts(15))
	back.custom_minimum_size = Vector2(0, 42)
	back.pressed.connect(func(): show_screen("hub"))
	menu.add_child(back)
	for tb in [["hangar", "HANGAR"], ["weapon", "WEAPON"], ["module", "EQUIPMENT"], ["ammo", "REPAIR & AMMO"]]:
		var b := Button.new()
		b.name = "Tab_" + tb[0]
		b.text = tb[1]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 52)
		b.clip_text = true
		b.add_theme_font_size_override("font_size", Data.ts(16))
		if eq_tab == tb[0]:
			b.add_theme_color_override("font_color", GOLD)
			b.add_theme_stylebox_override("normal", _glass(true))
		var tid: String = tb[0]
		b.pressed.connect(func():
			eq_tab = tid
			eq_card = ""
			show_screen("equipment"))
		menu.add_child(b)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	menu.add_child(sp)
	var vw := Button.new()
	vw.name = "EqView"
	vw.text = "SHOW SHIP" if _eq_mech() else "SHOW MECH"
	vw.clip_text = true
	vw.add_theme_font_size_override("font_size", Data.ts(15))
	vw.custom_minimum_size = Vector2(0, 44)
	vw.pressed.connect(func():
		eq_view = "ship" if _eq_mech() else "mech"
		show_screen("equipment"))
	menu.add_child(vw)
	# right: the section's panel
	var rp := PanelContainer.new()
	rp.name = "HangarPanel"
	rp.add_theme_stylebox_override("panel", _glass())
	rp.anchor_left = 0.6
	rp.anchor_right = 1.0
	rp.anchor_bottom = 1.0
	rp.offset_left = 2
	rp.offset_top = 4
	rp.offset_right = -4
	rp.offset_bottom = -4
	root.add_child(rp)
	var shop := VBoxContainer.new()
	shop.name = "Shop"
	shop.add_theme_constant_override("separation", 5)
	rp.add_child(shop)
	var dock := VBoxContainer.new()   # HANGAR: dock status, the ship's level and its status
	dock.name = "DockStatus"
	dock.visible = eq_tab == "hangar"
	dock.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dock.add_theme_constant_override("separation", 5)
	shop.add_child(dock)
	_dock_status(dock)
	var sec := VBoxContainer.new()
	sec.visible = eq_tab != "hangar"
	sec.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sec.add_theme_constant_override("separation", 5)
	shop.add_child(sec)
	_shop_panel(sec)

## The see-through navy panels the hangar floats over the bay (lit = the open menu item).
func _glass(lit := false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.08, 0.14, 0.86) if not lit else Color(0.06, 0.2, 0.33, 0.95)
	sb.border_color = Color(0.3, 0.75, 1.0, 0.75)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb

## HANGAR panel: DOCK STATUS (the level wireframe, your frame among the three) and SHIP STATUS.
func _dock_status(v: VBoxContainer) -> void:
	var t := _label(16, CYAN)
	t.text = "DOCK STATUS  ·  DOCKED  ·  %s" % str(base.get("name", "")).to_upper()
	t.clip_text = true
	v.add_child(t)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 6)
	v.add_child(row)
	var bp := TextureRect.new()
	bp.name = "DockBlueprint"
	bp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bp.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bp.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var ap: String = GS.level_def()["mech_icon" if _eq_mech() else "icon"]
	if ResourceLoader.exists(ap): bp.texture = load(ap)
	row.add_child(bp)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 4)
	row.add_child(lv)
	_ship_select(lv)
	_spec_bar(v)

## v2.7 (owner): the bay behind everything, a front view: the faction's own (each its own small pack), else a spare.
func _hangar_name() -> String:
	var f := str(Factions.owner_of(base, Data.SYSTEMS[GS.system_id])).to_lower()
	if f.begins_with("liberator"): f = "liberator"
	if f.begins_with("savager"): f = "savagers"
	if f.begins_with("cybermorph"): f = "cybermorph"
	if kind == "planet" and Data.BAYS.has("p_" + f): return "p_" + f   # v2.8 (owner): on a planet, the planet hangar
	if Data.BAYS.has(f) and not (f in Data.BAY_SPARES): return f
	return Data.BAY_SPARES[absi(hash(str(base.get("id", base.get("name", ""))))) % Data.BAY_SPARES.size()]

func _bay_art() -> Control:
	var nm := _hangar_name()
	var tr := TextureRect.new()
	tr.name = "BayArt"
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pk := "hangar_" + nm
	var path := "res://assets/hangars/bay_%s.jpg" % nm
	if Packs.is_ready(pk) and ResourceLoader.exists(path): tr.texture = load(path)
	else:
		Packs.request(pk)
		if not Packs.pack_ready.is_connected(_on_hangar_pack): Packs.pack_ready.connect(_on_hangar_pack)
	return tr

func _on_hangar_pack(pk: String) -> void:
	if visible and screen == "equipment" and pk.begins_with("hangar_"): show_screen("equipment")

## The bay picture covers the page, centred on the bay, its floor along the bottom; the ship or mech stands on its pad.
func _place_bay_art(art: Control, bay: Control) -> void:
	if not is_instance_valid(art) or not is_instance_valid(bay): return
	var root := art.get_parent() as Control
	if root == null: return
	var asp := 1672.0 / 941.0
	if art is TextureRect and (art as TextureRect).texture != null: asp = (art as TextureRect).texture.get_width() / float((art as TextureRect).texture.get_height())
	var hm: float = maxf(root.size.y, (bay.size.x + 400.0) / asp)
	art.size = Vector2(hm * asp, hm)
	art.position = Vector2(bay.position.x + bay.size.x * 0.5 - art.size.x * 0.5, root.size.y - hm)
	_stand_model(art, bay)
	var mm0: Control = bay.find_child("MountMap", true, false)
	if mm0 != null: mm0.queue_redraw()

## The bay: your ship (or mech) on the pad, a square on every slot.
func _hangar_bay(bay: Control) -> void:
	if _eq_mech() and _mech_bay(bay): return
	if _eq_mech():
		var mm := Control.new()   # (until the mech's packs are in: its cut-out picture with the same slots)
		mm.name = "MountMap"
		mm.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mm.mouse_filter = Control.MOUSE_FILTER_STOP
		bay.add_child(mm)
		mm.draw.connect(func(): _draw_mount_map(mm))
		mm.gui_input.connect(func(e: InputEvent): _bay_tap(e, _mount_points(mm.size), mm))
		return
	var svc := SubViewportContainer.new()
	svc.name = "LoadoutPreview"
	svc.stretch = true
	svc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bay.add_child(svc)
	preview_vp = SubViewport.new()
	preview_vp.own_world_3d = true
	preview_vp.transparent_bg = true
	svc.add_child(preview_vp)
	var cam := Camera3D.new()
	cam.name = "BayCam"
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 15.0
	preview_vp.add_child(cam)
	cam.look_at_from_position(Data.SHIP_BAY_VIEW.normalized() * 80.0, Vector3.ZERO, Vector3.UP)   # v2.7: front-right, from above
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 150, 0)
	light.light_energy = 1.5
	preview_vp.add_child(light)
	var we := WorldEnvironment.new()
	we.environment = Environment.new()
	we.environment.background_mode = Environment.BG_CLEAR_COLOR
	we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	we.environment.ambient_light_color = Color(0.75, 0.78, 0.85)
	we.environment.ambient_light_energy = 1.2
	preview_vp.add_child(we)
	preview_pivot = Node3D.new()
	preview_pivot.name = "Turntable"
	preview_vp.add_child(preview_pivot)
	var m := ShipFactory.build(Data.SHIPS[GS.ship_id]["model"], true)
	preview_pivot.add_child(m)
	preview_key = GS.ship_id
	var bb0: AABB = ShipFactory._aabb(m, Transform3D.IDENTITY)   # (in the turntable's space: includes its scale)
	var span: float = maxf(bb0.size.x, bb0.size.z)
	if span > 0.01:
		m.scale *= 11.5 / span
		m.position = -ShipFactory._aabb(m, Transform3D.IDENTITY).get_center()   # centred on the turntable
	_dress_mounts(m)
	var ov := Control.new()   # the slot squares, placed where each slot sits on the ship
	ov.name = "MountMap"
	ov.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_STOP
	bay.add_child(ov)
	ov.draw.connect(func(): _draw_slots(ov, _ship_slot_points(cam, m, ov.size)))
	ov.gui_input.connect(func(e: InputEvent): _bay_tap(e, _ship_slot_points(cam, m, ov.size), ov))
	ov.resized.connect(func(): ov.queue_redraw())

## v2.4 (owner: "mech hangar, use the real GLB mech"): your mech, built from its fitted parts, standing in the bay seen
## from the front, a square on every slot. False while its packs are still coming (the picture stands in meanwhile).
func _mech_bay(bay: Control) -> bool:
	var k: Dictionary = GS.mech_keys()
	var waiting := false
	for pk in ["mechs"] + k.values().map(func(x): return ShipFactory.pack_of(str(x))):
		if pk == "" or Packs.is_ready(pk): continue
		waiting = true
		Packs.request(pk)
	if waiting:
		if not Packs.pack_ready.is_connected(_on_mech_bay_pack): Packs.pack_ready.connect(_on_mech_bay_pack)
		return false
	var svc := SubViewportContainer.new()
	svc.name = "LoadoutPreview"
	svc.stretch = true
	svc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bay.add_child(svc)
	preview_vp = SubViewport.new()
	preview_vp.own_world_3d = true
	preview_vp.transparent_bg = true
	svc.add_child(preview_vp)
	var m := ShipFactory.build_mech(str(k["core"]), str(k["arms"]), str(k["legs"]))
	m.name = "BayMech"
	preview_pivot = Node3D.new()
	preview_pivot.name = "Turntable"
	preview_vp.add_child(preview_pivot)
	preview_pivot.add_child(m)
	preview_key = "mech"
	var bb: AABB = ShipFactory._aabb(m, Transform3D.IDENTITY)
	var hgt: float = maxf(bb.size.y, 0.5)
	var c0: Vector3 = bb.get_center()
	m.position = Vector3(-c0.x, 0.0, -c0.z)   # (centred on the turntable)
	var c := Vector3(0.0, c0.y, 0.0)
	var cam := Camera3D.new()
	cam.name = "BayCam"
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = hgt / 0.8   # (_stand_model sizes it to the pad)
	preview_vp.add_child(cam)
	cam.look_at_from_position(Vector3(c.x, c.y, c.z - 80.0), c, Vector3.UP)   # in front of it (its front faces -Z)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-30, 160, 0)
	light.light_energy = 1.4
	preview_vp.add_child(light)
	var we := WorldEnvironment.new()
	we.environment = Environment.new()
	we.environment.background_mode = Environment.BG_CLEAR_COLOR
	we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	we.environment.ambient_light_color = Color(0.78, 0.8, 0.88)
	we.environment.ambient_light_energy = 1.1
	preview_vp.add_child(we)
	var ov := Control.new()
	ov.name = "MountMap"
	ov.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_STOP
	bay.add_child(ov)
	ov.draw.connect(func(): _draw_slots(ov, _mech_slot_points(cam, m, ov.size)))
	ov.gui_input.connect(func(e: InputEvent): _bay_tap(e, _mech_slot_points(cam, m, ov.size), ov))
	ov.resized.connect(func(): ov.queue_redraw())
	return true

## v2.6/2.7 (owner): the ship or mech stands on the bay's round pad (its base on the pad's centre), sized to the picture.
func _stand_model(art: Control, bay: Control) -> void:
	var cam: Camera3D = bay.find_child("BayCam", true, false)
	if cam == null or not is_instance_valid(preview_pivot) or preview_pivot.get_child_count() == 0 or not is_instance_valid(preview_vp): return
	var m := preview_pivot.get_child(0) as Node3D
	var vs := Vector2(preview_vp.size)
	if vs.y <= 1.0 or bay.size.y <= 1.0: return
	var B: Basis = cam.global_transform.basis
	var bb: AABB = ShipFactory._aabb(m, Transform3D.IDENTITY)
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	var min_y := 1e9
	for i in 8:   # (its corners as it stands facing you, on the turntable)
		var p: Vector3 = bb.get_endpoint(i)   # (_aabb already includes the model's own place and scale)
		var q := Vector2(p.dot(B.x), p.dot(B.y))
		lo = lo.min(q)
		hi = hi.max(q)
		min_y = minf(min_y, p.y)
	var k: float = vs.y / bay.size.y   # viewport pixels per screen pixel
	var mech := m.name == "BayMech"
	var pad_y: float = float(Data.BAYS.get(_hangar_name(), 0.85))
	var feet: float = art.position.y + pad_y * art.size.y - bay.position.y   # (screen px from the bay's top)
	if mech:   # v3.3 (owner's screenshot): never taller than the room above the pad (its head was cut off)
		var tall: float = minf(art.size.y * Data.MECH_ON_PAD, feet * 0.9)
		cam.size = maxf(hi.y - lo.y, 0.1) * vs.y / maxf(tall * k, 20.0)
	else: cam.size = maxf(hi.x - lo.x, 0.1) * vs.y / maxf(minf(art.size.y * Data.SHIP_ON_PAD, bay.size.x * 0.9) * k, 20.0)
	var ty: float = feet * k   # where its base goes
	var tx: float = vs.x * 0.5
	var base_pt := Vector3(0.0, min_y, 0.0)
	cam.global_position = base_pt - B.x * ((tx - vs.x * 0.5) * cam.size / vs.y) + B.y * ((ty - vs.y * 0.5) * cam.size / vs.y) + B.z * 80.0

func _on_mech_bay_pack(pk: String) -> void:
	if visible and screen == "equipment" and _eq_mech() and (pk == "mechs" or pk.begins_with("mf_")): show_screen("equipment")

## The mech's slots on screen: the level's slot layout (the owner's sheet) laid over the model's outline as the camera
## sees it, nudged apart where they crowd.
func _mech_slot_points(cam: Camera3D, m: Node3D, sz: Vector2) -> Dictionary:
	var out := {}
	if not is_instance_valid(cam) or not is_instance_valid(m) or not is_instance_valid(preview_vp): return out
	var bb: AABB = ShipFactory._aabb(m, Transform3D.IDENTITY)
	var vs := Vector2(preview_vp.size)
	if vs.x <= 0.0: return out
	if cos(bay_yaw) < 0.15: return out   # (its back to you: the slots are on its front)
	var uv: Dictionary = GS.level_def()["mech_uv"]
	for kk in uv:   # (the camera looks along +Z, so screen-left is +X)
		var u: Vector2 = uv[kk]
		var lp := Vector3(lerpf(bb.end.x, bb.position.x, u.x), lerpf(bb.end.y, bb.position.y, u.y), bb.get_center().z)
		out[kk] = cam.unproject_position(preview_pivot.global_transform * lp) * (sz / vs)
	return _spread(out, 34.0) if _facing() else out

## The three frames (levels): their wireframes, yours lit. A tap on another says which ships are that level.
func _ship_select(col: Control) -> void:
	var fl := _label(13, CYAN)
	fl.text = "MECH LEVEL" if _eq_mech() else "SHIP LEVEL"
	col.add_child(fl)
	for lv in [1, 2, 3]:
		var ld: Dictionary = Data.LEVELS[lv]
		var fb := Button.new()
		fb.name = "Frame_%d" % lv
		fb.custom_minimum_size = Vector2(120, 62)
		fb.size_flags_vertical = Control.SIZE_EXPAND_FILL
		fb.expand_icon = true
		fb.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fb.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		var ap: String = ld["mech_icon" if _eq_mech() else "icon"]
		if ResourceLoader.exists(ap): fb.icon = load(ap)
		fb.text = "LV %d  %s" % [lv, str(ld["mech_name" if _eq_mech() else "name"]).to_upper()]
		fb.clip_text = true
		fb.add_theme_font_size_override("font_size", Data.ts(10))
		if lv == GS.ship_level():
			fb.add_theme_color_override("font_color", GOLD)
			fb.add_theme_stylebox_override("normal", _glass(true))
		var lvv: int = lv
		fb.pressed.connect(func():
			if lvv == GS.ship_level(): status.text = "You are flying a Level %d frame." % lvv
			else:
				var nms: Array = Data.SHIP_LEVEL.keys().filter(func(k): return int(Data.SHIP_LEVEL[k]) == lvv).map(func(k): return Data.SHIPS[k]["name"])
				status.text = "Level %d: %s. Buy one at the SHIP DEALER." % [lvv, ", ".join(nms)])
		col.add_child(fb)

func _bay_tap(e: InputEvent, pts: Dictionary, c: Control = null) -> void:
	if (e is InputEventMouseButton and (e as InputEventMouseButton).pressed) or (e is InputEventScreenTouch and (e as InputEventScreenTouch).pressed): _dragged = false
	var drag := Vector2.ZERO
	if e is InputEventScreenDrag: drag = (e as InputEventScreenDrag).relative
	elif e is InputEventMouseMotion and ((e as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT): drag = (e as InputEventMouseMotion).relative
	if drag != Vector2.ZERO:   # v2.6: drag sideways to turn it on the platform
		bay_yaw = fmod(bay_yaw + drag.x * 0.012, TAU)
		bay_hold = Data.BAY_SPIN_WAIT
		_dragged = true
		return
	if _dragged and ((e is InputEventMouseButton and not (e as InputEventMouseButton).pressed) or (e is InputEventScreenTouch and not (e as InputEventScreenTouch).pressed)):
		_dragged = false
		return
	var tap := (e is InputEventScreenTouch and not (e as InputEventScreenTouch).pressed) or (e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and not (e as InputEventMouseButton).pressed)
	if not tap: return
	var at: Vector2 = (e as InputEventMouseButton).position if e is InputEventMouseButton else (e as InputEventScreenTouch).position
	if c != null and c.has_meta("pts"): pts = c.get_meta("pts")   # v3.5: tap what is drawn (the camera may have moved since)
	var k := _slot_at(at, pts, c)
	if k > -9:
		bay_yaw = 0.0   # face front so its tags show
		bay_hold = Data.BAY_SPIN_WAIT
		eq_sel = k
		eq_tab = "ammo" if k in [-2, -3, -4] else "weapon"
		show_screen("equipment")

## The slot under a tap: its square (with a finger's margin) or its name tag.
var _dragged := false
func _slot_at(at: Vector2, pts: Dictionary, c: Control = null) -> int:
	var best := -9
	var bd := 30.0
	for k in pts:
		var d: float = at.distance_to(pts[k])
		if d < bd:
			bd = d
			best = k
	if best == -9 and c != null:
		var tags := _slot_layout(c.size, pts, _slot_half(c))
		for k in tags:
			if (tags[k] as Rect2).grow(3.0).has_point(at): return k
	return best

## Where each of the ship's slots sits on screen: the same spots the guns are fitted at, seen by the bay camera.
func _ship_slot_points(cam: Camera3D, m: Node3D, sz: Vector2) -> Dictionary:
	var out := {}
	if not is_instance_valid(cam) or not is_instance_valid(m) or not is_instance_valid(preview_vp): return out
	var bb: AABB = ShipFactory._aabb(m, Transform3D.IDENTITY)
	var hw: float = maxf(bb.size.x * 0.5, 0.5)
	var ln: float = maxf(bb.size.z, 1.0)
	var c: Vector3 = bb.get_center()
	var loc := {-2: Vector3(-hw * 0.16, 0, 0.0), -3: Vector3(hw * 0.16, 0, 0.0), -4: Vector3(0, 0, ln * 0.28)}
	var guns: Array = GS.core_slots()
	for k in guns:
		var ox := 0.0
		if guns.size() > 1 and k in [-1, -5]: ox = hw * (0.14 if k == -5 else -0.14)
		loc[k] = Vector3(ox, 0, -ln * (0.05 if k == -6 else 0.34))
	for g in 6:
		if not GS.mount_open(g): continue
		var at: float = Data.MOUNT_TIP_AT if GS.is_tip(g) else (Data.MOUNT_MID_AT if g >= 4 else Data.MOUNT_SHOULDER_AT)
		loc[g] = Vector3(GS.mount_side(g) * hw * at, 0, ln * (0.12 if GS.is_tip(g) else 0.02))
	var vs := Vector2(preview_vp.size)
	for k in loc:
		var wp: Vector3 = preview_pivot.global_transform * (Vector3(c.x, bb.end.y, c.z) + loc[k])
		var sp: Vector2 = cam.unproject_position(wp)
		out[k] = sp * (sz / vs) if vs.x > 0.0 else sp
	return _spread(out, 34.0) if _facing() else out

## v2.2: on a narrow hull the slots crowd together; nudge them apart (sideways first) so every square can be tapped.
func _spread(pts: Dictionary, gap: float) -> Dictionary:
	var ks: Array = pts.keys()
	for it in 24:
		var moved := false
		for i in ks.size():
			for j in range(i + 1, ks.size()):
				var a: Vector2 = pts[ks[i]]
				var b: Vector2 = pts[ks[j]]
				var d := b - a
				if absf(d.x) >= gap or absf(d.y) >= gap: continue
				moved = true
				var push := (gap - absf(d.x)) * 0.5 + 0.5
				var dir := signf(d.x) if absf(d.x) > 0.5 else (1.0 if (ks[j] as int) % 2 == 0 else -1.0)
				if absf(d.y) > absf(d.x) * 1.5:   # stacked: part them up and down instead
					var py := (gap - absf(d.y)) * 0.5 + 0.5
					pts[ks[i]] = a - Vector2(0, py * signf(d.y))
					pts[ks[j]] = b + Vector2(0, py * signf(d.y))
				else:
					pts[ks[i]] = a - Vector2(push * dir, 0)
					pts[ks[j]] = b + Vector2(push * dir, 0)
		if not moved: break
	return pts

const SLOT_LABEL := {-1: "CORE GUN", -5: "CORE GUN 2", -6: "BELLY GUN", -2: "MISSILES", -3: "SUPER MSL", -4: "MINES",
	0: "LEFT WING", 1: "LEFT TIP", 4: "LEFT MID", 2: "RIGHT WING", 3: "RIGHT TIP", 5: "RIGHT MID"}
func _slot_color(k: int) -> Color:
	var items: Array = GS.mount_items()
	match k:
		-1, -5, -6: return Data.WEAPONS[GS.core_item(k)]["color"]
		-2: return Color(1.0, 0.72, 0.3)
		-3: return Data.HEAVY_LOCK_COLOR
		-4: return Color(1.0, 0.3, 0.25)
	var it: String = str(items[k])
	if Data.WEAPONS.has(it): return Data.WEAPONS[it]["color"]
	if Data.MOUNT_PODS.has(it): return Color(1.0, 0.6, 0.25)
	return Color(0.4, 0.85, 1.0)

## v2.2 (owner's concept): every slot is a square on the ship with a "+" when it is empty (the weapon's picture when it
## holds one), and a line out to its name tag at the side. Tap the square or its tag to pick that slot.
var _icon_cache := {}
func _wicon(id: String) -> Texture2D:
	var path := Data.weapon_icon(id, _eq_mech())
	if path == "" or not ResourceLoader.exists(path): return null
	if not _icon_cache.has(path): _icon_cache[path] = load(path)
	return _icon_cache[path]

func _slot_item(k: int) -> String:
	match k:
		-1, -5, -6: return GS.core_item(k)
		-2: return "light_missile"
		-3: return "heavy_missile"
		-4: return ""
	return str(GS.mount_items()[k])

func _slot_sub(k: int) -> String:
	match k:
		-2: return "%d / %d" % [GS.missiles, GS.max_missiles()]
		-3: return "%d / %d" % [GS.heavy_missiles, GS.max_heavy()]
		-4: return "%d / %d" % [GS.mines, GS.max_mines()]
	var it := _slot_item(k)
	if it == "empty" or it == "": return "EMPTY  +"
	var d: Dictionary = Data.WEAPONS.get(it, Data.MOUNT_PODS.get(it, {}))
	return str(d.get("short", d.get("name", it))).to_upper()

const TAG_W := 92.0
func _facing() -> bool: return cos(bay_yaw) > Data.BAY_TAGS_FACING
const TAG_H := 30.0
## Where each slot's tag goes: left-hand slots tag out to the left, right-hand to the right, centre ones above/below;
## tags on one side are spread so they never overlap.
func _slot_layout(c: Vector2, pts: Dictionary, half: float) -> Dictionary:
	var mid := c.x * 0.5
	var sides := {"l": [], "r": [], "t": [], "b": []}
	for k in pts:
		var p: Vector2 = pts[k]
		var sd := "l" if p.x < mid - 3.0 else ("r" if p.x > mid + 3.0 else "c")
		if sd == "c":   # a centre slot: low ones tag below, the rest join the shorter side column
			sd = "b" if p.y > c.y * 0.62 else ("l" if sides["l"].size() <= sides["r"].size() else "r")
		sides[sd].append(k)
	var out := {}
	for sd in ["l", "r"]:
		var ks: Array = sides[sd]
		ks.sort_custom(func(a, b): return (pts[a] as Vector2).y < (pts[b] as Vector2).y)
		var edge := 1e9 if sd == "l" else -1e9
		for k in ks: edge = minf(edge, pts[k].x) if sd == "l" else maxf(edge, pts[k].x)
		var x := (edge - half - 22.0 - TAG_W) if sd == "l" else (edge + half + 22.0)
		x = clampf(x, 2.0, c.x - TAG_W - 2.0)
		var y := -1e9
		for k in ks:
			var ty: float = maxf((pts[k] as Vector2).y - TAG_H * 0.5, y + TAG_H + 4.0)
			out[k] = Rect2(x, ty, TAG_W, TAG_H)
			y = ty
		var over := y + TAG_H - (c.y - 2.0)   # pushed off the bottom: slide the stack back up
		if over > 0.0:
			for k in ks: out[k].position.y -= over
	for sd in ["t", "b"]:
		for k in sides[sd]:
			var p: Vector2 = pts[k]
			var ty: float = (p.y - half - 26.0 - TAG_H) if sd == "t" else (p.y + half + 26.0)
			out[k] = Rect2(clampf(p.x - TAG_W * 0.5, 2.0, c.x - TAG_W - 2.0), clampf(ty, 2.0, c.y - TAG_H - 2.0), TAG_W, TAG_H)
	return out

func _slot_half(c: Control) -> float:
	if _eq_mech() and c.get_parent() != null and c.get_parent().find_child("BayMech", true, false) == null: return clampf(_map_rect(c.size).size.y * 0.047, 10.0, 22.0)   # (covers the sheet's own squares)
	return 14.0

func _draw_slots(c: Control, pts: Dictionary) -> void:
	c.set_meta("pts", pts)
	var font := ThemeDB.fallback_font
	var half := _slot_half(c)
	var tags := _slot_layout(c.size, pts, half)
	var show_tags := _facing() or not is_instance_valid(preview_pivot)
	for k in pts:   # the lines first, under the squares and tags
		if not show_tags: break
		var p: Vector2 = pts[k]
		var r: Rect2 = tags[k]
		var to := Vector2(r.end.x if r.get_center().x < p.x else r.position.x, r.get_center().y)
		if absf(r.get_center().x - p.x) < TAG_W * 0.5: to = Vector2(p.x, r.end.y if r.get_center().y < p.y else r.position.y)
		var lc := GOLD if k == eq_sel else Color(0.45, 0.9, 1.0, 0.85)
		var from := p + (to - p).normalized() * half
		c.draw_line(from, to, lc, 1.5, true)
		c.draw_circle(to, 2.5, lc)
	for k in pts:
		var p: Vector2 = pts[k]
		var it := _slot_item(k)
		var empty: bool = it == "empty" or (k == -2 and GS.missiles <= 0) or (k == -3 and GS.heavy_missiles <= 0) or (k == -4 and GS.mines <= 0)
		var sq := Rect2(p - Vector2(half, half), Vector2(half, half) * 2.0)
		var sel: bool = k == eq_sel
		c.draw_rect(sq.grow(3.0), Color(0.3, 0.85, 1.0, 0.22) if not sel else Color(GOLD, 0.35))   # glow
		c.draw_rect(sq, Color(0.02, 0.07, 0.13, 0.94))
		var tex := _wicon(it) if not empty else null
		if tex != null:
			var ts := Vector2(tex.get_size())
			var f := minf((sq.size.x - 4.0) / ts.x, (sq.size.y - 4.0) / ts.y)
			c.draw_texture_rect(tex, Rect2(sq.get_center() - ts * f * 0.5, ts * f), false)
		elif k == -4 and not empty:
			c.draw_circle(sq.get_center(), half * 0.45, Color(1.0, 0.35, 0.25))
		else:
			var pl := half * 0.5
			var pc := Color(0.85, 0.97, 1.0)
			c.draw_line(sq.get_center() - Vector2(pl, 0), sq.get_center() + Vector2(pl, 0), pc, 2.5)
			c.draw_line(sq.get_center() - Vector2(0, pl), sq.get_center() + Vector2(0, pl), pc, 2.5)
		c.draw_rect(sq, GOLD if sel else Color(0.45, 0.9, 1.0), false, 2.5 if sel else 1.5)
		if not show_tags: continue
		var r: Rect2 = tags[k]
		c.draw_rect(r, Color(0.02, 0.07, 0.13, 0.86))
		c.draw_rect(r, GOLD if sel else Color(0.45, 0.9, 1.0, 0.7), false, 1.0)
		c.draw_string(font, r.position + Vector2(0, 12), str(SLOT_LABEL.get(k, "")), HORIZONTAL_ALIGNMENT_CENTER, TAG_W, 10, GOLD if sel else Color(0.85, 0.96, 1.0))
		c.draw_string(font, r.position + Vector2(0, 25), _slot_sub(k), HORIZONTAL_ALIGNMENT_CENTER, TAG_W, 9, Color(0.6, 0.85, 1.0) if not empty else Color(0.55, 0.65, 0.75))

## The bay floor behind the ship: dark deck plates, a grid, hazard stripes and lights.
func _draw_bay_floor(c: Control) -> void:
	var sz := c.size
	c.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.09, 0.1, 0.12))
	var step := 46.0
	var x := fmod(sz.x * 0.5, step) - step
	while x < sz.x:
		c.draw_line(Vector2(x, 0), Vector2(x, sz.y), Color(0.16, 0.18, 0.21), 1.0)
		x += step
	var y := 0.0
	while y < sz.y:
		c.draw_line(Vector2(0, y), Vector2(sz.x, y), Color(0.16, 0.18, 0.21), 1.0)
		y += step
	for sd in [0.12, 0.88]:   # the landing lane's hazard edges
		var lx: float = sz.x * sd
		var k := 0.0
		while k < sz.y:
			c.draw_line(Vector2(lx - 5, k), Vector2(lx + 5, k + 10), Color(0.95, 0.72, 0.15, 0.7), 4.0)
			k += 18.0
	for i in 6:
		c.draw_rect(Rect2(sz.x * 0.04, sz.y * (0.1 + i * 0.16), 6, 22), Color(0.35, 0.8, 1.0, 0.75))
		c.draw_rect(Rect2(sz.x * 0.96 - 6, sz.y * (0.1 + i * 0.16), 6, 22), Color(0.35, 0.8, 1.0, 0.75))
	c.draw_arc(sz * 0.5, minf(sz.x, sz.y) * 0.46, 0.0, TAU, 64, Color(0.95, 0.72, 0.15, 0.35), 2.0)

## The ability module slots under the bay (2 / 4 / 6 by level).
func _module_strip(mid: Control) -> void:
	var mrow := HBoxContainer.new()
	mrow.name = "ModuleSlots"
	mrow.add_theme_constant_override("separation", 4)
	mid.add_child(mrow)
	var ml := _label(12, CYAN)
	ml.text = "MODULES"
	mrow.add_child(ml)
	var mods: Array = GS.module_items()
	for i in mods.size():
		var mb := Button.new()
		mb.name = "ModSlot_%d" % i
		mb.custom_minimum_size = Vector2(40, 40)
		mb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mb.expand_icon = true
		mb.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if mods[i] != "" and ResourceLoader.exists(str(Data.MODULES[mods[i]]["icon"])): mb.icon = load(str(Data.MODULES[mods[i]]["icon"]))
		else: mb.text = "+"
		if eq_sel == 100 + i: mb.add_theme_color_override("font_color", GOLD)
		mb.pressed.connect(func():
			eq_sel = 100 + i
			eq_tab = "module"
			show_screen("equipment"))
		mrow.add_child(mb)
	if not Packs.is_ready("wing_guns"):
		Packs.request("wing_guns")
		if not Packs.pack_ready.is_connected(_on_eq_pack): Packs.pack_ready.connect(_on_eq_pack)

## The shop: filters, the card grid, and BUY / INSTALL (UPGRADE for an owned Nexus blaster) for the picked card.
func _shop_panel(shop: VBoxContainer) -> void:
	var st := _label(16, GOLD)
	st.name = "ShopTitle"
	st.text = {"weapon": "WEAPON SHOP", "module": "EQUIPMENT  ·  ABILITY MODULES", "ammo": "REPAIR & AMMO", "hangar": ""}[eq_tab]
	shop.add_child(st)
	var tgt := _label(12, CYAN)
	tgt.name = "ShopTarget"
	tgt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tgt.text = "SLOT: %s  ·  %s" % [_slot_name(eq_sel), _slot_now(eq_sel)]
	shop.add_child(tgt)
	var va := _eq_scroll(shop, "EqAmmo", eq_tab == "ammo")   # (built every time; shown on its tab)
	_ammo_panel(va)
	if true:
		var frow := HBoxContainer.new()
		frow.name = "ShopFilters"
		frow.visible = eq_tab == "weapon"
		frow.add_theme_constant_override("separation", 3)
		shop.add_child(frow)
		for f in [["all", "ALL"], ["blaster", "BLASTER"], ["gun", "CANNON"], ["pod", "MISSILE"]]:
			var b := Button.new()
			b.name = "Filter_" + f[0]
			b.text = f[1]
			b.custom_minimum_size = Vector2(0, 34)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.clip_text = true
			b.add_theme_font_size_override("font_size", Data.ts(12))
			if eq_filter == f[0]: b.add_theme_color_override("font_color", GOLD)
			var fid: String = f[0]
			b.pressed.connect(func():
				eq_filter = fid
				show_screen("equipment"))
			frow.add_child(b)
	var vb := _eq_scroll(shop, "EqBuy", eq_tab in ["weapon", "module"])
	var grid := GridContainer.new()
	grid.name = "ShopGrid"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 5)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(grid)
	var cards: Array = []
	for id in Data.NEXUS_BLASTERS: cards.append([id, "blaster"])
	for id in Data.WEAPON_ORDER:
		if not (id in Data.NEXUS_BLASTERS): cards.append([id, "gun"])
	for pid in Data.MOUNT_PODS: cards.append([pid, "pod"])
	for mid2 in Data.MODULE_ORDER: cards.append([mid2, "module"])
	for cd in cards:
		var c := _card(cd[0], cd[1])
		c.visible = (cd[1] == "module") if eq_tab == "module" else (cd[1] != "module" and (eq_filter == "all" or eq_filter == cd[1]))
		grid.add_child(c)
	# BUY / INSTALL
	var act := HBoxContainer.new()
	act.name = "ShopActions"
	act.visible = eq_tab != "ammo"
	act.add_theme_constant_override("separation", 6)
	shop.add_child(act)
	var kind := _card_kind(eq_card)
	var owned := _card_owned(eq_card, kind)
	var buy := Button.new()
	buy.name = "ShopBuy"
	buy.text = "BUY" if eq_card == "" or not owned else "OWNED"
	buy.custom_minimum_size = Vector2(0, 50)
	buy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buy.disabled = eq_card == "" or owned or GS.credits < _card_price(eq_card, kind)
	buy.add_theme_color_override("font_color", Color(1.0, 0.78, 0.3))
	for ab in [buy]: ab.clip_text = true
	buy.pressed.connect(func():
		status.text = _card_buy(eq_card, kind)
		show_screen("equipment"))
	act.add_child(buy)
	if owned and eq_card in Data.NEXUS_BLASTERS:
		var u := Button.new()
		u.name = "Up_" + eq_card
		u.custom_minimum_size = Vector2(0, 50)
		u.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		u.clip_text = true
		var lid: String = eq_card
		if GS.gun_level(lid) >= Data.BLASTER_LEVELS: u.text = "MAX MK %s" % GS.roman(Data.BLASTER_LEVELS); u.disabled = true
		else: u.text = "MK %s  %d cr" % [GS.roman(GS.gun_level(lid) + 1), GS.upgrade_cost(lid)]; u.disabled = GS.credits < GS.upgrade_cost(lid)
		u.pressed.connect(func(): status.text = GS.upgrade_gun(lid); show_screen("equipment"))
		act.add_child(u)
	var inst := Button.new()
	inst.name = "ShopInstall"
	inst.text = "INSTALL"
	inst.custom_minimum_size = Vector2(0, 50)
	inst.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inst.disabled = eq_card == "" or not owned
	inst.add_theme_color_override("font_color", CYAN)
	inst.clip_text = true
	inst.pressed.connect(func():
		status.text = _card_install(eq_card, kind)
		show_screen("equipment"))
	act.add_child(inst)
	var rem := Button.new()
	rem.name = "ShopRemove"
	rem.text = "REMOVE"
	rem.custom_minimum_size = Vector2(0, 50)
	rem.clip_text = true
	rem.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rem.disabled = not ((eq_sel >= 0 and eq_sel < 100 and str(GS.mount_items()[eq_sel]) != "empty") or (eq_sel >= 100 and GS.module_items()[eq_sel - 100] != ""))
	rem.pressed.connect(func():
		status.text = GS.fit_module(eq_sel - 100, "") if eq_sel >= 100 else GS.fit_mount(eq_sel, "empty")
		show_screen("equipment"))
	act.add_child(rem)

func _slot_name(k: int) -> String:
	if k >= 100: return "MODULE %d" % (k - 99)
	return str(SLOT_LABEL.get(k, "?"))
func _slot_now(k: int) -> String:
	if k >= 100:
		var m: String = GS.module_items()[k - 100]
		return Data.MODULES[m]["name"] if m != "" else "empty"
	match k:
		-2: return "%d / %d light missiles" % [GS.missiles, GS.max_missiles()]
		-3: return "%d / %d super missiles" % [GS.heavy_missiles, GS.max_heavy()]
		-4: return "%d / %d mines" % [GS.mines, GS.max_mines()]
		-1, -5, -6: return _item_name(GS.core_item(k))
	return _item_name(str(GS.mount_items()[k]))

var eq_card := ""      # v1.9y: the shop card picked (BUY / INSTALL act on it)
## v1.9y: one card in the shop grid: colour or icon, name, price and type. Tap = pick it; BUY / INSTALL below.
func _card(id: String, kind: String) -> Control:
	var d: Dictionary = Data.MODULES[id] if kind == "module" else (Data.MOUNT_PODS[id] if kind == "pod" else Data.WEAPONS[id])
	var owned := _card_owned(id, kind)
	var b := Button.new()
	b.name = "Card_" + id
	b.custom_minimum_size = Vector2(100, 84)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.clip_text = true
	b.add_theme_font_size_override("font_size", Data.ts(12))
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var tag: String = {"blaster": "BLASTER", "gun": "CANNON", "pod": "MISSILE", "module": "MODULE"}[kind]
	if kind == "gun" and d.get("heavy", false): tag = "HEAVY"
	var line2 := ""
	match kind:
		"blaster":
			var sh := int(round(float(d["shield"]) * 100.0))
			line2 = "%d%% shield / %d%% hull" % [sh, 100 - sh]
		"gun": line2 = "dmg %d  ·  %.1f/s" % [int(round(GS.gun_damage(id))), float(d["rate"])]
		"pod": line2 = "+%d missiles · +%d locks" % [int(d["ammo"]), int(d["locks"])]
		"module": line2 = str(d["desc"])
	var nm: String = str(d.get("short", d["name"])) if kind != "module" else str(d["name"])
	if kind in ["blaster", "gun"] and owned: nm += " Mk %s" % GS.roman(GS.gun_level(id))
	# v2.2 (owner's concept): the weapon's picture on top, then name, what it does, price and type
	b.text = ""
	b.custom_minimum_size = Vector2(100, 154 if kind != "module" else 100)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 10
	col.offset_right = -6
	col.offset_top = 4
	col.offset_bottom = -4
	col.add_theme_constant_override("separation", 0)
	b.add_child(col)
	var pic := TextureRect.new()
	pic.name = "Pic"
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.custom_minimum_size = Vector2(0, 84 if kind != "module" else 40)
	var ipath: String = str(d["icon"]) if kind == "module" else Data.weapon_icon(id, _eq_mech())
	if ipath != "" and ResourceLoader.exists(ipath): pic.texture = load(ipath)
	col.add_child(pic)
	for ln in [[nm.to_upper(), 12, Color(1, 1, 1) if not owned else GOLD], [line2, 10, Color(0.7, 0.88, 1.0)],
			["%s  ·  %s" % ["OWNED" if owned else "%d cr" % int(d["price"]), tag], 10, GOLD if owned else Color(1.0, 0.82, 0.4)]]:
		var l := Label.new()
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.text = ln[0]
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.add_theme_font_size_override("font_size", Data.ts(ln[1]))
		l.add_theme_color_override("font_color", ln[2])
		col.add_child(l)
	var accent: Color = (d.get("color", Color(1.0, 0.65, 0.3)) as Color) if kind != "module" else CYAN
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.09, 0.15, 0.92)
	sb.border_color = GOLD if id == eq_card else Color(accent, 0.7)
	sb.set_border_width_all(3 if id == eq_card else 1)
	sb.border_width_left = 6
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	for stn in ["normal", "hover", "pressed", "focus"]: b.add_theme_stylebox_override(stn, sb)
	b.add_theme_color_override("font_color", Color(1, 1, 1) if not owned else GOLD)
	b.pressed.connect(func():
		eq_card = id
		show_screen("equipment"))
	return b

func _card_kind(id: String) -> String:
	if id == "": return ""
	if Data.MODULES.has(id): return "module"
	if Data.MOUNT_PODS.has(id): return "pod"
	return "blaster" if id in Data.NEXUS_BLASTERS else "gun"
func _card_owned(id: String, kind: String) -> bool:
	if id == "": return false
	return (id in GS.owned_modules) if kind == "module" else (id in GS.owned_weapons)
func _card_price(id: String, kind: String) -> int:
	if id == "": return 0
	return int((Data.MODULES[id] if kind == "module" else (Data.MOUNT_PODS[id] if kind == "pod" else Data.WEAPONS[id]))["price"])
func _card_buy(id: String, kind: String) -> String:
	match kind:
		"module": return GS.buy_module(id)
		"pod": return GS.buy_pod(id)
		"": return "Pick something in the shop first."
	return GS.buy_weapon(id)   # (a bought gun goes on every gun slot it fits, as before; INSTALL puts it on one slot)
## Put the picked card in the picked slot.
func _card_install(id: String, kind: String) -> String:
	if id == "": return "Pick something in the shop first."
	if not _card_owned(id, kind): return "Buy it first."
	match kind:
		"module":
			var slot: int = eq_sel - 100 if eq_sel >= 100 else GS.module_items().find("")
			if slot < 0: return "Tap a module slot first (all are full)."
			return GS.fit_module(slot, id)
		"pod":
			if eq_sel >= 0 and eq_sel < 100: return GS.fit_mount(eq_sel, id)
			return "Missile pods go on a wing slot: tap one on the ship."
	if eq_sel in [-1, -5, -6]: return GS.fit_core(id, eq_sel)
	if eq_sel >= 0 and eq_sel < 100: return GS.fit_mount(eq_sel, id)
	return "Guns go on a gun or wing slot: tap one on the ship."

func _ammo_panel(va: VBoxContainer) -> void:
	# v1.4n: one tap each, right at the top
	var quick := HBoxContainer.new()
	quick.add_theme_constant_override("separation", 14)
	var rcost := GS.restock_cost()
	var rs := Button.new()
	rs.name = "RestockAll"
	rs.custom_minimum_size = Vector2(0, 64)
	rs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rs.text = "RESTOCK ALL  ·  %d cr" % rcost if rcost > 0 else "RESTOCK ALL  ·  FULL"
	rs.disabled = rcost <= 0
	rs.pressed.connect(func(): status.text = GS.restock_all(); show_screen("equipment"))
	quick.add_child(rs)
	var rp := Button.new()
	rp.name = "RepairNow"
	rp.custom_minimum_size = Vector2(0, 64)
	rp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rp.text = "REPAIR  ·  FREE" if GS.needs_repair() else "REPAIR  ·  HULL OK"
	rp.disabled = not GS.needs_repair()
	rp.pressed.connect(func(): status.text = GS.repair_all(); show_screen("equipment"))
	quick.add_child(rp)
	va.add_child(quick)
	var qcap := _label(15, Color(0.8, 0.88, 0.95))
	qcap.text = "Missiles %d/%d  ·  Heavy %d/%d  ·  Mines %d/%d  ·  Hull %d/%d" % [GS.missiles, GS.max_missiles(), GS.heavy_missiles, GS.max_heavy(), GS.mines, GS.max_mines(), int(GS.hull), int(GS.max_hull())]
	va.add_child(qcap)
	var sep := HSeparator.new()
	va.add_child(sep)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 14)
	var ml := _label(18, Color(1, 1, 1))
	ml.text = "Light missiles   ·   %d/%d loaded   ·   %d cr each   ·   30%% of target hull" % [GS.missiles, GS.max_missiles(), Data.MISSILE_PRICE]
	ml.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(ml)
	for n in [1, 99]:
		var b2 := Button.new()
		b2.text = "+1" if n == 1 else "FILL"
		b2.name = "Missile_" + str(n)
		b2.custom_minimum_size = Vector2(110, 54)
		b2.disabled = GS.missiles >= GS.max_missiles()
		b2.pressed.connect(func(): status.text = GS.buy_missiles(n); show_screen("equipment"))
		row2.add_child(b2)
	va.add_child(row2)
	for rid in Data.RACK_ORDER:   # Job M: missile racks for the LIGHT slot
		var rk: Dictionary = Data.MISSILE_RACKS[rid]
		var rr := HBoxContainer.new()
		rr.add_theme_constant_override("separation", 14)
		var rl := _label(18, Color(1, 1, 1))
		rl.text = "%s   ·   %d locks   ·   %d%% damage each" % [rk["name"], int(rk["locks"]), int(float(rk["damage"]) * 100.0)]
		rl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rr.add_child(rl)
		var rb := Button.new()
		rb.name = "Rack_" + rid
		rb.custom_minimum_size = Vector2(234, 54)
		if rid == GS.rack: rb.text = "FITTED"; rb.disabled = true
		elif rid in GS.owned_racks: rb.text = "FIT"
		else: rb.text = "BUY  %d cr" % int(rk["price"]); rb.disabled = GS.credits < int(rk["price"])
		rb.pressed.connect(func(): status.text = GS.buy_rack(rid); show_screen("equipment"))
		rr.add_child(rb)
		va.add_child(rr)
	var rowh := HBoxContainer.new()
	rowh.add_theme_constant_override("separation", 14)
	var hl := _label(18, Color(1, 1, 1))
	hl.text = "Heavy missiles   ·   %d/%d loaded   ·   %d cr each   ·   one lock, %d%% of target hull" % [GS.heavy_missiles, GS.max_heavy(), Data.HEAVY_MISSILE_PRICE, int(Data.HEAVY_MISSILE_HULL_FRAC * 100.0)]
	hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rowh.add_child(hl)
	for n in [1, 99]:
		var bh := Button.new()
		bh.text = "+1" if n == 1 else "FILL"
		bh.name = "Heavy_" + str(n)
		bh.custom_minimum_size = Vector2(110, 54)
		bh.disabled = GS.heavy_missiles >= GS.max_heavy()
		bh.pressed.connect(func(): status.text = GS.buy_heavy(n); show_screen("equipment"))
		rowh.add_child(bh)
	va.add_child(rowh)
	var row3 := HBoxContainer.new()
	row3.add_theme_constant_override("separation", 14)
	var nl := _label(18, Color(1, 1, 1))
	nl.text = "Proximity mines   ·   %d/%d loaded   ·   %d cr each   ·   as strong as a super missile" % [GS.mines, GS.max_mines(), Data.MINE_PRICE]
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row3.add_child(nl)
	var bk := Button.new()   # v1.5x: two kinds of mine; this switches which one you drop
	bk.name = "MineKind"
	bk.text = "MAGNETIC" if GS.mine_kind == "magnetic" else "BLAST"
	bk.tooltip_text = "Blast: a big explosion. Magnetic: the same blast, and it pulls the ships it hits in and holds them stuck for a few seconds. Tap to switch."
	bk.custom_minimum_size = Vector2(150, 54)
	bk.pressed.connect(func():
		GS.mine_kind = "blast" if GS.mine_kind == "magnetic" else "magnetic"
		status.text = "Mines: %s." % ("magnetic (pull in and hold)" if GS.mine_kind == "magnetic" else "blast")
		show_screen("equipment"))
	row3.add_child(bk)
	for n in [1, 99]:
		var b3 := Button.new()
		b3.text = "+1" if n == 1 else "FILL"
		b3.name = "Mine_" + str(n)
		b3.custom_minimum_size = Vector2(110, 54)
		b3.disabled = GS.mines >= GS.max_mines()
		b3.pressed.connect(func(): status.text = GS.buy_mines(n); show_screen("equipment"))
		row3.add_child(b3)
	va.add_child(row3)
	_wrap_rows(va)

var eq_filter := "all"   # v1.9x: the weapon shop's filter

## v1.9y: SHIP SPECS along the bottom (the concept's strip): the level silhouette, bars, and the big numbers.
func _spec_bar(parent: Control) -> void:
	var row := HBoxContainer.new()
	row.name = "FrameSpec"
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var ic := TextureRect.new()
	ic.custom_minimum_size = Vector2(56, 56)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var ap: String = GS.level_def()["mech_icon" if _eq_mech() else "icon"]
	if ResourceLoader.exists(ap): ic.texture = load(ap)
	row.add_child(ic)
	var bars := VBoxContainer.new()
	bars.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bars.add_theme_constant_override("separation", 1)
	row.add_child(bars)
	var t0 := _label(12, CYAN)
	t0.text = "SHIP SPECS  (LV %d %s)" % [GS.ship_level(), str(GS.level_def()["name"]).to_upper()]
	bars.add_child(t0)
	var sp: Dictionary = GS.ship()
	var g2 := GridContainer.new()
	g2.columns = 2
	g2.add_theme_constant_override("h_separation", 14)
	bars.add_child(g2)
	for it in [["HULL", GS.max_hull(), 500.0], ["SHIELD", GS.max_shield(), 260.0], ["SPEED", float(sp["speed"]), 60.0], ["MANEUVER", float(sp["turn"]) * (1.0 + GS.mod("turn")) * 50.0, 100.0]]:
		var h := HBoxContainer.new()
		h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var l := _label(11, Color(0.8, 0.9, 1.0))
		l.text = "%s %d" % [it[0], int(it[1])]
		l.custom_minimum_size = Vector2(92, 0)
		h.add_child(l)
		var pb := ProgressBar.new()
		pb.show_percentage = false
		pb.max_value = float(it[2])
		pb.value = minf(float(it[1]), float(it[2]))
		pb.custom_minimum_size = Vector2(60, 10)
		pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var fsb := StyleBoxFlat.new()
		fsb.bg_color = CYAN
		pb.add_theme_stylebox_override("fill", fsb)
		h.add_child(pb)
		g2.add_child(h)
	var fire := 0.0
	for k in GS.core_slots(): fire += GS.gun_damage(GS.core_item(k)) * float(Data.WEAPONS[GS.core_item(k)]["rate"])
	for it in GS.mount_items():
		if Data.WEAPONS.has(it): fire += GS.gun_damage(it) * float(Data.WEAPONS[it]["rate"])
	for nb in [["FIREPOWER", "%d/s" % int(fire)], ["DEFENSE", "%d" % int(GS.max_hull() + GS.max_shield())], ["MISSILES", "%d+%d" % [GS.max_missiles(), GS.max_heavy()]], ["MINES", "%d" % GS.max_mines()]]:
		var cbox := VBoxContainer.new()
		cbox.add_theme_constant_override("separation", 0)
		var a1 := _label(10, Color(0.7, 0.85, 1.0))
		a1.text = nb[0]
		cbox.add_child(a1)
		var a2 := _label(17, GOLD)
		a2.text = nb[1]
		cbox.add_child(a2)
		row.add_child(cbox)
	var nums := _label(1, GOLD)   # (kept for the checks: the same numbers in one line)
	nums.name = "SpecNumbers"
	nums.visible = false
	nums.text = "FIREPOWER %d/s" % int(fire)
	row.add_child(nums)

## v1.9u: one gun in the shop: colour chip, name and Mk, what it does, BUY / EQUIP, and UPGRADE for the Nexus blasters.
func _gun_row(id: String, nexus: bool) -> Control:
	var w: Dictionary = Data.WEAPONS[id]
	var row := HBoxContainer.new()
	row.name = "Gun_" + id
	row.add_theme_constant_override("separation", 10)
	var chip := ColorRect.new()
	chip.color = w["color"]
	chip.custom_minimum_size = Vector2(14, 40)
	row.add_child(chip)
	var owned: bool = id in GS.owned_weapons
	var l := _label(17, Color(1, 1, 1) if id != GS.weapon_id else GOLD)
	var mk: String = ("  Mk %s" % GS.roman(GS.gun_level(id))) if owned else ""
	if nexus:
		var sh := int(round(float(w["shield"]) * 100.0))
		l.text = "%s%s   ·   %d%% shield / %d%% hull   ·   dmg %d" % [w["name"], mk, sh, 100 - sh, int(round(GS.gun_damage(id)))]
	else:
		l.text = "%s%s   ·   dmg %d   ·   %.1f/s   ·   range %dm" % [w["name"], mk, int(round(GS.gun_damage(id))), w["rate"], w["range"]]
		if w.get("heavy", false): l.text += "   ·   HEAVY (shoulders)"
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var b := Button.new()
	b.custom_minimum_size = Vector2(170, 54)
	b.name = "Buy_" + id
	if id == GS.weapon_id: b.text = "EQUIPPED"; b.disabled = true
	elif owned: b.text = "EQUIP"
	else: b.text = "BUY  %d cr" % w["price"]; b.disabled = GS.credits < int(w["price"])
	b.pressed.connect(func(): status.text = GS.buy_weapon(id); show_screen("equipment"))
	row.add_child(b)
	if nexus and owned:
		var u := Button.new()
		u.name = "Up_" + id
		u.custom_minimum_size = Vector2(170, 54)
		if GS.gun_level(id) >= Data.BLASTER_LEVELS: u.text = "MAX MK %s" % GS.roman(Data.BLASTER_LEVELS); u.disabled = true
		else: u.text = "MK %s  %d cr" % [GS.roman(GS.gun_level(id) + 1), GS.upgrade_cost(id)]; u.disabled = GS.credits < GS.upgrade_cost(id)
		u.pressed.connect(func(): status.text = GS.upgrade_gun(id); show_screen("equipment"))
		row.add_child(u)
	return row

func _item_name(it: String) -> String:
	if it == "empty" or it == "": return "empty"
	var d: Dictionary = Data.WEAPONS.get(it, Data.MOUNT_PODS.get(it, {}))
	var mk: String = ("  Mk %s" % GS.roman(GS.gun_level(it))) if Data.WEAPONS.has(it) and str(Data.WEAPONS[it]["name"]).find(" Mk ") < 0 else ""
	return str(d.get("name", it)) + mk

## v1.9u (owner): YOUR SHIP on a turntable (turn it by dragging; it never flips over), what it carries on each mount,
## and a small outline of it with a dot per mount: tap a dot to fit that mount.
var eq_sel := -1          # the mount being fitted: -1 = the core, 0-3 = the wing mounts
var eq_yaw := 0.0
func _loadout_panel(split: Control) -> void:
	var col := VBoxContainer.new()
	col.name = "LoadoutPanel"
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	split.add_child(col)
	var items: Array = GS.mount_items()
	var core_n: int = GS.core_slots().size() + 3   # front guns + the three bays
	var wing_used := 0
	for i in 6:
		if GS.mount_open(i) and items[i] != "empty": wing_used += 1
	var t1 := _label(16, GOLD)
	t1.name = "LoadoutShip"
	var lv: Dictionary = GS.level_def()
	t1.text = "%s  ·  LEVEL %d %s\nCORE %d  ·  %s %d/%d  ·  MODULES %d" % [str(GS.ship()["name"]).to_upper(), GS.ship_level(), str(lv["mech_name"] if _eq_mech() else lv["name"]).to_upper(),
		core_n, "ARMS" if _eq_mech() else "WINGS", wing_used, GS.wing_slots(), GS.module_slots()]
	col.add_child(t1)
	var mm := Control.new()
	mm.name = "MountMap"
	mm.custom_minimum_size = Vector2(220, 220)
	mm.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mm.mouse_filter = Control.MOUSE_FILTER_STOP
	col.add_child(mm)
	mm.draw.connect(func(): _draw_mount_map(mm))
	mm.gui_input.connect(func(e: InputEvent):
		var tap := (e is InputEventScreenTouch and not (e as InputEventScreenTouch).pressed) or (e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and not (e as InputEventMouseButton).pressed)
		if not tap: return
		var at: Vector2 = (e as InputEventMouseButton).position if e is InputEventMouseButton else (e as InputEventScreenTouch).position
		var best := -9
		var bd := 28.0
		var pts := _mount_points(mm.size)
		for k in pts:
			var d: float = at.distance_to(pts[k])
			if d < bd:
				bd = d
				best = k
		if best > -9:
			eq_sel = best
			show_screen("equipment"))
	# the ability module slots (2 / 4 / 6 by level): tap one to fit a module
	var mrow := HBoxContainer.new()
	mrow.name = "ModuleSlots"
	mrow.add_theme_constant_override("separation", 6)
	col.add_child(mrow)
	var mods: Array = GS.module_items()
	for i in mods.size():
		var mb := Button.new()
		mb.name = "ModSlot_%d" % i
		mb.custom_minimum_size = Vector2(44, 46)
		mb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mb.expand_icon = true
		mb.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if mods[i] != "" and ResourceLoader.exists(str(Data.MODULES[mods[i]]["icon"])): mb.icon = load(str(Data.MODULES[mods[i]]["icon"]))
		else: mb.text = "+"
		mb.tooltip_text = Data.MODULES[mods[i]]["name"] if mods[i] != "" else "Empty module slot"
		if eq_sel == 100 + i: mb.add_theme_color_override("font_color", GOLD)
		mb.pressed.connect(func():
			eq_sel = 100 + i
			show_screen("equipment"))
		mrow.add_child(mb)
	if not Packs.is_ready("wing_guns"):
		Packs.request("wing_guns")
		if not Packs.pack_ready.is_connected(_on_eq_pack): Packs.pack_ready.connect(_on_eq_pack)

## The equip turntable (top of the slot panel): your ship turning on a lit ring, wearing what it carries. Drag turns it
## (yaw only: it never flips over).
func _turntable(parent: Control) -> void:
	var svc := SubViewportContainer.new()
	svc.name = "LoadoutPreview"
	svc.stretch = true
	svc.custom_minimum_size = Vector2(200, 130)
	parent.add_child(svc)
	preview_vp = SubViewport.new()
	preview_vp.own_world_3d = true
	preview_vp.transparent_bg = true
	svc.add_child(preview_vp)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 5.0, 12.0)
	cam.fov = 44
	preview_vp.add_child(cam)
	cam.look_at(Vector3(0, -1.4, 0), Vector3.UP)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 25, 0)
	preview_vp.add_child(light)
	var we := WorldEnvironment.new()
	we.environment = Environment.new()
	we.environment.background_mode = Environment.BG_CLEAR_COLOR
	we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	we.environment.ambient_light_color = Color(0.55, 0.6, 0.7)
	preview_vp.add_child(we)
	var plat := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 6.6
	tm.outer_radius = 7.0
	tm.rings = 48
	tm.ring_segments = 6
	plat.mesh = tm
	plat.material_override = ShipFactory.mat(Color(0.35, 0.85, 1.0), true)
	plat.position = Vector3(0, -2.6, 0)
	preview_vp.add_child(plat)
	preview_pivot = Node3D.new()
	preview_pivot.name = "Turntable"
	preview_vp.add_child(preview_pivot)
	var m := ShipFactory.build(Data.SHIPS[GS.ship_id]["model"], true)
	preview_pivot.add_child(m)
	preview_key = GS.ship_id
	var bb0: AABB = ShipFactory._aabb(m, Transform3D.IDENTITY)   # (in the turntable's space: includes its scale)
	var span: float = maxf(bb0.size.x, bb0.size.z)
	if span > 0.01:
		m.scale *= 11.5 / span
		m.position = -ShipFactory._aabb(m, Transform3D.IDENTITY).get_center()   # centred on the turntable + Vector3(0, -1.2, 0)
	_dress_mounts(m)
	svc.gui_input.connect(func(e: InputEvent):
		if e is InputEventScreenDrag: eq_yaw += (e as InputEventScreenDrag).relative.x * 0.012
		elif e is InputEventMouseMotion and ((e as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT): eq_yaw += (e as InputEventMouseMotion).relative.x * 0.012)

func _eq_scroll(outer: Control, nm: String, show: bool) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.name = nm
	sc.visible = show
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(sc)
	var vv := VBoxContainer.new()
	vv.add_theme_constant_override("separation", 10)
	vv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(vv)
	return vv

var eq_tab := "weapon"   # v1.9y: the open HANGAR tab: "weapon" | "module" | "ammo"
var eq_view := ""         # v1.9x: "ship" | "mech" blueprint ("" = the form you are flying)
func _eq_mech() -> bool: return eq_view == "mech" or (eq_view == "" and GS.form == "mech")

func _on_eq_pack(pk: String) -> void:
	if pk == "wing_guns" and visible and is_instance_valid(preview_pivot) and preview_pivot.get_child_count() > 0: _dress_mounts(preview_pivot.get_child(0))

## The guns and pods on the showroom ship, placed as in flight (shoulders on top, tips hung under, the core gun under the nose).
func _dress_mounts(model: Node3D) -> void:
	var old := model.get_node_or_null("ShowMounts")
	if old != null: old.free()
	if not Packs.is_ready("wing_guns"): return
	var holder := Node3D.new()
	holder.name = "ShowMounts"
	model.add_child(holder)
	var bb: AABB = ShipFactory._aabb(model, Transform3D.IDENTITY)
	var sc: float = maxf(model.scale.x, 0.001)
	var hw: float = maxf(bb.size.x * 0.5 * model.scale.x, 1.0)
	var ln: float = maxf(bb.size.z * model.scale.z, 2.0)
	var items: Array = GS.mount_items()
	var slots: Array = []
	for k in GS.core_slots(): slots.append([k, GS.core_item(k)])
	for g in items.size(): slots.append([g, items[g]])
	for pr in slots:
		var g: int = pr[0]
		var it: String = pr[1]
		var info: Dictionary = Data.WEAPONS.get(it, Data.MOUNT_PODS.get(it, {}))
		var key: String = str(info.get("model", ""))
		if key == "" or not ShipFactory.has_real_model(key): continue
		var gun := ShipFactory.build(key)
		gun.name = "Show%d" % g
		var share: float = float(info.get("share", Data.WING_POD_SHARE if Data.MOUNT_PODS.has(it) else Data.WING_GUN_SHARE))
		gun.scale = Vector3.ONE * (ln * share / Data.WING_GUN_LEN) / sc
		if g < 0:
			var ox := 0.0
			if GS.core_slots().size() > 1 and g in [-1, -5]: ox = hw * (0.14 if g == -5 else -0.14)
			gun.position = Vector3(ox, -Data.MOUNT_DROP * (2.4 if g == -6 else 1.4), -ln * (0.05 if g == -6 else 0.3)) / sc
			gun.rotation_degrees.z = 180.0
		else:
			var side := GS.mount_side(g)
			var tip: bool = GS.is_tip(g)
			var at: float = Data.MOUNT_TIP_AT if tip else (Data.MOUNT_MID_AT if g >= 4 else Data.MOUNT_SHOULDER_AT)
			gun.position = Vector3(side * hw * at, -Data.MOUNT_DROP if tip else Data.MOUNT_DROP, 0.0) / sc
			if tip: gun.rotation_degrees.z = 180.0
		holder.add_child(gun)

## v1.9w (owner's three-level sheet): the ship's level blueprint with a dot on each of its slots.
## Ids: -1 front gun, -5 second front gun, -6 belly gun, -2 light bay, -3 super bay, -4 mine bay, 0-5 wing slots.
const SLOT_TAG := {-1: "GUN", -5: "GUN 2", -6: "GUN 3", -2: "MSL", -3: "SUPER", -4: "MINES"}
var _lvl_tex := {}
func _level_tex() -> Texture2D:
	var path: String = GS.level_def()["mech_art" if _eq_mech() else "art"]
	if not _lvl_tex.has(path) and ResourceLoader.exists(path): _lvl_tex[path] = load(path)
	return _lvl_tex.get(path)
func _map_rect(sz: Vector2) -> Rect2:
	var tx := _level_tex()
	var asp: float = (tx.get_width() / float(tx.get_height())) if tx != null else 0.8
	var hgt := sz.y * 0.9
	var wdt := hgt * asp
	if wdt > sz.x * 0.64:   # (room for the tags either side)
		wdt = sz.x * 0.64
		hgt = wdt / asp
	return Rect2((sz.x - wdt) * 0.5, (sz.y - hgt) * 0.55, wdt, hgt)

func _mount_points(sz: Vector2) -> Dictionary:
	var r := _map_rect(sz)
	var out := {}
	var uv: Dictionary = GS.level_def()["mech_uv" if _eq_mech() else "uv"]
	for k in uv: out[k] = r.position + r.size * (uv[k] as Vector2)
	return out

func _draw_mount_map(mm: Control) -> void:
	var tx := _level_tex()
	if tx != null: mm.draw_texture_rect(tx, _map_rect(mm.size), false)
	_draw_slots(mm, _mount_points(mm.size))

## v1.9e: long shop lines wrap instead of pushing the page (and its buttons) off the right of the screen.
func _wrap_rows(root: Node) -> void:
	for l in root.find_children("*", "Label", true, false):
		var lb := l as Label
		if lb.get_parent() is VBoxContainer and lb.text.length() > 40:   # captions straight in the list wrap too
			lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if lb.size_flags_horizontal & Control.SIZE_EXPAND:
			lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			lb.custom_minimum_size.x = maxf(lb.custom_minimum_size.x, 160.0)

func _ships_page() -> void:
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 18
	h.offset_top = 14
	h.offset_right = -18
	h.offset_bottom = -14
	h.add_theme_constant_override("separation", 16)
	content.add_child(h)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 10)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var scroll := ScrollContainer.new()      # five ships no longer fit on one screen: drag the list
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	h.add_child(scroll)
	scroll.add_child(list)
	for id in Data.SHIP_ORDER:
		var s: Dictionary = Data.SHIPS[id]
		var card := VBoxContainer.new()
		var l := _label(19, GOLD if id == GS.ship_id else Color(1, 1, 1))
		l.text = "%s  —  %s%s" % [s["name"].to_upper(), s["class"], "   (CURRENT)" if id == GS.ship_id else ""]
		card.add_child(l)
		var st := _label(15, CYAN)
		st.text = "Hull %d · Shield %d · Speed %d · Turn %.2f · Guns %d · Missiles %d · Mines %d" % [s["hull"], s["shield"], s["speed"], s["turn"], s["guns"], s["missiles"], s["mines"]]
		card.add_child(st)
		var row := HBoxContainer.new()
		var b := Button.new()
		b.name = "Ship_" + id
		b.custom_minimum_size = Vector2(220, 50)
		if id == GS.ship_id: b.text = "FLYING"; b.disabled = true
		elif id in GS.owned_ships: b.text = "SWITCH"
		else: b.text = "BUY  %d cr" % s["price"]; b.disabled = GS.credits < int(s["price"])
		b.pressed.connect(func(): status.text = GS.buy_ship(id); show_screen("ships"))
		row.add_child(b)
		var pv := Button.new()
		pv.text = "VIEW"
		pv.custom_minimum_size = Vector2(100, 50)
		pv.pressed.connect(func(): _set_preview(id); open_inspector(id))
		row.add_child(pv)
		card.add_child(row)
		list.add_child(card)
	# 3D showroom
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.custom_minimum_size = Vector2(200, 160)
	svc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_left_slot(h).add_child(svc)   # v3.5: the model in the left window, the list on the right
	preview_vp = SubViewport.new()
	preview_vp.own_world_3d = true
	preview_vp.transparent_bg = true
	svc.add_child(preview_vp)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 6, 17)
	cam.fov = 45
	preview_vp.add_child(cam)
	cam.look_at(Vector3.ZERO, Vector3.UP)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, 30, 0)
	preview_vp.add_child(light)
	var we := WorldEnvironment.new()
	we.environment = Environment.new()
	we.environment.background_mode = Environment.BG_CLEAR_COLOR
	we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	we.environment.ambient_light_color = Color(0.5, 0.55, 0.65)
	preview_vp.add_child(we)
	preview_pivot = Node3D.new()
	preview_vp.add_child(preview_pivot)
	_set_preview(GS.ship_id)
	svc.gui_input.connect(func(e: InputEvent):
		if (e is InputEventScreenTouch and not e.pressed) or (e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed):
			open_inspector(preview_key))
	var hint := _label(14, CYAN)
	hint.text = "TAP THE SHIP TO INSPECT"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -26
	svc.add_child(hint)

## v1.9i (owner): MECH DEALER. A mech is ARMS + CORE (upper body) + LEGS. Buy a frame to own its three parts, then
## fit each part from any frame you own (the arms are always a matched pair).
func _mechs_page() -> void:
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 18
	h.offset_top = 14
	h.offset_right = -18
	h.offset_bottom = -14
	h.add_theme_constant_override("separation", 16)
	content.add_child(h)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	h.add_child(scroll)
	var list := VBoxContainer.new()
	list.name = "MechList"
	list.add_theme_constant_override("separation", 10)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var cap := _label(17, CYAN)
	cap.text = "YOUR MECH  ·  Armour %d%%  ·  Gun power x%.2f  ·  Pace x%.2f" % [int(round(GS.mech_armor() * 100.0)), GS.mech_arm(), GS.mech_speed()]
	cap.name = "MechStats"
	list.add_child(cap)
	for part in ["arms", "core", "legs"]:
		var row := HFlowContainer.new()
		row.name = "Part_" + part
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("h_separation", 8)
		row.add_theme_constant_override("v_separation", 6)
		var pl := _label(17, GOLD)
		pl.text = "%s:" % str(Data.MECH_PART_NAMES[part]).to_upper()
		pl.custom_minimum_size = Vector2(200, 50)
		row.add_child(pl)
		for fid in Data.MECH_ORDER:
			if not (fid in GS.owned_mechs): continue
			var b := Button.new()
			b.name = "Fit_%s_%s" % [part, fid]
			b.custom_minimum_size = Vector2(150, 50)
			b.clip_text = true
			var nm := str(Data.MECHS[fid].get("short", Data.MECHS[fid]["name"]))
			b.text = ("[%s]" % nm) if GS.mech_parts[part] == fid else nm
			b.disabled = GS.mech_parts[part] == fid
			b.pressed.connect(func(): status.text = GS.fit_mech_part(part, fid); show_screen("mechs"))
			row.add_child(b)
		list.add_child(row)
	var cap2 := _label(16, CYAN)
	cap2.text = "FRAMES  ·  a frame gives you its arms, core and legs. Armour = core, gun power = arms, pace = legs."
	cap2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list.add_child(cap2)
	for fid in Data.MECH_ORDER:
		var f: Dictionary = Data.MECHS[fid]
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 14)
		var l := _label(17, Color(1, 1, 1))
		l.text = "%s   ·   armour %d%%  ·  gun x%.2f  ·  pace x%.2f" % [f["name"], int(round(float(f["armor"]) * 100.0)), float(f["arm"]), float(f["speed"])]
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		r.add_child(l)
		var b := Button.new()
		b.name = "Mech_" + fid
		b.custom_minimum_size = Vector2(210, 52)
		var worn: bool = GS.mech_parts.values().all(func(x): return x == fid)
		if worn: b.text = "WORN"; b.disabled = true
		elif fid in GS.owned_mechs: b.text = "WEAR ALL"
		else: b.text = "BUY  %d cr" % int(f["price"]); b.disabled = GS.credits < int(f["price"])
		b.pressed.connect(func():
			status.text = GS.buy_mech(fid)
			var pk := ShipFactory.pack_of(str(f["model"]))
			if pk != "": Packs.request(pk)
			show_screen("mechs"))
		r.add_child(b)
		list.add_child(r)
	# the mech you have fitted, turning in the showroom
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.custom_minimum_size = Vector2(200, 160)
	svc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_left_slot(h).add_child(svc)   # v3.5: the mech in the left window
	preview_vp = SubViewport.new()
	preview_vp.own_world_3d = true
	preview_vp.transparent_bg = true
	svc.add_child(preview_vp)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0.5, 24)
	cam.fov = 40
	preview_vp.add_child(cam)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, 25, 0)
	preview_vp.add_child(light)
	var we := WorldEnvironment.new()
	we.environment = Environment.new()
	we.environment.background_mode = Environment.BG_CLEAR_COLOR
	we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	we.environment.ambient_light_color = Color(0.55, 0.58, 0.68)
	preview_vp.add_child(we)
	preview_pivot = Node3D.new()
	preview_pivot.rotation_degrees.y = 180.0   # (face the camera)
	preview_vp.add_child(preview_pivot)
	_mech_preview()
	if not Packs.pack_ready.is_connected(_on_mech_pack_hub): Packs.pack_ready.connect(_on_mech_pack_hub)

## The fitted mech in the showroom (the Black-Gold frame stands in while a part's pack is still coming).
func _mech_preview() -> void:
	if preview_pivot == null or not is_instance_valid(preview_pivot): return
	for c in preview_pivot.get_children(): c.queue_free()
	var k: Dictionary = GS.mech_keys()
	var ready := true
	for p in k.values():
		var pk := ShipFactory.pack_of(str(p))
		if pk != "" and not Packs.is_ready(pk): ready = false
	var m: Node3D = ShipFactory.build_mech(str(k["core"]), str(k["arms"]), str(k["legs"])) if ready else ShipFactory.build("mech_player")
	m.name = "MechPreview"
	preview_pivot.add_child(m)
	preview_key = "mech"

func _on_mech_pack_hub(pk: String) -> void:
	if pk.begins_with("mf_") and is_instance_valid(preview_pivot) and preview_key == "mech": _mech_preview()

func _set_preview(id: String) -> void:
	if preview_pivot == null or not is_instance_valid(preview_pivot): return
	for c in preview_pivot.get_children(): c.queue_free()
	var m := ShipFactory.build(Data.SHIPS[id]["model"], id == GS.ship_id)
	preview_pivot.add_child(m)
	preview_key = id
	if m.get_meta("placeholder", false):
		status.text = "%s shown as a temporary original stand-in model until final art is supplied." % Data.SHIPS[id]["name"]

## Full-screen ship inspector: the ship up close in 3D (drag to turn, pinch or wheel to zoom) and everything about it,
## like checking a ship out in Freelancer before you buy.
func open_inspector(id: String) -> void:
	close_inspector()
	insp_id = id
	insp_yaw = 0.7
	insp_pitch = 0.25
	insp_dist = 24.0
	inspect = Control.new()
	inspect.name = "Inspector"
	inspect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inspect.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(inspect)
	var bg := ColorRect.new()
	bg.color = Color(0.01, 0.04, 0.08, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inspect.add_child(bg)
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.anchor_right = 0.62
	svc.anchor_bottom = 1.0
	svc.offset_left = 20
	svc.offset_top = 20
	svc.offset_bottom = -20
	inspect.add_child(svc)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	svc.add_child(vp)
	var we := WorldEnvironment.new()
	we.environment = Environment.new()
	we.environment.background_mode = Environment.BG_COLOR
	we.environment.background_color = Color(0.03, 0.07, 0.13)
	we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	we.environment.ambient_light_color = Color(0.5, 0.56, 0.68)
	vp.add_child(we)
	for r in [Vector3(-40, 30, 0), Vector3(-15, 200, 0)]:
		var l := DirectionalLight3D.new()
		l.rotation_degrees = r
		l.light_energy = 1.0 if r.y < 100 else 0.6
		vp.add_child(l)
	insp_cam = Camera3D.new()
	insp_cam.fov = 40
	vp.add_child(insp_cam)
	insp_pivot = Node3D.new()
	vp.add_child(insp_pivot)
	insp_pivot.add_child(ShipFactory.build(Data.SHIPS[id]["model"], id == GS.ship_id))
	var grid := MeshInstance3D.new()   # a floor ring so the turn and scale read
	var tm := TorusMesh.new()
	tm.inner_radius = 7.6
	tm.outer_radius = 7.8
	grid.mesh = tm
	grid.position.y = -2.5
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.albedo_color = Color(0.4, 0.86, 1.0, 0.8)
	grid.material_override = gm
	vp.add_child(grid)
	svc.gui_input.connect(_insp_input)
	insp_stats = RichTextLabel.new()
	insp_stats.bbcode_enabled = true
	insp_stats.anchor_left = 0.64
	insp_stats.anchor_right = 1.0
	insp_stats.anchor_bottom = 1.0
	insp_stats.offset_top = 24
	insp_stats.offset_right = -24
	insp_stats.offset_bottom = -100
	insp_stats.add_theme_font_size_override("normal_font_size", Data.ts(17))
	insp_stats.add_theme_font_size_override("bold_font_size", Data.ts(26))
	insp_stats.text = ship_sheet(id)
	inspect.add_child(insp_stats)
	var close := Button.new()
	close.name = "InspectClose"
	close.text = "CLOSE"
	close.anchor_left = 0.64
	close.anchor_right = 1.0
	close.anchor_top = 1.0
	close.anchor_bottom = 1.0
	close.offset_top = -84
	close.offset_bottom = -24
	close.offset_right = -24
	close.pressed.connect(close_inspector)
	inspect.add_child(close)
	_insp_camera()

func close_inspector() -> void:
	if is_instance_valid(inspect): inspect.queue_free()
	inspect = null
	_touches.clear()

## Everything about a ship, as shown in the inspector.
static func ship_sheet(id: String) -> String:
	var s: Dictionary = Data.SHIPS[id]
	var w: Dictionary = GS.weapon()
	var dps: float = float(s["guns"]) * float(w["damage"]) * float(w["rate"])
	var own := "FLYING" if id == GS.ship_id else ("OWNED" if id in GS.owned_ships else "%d cr" % s["price"])
	var lines := [
		"[b]%s[/b]" % (s["name"] as String).to_upper(),
		"[color=#66dbff]%s  ·  %s[/color]" % [s["class"], own],
		"%s" % s["desc"], "",
		"[color=#ffd166]DEFENCE[/color]",
		"Hull  %d   ·   Shield  %d" % [s["hull"], s["shield"]],
		"Wings  %d each (break off separately)" % int(float(s["hull"]) * Data.SECTION_SHARE), "",
		"[color=#ffd166]ENGINES[/color]",
		"Cruise  %d m/s   ·   Top  %d m/s" % [int(float(s["speed"]) * Data.CRUISE), int(s["speed"])],
		"Thrust  %d m/s   ·   Warp  %d m/s" % [int(float(s["speed"]) * Data.THRUST_MULT), int(float(s["speed"]) * Data.WARP_MULT)],
		"Turn rate  %.2f" % s["turn"], "",
		"[color=#ffd166]WEAPONS[/color]",
		"Gun hardpoints  %d   (%s)" % [s["guns"], w["name"]],
		"Gun damage  %d per second" % int(dps),
		"Light missiles  %d   ·   Heavy  %d   ·   Mines  %d" % [s["missiles"], s["heavy"], s["mines"]],
		"Weapon slots  3", "",
		"[color=#9fb3c8]Drag the ship to turn it · pinch or scroll to zoom[/color]"]
	return "\n".join(lines)

func _insp_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed: _touches[e.index] = e.position
		else: _touches.erase(e.index)
		if _touches.size() == 2: _pinch0 = (_touches.values()[0] as Vector2).distance_to(_touches.values()[1])
	elif e is InputEventScreenDrag:
		_touches[e.index] = e.position
		if _touches.size() >= 2:
			var d := (_touches.values()[0] as Vector2).distance_to(_touches.values()[1])
			if _pinch0 > 1.0: zoom_inspector(_pinch0 / d)
			_pinch0 = d
		else: turn_inspector(e.relative)
	elif e is InputEventMouseMotion and e.button_mask & MOUSE_BUTTON_MASK_LEFT:
		turn_inspector(e.relative)
	elif e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP: zoom_inspector(0.9)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN: zoom_inspector(1.1)
	elif e is InputEventMagnifyGesture:
		zoom_inspector(1.0 / e.factor)

func turn_inspector(rel: Vector2) -> void:
	insp_yaw -= rel.x * 0.01
	insp_pitch = clampf(insp_pitch + rel.y * 0.008, -0.6, 1.2)
	_insp_camera()

func zoom_inspector(k: float) -> void:
	insp_dist = clampf(insp_dist * k, 12.0, 45.0)
	_insp_camera()

func _insp_camera() -> void:
	if not is_instance_valid(insp_cam): return
	insp_cam.position = Vector3(sin(insp_yaw) * cos(insp_pitch), sin(insp_pitch), cos(insp_yaw) * cos(insp_pitch)) * insp_dist
	insp_cam.look_at(Vector3.ZERO, Vector3.UP)

## v1.4q: the bounty board. One row per named target (weakest first): face, where they hide, the reward.
## v1.5k: the tab bar of the MISSION BOARD (MISSIONS | BOUNTIES) and the line saying what is being tracked.
func _board_head(v: VBoxContainer, tab: String) -> void:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	for tb in [["missions", "MISSIONS"], ["bounty", "BOUNTIES"]]:
		var b := Button.new()
		b.name = "Tab_" + tb[0]
		b.text = tb[1]
		b.custom_minimum_size = Vector2(200, 50)
		b.toggle_mode = true
		b.button_pressed = tb[0] == tab
		if tb[0] == tab: b.add_theme_color_override("font_color", GOLD)
		b.pressed.connect(func(): show_screen(tb[0]))
		bar.add_child(b)
	v.add_child(bar)
	var tr := _label(17, GOLD)
	tr.name = "Tracking"
	tr.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tr.text = Missions.tracking_line(GS.system_id)
	v.add_child(tr)

## A row's highlight: a gold frame when it is the job being tracked.
func _row_frame(row: Control, on: bool) -> PanelContainer:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.35, 0.27, 0.05, 0.55) if on else Color(0, 0, 0, 0.0)
	sb.border_color = GOLD if on else Color(1, 1, 1, 0.08)
	sb.set_border_width_all(3 if on else 1)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	pc.add_theme_stylebox_override("panel", sb)
	pc.mouse_filter = Control.MOUSE_FILTER_PASS   # v1.7v: a drag on a row scrolls the list
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	pc.add_child(row)
	return pc

func _bounty_page() -> void:
	var v := _scroll_box()
	_board_head(v, "bounty")
	var l := _label(17, Color(1, 1, 1))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.text = "Tap a target to hear it. ACCEPT takes the hunt (a gold waypoint leads you there). Every bounty is a capture: destroy the ship, TRACTOR the pilot into your hold and bring them back here to be paid."   # v1.8x (owner); v1.9o: tap = hear, ACCEPT / DECLINE
	v.add_child(l)
	if _board_locked(v): return
	_standing_rows(v)
	var posted: Array = Data.bounties_for(Factions.owner_of(base, Data.SYSTEMS[GS.system_id]))   # v1.5l: this station's enemies
	posted.sort_custom(func(a, b): return [str(a["faction"]) != "Savagers", str(a["faction"]), int(a["slot"])] < [str(b["faction"]) != "Savagers", str(b["faction"]), int(b["slot"])])
	for p in posted:
		var id: String = p["id"]
		var row := HBoxContainer.new()
		row.name = "Row_" + id
		row.add_theme_constant_override("separation", 14)
		var pic := TextureRect.new()
		pic.custom_minimum_size = Vector2(Data.BOUNTY_FACE_PX, Data.BOUNTY_FACE_PX)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		var path: String = p["portrait_clean"]
		if ResourceLoader.exists(path): pic.texture = load(path)
		else:
			var ph := GradientTexture2D.new()
			ph.gradient = Gradient.new()
			ph.gradient.colors = PackedColorArray([Color(0.35, 0.1, 0.08), Color(0.12, 0.05, 0.05)])
			pic.texture = ph
		pic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(tier_frame(pic, Data.tier_of_pay(Data.bounty_reward(id))))   # v1.9m: framed in the difficulty colour
		var t := _label(Data.BOARD_FONT, CYAN)   # v1.9k (owner): bigger, easier to read
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t.text = "%02d  %s  ·  %s  ·  %s\nHunt: here in %s   ·   Flies a %s\nReward %d cr  ·  wanted %s" % [int(p["rank"]), str(p["name"]).to_upper(), p["type"], p["faction"],
			Data.SYSTEMS[GS.system_id]["name"], Data.ENEMIES[p["fighter_primary"]]["name"], Data.bounty_reward(id), "ALIVE" if int(p["rank"]) >= Data.BOUNTY_ALIVE_RANK else "dead"]
		row.add_child(t)
		var mine: bool = GS.bounty.get("id", "") == id
		var shut := ""
		if GS.bounty_jail.has(id):   # v1.8k: locked up for now; breaks out later
			var down: bool = not bool(GS.cast_state(str(p.get("character_id", id))).get("alive", true))
			shut = ("KILLED\nreplaced in %d min" if down else "IN CUSTODY\nout in %d min") % GS.jail_minutes(id)   # (masked soldiers: another takes the post)
		elif id in GS.bounties_done: shut = "PAID"
		var key := "b:" + id
		_tap_to_hear([row.get_child(0), t], key, func(): read_bounty(p))
		row.add_child(_board_buttons("Bounty_" + id, key, mine, shut,
			func():
				var said := Missions.toggle_bounty(id)
				status.text = said
				_note_giver()
				if GS.bounty.get("id", "") == id and board_pick != key: read_bounty(p)   # v1.7v: read out when taken (unless just heard)
				board_pick = ""
				show_screen("bounty"),
			func():
				status.text = Missions.disengage()
				board_pick = ""
				show_screen("bounty")))
		v.add_child(_row_frame(row, mine or board_pick == key))

## v1.9k: the job just taken remembers this dock's name, so the way back and the messages name the right place.
func _note_giver() -> void:
	if not GS.mission.is_empty() and str(GS.mission.get("giver", "")) == str(base.get("id", "")): GS.mission["giver_name"] = str(base.get("name", ""))

## v1.9k (owner: the other jobs need a picture too): the job's picture (assets/missions/<kind>.png) or, until it is
## delivered, a tile with the job's kind written on it, the same size as a bounty face.
static func mission_icon_key(o: Dictionary) -> String:
	var k := str(o.get("kind", ""))
	if k == "threats": return "elite" if o.get("hard", false) else "patrol"
	return k
func _mission_icon(o: Dictionary) -> Control:
	var key := mission_icon_key(o)
	var path := Data.MISSION_ICON_DIR + key + ".png"
	if ResourceLoader.exists(path):
		var pic := TextureRect.new()
		pic.name = "Icon_" + key
		pic.custom_minimum_size = Vector2(Data.BOUNTY_FACE_PX, Data.BOUNTY_FACE_PX)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.size_flags_vertical = Control.SIZE_SHRINK_CENTER   # (square, not stretched to the row's height)
		pic.texture = load(path)
		return pic
	var tile := PanelContainer.new()
	tile.name = "Icon_" + key
	tile.custom_minimum_size = Vector2(Data.BOUNTY_FACE_PX, Data.BOUNTY_FACE_PX)
	tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.12, 0.2)
	sb.border_color = CYAN
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	tile.add_theme_stylebox_override("panel", sb)
	var lab := _label(15, GOLD)
	lab.text = {"patrol": "PATROL", "elite": "ELITE", "escort": "ESCORT", "convoy": "CARGO\nRUN", "ground": "GROUND\nSTRIKE", "land_escort": "GROUND\nESCORT", "outlaws": "OUTLAWS", "invasion": "FLEET\nINVASION"}.get(key, key.to_upper())
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tile.add_child(lab)
	return tile

## v1.9m (owner): a picture in a frame of its difficulty tier's colour (Data.TIER_COLORS), with a thin light edge
## round the outside so even the BLACK tier shows on the dark board.
func tier_frame(inner: Control, tier: int) -> Control:
	var col: Color = Data.TIER_COLORS[clampi(tier, 1, Data.TIER_COLORS.size()) - 1]
	var outer := PanelContainer.new()
	outer.name = "Tier_%d" % tier
	outer.set_meta("tier", tier)
	outer.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var so := StyleBoxFlat.new()
	so.bg_color = col
	so.border_color = Color(0.85, 0.88, 0.95, 0.9)
	so.set_border_width_all(1)
	so.set_corner_radius_all(8)
	so.set_content_margin_all(4)
	outer.add_theme_stylebox_override("panel", so)
	inner.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	outer.add_child(inner)
	outer.tooltip_text = "Difficulty: %s" % Data.TIER_NAMES[clampi(tier, 1, Data.TIER_NAMES.size()) - 1]
	return outer

## v1.9o (owner: "make it simple, not everybody wants to read"): tap a job or a bounty (its picture or its words) and
## it is read out in the phone voice; the row lights up and its buttons are ACCEPT / DECLINE. The job you have shows
## CONTINUE (launch and fly it) / DISENGAGE (drop it, even with a prisoner aboard: they are let go).
var board_pick := ""   # the row that was just tapped (heard)
func _tap_to_hear(parts: Array, key: String, hear: Callable) -> void:
	for c in parts:
		var ctl := c as Control
		ctl.mouse_filter = Control.MOUSE_FILTER_PASS
		ctl.gui_input.connect(func(ev: InputEvent):
			var tap: bool = (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT) or (ev is InputEventScreenTouch and ev.pressed)
			if not tap: return
			pick_row(key, hear))

## (tests call this too) the tap on a row: hear it and show ACCEPT / DECLINE.
func pick_row(key: String, hear: Callable) -> void:
	board_pick = key
	hear.call()
	show_screen(screen)

func _board_buttons(main_name: String, key: String, mine: bool, shut: String, on_accept: Callable, on_drop: Callable) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var b := Button.new()
	b.name = main_name
	b.custom_minimum_size = Vector2(230, 56)
	col.add_child(b)
	if shut != "":
		b.text = shut
		b.disabled = true
		return col
	if mine:
		b.text = "DISENGAGE"
		b.add_theme_color_override("font_color", Color(1.0, 0.55, 0.5))
		b.pressed.connect(on_drop)
		var c := Button.new()
		c.name = "Continue_" + main_name
		c.text = "CONTINUE"
		c.custom_minimum_size = Vector2(230, 56)
		c.add_theme_color_override("font_color", GOLD)
		c.pressed.connect(func(): launch_requested.emit())
		col.add_child(c)
		col.move_child(c, 0)
		return col
	b.text = "ACCEPT"
	b.add_theme_color_override("font_color", Color(0.55, 1.0, 0.6))
	b.pressed.connect(on_accept)
	if board_pick == key:
		var d := Button.new()
		d.name = "Decline_" + main_name
		d.text = "DECLINE"
		d.custom_minimum_size = Vector2(230, 56)
		d.pressed.connect(func():
			board_pick = ""
			Sfx.stop_voice()
			show_screen(screen))
		col.add_child(d)
	return col

## v1.9o (owner: "they don't want your business"): a base whose people are hostile to you gives you no work.
func _board_locked(v: VBoxContainer) -> bool:
	var own: String = Factions.owner_of(base, Data.SYSTEMS[GS.system_id])
	if own == "" or not Factions.has(own) or not Factions.hostile(own): return false
	var lk := _label(Data.BOARD_FONT, Color(1.0, 0.5, 0.45))
	lk.name = "BoardLocked"
	lk.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lk.text = "LOCKED. %s don't want your business: your standing with them is %s. Raise it (work for their friends, stop hitting their ships) and come back." % [own, Factions.band(own).to_upper()]
	v.add_child(lk)
	return true

## A job read out (title, brief, reward) in the coordinator's phone voice.
func read_job(o: Dictionary) -> void:
	var said := "%s. %s Reward %d credits." % [str(o["title"]), str(o["brief"]), int(o["pay"])]
	last_read = said
	_say_board(said)

func _say_board(line: String) -> void:
	var co: Dictionary = Factions.coordinator(Factions.owner_of(base, Data.SYSTEMS[GS.system_id]))
	Sfx.read_aloud(line, str(co.get("voice_id", co.get("id", ""))) if not co.is_empty() else "", float(co.get("voice", 1.0)), str(co.get("sex", "")) == "female")

## v1.7v: the coordinator reads a selected bounty out (same voice as the jobs).
var last_read := ""   # (tests) the last line read out from the board
func read_bounty(p: Dictionary) -> void:
	var co: Dictionary = Factions.coordinator(Factions.owner_of(base, Data.SYSTEMS[GS.system_id]))
	var line := "Bounty: %s, %s. %s. Reward %d credits, wanted %s. They're in this system: follow the waypoint." % [str(p["name"]), str(p["type"]), str(p["faction"]),
		Data.bounty_reward(str(p["id"])), "alive" if int(p["rank"]) >= Data.BOUNTY_ALIVE_RANK else "dead"]
	last_read = line
	_say_board(line)

## v1.5f / v1.5k: the MISSIONS tab: the station's jobs; tap one to take and track it, tap it again to drop it, tap
## another to switch.
func _missions_page() -> void:
	var v := _scroll_box()
	_board_head(v, "missions")
	var l := _label(17, Color(1, 1, 1))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var co: Dictionary = Factions.coordinator(Factions.owner_of(base, Data.SYSTEMS[GS.system_id]))
	l.text = "Work for %s%s. Tap a job to hear it; ACCEPT takes it (a gold waypoint leads you through it). DISENGAGE drops the job you have." % [base["name"], (", from %s" % co["name"]) if not co.is_empty() else ""]
	v.add_child(l)
	if _board_locked(v): return
	for o in Missions.offers(GS.system_id, base["id"], Factions.owner_of(base, Data.SYSTEMS[GS.system_id]), "planet" if str(base.get("kind", "station")) == "planet" else "station"):   # v1.9b
		var row := HBoxContainer.new()
		row.name = "Job_" + str(o["kind"]) + ("_hard" if o.get("hard", false) else "")
		row.add_theme_constant_override("separation", 14)
		var mine: bool = Missions.is_current(o)
		row.add_child(tier_frame(_mission_icon(o), Data.tier_of_pay(int(o["pay"]))))   # v1.9k (owner): every job has a picture; v1.9m: in its difficulty colour
		var t := _label(Data.BOARD_FONT, CYAN)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t.text = "%s\n%s\nReward %d cr" % [str(o["title"]).to_upper(), o["brief"], int(o["pay"])]
		row.add_child(t)
		var key := "j:" + row.name
		var hear := func(): read_job(o)
		_tap_to_hear([row.get_child(0), t], key, hear)
		row.add_child(_board_buttons("Take_" + row.name, key, mine, "",
			func():
				status.text = Missions.toggle(o) if not Missions.is_current(o) else status.text
				_note_giver()
				if Missions.is_current(o) and board_pick != key: read_job(o)   # v1.7p: read out when taken (unless just heard)
				board_pick = ""
				show_screen("missions"),
			func():
				status.text = Missions.disengage()
				board_pick = ""
				show_screen("missions")))
		v.add_child(_row_frame(row, mine or board_pick == key))

## v1.5f: YOUR SHIP: weapons and the hold (and the job you carry, which can be dropped here).
func _ship_page() -> void:
	var v := _page_box()
	var sh := GS.ship()
	var head := _label(22, Color(1, 1, 1))
	head.text = "%s  ·  %s" % [str(sh["name"]).to_upper(), sh["class"]]
	v.add_child(head)
	var w := _label(18, CYAN)
	w.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	w.name = "Weapons"
	var slots: Array = []
	for it in GS.slots: slots.append("%s %s %d/%d" % [Data.SLOT_ITEMS[it]["label"], Data.SLOT_ITEMS[it]["sub"], GS.slot_ammo(it), {"light_missile": GS.max_missiles(), "heavy_missile": GS.max_heavy(), "mine": GS.max_mines()}[it]])
	w.text = "WEAPONS\nGuns: %s ×%d   ·   Hull %d/%d   ·   Shield %d\nRacks: %s" % [GS.weapon()["name"], sh["guns"], int(GS.hull), int(sh["hull"]), int(sh["shield"]), "   ·   ".join(slots)]
	v.add_child(w)
	var c := _label(18, CYAN)
	c.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	c.name = "Cargo"
	var lines: Array = []
	for item in GS.cargo:
		if item.get("kind", "") == "ore":   # v1.8l: mined gold / diamond, with what this base pays
			var op: int = GS.ore_price(str(item["id"]), str(base["name"]))
			lines.append("%s x%d (%d cr each here = %d cr)" % [Data.ORE_NAME.get(item["id"], "Ore"), int(item["n"]), op, op * int(item["n"])])
		else: lines.append("%s (%s)" % [item.get("name", item.get("kind", "?")), item.get("note", item.get("kind", ""))])
	c.text = "CARGO HOLD  %d / %d\n%s" % [GS.cargo.size(), Data.CARGO_HOLD, "\n".join(lines) if not lines.is_empty() else "Empty."]
	v.add_child(c)
	var worth: int = GS.ore_worth(str(base["name"]))
	if worth > 0:
		var sb := Button.new()
		sb.name = "SellOre"
		sb.text = "SELL GOLD / DIAMOND  +%d cr" % worth
		sb.custom_minimum_size = Vector2(330, 56)
		sb.add_theme_color_override("font_color", GOLD)
		sb.pressed.connect(func(): status.text = GS.sell_ore(str(base["name"])); Sfx.play("pickup", -6.0); show_screen("ship"))
		v.add_child(sb)
	if not GS.mission.is_empty():
		var m := _label(18, GOLD)
		m.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		m.text = "CURRENT JOB: %s\n%s" % [str(GS.mission["title"]).to_upper(), GS.mission["brief"]]
		v.add_child(m)
		var b := Button.new()
		b.name = "DropJob"
		b.text = "DROP THIS JOB"
		b.custom_minimum_size = Vector2(230, 56)
		b.pressed.connect(func(): Missions.abandon(); status.text = "Job dropped."; show_screen("ship"))
		v.add_child(b)

## v1.4r: where you stand with the major factions, in their reputation colour (purple .. red, gray = permanent enemy).
## This system's owner and its rival come first.
func _standing_rows(v: VBoxContainer) -> void:
	var here: String = str(Data.SYSTEMS[GS.system_id].get("faction", ""))
	var order: Array = []
	for f in [here, Factions.rival(here), "Savagers", "Liberator"]:
		if Factions.has(f) and not (f in order): order.append(f)
	var flow := HFlowContainer.new()
	flow.name = "Standing"
	flow.add_theme_constant_override("h_separation", 22)
	for f in order.slice(0, 4):
		var i: Dictionary = Factions.info(f)
		var l := _label(15 if screen == "hub" else 17, i["color"])
		l.name = "Standing_" + f
		l.text = "%s: %s" % [Factions.def(f)["display_name"].to_upper(), i["name"]]
		l.tooltip_text = i["note"]
		flow.add_child(l)
	v.add_child(flow)

## v1.4s: who runs this place and where you stand with them.
func _faction_page() -> void:
	var v := _page_box()
	var f: String = Factions.owner_of(base, Data.SYSTEMS[GS.system_id])
	var d: Dictionary = Factions.def(f)
	var title := _label(26, d.get("primary_color", Color(1, 1, 1)))
	title.name = "FactionName"
	title.text = str(d.get("display_name", f if f != "" else "Independent")).to_upper()
	v.add_child(title)
	var l := _label(19, Color(1, 1, 1))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if d.is_empty():
		l.text = "No major faction holds this place."
	else:
		var i: Dictionary = Factions.info(f)
		var rv: String = Factions.rival(f)
		l.text = "This station is run by the %s.\nYour standing: %s. %s\n%s" % [d["display_name"], i["name"], i["note"],
			("Their rival: the %s. What you do for one side counts against the other." % Factions.def(rv)["display_name"]) if rv != "" else "A permanent enemy: no diplomacy."]
	v.add_child(l)
	_standing_rows(v)
	# v1.4w: the faction's six people (names, ranks and faces from the owner's roster)
	var cast: Array = Data.ROSTERS.get(f, {}).get("pilots", [])
	if not cast.is_empty():
		var strip := HBoxContainer.new()
		strip.name = "Cast"
		strip.add_theme_constant_override("separation", 10)
		for p0 in cast:
			var p: Dictionary = Data.roster_pilot(p0["id"])
			var col := VBoxContainer.new()
			col.name = "Cast_" + str(p["id"])
			col.custom_minimum_size = Vector2(Data.FACTION_FACE_PX + 44, 0)
			var pic := TextureRect.new()
			pic.custom_minimum_size = Vector2(Data.FACTION_FACE_PX, Data.FACTION_FACE_PX)
			pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			Packs.request("enemies")
			if ResourceLoader.exists(p["portrait_clean"]): pic.texture = load(p["portrait_clean"])
			col.add_child(pic)
			var nm := _label(13, Color(1, 1, 1))
			nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			nm.text = "%02d %s" % [int(p["slot"]), p["name"]]
			col.add_child(nm)
			strip.add_child(col)
		v.add_child(strip)

func _repair_page() -> void:
	var v := _page_box()
	var l := _label(20, Color(1, 1, 1))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.text = "Hull %d/%d  ·  Shield %d/%d  ·  Repair kits %d/%d  ·  Shield charges %d/%d  ·  Energy cells %d/%d  ·  Missiles %d/%d  ·  Mines %d/%d\n\nDocking crews repair every ship that lands here, free of charge for Unity-registered pilots." % [int(GS.hull), int(GS.max_hull()), int(GS.shield), int(GS.max_shield()), GS.repairs, Data.MAX_REPAIRS, GS.shield_charges, Data.MAX_SHIELD_CHARGES, GS.energy_cells, Data.MAX_ENERGY_CELLS, GS.missiles, GS.max_missiles(), GS.mines, GS.max_mines()]
	v.add_child(l)
	var b := Button.new()
	b.text = "REPAIR NOW  ·  FREE"
	b.name = "RepairAll"
	b.custom_minimum_size = Vector2(360, 60)
	b.disabled = not GS.needs_repair()
	b.pressed.connect(func(): status.text = GS.repair_all(); show_screen("repair"))
	v.add_child(b)
	var b2 := Button.new()   # v1.4n: ammo is billed, same button as at Equipment
	var rc := GS.restock_cost()
	b2.text = "RESTOCK ALL  ·  %d cr" % rc if rc > 0 else "RESTOCK ALL  ·  FULL"
	b2.name = "RestockAll"
	b2.custom_minimum_size = Vector2(360, 60)
	b2.disabled = rc <= 0
	b2.pressed.connect(func(): status.text = GS.restock_all(); show_screen("repair"))
	v.add_child(b2)

func _process(dt: float) -> void:
	if not visible: return
	t += dt
	_update_room(dt)
	_asst_place()
	if preview_pivot and is_instance_valid(preview_pivot) and screen != "equipment": preview_pivot.rotation.y = t * 0.4 + eq_yaw
	elif preview_pivot and is_instance_valid(preview_pivot) and screen == "equipment":   # v2.6 (owner): it turns on the platform
		if bay_hold > 0.0: bay_hold -= dt
		else: bay_yaw = fmod(bay_yaw + dt * Data.BAY_SPIN, TAU)
		preview_pivot.rotation.y = bay_yaw
		if is_instance_valid(_bay_art_node) and is_instance_valid(_bay_node): _stand_model(_bay_art_node, _bay_node)   # (keeps it on the pad as the page settles)
		var ov: Control = content.find_child("MountMap", true, false) if is_instance_valid(content) else null
		if ov != null: ov.queue_redraw()
	queue_redraw()

# ---------------------------------------------------------------- scenic background
func _draw() -> void:
	var S := get_viewport_rect().size
	if bg_tex != null:
		# the faction's (or this station's own) interface picture: fixed, filling the screen, never moving
		var src := Rect2(Vector2.ZERO, bg_tex.get_size())
		var k := maxf(S.x / src.size.x, S.y / src.size.y)
		draw_texture_rect_region(bg_tex, Rect2((S.x - src.size.x * k) * 0.5, (S.y - src.size.y * k) * 0.5, src.size.x * k, src.size.y * k), src)
		draw_rect(Rect2(Vector2.ZERO, S), Color(0.01, 0.02, 0.04, Data.HUB_BG_WASH))
		draw_rect(Rect2(0, 0, S.x, 116), Color(0, 0, 0, Data.HUB_HEADER_BAND))
	elif kind == "planet":
		var sky_top := Color(0.2, 0.42, 0.75) if base.get("palette", "") == "terran" else Color(0.15, 0.45, 0.4)
		var sky_bot := Color(0.95, 0.75, 0.55) if base.get("palette", "") == "terran" else Color(0.75, 0.9, 0.6)
		for i in 24:
			var k := i / 23.0
			draw_rect(Rect2(0, S.y * k, S.x, S.y / 23.0 + 1), sky_top.lerp(sky_bot, k * 0.8))
		# distant mountains and towers
		var pts := PackedVector2Array([Vector2(0, S.y)])
		for x in range(0, int(S.x) + 40, 40):
			pts.append(Vector2(x, S.y * 0.68 - 40 * sin(x * 0.011) - 22 * sin(x * 0.037)))
		pts.append(Vector2(S.x, S.y))
		draw_colored_polygon(pts, Color(0.18, 0.25, 0.3))
		for i in 14:
			var x := S.x * (0.08 + i * 0.065)
			var h := 60.0 + 90.0 * absf(sin(i * 2.3))
			draw_rect(Rect2(x, S.y * 0.7 - h, 26, h), Color(0.12, 0.16, 0.2))
			for w in int(h / 14):
				draw_rect(Rect2(x + 6, S.y * 0.7 - h + 8 + w * 14, 5, 4), Color(1.0, 0.85, 0.5, 0.7))
		draw_rect(Rect2(0, S.y * 0.72, S.x, S.y * 0.28), Color(0.1, 0.12, 0.14))
		for i in 8:
			draw_line(Vector2(S.x * 0.5, S.y * 0.72), Vector2(S.x * (i / 7.0), S.y), Color(1.0, 0.85, 0.4, 0.25), 2)
	else:
		draw_rect(Rect2(Vector2.ZERO, S), Color(0.04, 0.06, 0.09))
		# hangar window onto space
		var win := Rect2(S.x * 0.3, 40, S.x * 0.64, S.y * 0.5)
		draw_rect(win, Color(0.01, 0.02, 0.05))
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(base.get("name", ""))
		for i in 90:
			draw_circle(win.position + Vector2(rng.randf() * win.size.x, rng.randf() * win.size.y), rng.randf_range(0.6, 1.8), Color(1, 1, 1, rng.randf_range(0.3, 0.9)))
		draw_circle(win.position + win.size * Vector2(0.78, 0.9), win.size.y * 0.5, Color(0.2, 0.45, 0.8))
		draw_arc(win.position + win.size * Vector2(0.78, 0.9), win.size.y * 0.5, PI, TAU, 48, Color(0.6, 0.85, 1.0, 0.8), 4)
		for i in 7:
			var x := win.position.x + win.size.x * i / 6.0
			draw_line(Vector2(x, win.position.y), Vector2(x, win.end.y), Color(0.2, 0.24, 0.3), 6)
		draw_rect(win, Color(0.3, 0.36, 0.45), false, 8)
		# floor perspective
		for i in 12:
			draw_line(Vector2(S.x * 0.5, S.y * 0.6), Vector2(S.x * (i / 11.0) * 1.4 - S.x * 0.2, S.y), Color(0.3, 0.8, 1.0, 0.12), 2)
		for i in 6:
			var y := S.y * 0.6 + pow(i / 5.0, 2.0) * S.y * 0.4
			draw_line(Vector2(0, y), Vector2(S.x, y), Color(0.3, 0.8, 1.0, 0.1), 2)
		var blink := 0.5 + 0.5 * sin(t * 3.0)
		for i in 10:
			draw_circle(Vector2(S.x * (0.05 + i * 0.1), S.y * 0.6), 4, Color(1.0, 0.8, 0.3, 0.4 + 0.5 * blink))
	# darken behind UI (v3.1: a band under the tabs and name, and a fade at the foot for the status line)
	draw_rect(Rect2(Vector2.ZERO, Vector2(S.x, CONTENT_Y - 4.0)), Color(0, 0, 0, 0.42))
	draw_line(Vector2(0, CONTENT_Y - 4.0), Vector2(S.x, CONTENT_Y - 4.0), Color(CYAN, 0.25), 1.0)
	for i in 8:
		draw_rect(Rect2(0, S.y - 70.0 + i * 9.0, S.x, 9.0), Color(0, 0, 0, 0.05 + i * 0.05))

## Which planet this base belongs to, if that planet has a surface (orbital port or a town on it).
func _surface_planet() -> String:
	var id: String = base.get("id", "")
	if Surface.has_surface(id): return id
	for pid in Surface.PLANETS:
		for l in Surface.PLANETS[pid]["locations"]:
			if l["id"] == id: return pid
	return ""

## Fast travel: every landing site on the planet; pick one to fly straight there.
func _surface_page() -> void:
	var pid := _surface_planet()
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 18
	v.offset_top = 14
	v.offset_right = -18
	v.add_theme_constant_override("separation", 8)
	content.add_child(v)
	var intro := _label(16, CYAN)
	var g := Surface.grid(pid)
	intro.text = "%s · %d×%d surface sectors, wrapping around the globe. Choose where to set down:" % [Surface.PLANETS[pid]["name"], g, g]
	v.add_child(intro)
	for l in Surface.PLANETS[pid]["locations"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		var lab := _label(17, Color(1, 1, 1))
		lab.text = "%s  ·  %s\n%s" % [l["name"], l["role"], Surface.tile_name(pid, int(l["tile"])).capitalize()]
		lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lab)
		var b := Button.new()
		b.name = "Go_" + l["id"]
		b.text = "HERE" if l["id"] == base.get("id", "") else "TRAVEL"
		b.disabled = l["id"] == base.get("id", "")
		b.custom_minimum_size = Vector2(150, 54)
		b.pressed.connect(func(): descend_requested.emit(pid, l["id"]))
		row.add_child(b)
		v.add_child(row)
