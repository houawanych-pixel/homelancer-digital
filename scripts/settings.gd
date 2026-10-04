extends Control
## Job J (v1.4f): Settings screen. Control mode (Auto / Touch / Keyboard + mouse) for everyone; the Controls list
## (rebinding) only in keyboard + mouse mode, so phone/touch players never see it.
## Opened from the title screen (SETTINGS) or with the Settings key (default F1) in flight.

signal closed

var controls: Controls
var panel: PanelContainer
var mode_btns := {}
var mode_label: Label
var controls_box: VBoxContainer
var list: VBoxContainer
var note: Label
var reset_btn: Button
var effects_btn: Button   # Job K: reduced motion / effects (shown in every mode, phones too)
var close_btn: Button
var row_btns := {}        # action id -> key Button
var _reset_armed := 0.0   # seconds left to confirm a reset

func _ready() -> void:
	name = "Settings"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.02, 0.06, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.07, 0.14, 0.96)
	sb.border_color = Color(0.3, 0.72, 1.0, 0.85)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var title := Label.new()
	title.text = "SETTINGS"
	title.add_theme_font_size_override("font_size", 28)
	v.add_child(title)
	var mrow := HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 8)
	v.add_child(mrow)
	var ml := Label.new()
	ml.text = "Controls:"
	ml.add_theme_font_size_override("font_size", 18)
	mrow.add_child(ml)
	for m in [["auto", "AUTO"], ["touch", "TOUCH"], ["kbm", "KEYBOARD + MOUSE"]]:
		var b := _button(m[1])
		b.toggle_mode = true
		b.pressed.connect(func(): _set_mode(m[0]))
		mrow.add_child(b)
		mode_btns[m[0]] = b
	mode_label = Label.new()
	mode_label.add_theme_font_size_override("font_size", 15)
	v.add_child(mode_label)
	effects_btn = _button("")
	effects_btn.pressed.connect(press_effects)
	v.add_child(effects_btn)
	controls_box = VBoxContainer.new()
	controls_box.add_theme_constant_override("separation", 8)
	controls_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(controls_box)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	controls_box.add_child(scroll)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	note = Label.new()
	note.add_theme_font_size_override("font_size", 15)
	note.add_theme_color_override("font_color", Color(1.0, 0.84, 0.3))
	controls_box.add_child(note)
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 10)
	v.add_child(brow)
	reset_btn = _button("RESET TO DEFAULTS")
	reset_btn.pressed.connect(press_reset)
	brow.add_child(reset_btn)
	close_btn = _button("CLOSE")
	close_btn.pressed.connect(close)
	brow.add_child(close_btn)

func _button(txt: String) -> Button:
	var b := Button.new()
	b.text = txt
	b.focus_mode = Control.FOCUS_NONE   # Space/Enter never "click" a settings button by accident
	b.custom_minimum_size = Vector2(0, Data.SETTINGS_ROW_H)
	b.add_theme_font_size_override("font_size", 17)
	return b

func open() -> void:
	visible = true
	controls.blocked = true
	_reset_armed = 0.0
	refresh()

func close() -> void:
	if controls.capturing != "": controls.cancel_capture()
	visible = false
	controls.blocked = false
	closed.emit()

func is_open() -> bool:
	return visible

func _set_mode(m: String) -> void:
	controls.set_mode(m)
	refresh()

## The Controls list is shown only in keyboard + mouse mode.
func controls_list_shown() -> bool:
	return visible and controls_box.visible

func refresh() -> void:
	var S := get_viewport_rect().size
	var w := clampf(S.x - 40.0, 360.0, 760.0)
	var h := clampf(S.y - 30.0, 300.0, 680.0)
	panel.position = Vector2(S.x * 0.5 - w * 0.5, S.y * 0.5 - h * 0.5)
	panel.size = Vector2(w, h)
	panel.custom_minimum_size = Vector2(w, h)
	for m in mode_btns: mode_btns[m].button_pressed = controls.mode_pref == m
	var act := controls.active_mode()
	mode_label.text = "Active: %s%s" % ["Keyboard + mouse" if act == "kbm" else "Touch", " (auto-detected)" if controls.mode_pref == "auto" else ""]
	effects_btn.text = "REDUCED MOTION (jump effects): %s" % ("ON — simple fade" if controls.reduced_effects else "OFF — full warp tunnel")
	var kbm := controls.is_kbm()
	controls_box.visible = kbm
	reset_btn.visible = kbm
	note.text = controls.last_note
	reset_btn.text = "CONFIRM RESET?" if _reset_armed > 0.0 else "RESET TO DEFAULTS"
	for c in list.get_children():
		list.remove_child(c)
		c.queue_free()
	row_btns.clear()
	if not kbm: return
	for a in Data.KBM_ACTIONS:
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, Data.SETTINGS_ROW_H)
		var l := Label.new()
		l.text = a["name"] + ("  (Homelancer)" if a["extra"] else "")
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.add_theme_font_size_override("font_size", 16)
		row.add_child(l)
		var id: String = a["id"]
		var b := _button("Press a key…  (Esc cancels)" if controls.capturing == id else controls.binding(id))
		b.custom_minimum_size = Vector2(230, Data.SETTINGS_ROW_H)
		b.disabled = not a["rebind"]
		if not a["rebind"]: b.tooltip_text = "Fixed"
		b.pressed.connect(func(): press_row(id))
		row.add_child(b)
		list.add_child(row)
		row_btns[id] = b

func press_row(id: String) -> void:
	if controls.capturing != "": controls.cancel_capture()
	controls.begin_capture(id)
	refresh()

func press_effects() -> void:
	controls.set_reduced_effects(not controls.reduced_effects)
	refresh()

func press_reset() -> void:
	if _reset_armed > 0.0:
		controls.reset_defaults()
		controls.last_note = "Controls reset to the Freelancer defaults."
		_reset_armed = 0.0
	else:
		_reset_armed = Data.SETTINGS_RESET_CONFIRM_S
	refresh()

func _process(dt: float) -> void:
	if not visible: return
	if _reset_armed > 0.0:
		_reset_armed -= dt
		if _reset_armed <= 0.0: refresh()

func _unhandled_input(e: InputEvent) -> void:
	if visible and controls.capturing == "" and e is InputEventKey and e.pressed and e.physical_keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
