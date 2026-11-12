extends Control
## v12.11 (owner: "make me a tool to scale and set characters in place, with a copy of the code positions to give you
## ... copy all characters' positions in one copy ... and a square block of movement area per character, so they don't
## break the illusion walking over things ... it should be on every room, an editing tool for me, take it off before
## the launch"). A DEV TOOL (Data.DEV_TOOLS): CROWD EDIT on every room page.
##   + ADD: pick one of the Orion crew; they stand in the middle of the view.
##   Drag a person to move them (they grow / shrink with the floor). Their box (the movement area) follows; drag the
##   box to move it, its corners to size it: they walk only inside it, whole body in the box.
##   SIZE - / +, WALKS / STANDS, TURN, DELETE, PREVIEW (let them walk), COPY ALL (every room edited, one block).

const PAD := 26.0   # px: how close a finger must be to a box corner
var hub: Node
var crowd: Crowd3D
var bar: HBoxContainer
var picker: GridContainer
var roster: PanelContainer
var roster_tab := "faction"
var out_box: TextEdit
var sel_src = null             # the selected person's entry in the room's list (people get re-sorted each frame)
var layers: PanelContainer     # v12.12 (owner: "a side window like Photoshop, character order top to bottom")
var layer_rows: VBoxContainer
var drag := ""                 # "body", "zone", "nw", "ne", "sw", "se"
var drag_idx := -1
var btns := {}
var editor_log: Array = []     # (tests)

func setup(h: Node) -> void:
	hub = h
	crowd = h.crowd
	name = "CrowdEdit"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar = HBoxContainer.new()
	bar.position = Vector2(12, 74)
	bar.add_theme_constant_override("separation", 6)
	add_child(bar)
	for k in [["edit", "CROWD EDIT"], ["add", "+ ADD"], ["smaller", "SIZE −"], ["bigger", "SIZE +"], ["walk", "WALKS"], ["turn", "TURN"],
			["del", "DELETE"], ["preview", "PREVIEW"], ["copy", "COPY ALL"]]:
		var b := Button.new()
		b.text = k[1]
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 15)
		b.pressed.connect(_on.bind(k[0]))
		bar.add_child(b)
		btns[k[0]] = b
	# v13.76 (owner: "it should open a roster: who to pick to set in there; the roster is just the face profiles, for that
	# faction or my crew; I should be able to call that person, and they'd be in that 360 area"): + ADD opens the ROSTER
	roster = PanelContainer.new()
	roster.name = "Roster"
	var rsb := StyleBoxFlat.new()
	rsb.bg_color = Color(0.03, 0.06, 0.09, 0.94)
	rsb.border_color = Color(0.22, 0.8, 0.75, 0.8)
	rsb.set_border_width_all(2)
	rsb.set_corner_radius_all(8)
	rsb.set_content_margin_all(10)
	roster.add_theme_stylebox_override("panel", rsb)
	roster.position = Vector2(12, 116)
	roster.visible = false
	add_child(roster)
	var rv := VBoxContainer.new()
	roster.add_child(rv)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	rv.add_child(tabs)
	for t in [["faction", "FACTION"], ["crew", "MY CREW"]]:
		var tb := Button.new()
		tb.name = "RosterTab_" + t[0]
		tb.text = t[1]
		tb.toggle_mode = true
		tb.focus_mode = Control.FOCUS_NONE
		tb.add_theme_font_size_override("font_size", 16)
		tb.pressed.connect(func(): roster_tab = t[0]; _fill_roster())
		tabs.add_child(tb)
	var rsc := ScrollContainer.new()
	rsc.custom_minimum_size = Vector2(640, 300)
	rsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rv.add_child(rsc)
	picker = GridContainer.new()
	picker.columns = 5
	picker.add_theme_constant_override("h_separation", 8)
	picker.add_theme_constant_override("v_separation", 8)
	rsc.add_child(picker)
	out_box = TextEdit.new()
	out_box.visible = false
	out_box.position = Vector2(12, 116)
	out_box.size = Vector2(620, 220)
	out_box.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	add_child(out_box)
	layers = PanelContainer.new()
	layers.name = "Layers"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.07, 0.1, 0.86)
	sb.border_color = Color(0.22, 0.8, 0.75, 0.7)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(8)
	layers.add_theme_stylebox_override("panel", sb)
	layers.anchor_left = 1.0
	layers.anchor_right = 1.0
	layers.offset_left = -300
	layers.offset_right = -12
	layers.offset_top = 74
	add_child(layers)
	var lv := VBoxContainer.new()
	layers.add_child(lv)
	var title := Label.new()
	title.text = "LAYERS  (top = in front)"
	title.add_theme_font_size_override("font_size", 14)
	lv.add_child(title)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(276, 0)
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lv.add_child(sc)
	layer_rows = VBoxContainer.new()
	layer_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(layer_rows)
	_refresh()

