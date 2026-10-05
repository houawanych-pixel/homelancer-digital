extends Control
## Docked base screens: Hub, Equipment Dealer, Ship Dealer, Repair/Resupply. Map and Launch are handled by main.

signal launch_requested
signal map_requested
signal descend_requested(planet_id: String, location_id: String)

const CYAN := Color(0.4, 0.86, 1.0)
const GOLD := Color(1.0, 0.82, 0.4)
const INK := Color(0.03, 0.07, 0.12, 0.74)

var base: Dictionary = {} # station or planet info from Data
var kind := "station"
var screen := "hub"
var font: Font = ThemeDB.fallback_font
var theme_obj: Theme
var left: VBoxContainer
var content: Control
var status: Label
var header: Label
var subheader: Label
var credits_label: Label
var preview_vp: SubViewport
var preview_pivot: Node3D
var preview_key := ""
var t := 0.0
# ship inspector: tap the showroom (or VIEW) to look the ship over: drag to turn it, pinch / wheel to zoom, full stats
var rooms: Rooms
var last_room := ""
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
	header = _label(40, Color(1, 1, 1))
	header.position = Vector2(40, 22)
	add_child(header)
	subheader = _label(17, CYAN)
	subheader.position = Vector2(42, 78)
	add_child(subheader)
	credits_label = _label(22, GOLD)
	credits_label.anchor_left = 1.0
	credits_label.anchor_right = 1.0
	credits_label.offset_left = -420
	credits_label.offset_right = -36
	credits_label.offset_top = 30
	credits_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(credits_label)
	left = VBoxContainer.new()
	left.position = Vector2(40, 130)
	left.add_theme_constant_override("separation", 10)
	add_child(left)
	content = Panel.new()
	content.anchor_left = 0.0
	content.anchor_right = 1.0
	content.anchor_bottom = 1.0
	content.offset_left = 330
	content.offset_top = 130
	content.offset_right = -36
	content.offset_bottom = -86
	add_child(content)
	status = _label(18, GOLD)
	status.anchor_top = 1.0
	status.anchor_bottom = 1.0
	status.anchor_right = 1.0
	status.offset_left = 330
	status.offset_top = -70
	status.offset_bottom = -30
	status.offset_right = -36
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status)
	GS.changed.connect(_refresh_credits)
	rooms = Rooms.new()
	add_child(rooms)
	rooms.action.connect(_on_room_action)
	Packs.pack_ready.connect(func(pk: String):
		if pk.begins_with("rooms") and visible and screen == "hub": show_screen("hub"))
	visible = false

## A marker in a panorama room was tapped: open the matching dealer screen, the map, the inspector, or launch.
func _on_room_action(act: String) -> void:
	if act == "launch": launch_requested.emit()
	elif act == "map": map_requested.emit()
	elif act == "inspect":
		show_screen("ships")
		open_inspector(GS.ship_id)
	elif act.begins_with("screen:"): show_screen(act.substr(7))

## Stations with painted rooms (scripts/rooms.gd) show those instead of the plain hub page, once the pack is in.
func has_rooms() -> bool:
	return kind == "station" and Rooms.available(base.get("id", ""))

func _label(size: int, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
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
	th.set_stylebox("normal", "Button", mk.call(Color(0.05, 0.12, 0.2, 0.92), Color(CYAN, 0.6)))
	th.set_stylebox("hover", "Button", mk.call(Color(0.08, 0.2, 0.32, 0.95), CYAN))
	th.set_stylebox("pressed", "Button", mk.call(Color(0.15, 0.35, 0.5, 0.98), CYAN))
	th.set_stylebox("focus", "Button", mk.call(Color(0, 0, 0, 0), Color(0, 0, 0, 0)))
	th.set_stylebox("disabled", "Button", mk.call(Color(0.05, 0.07, 0.1, 0.8), Color(1, 1, 1, 0.15)))
	th.set_font_size("font_size", "Button", 21)
	th.set_color("font_color", "Button", Color(0.93, 0.97, 1.0))
	th.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.35))
	th.set_stylebox("panel", "Panel", mk.call(INK, Color(CYAN, 0.35)))
	th.set_font_size("font_size", "Label", 18)
	return th

func open(station_or_planet: Dictionary) -> void:
	base = station_or_planet
	kind = base.get("kind", "station")
	visible = true
	last_room = ""
	Packs.request("rooms")
	if Rooms.station_pack(base.get("id", "")) != "": Packs.request(Rooms.station_pack(base["id"]))   # v1.4l: each hub's rooms are their own pack
	if last_room != "" and Rooms.pack_of(last_room) != Rooms.station_pack(base.get("id", "")): last_room = ""   # a room from another station
	show_screen("hub")
	status.text = "Docked at %s. Hull repaired, shields and repair kits restored, missiles reloaded." % base["name"]

