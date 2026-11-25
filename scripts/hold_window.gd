class_name HoldWindow
extends Control
## v13.295 (owner: "I need a place to check what's in my inventory, discard what I don't want to keep (and the tractor
## beam must not pull it back), and equip something I've just received"): the CARGO HOLD window, opened in flight from
## the HOLD button in the SHIP window. The game waits while it's open. Every thing in the hold is a row
## with its picture, what it is and what a base pays, and its buttons:
##   EQUIP (a weapon: straight onto your guns), DROP 1 (a stack), DROP / DROP ALL (out of the hold, behind the ship).
## A prisoner and a job's delivery crates can't be dropped.

signal closed

const CYAN := Color(0.45, 0.9, 1.0)
const GOLD := Color(1.0, 0.82, 0.3)
const RED := Color(1.0, 0.4, 0.35)
const GREEN := Color(0.4, 1.0, 0.55)

var space: Node = null
var _list: VBoxContainer
var _title: Label
var _bar: ProgressBar
var _say: Label
var _icons: PartIcons

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_icons = PartIcons.new()
	_icons.name = "PartIcons"
	add_child(_icons)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	panel.name = "HoldPanel"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.06, 0.12, 0.95)
	sb.border_color = Color(CYAN, 0.8)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", sb)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.anchor_left = 0.12
	panel.anchor_right = 0.88
	panel.anchor_top = 0.06
	panel.anchor_bottom = 0.94
	panel.offset_left = 0
	panel.offset_right = 0
	panel.offset_top = 0
	panel.offset_bottom = 0
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 26)
	_title.add_theme_color_override("font_color", CYAN)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_title)
	var cb := _btn("CLOSE", Color.WHITE, 120)
	cb.name = "Close"
	cb.pressed.connect(close)
	top.add_child(cb)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 10)
	v.add_child(_bar)
	_say = Label.new()
	_say.add_theme_font_size_override("font_size", 16)
	_say.add_theme_color_override("font_color", GOLD)
	_say.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_say)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	_list = VBoxContainer.new()
	_list.name = "Rows"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	sc.add_child(_list)
	refresh()

func close() -> void:
	closed.emit()
	queue_free()

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and (e.keycode == KEY_ESCAPE or e.keycode == KEY_I):
		get_viewport().set_input_as_handled()
		close()

func refresh() -> void:
	var full := GS.hold_free() <= 0
	_title.text = "CARGO HOLD   %s%s" % [GS.hold_text(), "   FULL" if full else ""]
	_title.add_theme_color_override("font_color", RED if full else CYAN)
	_bar.visible = not GS.hold_no_limit
	_bar.max_value = maxi(1, GS.hold_size())
	_bar.value = GS.hold_used()
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	if GS.cargo.is_empty():
		var l := Label.new()
		l.text = "Empty. Tractor in crates, weapons and ore to fill it."
		l.add_theme_font_size_override("font_size", 18)
		_list.add_child(l)
		return
	for i in GS.cargo.size(): _list.add_child(_row(i, GS.cargo[i]))

func _row(i: int, c: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.name = "Item_%d" % i
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.12, 0.2, 0.9)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(8)
	card.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	card.add_child(h)
	h.add_child(_pic(c))
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(info)
	var nm := Label.new()
	nm.text = _name(c)
	nm.add_theme_font_size_override("font_size", 20)
	nm.clip_text = true
	info.add_child(nm)
	var sub := Label.new()
	sub.text = _sub(c)
	sub.add_theme_font_size_override("font_size", 14)
	sub.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	sub.clip_text = true
	info.add_child(sub)
	var kind := str(c.get("kind", ""))
	if kind == "weapon":
		var eq := _btn("EQUIP", GREEN)
		eq.name = "Equip_%d" % i
		eq.pressed.connect(func(): _equip(i))
		h.add_child(eq)
	if not GS.can_drop(c):
		var keep := Label.new()
		keep.text = "KEPT\n(job cargo)" if kind == "delivery" else "PRISONER\n(hand in)"
		keep.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		keep.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
		h.add_child(keep)
		return card
	if c.has("n") and int(c["n"]) > 1:
		var d1 := _btn("DROP 1", GOLD)
		d1.name = "Drop1_%d" % i
		d1.pressed.connect(func(): _drop(i, 1))
		h.add_child(d1)
	var da := _btn("DROP ALL" if c.has("n") and int(c["n"]) > 1 else "DROP", RED)
	da.name = "Drop_%d" % i
	da.pressed.connect(func(): _drop(i, -1))
	h.add_child(da)
	return card