func _refresh() -> void:
	var on: bool = crowd.edit_on
	queue_redraw()   # (v13.76: the boxes go when editing stops)
	for k in btns: (btns[k] as Button).visible = on   # v13.78: CROWD EDIT itself is on the bottom bar; up here only while editing
	(btns["edit"] as Button).text = "DONE"
	var lb: Button = hub.look_bar.get_node_or_null("Crowd") if hub.get("look_bar") != null else null
	if lb != null: lb.text = "EDITING..." if on else "CROWD EDIT"
	(btns["preview"] as Button).text = "STOP" if crowd.preview else "PREVIEW"
	var p := _sel()
	(btns["walk"] as Button).text = "STANDS" if not p.is_empty() and not bool(p["src"].get("walk", true)) else "WALKS"
	layers.visible = on
	if on: _layer_rows()
	if not on:
		roster.visible = false
		out_box.visible = false

func _sel() -> Dictionary:
	if sel_src == null: return {}
	for q in crowd.people: if (q as Dictionary).has("src") and is_same(q["src"], sel_src): return q
	return {}

func _list() -> Array:
	if not Crowd3D.edits.has(crowd.full): Crowd3D.edits[crowd.full] = (crowd.placed_list() as Array).duplicate(true)
	return Crowd3D.edits[crowd.full]

func _on(k: String) -> void:
	var p := _sel()
	match k:
		"edit":
			crowd.edit_on = not crowd.edit_on
			crowd.preview = false
			if crowd.edit_on: _list()
			sel_src = null
			crowd.rebuild()
		"add":
			roster.visible = not roster.visible
			if roster.visible: _fill_roster()
			out_box.visible = false
		"smaller", "bigger":
			if not p.is_empty():
				var k2 := 0.95 if k == "smaller" else 1.05
				p["src"]["h"] = snappedf(float(p["src"]["h"]) * k2, 0.0001)
				crowd.sync(p)
		"walk":
			if not p.is_empty():
				p["src"]["walk"] = not bool(p["src"].get("walk", true))
				crowd.sync(p)
		"turn":
			if not p.is_empty():
				p["src"]["face"] = -int(p["src"].get("face", 1))
				crowd.sync(p)
		"del":
			if not p.is_empty():
				_list().erase(p["src"])
				sel_src = null
				crowd.rebuild()
		"preview":
			crowd.preview = not crowd.preview
			crowd.rebuild()
		"copy":
			var txt := copy_text()
			DisplayServer.clipboard_set(txt)
			out_box.text = txt
			out_box.visible = true
			picker.visible = false
			editor_log.append("copied:%d" % txt.length())
			if hub.has_method("toast"): hub.toast("Copied all crowd positions")
	_refresh()

## Every room edited this visit, one line each: HL_CROWD {"room": "<faction>/<file>", "people": [...]}
func copy_text() -> String:
	var lines: Array = []
	for rk in Crowd3D.edits:
		var ppl: Array = []
		for pl in Crowd3D.edits[rk]:
			ppl.append({"who": str(pl.get("who", "")), "who_kind": str(pl.get("who_kind", "")), "name": str(pl.get("name", "")), "model": pl["model"], "x": snappedf(float(pl["x"]), 0.0001), "feet": snappedf(float(pl["feet"]), 0.0001), "h": snappedf(float(pl["h"]), 0.0001),
				"walk": bool(pl.get("walk", true)), "face": int(pl.get("face", 1)), "zone": (pl["zone"] as Array).map(func(v): return snappedf(float(v), 0.0001))})
		lines.append("HL_CROWD " + JSON.stringify({"room": rk, "people": ppl}))
	return "\n".join(lines)