func _refresh_credits() -> void:
	credits_label.text = "CREDITS  %d cr" % GS.credits

var screen_bg: Texture2D   # v1.4m: a room of this station, dimmed, behind the dealer screens

func show_screen(s: String) -> void:
	close_inspector()
	screen_bg = null
	var bg_room: String = Rooms.SCREEN_BG.get(base.get("id", ""), {}).get(s, "")
	if bg_room != "" and kind == "station" and Rooms.available(base.get("id", "")) and ResourceLoader.exists(Rooms.path(bg_room)): screen_bg = load(Rooms.path(bg_room))
	if screen == "hub" and rooms.visible: last_room = rooms.room
	screen = s
	_refresh_credits()
	var in_rooms := s == "hub" and has_rooms()
	for c in [header, subheader, credits_label, left, content, status]: c.visible = not in_rooms
	rooms.visible = in_rooms
	if in_rooms:
		for c in left.get_children(): c.queue_free()
		for c in content.get_children(): c.queue_free()
		preview_vp = null
		rooms.open(last_room if last_room != "" else Rooms.start_room(base["id"]))
		queue_redraw()
		return
	var sysname: String = Data.SYSTEMS[GS.system_id]["name"]
	header.text = base["name"].to_upper() if s == "hub" else {"equipment": "EQUIPMENT DEALER", "ships": "SHIP DEALER", "repair": "REPAIR & RESUPPLY", "surface": "PLANET DESTINATIONS"}[s]
	subheader.text = "%s  ·  %s SYSTEM  ·  %s" % ["ORBITAL STATION" if kind == "station" else "PLANET SURFACE", sysname.to_upper(), base["name"]]
	for c in left.get_children(): c.queue_free()
	for c in content.get_children(): c.queue_free()
	preview_vp = null
	var menu := [["hub", "STATION" if has_rooms() else "HUB"], ["equipment", "EQUIPMENT"], ["ships", "SHIP DEALER"], ["repair", "REPAIR / RESUPPLY"], ["map", "NAVIGATION"], ["launch", "LAUNCH"]]
	if _surface_planet() != "": menu.insert(4, ["surface", "SURFACE TRAVEL"])
	for m in menu:
		var b := Button.new()
		b.text = m[1]
		b.custom_minimum_size = Vector2(270, 64)
		b.name = "Btn_" + m[0]
		if m[0] == s: b.add_theme_color_override("font_color", GOLD)
		if m[0] == "launch": b.add_theme_color_override("font_color", Color(0.5, 1.0, 0.65))
		b.pressed.connect(_menu.bind(m[0]))
		left.add_child(b)
	match s:
		"hub": _hub_page()
		"equipment": _equipment_page()
		"ships":
			Packs.request("lancer")
			Packs.request("ranger")
			Packs.request("hauler")
			Packs.request("bulk")
			_ships_page()
		"repair": _repair_page()
		"surface": _surface_page()
	queue_redraw()

func _menu(id: String) -> void:
	if id == "launch": launch_requested.emit()
	elif id == "map": map_requested.emit()
	else: show_screen(id)

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

func _hub_page() -> void:
	var v := _page_box()
	var l := _label(22, Color(1, 1, 1))
	l.text = base.get("desc", "")
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(l)
	var s := GS.ship()
	var info := _label(18, CYAN)
	info.text = "Your ship: %s (%s)   ·   Weapon: %s ×%d   ·   Missiles %d/%d + heavy %d/%d   ·   Mines %d/%d   ·   Hull %d/%d" % [s["name"], s["class"], GS.weapon()["name"], s["guns"], GS.missiles, GS.max_missiles(), GS.heavy_missiles, GS.max_heavy(), GS.mines, GS.max_mines(), int(GS.hull), int(GS.max_hull())]
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(info)
	var tips := _label(17, Color(0.85, 0.9, 0.95))
	tips.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var gate: Dictionary = Data.SYSTEMS[GS.system_id]["gate"]
	tips.text = "Local traffic report: hostile %ss patrol the lanes. The %s leads to %s.\nEquipment sells new guns and missiles. The Ship Dealer trades up to heavier hulls. Launch when ready." % [Data.ENEMIES[Data.SYSTEMS[GS.system_id]["enemy"]]["name"].to_lower(), gate["name"], Data.SYSTEMS[gate["to"]]["name"]]
	v.add_child(tips)