func _pic(c: Dictionary) -> Control:
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(72, 72)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.45)
	sb.set_corner_radius_all(6)
	box.add_theme_stylebox_override("panel", sb)
	var kind := str(c.get("kind", ""))
	if kind == "weapon" and Data.WEAPONS.has(str(c.get("id", ""))):
		var pic := TextureRect.new()
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.custom_minimum_size = Vector2(72, 72)
		box.add_child(pic)
		_icons.get_icon("wpn_" + str(c["id"]), PartIcons.weapon.bind(str(c["id"])), pic)
		return box
	var col: Color = {"ore": Data.VALUABLE_COLOR.get(str(c.get("id", "")), GOLD), "goods": RED if GS.is_contraband(str(c.get("id", ""))) else Color(0.7, 0.8, 0.9), "part": CYAN, "pilot": Color(1.0, 0.6, 0.5), "delivery": Color(0.9, 0.75, 0.45)}.get(kind, Color.WHITE)
	var l := Label.new()
	l.text = {"ore": "ORE", "goods": "GOODS", "part": "PART", "pilot": "PILOT", "delivery": "CRATES"}.get(kind, "?")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", col)
	box.add_child(l)
	return box

func _name(c: Dictionary) -> String:
	var kind := str(c.get("kind", ""))
	var n := ("  x%d" % int(c["n"])) if c.has("n") else ""
	if kind == "ore": return str(Data.ORE_NAME.get(str(c.get("id", "")), "Ore")) + n
	return str(c.get("name", kind.capitalize())) + n

func _sub(c: Dictionary) -> String:
	var kind := str(c.get("kind", ""))
	var slots := GS.hold_slots(c)
	var room := "%d unit%s" % [slots, "" if slots == 1 else "s"]
	match kind:
		"weapon":
			var w: Dictionary = Data.WEAPONS.get(str(c.get("id", "")), {})
			var have := " · you have one" if str(c.get("id", "")) in GS.owned_weapons else ""
			return "Weapon · damage %d · sells ~%d cr%s · %s" % [int(w.get("damage", 0)), GS.cargo_sell_price(c), have, room]
		"part": return "Spare part · sells ~%d cr · %s" % [GS.cargo_sell_price(c), room]
		"ore": return "Valuable · sell at any base · %s" % room
		"goods": return "%s · %s" % [str(c.get("note", "Trade goods")).capitalize(), room]
	return str(c.get("note", kind))

func _btn(t: String, col: Color, w := 108) -> Button:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size = Vector2(w, 56)
	b.add_theme_font_size_override("font_size", 16)
	b.add_theme_color_override("font_color", col)
	return b

func _equip(i: int) -> void:
	_say.text = GS.equip_from_hold(i)
	if space != null and space.has_method("mount_visuals"): space.mount_visuals()
	Sfx.play("pickup", -6.0)
	refresh()

func _drop(i: int, n: int) -> void:
	var out := GS.drop_cargo(i, n)
	if out.is_empty():
		_say.text = "That stays in the hold."
		return
	if space != null and space.has_method("jettison"): space.jettison(out)
	_say.text = "%s thrown out. The tractor beam leaves it alone." % _name(out)
	refresh()