func _col(src) -> Color:
	return Color.from_hsv(fmod(absi(hash(str(src.get("model", "")) + str(src.get("id", "")))) * 0.0001 * 7.0, 1.0), 0.75, 1.0)

## The layers window: the room's people, top row = drawn in front. Tap a name to pick them; ▲ / ▼ move them a layer.
func _layer_rows() -> void:
	for c in layer_rows.get_children(): c.queue_free()
	var lst := _list()
	var sc := layers.get_child(0).get_child(1) as ScrollContainer
	sc.custom_minimum_size.y = clampf(68.0 * lst.size() + 8.0, 40.0, get_viewport_rect().size.y * 0.6)   # (rows are the theme's button height)
	for i in range(lst.size() - 1, -1, -1):
		var src: Dictionary = lst[i]
		var row := HBoxContainer.new()
		var nb := Button.new()
		nb.text = "%d  %s%s" % [i + 1, str(src["model"]), "" if bool(src.get("walk", true)) else "  (stands)"]
		nb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		nb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nb.focus_mode = Control.FOCUS_NONE
		nb.add_theme_font_size_override("font_size", 13)
		nb.add_theme_color_override("font_color", _col(src) if not is_same(src, sel_src) else Color.WHITE)
		if is_same(src, sel_src):
			var st := StyleBoxFlat.new()
			st.bg_color = Color(_col(src), 0.35)
			nb.add_theme_stylebox_override("normal", st)
		nb.pressed.connect(func(): sel_src = src; _refresh())
		row.add_child(nb)
		for d in [["▲", 1], ["▼", -1]]:
			var b := Button.new()
			b.text = d[0]
			b.focus_mode = Control.FOCUS_NONE
			b.custom_minimum_size = Vector2(34, 0)
			b.disabled = (d[1] == 1 and i == lst.size() - 1) or (d[1] == -1 and i == 0)
			b.pressed.connect(move_layer.bind(src, d[1]))
			row.add_child(b)
		layer_rows.add_child(row)

## Move a person up (+1, more in front) or down (-1) a layer.
func move_layer(src: Dictionary, step: int) -> void:
	var lst := _list()
	var i := lst.find(src)
	var j := clampi(i + step, 0, lst.size() - 1)
	if i < 0 or i == j: return
	lst.remove_at(i)
	lst.insert(j, src)
	sel_src = src
	editor_log.append("layer:%s %d->%d" % [src["model"], i, j])
	_refresh()

func _fit() -> Array:
	return Data.CROWD3D_PLACED_FIT.get(crowd.full, [1.0, -0.44])

## v13.76: everyone you can put in this room: the room's faction (leader and pilots, their face profiles) or your crew.
func roster_people(tab: String) -> Array:
	var out: Array = []
	if tab == "faction":
		var f := str(crowd.full.get_slice("/", 0)).capitalize()
		var R: Dictionary = Data.ROSTERS.get(f, {})
		for p in R.get("pilots", []):
			out.append({"who": str(p["id"]), "kind": "pilot", "name": str(p["name"]), "sub": str(p.get("role", "")), "face": str(p.get("portrait_clean", "res://assets/enemy_pilots/%s_clean.jpg" % str(p["id"]))), "faction": f})
	else:
		for fk in Data.CREW:
			for c in Data.CREW[fk]:
				out.append({"who": str(c["id"]), "kind": "crew", "name": str(c["name"]), "sub": str(c.get("role", "")), "face": "res://assets/crew/%s/%s_face.png" % [fk, str(c["file"])], "faction": fk})
	return out

func _fill_roster() -> void:
	for c in picker.get_children(): c.queue_free()
	for t in ["faction", "crew"]:
		var tb := roster.find_child("RosterTab_" + t, true, false) as Button
		if tb != null: tb.button_pressed = t == roster_tab
	if roster_tab == "faction" and not Packs.is_ready("enemies"):   # (the pilots' faces come in their own pack on the web)
		Packs.request("enemies")
		if not Packs.pack_ready.is_connected(_on_roster_pack): Packs.pack_ready.connect(_on_roster_pack)
	for who in roster_people(roster_tab):
		var b := Button.new()
		b.name = "Pick_" + str(who["who"])
		b.custom_minimum_size = Vector2(118, 150)
		b.focus_mode = Control.FOCUS_NONE
		b.clip_text = true
		b.text = str(who["name"])
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.expand_icon = true
		b.add_theme_font_size_override("font_size", 12)
		if ResourceLoader.exists(str(who["face"])): b.icon = load(str(who["face"]))
		b.pressed.connect(_add_who.bind(who))
		picker.add_child(b)