func _equipment_page() -> void:
	var outer := _page_box()
	var scroll := ScrollContainer.new()      # v1.4j: the missile racks made the list taller than the screen: drag it
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	var cap := _label(16, CYAN)
	cap.text = "GUNS  ·  your %s carries %d hardpoints. Damage shown per shot." % [GS.ship()["name"], GS.ship()["guns"]]
	v.add_child(cap)
	for id in Data.WEAPON_ORDER:
		var w: Dictionary = Data.WEAPONS[id]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		var l := _label(18, Color(1, 1, 1) if id != GS.weapon_id else GOLD)
		l.text = "%s   ·   dmg %d   ·   %.1f/s   ·   range %dm" % [w["name"], w["damage"], w["rate"], w["range"]]
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var b := Button.new()
		b.custom_minimum_size = Vector2(230, 54)
		b.name = "Buy_" + id
		if id == GS.weapon_id: b.text = "EQUIPPED"; b.disabled = true
		elif id in GS.owned_weapons: b.text = "EQUIP"
		else: b.text = "BUY  %d cr" % w["price"]; b.disabled = GS.credits < int(w["price"])
		b.pressed.connect(func(): status.text = GS.buy_weapon(id); show_screen("equipment"))
		row.add_child(b)
		v.add_child(row)
	var sep := HSeparator.new()
	v.add_child(sep)
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
	v.add_child(row2)
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
		v.add_child(rr)
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
	v.add_child(rowh)
	var row3 := HBoxContainer.new()
	row3.add_theme_constant_override("separation", 14)
	var nl := _label(18, Color(1, 1, 1))
	nl.text = "Proximity mines   ·   %d/%d loaded   ·   %d cr each   ·   dmg %d" % [GS.mines, GS.max_mines(), Data.MINE_PRICE, int(Data.MINE_DAMAGE)]
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row3.add_child(nl)
	for n in [1, 99]:
		var b3 := Button.new()
		b3.text = "+1" if n == 1 else "FILL"
		b3.name = "Mine_" + str(n)
		b3.custom_minimum_size = Vector2(110, 54)
		b3.disabled = GS.mines >= GS.max_mines()
		b3.pressed.connect(func(): status.text = GS.buy_mines(n); show_screen("equipment"))
		row3.add_child(b3)
	v.add_child(row3)

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
	svc.custom_minimum_size = Vector2(340, 300)
	svc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	h.add_child(svc)
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
	insp_stats.add_theme_font_size_override("normal_font_size", 17)
	insp_stats.add_theme_font_size_override("bold_font_size", 26)
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

func _repair_page() -> void:
	var v := _page_box()
	var l := _label(20, Color(1, 1, 1))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.text = "Hull %d/%d  ·  Shield %d/%d  ·  Repair kits %d/%d  ·  Shield charges %d/%d  ·  Energy cells %d/%d  ·  Missiles %d/%d  ·  Mines %d/%d\n\nDocking crews repair and resupply every ship that lands here, free of charge for Unity-registered pilots." % [int(GS.hull), int(GS.max_hull()), int(GS.shield), int(GS.max_shield()), GS.repairs, Data.MAX_REPAIRS, GS.shield_charges, Data.MAX_SHIELD_CHARGES, GS.energy_cells, Data.MAX_ENERGY_CELLS, GS.missiles, GS.max_missiles(), GS.mines, GS.max_mines()]
	v.add_child(l)
	var b := Button.new()
	b.text = "REPAIR AND RESUPPLY NOW"
	b.name = "RepairAll"
	b.custom_minimum_size = Vector2(360, 60)
	b.pressed.connect(func(): GS.restore_full(); status.text = "All systems restored."; show_screen("repair"))
	v.add_child(b)

func _process(dt: float) -> void:
	if not visible: return
	t += dt
	if preview_pivot and is_instance_valid(preview_pivot): preview_pivot.rotation.y = t * 0.6
	queue_redraw()

# ---------------------------------------------------------------- scenic background
func _draw() -> void:
	var S := get_viewport_rect().size
	if kind == "planet":
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
	elif screen_bg != null:
		# the room this dealer works in, filling the screen and dimmed so the lists read (front view of a two-view strip)
		var two: bool = screen_bg.get_width() > screen_bg.get_height() * 4
		var src := Rect2(0, 0, Rooms.VIEW_W if two else float(screen_bg.get_width()), screen_bg.get_height())
		var k := maxf(S.x / src.size.x, S.y / src.size.y)
		var dst := Rect2((S.x - src.size.x * k) * 0.5, (S.y - src.size.y * k) * 0.5, src.size.x * k, src.size.y * k)
		draw_texture_rect_region(screen_bg, dst, src)
		draw_rect(Rect2(Vector2.ZERO, S), Color(0.01, 0.03, 0.06, 0.62))
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
	# darken behind UI
	draw_rect(Rect2(Vector2.ZERO, Vector2(S.x, 118)), Color(0, 0, 0, 0.45))
	draw_rect(Rect2(Vector2(0, 118), Vector2(326, S.y)), Color(0, 0, 0, 0.35))

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
