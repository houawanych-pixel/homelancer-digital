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
var launch_btn: Button   # v1.5k: always there, upper right
var board_tab := "missions"   # v1.5k: the MISSION BOARD's open tab: "missions" | "bounty"
var preview_vp: SubViewport
var preview_pivot: Node3D
var preview_key := ""
var t := 0.0
# ship inspector: tap the showroom (or VIEW) to look the ship over: drag to turn it, pinch / wheel to zoom, full stats
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
	# v1.5k: LAUNCH is always on screen (upper right, under the credits), on every page: you can never be stuck here
	launch_btn = Button.new()
	launch_btn.name = "LaunchButton"
	launch_btn.text = "LAUNCH"
	launch_btn.anchor_left = 1.0
	launch_btn.anchor_right = 1.0
	launch_btn.offset_left = -36 - Data.HUB_LAUNCH_SIZE.x
	launch_btn.offset_right = -36
	launch_btn.offset_top = 64
	launch_btn.offset_bottom = 64 + Data.HUB_LAUNCH_SIZE.y
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
	left = VBoxContainer.new()
	left.position = Vector2(40, 130)
	left.add_theme_constant_override("separation", 8)
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
	screen = s
	_refresh_credits()
	var sysname: String = Data.SYSTEMS[GS.system_id]["name"]
	header.text = base["name"].to_upper() if s == "hub" else {"equipment": "WEAPONS & EQUIPMENT DEALER", "ships": "SHIP DEALER", "mechs": "MECH DEALER", "repair": "REPAIR & RESUPPLY", "bounty": "MISSION BOARD", "missions": "MISSION BOARD", "board": "MISSION BOARD", "ship": "YOUR SHIP", "faction": "FACTION", "surface": "PLANET DESTINATIONS"}[s]
	subheader.text = "%s  ·  %s SYSTEM  ·  %s" % ["ORBITAL STATION" if kind == "station" else "PLANET SURFACE", sysname.to_upper(), base["name"]]
	for box in [left, content]:   # take the old page out at once, so the new buttons keep their own names
		for c in box.get_children():
			box.remove_child(c)
			c.queue_free()
	preview_vp = null
	var menu := [["hub", "HUB"], ["equipment", "WEAPONS & GEAR"], ["ships", "SHIP DEALER"], ["mechs", "MECH DEALER"], ["repair", "REPAIR / RESUPPLY"], ["board", "MISSION BOARD"], ["ship", "YOUR SHIP"], ["faction", "FACTION"], ["map", "NAVIGATION"]]   # (v1.5k: LAUNCH is its own always-visible button)
	if _surface_planet() != "": menu.insert(4, ["surface", "SURFACE TRAVEL"])
	for m in menu:
		var b := Button.new()
		b.text = m[1]
		b.custom_minimum_size = Vector2(270, 56)
		b.name = "Btn_" + m[0]
		if m[0] == s or (m[0] == "board" and s in ["missions", "bounty"]): b.add_theme_color_override("font_color", GOLD)
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
	var v := _page_box()
	_people_rows(v)
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
	_standing_rows(v)
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
	v.add_child(quick)
	var qcap := _label(15, Color(0.8, 0.88, 0.95))
	qcap.text = "Missiles %d/%d  ·  Heavy %d/%d  ·  Mines %d/%d  ·  Hull %d/%d" % [GS.missiles, GS.max_missiles(), GS.heavy_missiles, GS.max_heavy(), GS.mines, GS.max_mines(), int(GS.hull), int(GS.max_hull())]
	v.add_child(qcap)
	var lcap := _label(16, CYAN)
	lcap.name = "LoadoutCaption"
	lcap.text = "LOADOUT  ·  what each mount carries. Tap a gun or a pod to fit it."
	v.add_child(lcap)
	var items: Array = GS.mount_items()
	var names: Array = GS.mount_names()
	var fit_opts: Array = Data.WEAPON_ORDER.filter(func(x): return x in GS.owned_weapons) + Data.MOUNT_PODS.keys().filter(func(x): return x in GS.owned_weapons) + ["empty"]
	for mi in items.size():
		var mrow := HFlowContainer.new()   # (the buttons wrap: the page never grows wider than the screen)
		mrow.name = "Mount_%d" % mi
		mrow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mrow.add_theme_constant_override("h_separation", 8)
		mrow.add_theme_constant_override("v_separation", 6)
		var mlab := _label(17, GOLD)
		mlab.text = "%s:" % str(names[mi]).to_upper()
		mlab.custom_minimum_size = Vector2(215, 50)
		mrow.add_child(mlab)
		for opt in fit_opts:
			if mi % 2 == 1 and GS.is_heavy(opt): continue   # v1.9h: heavy = shoulders only
			var ob := Button.new()
			ob.name = "Fit_%d_%s" % [mi, opt]
			ob.custom_minimum_size = Vector2(142, 50)
			var onm: String = "Empty" if opt == "empty" else str((Data.WEAPONS[opt] if Data.WEAPONS.has(opt) else Data.MOUNT_PODS[opt]).get("short", opt))
			ob.text = ("[%s]" % onm) if items[mi] == opt else onm
			ob.disabled = items[mi] == opt
			ob.clip_text = true
			ob.pressed.connect(func(): status.text = GS.fit_mount(mi, opt); show_screen("equipment"))
			mrow.add_child(ob)
		v.add_child(mrow)
	var cap := _label(16, CYAN)
	cap.text = "GUNS FOR SALE  ·  your %s has 4 wing mounts (a shoulder and a tip on each wing). Damage shown per shot." % GS.ship()["name"]
	v.add_child(cap)
	for id in Data.WEAPON_ORDER:
		var w: Dictionary = Data.WEAPONS[id]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		var l := _label(18, Color(1, 1, 1) if id != GS.weapon_id else GOLD)
		l.text = "%s   ·   dmg %d   ·   %.1f/s   ·   range %dm" % [w["name"], w["damage"], w["rate"], w["range"]]
		if w.get("heavy", false): l.text += "   ·   HEAVY (shoulders)"
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
	# v1.9e (owner): the missile pod, and what each mount carries (tap a gun or the pod to fit it on that mount)
	for pid in Data.MOUNT_PODS:
		var pd: Dictionary = Data.MOUNT_PODS[pid]
		var prow := HBoxContainer.new()
		prow.add_theme_constant_override("separation", 14)
		var pl := _label(18, Color(1, 1, 1))
		pl.text = "%s   ·   +%d missiles   ·   +%d locks   ·   %s" % [pd["name"], int(pd["ammo"]), int(pd["locks"]), "HEAVY (shoulders)" if pd.get("heavy", false) else "fits a wing mount"]
		pl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		prow.add_child(pl)
		var pb := Button.new()
		pb.name = "Buy_" + pid
		pb.custom_minimum_size = Vector2(230, 54)
		if pid in GS.owned_weapons: pb.text = "OWNED"; pb.disabled = true
		else: pb.text = "BUY  %d cr" % int(pd["price"]); pb.disabled = GS.credits < int(pd["price"])
		pb.pressed.connect(func(): status.text = GS.buy_pod(pid); show_screen("equipment"))
		prow.add_child(pb)
		v.add_child(prow)
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
	v.add_child(row3)
	_wrap_rows(v)   # v1.9e

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
	svc.custom_minimum_size = Vector2(300, 300)
	svc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	h.add_child(svc)
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
	l.text = "Tap a target to track it (a gold waypoint leads you there); tap it again to stop. Tapping another target switches. Every bounty is a capture: destroy the ship, TRACTOR the pilot into your hold and bring them back here to be paid."   # v1.8x (owner)
	v.add_child(l)
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
		var b := Button.new()
		b.name = "Bounty_" + id
		b.custom_minimum_size = Vector2(230, 60)
		var mine: bool = GS.bounty.get("id", "") == id
		if GS.bounty_jail.has(id):   # v1.8k: locked up for now; breaks out later
			var down: bool = not bool(GS.cast_state(str(p.get("character_id", id))).get("alive", true))
			b.text = ("KILLED\nreplaced in %d min" if down else "IN CUSTODY\nout in %d min") % GS.jail_minutes(id)   # (masked soldiers: another takes the post)
			b.disabled = true
		elif id in GS.bounties_done:
			b.text = "PAID"
			b.disabled = true
		elif mine and GS.bounty["state"] == "captured":
			b.text = "IN YOUR HOLD"
			b.disabled = true
		elif mine:
			b.text = "TRACKING\ntap to stop"
			b.add_theme_color_override("font_color", GOLD)
		else:
			b.text = "SELECT"
		b.pressed.connect(func():
			status.text = Missions.toggle_bounty(id)
			_note_giver()
			if GS.bounty.get("id", "") == id:   # v1.7v (owner): the bounty is read out when you select it, like a job
				read_bounty(p)
			show_screen("bounty"))
		row.add_child(b)
		v.add_child(_row_frame(row, mine))

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