func _on_roster_pack(pk: String) -> void:
	if pk == "enemies" and roster.visible: _fill_roster()

## Put someone from the roster in the room: their face, name and voice; a body from the 3D crowd (the same one each time).
func _add_who(who: Dictionary) -> void:
	var ms: Array = Data.CROWD3D_CREWS["orion"]["models"]
	var body := str(ms[absi(hash(str(who["who"]))) % ms.size()]).substr(12)
	_add(body)
	var pl: Dictionary = _list()[-1]
	pl["who"] = str(who["who"])
	pl["who_kind"] = str(who["kind"])
	pl["name"] = str(who["name"])
	pl["walk"] = false
	crowd.rebuild()
	editor_log.append("who:" + str(who["who"]))

func _add(model: String) -> void:
	roster.visible = false
	var c: Vector2 = crowd.from_screen(get_viewport_rect().size * Vector2(0.5, 0.78))
	var fit := _fit()
	var h := maxf(0.05, float(fit[0]) * c.y + float(fit[1]))
	var w := h * 0.28 * 0.15
	_list().append({"id": randi() % 100000, "model": model, "x": c.x, "feet": c.y, "h": h, "walk": true, "face": 1, "zone": [c.x - w * 4.0, c.y - h * 1.08, c.x + w * 4.0, minf(1.0, c.y + 0.04)]})
	sel_src = _list()[-1]
	crowd.rebuild()
	editor_log.append("add:" + model)
	_refresh()

func _body_rect(p: Dictionary) -> Rect2:
	var k: Vector2 = crowd.screen_per_strip()
	var f: Vector2 = crowd.to_screen(float(p["x"]), float(p["feet"]))
	var bh := float(p["h0"]) * k.y
	return Rect2(f.x - bh * 0.28, f.y - bh, bh * 0.56, bh)

func _zone_rect(p: Dictionary) -> Rect2:
	var z: Array = p["zone"]
	var a: Vector2 = crowd.to_screen(float(z[0]), float(z[1]))
	var k: Vector2 = crowd.screen_per_strip()
	return Rect2(a, Vector2((float(z[2]) - float(z[0])) * k.x, (float(z[3]) - float(z[1])) * k.y))

func _process(_dt: float) -> void:
	visible = Data.DEV_TOOLS and hub.room_view.visible
	if visible and crowd.edit_on: queue_redraw()

func _draw() -> void:
	if not crowd.edit_on: return
	for i in crowd.people.size():
		var p: Dictionary = crowd.people[i]
		if not p.has("src"): continue
		var is_sel: bool = is_same(p["src"], sel_src)
		var c := _col(p["src"])
		var zr := _zone_rect(p)
		draw_rect(zr, Color(c, 0.14 if is_sel else 0.07))
		draw_rect(zr, Color(c, 0.9 if is_sel else 0.4), false, 2.0)
		if is_sel:
			for q in [zr.position, Vector2(zr.end.x, zr.position.y), Vector2(zr.position.x, zr.end.y), zr.end]:
				draw_circle(q, 11.0, Color.WHITE)
				draw_circle(q, 7.0, c)
			draw_rect(_body_rect(p), Color(1, 1, 1, 0.9), false, 2.0)

