extends Control
## Job K (v1.4g): the jump-gate docking screen. Names the destination system, a big ACTIVATE JUMP button and UNDOCK.
## Opened by the gate prompt on the HUD (tap) or the Dock key (F3) from Job J. The world waits behind it.

signal activate_pressed
signal undock_pressed

var panel: PanelContainer
var gate_label: Label
var dest_label: Label
var activate_btn: Button
var undock_btn: Button
var destination := ""    # destination system name shown (tests read it)
var gate_name := ""

func _ready() -> void:
	name = "GateDock"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.02, 0.06, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.07, 0.14, 0.94)
	sb.border_color = Color(1.0, 0.84, 0.3, 0.9)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(v)
	gate_label = Label.new()
	gate_label.add_theme_font_size_override("font_size", 20)
	gate_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gate_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.3))
	v.add_child(gate_label)
	dest_label = Label.new()
	dest_label.add_theme_font_size_override("font_size", 30)
	dest_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(dest_label)
	activate_btn = _button("ACTIVATE JUMP", Vector2(340, 96), 32)
	activate_btn.pressed.connect(press_activate)
	v.add_child(activate_btn)
	undock_btn = _button("UNDOCK", Vector2(340, 60), 20)
	undock_btn.pressed.connect(press_undock)
	v.add_child(undock_btn)

func _button(txt: String, sz: Vector2, fs: int) -> Button:
	var b := Button.new()
	b.text = txt
	b.custom_minimum_size = sz          # thumb-sized
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", fs)
	return b

func open(gname: String, dest: String, kind: String) -> void:
	gate_name = gname
	destination = dest
	gate_label.text = "DOCKED · %s (%s)" % [gname.to_upper(), kind.to_upper()]
	dest_label.text = "DESTINATION: %s SYSTEM" % dest.to_upper()
	activate_btn.disabled = false
	undock_btn.disabled = false
	visible = true
	var S := get_viewport_rect().size
	var w := clampf(S.x - 40.0, 380.0, 560.0)
	panel.size = Vector2(w, 0)
	panel.reset_size()
	panel.position = Vector2(S.x * 0.5 - w * 0.5, S.y * 0.5 - 150)
	panel.custom_minimum_size = Vector2(w, 0)

func close() -> void:
	visible = false

## One press only: the button locks at once, so a double tap can't start two jumps.
func press_activate() -> void:
	if not visible or activate_btn.disabled: return
	activate_btn.disabled = true
	undock_btn.disabled = true
	activate_pressed.emit()

func press_undock() -> void:
	if not visible or undock_btn.disabled: return
	undock_pressed.emit()

func _unhandled_input(e: InputEvent) -> void:
	if visible and e is InputEventKey and e.pressed and not e.echo and e.physical_keycode == KEY_ESCAPE:
		press_undock()
		get_viewport().set_input_as_handled()