## v1.7v: the coordinator reads a selected bounty out (same voice as the jobs).
var last_read := ""   # (tests) the last line read out from the board
func read_bounty(p: Dictionary) -> void:
	var co: Dictionary = Factions.coordinator(Factions.owner_of(base, Data.SYSTEMS[GS.system_id]))
	var line := "Bounty: %s, %s. %s. Reward %d credits, wanted %s. They're in this system: follow the waypoint." % [str(p["name"]), str(p["type"]), str(p["faction"]),
		Data.bounty_reward(str(p["id"])), "alive" if int(p["rank"]) >= Data.BOUNTY_ALIVE_RANK else "dead"]
	last_read = line
	if co.is_empty(): Sfx.speak(line, 1.0, false, "")
	else: Sfx.play_character_voice(str(co.get("voice_id", co["id"])), "", line, float(co.get("voice", 1.0)), str(co.get("sex", "")) == "female")

## v1.5f / v1.5k: the MISSIONS tab: the station's jobs; tap one to take and track it, tap it again to drop it, tap
## another to switch.
func _missions_page() -> void:
	var v := _scroll_box()
	_board_head(v, "missions")
	var l := _label(17, Color(1, 1, 1))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var co: Dictionary = Factions.coordinator(Factions.owner_of(base, Data.SYSTEMS[GS.system_id]))
	l.text = "Work for %s%s. Tap a job to take it (a gold waypoint leads you through it); tap it again to drop it. Tapping another job switches." % [base["name"], (", from %s" % co["name"]) if not co.is_empty() else ""]
	v.add_child(l)
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
		var b := Button.new()
		b.name = "Take_" + row.name
		b.custom_minimum_size = Vector2(230, 60)
		b.text = "TRACKING\ntap to stop" if mine else "SELECT"
		if mine: b.add_theme_color_override("font_color", GOLD)
		b.pressed.connect(func():
			status.text = Missions.toggle(o)
			_note_giver()
			if Missions.is_current(o):   # v1.7p (owner): the job is read out when you select it (v1.9k: with its reward; dispatch's voice if nobody is posted here)
				var said := "%s. %s Reward %d credits." % [str(o["title"]), str(o["brief"]), int(o["pay"])]
				last_read = said
				if co.is_empty(): Sfx.speak(said, 1.0, false, "")
				else: Sfx.play_character_voice(str(co.get("voice_id", co["id"])), "", said, float(co.get("voice", 1.0)), str(co.get("sex", "")) == "female")
			show_screen("missions"))
		row.add_child(b)
		v.add_child(_row_frame(row, mine))

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
		var l := _label(17, i["color"])
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
	if preview_pivot and is_instance_valid(preview_pivot): preview_pivot.rotation.y = t * 0.6
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
