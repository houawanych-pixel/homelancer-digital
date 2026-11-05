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
var out_box: TextEdit
var sel := -1                  # index into crowd.people
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
	picker = GridContainer.new()
	picker.columns = 4
	picker.position = Vector2(12, 116)
	picker.visible = false
	add_child(picker)
	for m in Data.CROWD3D_CREWS["orion"]["models"]:
		var b := Button.new()
		var short := str(m).substr(12)
		b.text = short
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(_add.bind(short))
		picker.add_child(b)
	out_box = TextEdit.new()
	out_box.visible = false
	out_box.position = Vector2(12, 116)
	out_box.size = Vector2(620, 220)
	out_box.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	add_child(out_box)
	_refresh()

func _refresh() -> void:
	var on: bool = crowd.edit_on
	for k in btns: (btns[k] as Button).visible = on or k == "edit"
	(btns["edit"] as Button).text = "CROWD EDIT: ON" if on else "CROWD EDIT"
	(btns["preview"] as Button).text = "STOP" if crowd.preview else "PREVIEW"
	var p := _sel()
	(btns["walk"] as Button).text = "STANDS" if not p.is_empty() and not bool(p["src"].get("walk", true)) else "WALKS"
	if not on:
		picker.visible = false
		out_box.visible = false

func _sel() -> Dictionary:
	if sel >= 0 and sel < crowd.people.size() and (crowd.people[sel] as Dictionary).has("src"): return crowd.people[sel]
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
			sel = -1
			crowd.rebuild()
		"add":
			picker.visible = not picker.visible
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
				sel = -1
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
			ppl.append({"model": pl["model"], "x": snappedf(float(pl["x"]), 0.0001), "feet": snappedf(float(pl["feet"]), 0.0001), "h": snappedf(float(pl["h"]), 0.0001),
				"walk": bool(pl.get("walk", true)), "face": int(pl.get("face", 1)), "zone": (pl["zone"] as Array).map(func(v): return snappedf(float(v), 0.0001))})
		lines.append("HL_CROWD " + JSON.stringify({"room": rk, "people": ppl}))
	return "\n".join(lines)

func _fit() -> Array:
	return Data.CROWD3D_PLACED_FIT.get(crowd.full, [1.0, -0.44])

func _add(model: String) -> void:
	picker.visible = false
	var c: Vector2 = crowd.from_screen(get_viewport_rect().size * Vector2(0.5, 0.78))
	var fit := _fit()
	var h := maxf(0.05, float(fit[0]) * c.y + float(fit[1]))
	var w := h * 0.28 * 0.15
	_list().append({"model": model, "x": c.x, "feet": c.y, "h": h, "walk": true, "face": 1, "zone": [c.x - w * 4.0, c.y - h * 1.08, c.x + w * 4.0, minf(1.0, c.y + 0.04)]})
	crowd.rebuild()
	sel = crowd.people.size() - 1
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
		var c := Color.from_hsv(fmod(i * 0.17, 1.0), 0.75, 1.0)
		var zr := _zone_rect(p)
		draw_rect(zr, Color(c, 0.14 if i == sel else 0.07))
		draw_rect(zr, Color(c, 0.9 if i == sel else 0.4), false, 2.0)
		if i == sel:
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
		if bar.get_global_rect().has_point(pos) or (picker.visible and picker.get_global_rect().has_point(pos)) or (out_box.visible and out_box.get_global_rect().has_point(pos)): return
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
		if _body_rect(q).grow(6.0).has_point(pos) and float(q["feet"]) > best_feet:
			best = i
			best_feet = float(q["feet"])
	if best >= 0:
		sel = best
		return "body"
	if not p.is_empty() and _zone_rect(p).has_point(pos): return "zone"
	return ""