func _input(e: InputEvent) -> void:
	if not visible or not crowd.edit_on or crowd.preview: return
	var pos := Vector2.INF
	var down := false
	var up := false
	var rel := Vector2.ZERO
	if e is InputEventScreenTouch:
		if (e as InputEventScreenTouch).index != 0: return
		pos = (e as InputEventScreenTouch).position
		down = (e as InputEventScreenTouch).pressed
		up = not down
	elif e is InputEventScreenDrag:
		if (e as InputEventScreenDrag).index != 0: return
		pos = (e as InputEventScreenDrag).position
		rel = (e as InputEventScreenDrag).relative
	elif e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and not DisplayServer.is_touchscreen_available():
		pos = (e as InputEventMouseButton).position
		down = (e as InputEventMouseButton).pressed
		up = not down
	elif e is InputEventMouseMotion and ((e as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT) and not DisplayServer.is_touchscreen_available():
		pos = (e as InputEventMouseMotion).position
		rel = (e as InputEventMouseMotion).relative
	else: return
	if down:
		if bar.get_global_rect().has_point(pos) or (picker.visible and picker.get_global_rect().has_point(pos)) or (out_box.visible and out_box.get_global_rect().has_point(pos)) or (layers.visible and layers.get_global_rect().has_point(pos)): return
		drag = _pick(pos)
		if drag != "": get_viewport().set_input_as_handled()
		_refresh()
		return
	if up:
		if drag != "": get_viewport().set_input_as_handled()
		drag = ""
		return
	if drag == "" or rel == Vector2.ZERO: return
	get_viewport().set_input_as_handled()
	move_by(rel)

## Drag the selected person / box by `rel` pixels (tests call this too).
func move_by(rel: Vector2) -> void:
	var p := _sel()
	if p.is_empty(): return
	var k: Vector2 = crowd.screen_per_strip()
	var d := Vector2(rel.x / k.x, rel.y / k.y)
	var pl: Dictionary = p["src"]
	var z: Array = pl["zone"]
	if drag == "body":
		var fit := _fit()
		var hz := -float(fit[1]) / float(fit[0])
		var f0 := float(pl["feet"])
		var f1 := clampf(f0 + d.y, hz + 0.03, 1.0)
		pl["h"] = float(pl["h"]) * (f1 - hz) / maxf(0.01, f0 - hz)   # (they grow nearer, shrink further back)
		pl["x"] = float(pl["x"]) + d.x
		pl["feet"] = f1
		var w := float(pl["h"]) * 0.28 * float(crowd._xf()["sh"])
		if float(pl["x"]) - w < float(z[0]): z[0] = float(pl["x"]) - w
		if float(pl["x"]) + w > float(z[2]): z[2] = float(pl["x"]) + w
		if f1 - float(pl["h"]) < float(z[1]): z[1] = f1 - float(pl["h"])
		if f1 > float(z[3]): z[3] = f1
	elif drag == "zone":
		for i in 4: z[i] = float(z[i]) + (d.x if i % 2 == 0 else d.y)
		pl["x"] = float(pl["x"]) + d.x
		pl["feet"] = float(pl["feet"]) + d.y
	else:
		if drag.contains("w"): z[0] = minf(float(z[0]) + d.x, float(z[2]) - 0.004)
		if drag.contains("e"): z[2] = maxf(float(z[2]) + d.x, float(z[0]) + 0.004)
		if drag.contains("n"): z[1] = minf(float(z[1]) + d.y, float(z[3]) - 0.02)
		if drag.contains("s"): z[3] = maxf(float(z[3]) + d.y, float(z[1]) + 0.02)
	crowd.sync(p)

func _pick(pos: Vector2) -> String:
	var p := _sel()
	if not p.is_empty():
		var zr := _zone_rect(p)
		for c in [["nw", zr.position], ["ne", Vector2(zr.end.x, zr.position.y)], ["sw", Vector2(zr.position.x, zr.end.y)], ["se", zr.end]]:
			if pos.distance_to(c[1]) < PAD: return c[0]
	var best := -1
	var best_feet := -1.0
	for i in crowd.people.size():   # the nearest person (in front) under the finger
		var q: Dictionary = crowd.people[i]
		if not q.has("src"): continue
		var lay := float(_list().find(q["src"]))   # (the top layer wins, as drawn)
		if _body_rect(q).grow(6.0).has_point(pos) and lay > best_feet:
			best = i
			best_feet = lay
	if best >= 0:
		sel_src = crowd.people[best]["src"]
		return "body"
	if not p.is_empty() and _zone_rect(p).has_point(pos): return "zone"
	return ""

## v13.76: the screen box of a placed person (tests / taps)
func body_rect(p: Dictionary) -> Rect2: return _body_rect(p)
