class_name Controls
extends Node
## Job J (v1.4f): desktop keyboard + mouse controls, Freelancer style, with rebinding.
## Phone/touch is untouched: on a touch device (or with the Touch override) none of the mouse scheme runs and the
## Controls list is not shown. All numbers and default keys are in the Job J block of data.gd.
##
## Mouse (keyboard + mouse mode only):
##   - Mouse flight (Space toggles, on by default): the ship steers toward the cursor.
##   - Right-click (the "fire" binding): fire weapons.
##   - Left-click: select whatever is under the cursor as the target. Left-click held and dragged: steer.
##   - Wheel: throttle up / down.
## Keyboard bindings drive InputMap actions with the same ids as Data.KBM_ACTIONS.
## Settings are stored in a NEW file (Data.SETTINGS_PATH), section "controls": "mode" and "bindings". Nothing else
## in the game is saved or renamed by this.

signal action(id: String)        # a discrete action key was pressed (main.gd routes it)
signal capture_done(id: String, ok: bool, note: String)

const SECTION := "controls"
const EFFECTS_SECTION := "effects"   # Job K
const MOUSE_NAMES := {"Mouse Left": MOUSE_BUTTON_LEFT, "Mouse Right": MOUSE_BUTTON_RIGHT, "Mouse Middle": MOUSE_BUTTON_MIDDLE,
	"Mouse Back": MOUSE_BUTTON_XBUTTON1, "Mouse Forward": MOUSE_BUTTON_XBUTTON2}
## Actions that are held (read every frame) rather than pressed once.
const HELD := ["fire", "forward", "back", "strafe_left", "strafe_right", "afterburner", "yaw_left", "yaw_right", "pitch_up", "pitch_down", "select", "special"]

var settings_path: String = Data.SETTINGS_PATH
var mode_pref: String = Data.CONTROL_MODE_DEFAULT   # saved: auto | touch | kbm
var bindings := {}                                  # saved: action id -> binding string
var touch_available := DisplayServer.is_touchscreen_available()
var mouse_flight: bool = Data.MOUSE_FLIGHT_DEFAULT
var reduced_effects: bool = Data.REDUCED_EFFECTS_DEFAULT   # Job K: saved in its own section "effects", key "reduced"
var wheel_throttle := 0.0
var mouse_pos := Vector2.ZERO
var mouse_seen := false          # a real mouse moved over the game (headless runs never see one)
var capturing := ""              # action id waiting for "Press a key…"
var last_note := ""              # last rebinding warning (duplicate / reserved / cancelled)
var blocked := false             # settings panel open etc.: gameplay keys and mouse flight pause
var hud: Control                 # for HUD button rects (clicks on HUD buttons are not target picks)
var space_ref: Callable = func(): return null   # -> SpaceSystem or null
var _left_down := false
var _left_origin := Vector2.ZERO
var _dragging := false
var drag_vec := Vector2.ZERO     # -1..1 steer from a left-drag

func _ready() -> void:
	load_settings()

# ---------------------------------------------------------------- config / bindings
static func action_ids() -> Array:
	return Data.KBM_ACTIONS.map(func(a): return a["id"])

static func action_def(id: String) -> Dictionary:
	for a in Data.KBM_ACTIONS:
		if a["id"] == id: return a
	return {}

static func defaults() -> Dictionary:
	var d := {}
	for a in Data.KBM_ACTIONS: d[a["id"]] = a["key"]
	return d

## "Shift+W" / "F3" / "Mouse Right" -> an InputEvent (null if it can't be read).
static func parse_binding(s: String) -> InputEvent:
	if MOUSE_NAMES.has(s):
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_NAMES[s]
		return mb
	var parts := s.split("+")
	var k := InputEventKey.new()
	for i in parts.size() - 1:
		match parts[i].strip_edges().to_lower():
			"shift": k.shift_pressed = true
			"ctrl", "control": k.ctrl_pressed = true
			"alt": k.alt_pressed = true
			"meta", "cmd", "command": k.meta_pressed = true
			_: return null
	var code := OS.find_keycode_from_string(parts[parts.size() - 1].strip_edges())
	if code == KEY_NONE: return null
	k.physical_keycode = code
	return k

## InputEvent -> binding string ("" if it is not a key or mouse button).
static func binding_of(e: InputEvent) -> String:
	if e is InputEventMouseButton:
		for n in MOUSE_NAMES:
			if MOUSE_NAMES[n] == e.button_index: return n
		return ""
	if e is InputEventKey:
		var code: int = e.physical_keycode if e.physical_keycode != KEY_NONE else e.keycode
		if code == KEY_NONE or code in [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]: return ""
		var mods := ""
		if e.ctrl_pressed: mods += "Ctrl+"
		if e.alt_pressed: mods += "Alt+"
		if e.meta_pressed: mods += "Meta+"
		if e.shift_pressed: mods += "Shift+"
		return mods + OS.get_keycode_string(code)
	return ""

func binding(id: String) -> String:
	return str(bindings.get(id, action_def(id).get("key", "")))

## Which action (other than `except`) already uses this binding.
func bound_to(b: String, except := "") -> String:
	for id in action_ids():
		if id != except and binding(id) == b: return id
	return ""

## Rebind one action. Duplicate rule (simplest, owner open question 1): BLOCK — a key already on another action is
## refused with a warning; nothing else changes. Returns "" on success or the warning text.
func rebind(id: String, b: String) -> String:
	var d := action_def(id)
	if d.is_empty(): return "Unknown action."
	if not d["rebind"]: return "%s can't be rebound." % d["name"]
	if b == "" or parse_binding(b) == null: return "That key can't be used."
	if b == Data.KBM_CANCEL_KEY or b in Data.KBM_RESERVED: return "%s is reserved and can't be bound." % b
	var other := bound_to(b, id)
	if other != "": return "%s is already used by \"%s\". Pick another key." % [b, action_def(other)["name"]]
	bindings[id] = b
	apply()
	save_settings()
	return ""

func reset_defaults() -> void:
	bindings = defaults()
	apply()
	save_settings()

## Rebuild the InputMap actions from the bindings (old Job-D actions keep their names: forward, back, strafe_*,
## yaw_*, pitch_*, fire, transform).
func apply() -> void:
	for id in action_ids():
		if not InputMap.has_action(id): InputMap.add_action(id)
		InputMap.action_erase_events(id)
		var ev := parse_binding(binding(id))
		if ev != null: InputMap.action_add_event(id, ev)

# ---------------------------------------------------------------- control mode
## Auto-detect: touch on a phone / touch device, keyboard + mouse otherwise.
static func detect(has_touch: bool) -> String:
	return "touch" if has_touch or OS.has_feature("web_android") or OS.has_feature("web_ios") or OS.has_feature("mobile") else "kbm"

func active_mode() -> String:
	return detect(touch_available) if mode_pref == "auto" else mode_pref

func is_kbm() -> bool:
	return active_mode() == "kbm"

func set_mode(m: String) -> void:
	if not m in ["auto", "touch", "kbm"]: return
	mode_pref = m
	save_settings()

# ---------------------------------------------------------------- settings file (new; never touches other data)
func load_settings() -> void:
	mode_pref = Data.CONTROL_MODE_DEFAULT
	bindings = defaults()
	reduced_effects = Data.REDUCED_EFFECTS_DEFAULT
	var cf := ConfigFile.new()
	if cf.load(settings_path) == OK:
		var m = cf.get_value(SECTION, "mode", Data.CONTROL_MODE_DEFAULT)
		if m is String and m in ["auto", "touch", "kbm"]: mode_pref = m
		var re = cf.get_value(EFFECTS_SECTION, "reduced", Data.REDUCED_EFFECTS_DEFAULT)
		reduced_effects = re if re is bool else Data.REDUCED_EFFECTS_DEFAULT
		var saved = cf.get_value(SECTION, "bindings", {})
		if saved is Dictionary:
			for id in saved:
				var d := action_def(str(id))
				if not d.is_empty() and d["rebind"] and saved[id] is String and parse_binding(saved[id]) != null: bindings[str(id)] = saved[id]
	apply()

## Writes only the "controls" section; anything else already in the file is kept as it is.
func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.load(settings_path)
	cf.set_value(SECTION, "mode", mode_pref)
	cf.set_value(SECTION, "bindings", bindings.duplicate())
	cf.save(settings_path)

## Job K: reduced motion / effects (jump tunnel becomes a plain fade). Writes only the "effects" section.
func set_reduced_effects(on: bool) -> void:
	reduced_effects = on
	var cf := ConfigFile.new()
	cf.load(settings_path)
	cf.set_value(EFFECTS_SECTION, "reduced", on)
	cf.save(settings_path)

# ---------------------------------------------------------------- per-frame queries (used by hud.gd)
## Held action, honouring the mode: mouse-button bindings only count in keyboard + mouse mode.
func held(id: String) -> bool:
	if blocked: return false
	if parse_binding(binding(id)) is InputEventMouseButton and not is_kbm(): return false
	return Input.is_action_pressed(id)

## Cursor -> steer (-1..1), with a dead zone round the centre (mouse flight).
static func mouse_aim_from(pos: Vector2, size: Vector2) -> Vector2:
	var half := maxf(size.y * 0.5, 1.0)
	var off := (pos - size * 0.5) / (half * Data.MOUSE_FLIGHT_RANGE)
	var r := off.length()
	var dz := Data.MOUSE_DEAD_ZONE / Data.MOUSE_FLIGHT_RANGE
	if r <= dz: return Vector2.ZERO
	return off.normalized() * clampf((r - dz) / (1.0 - dz), 0.0, 1.0)

## Steer from the mouse this frame: a left-drag always works; otherwise mouse flight when it is on.
func mouse_steer(size: Vector2) -> Vector2:
	if not is_kbm() or blocked or (hud != null and not hud.visible): return Vector2.ZERO
	if _dragging: return drag_vec
	if not mouse_flight or not mouse_seen or _over_hud(mouse_pos): return Vector2.ZERO
	return mouse_aim_from(mouse_pos, size)

func _over_hud(p: Vector2) -> bool:
	return hud != null and hud.has_method("button_at") and hud.button_at(p) != ""

func toggle_mouse_flight() -> bool:
	mouse_flight = not mouse_flight
	return mouse_flight

# ---------------------------------------------------------------- input
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_MOUSE_EXIT or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		mouse_seen = false
		_end_drag()

func _input(e: InputEvent) -> void:
	if capturing != "":
		_capture_input(e)
		return
	if e is InputEventMouseMotion:
		mouse_pos = e.position
		mouse_seen = true
		if _left_down and is_kbm():
			var d: Vector2 = e.position - _left_origin
			if d.length() > Data.MOUSE_DRAG_PX: _dragging = true
			if _dragging: drag_vec = (d / Data.MOUSE_DRAG_RANGE).limit_length(1.0)
		return
	if e is InputEventMouseButton:
		mouse_pos = e.position
		if not is_kbm() or blocked: return
		if e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				if _over_hud(e.position): return      # HUD buttons keep working (emulated touch presses them)
				_left_down = true
				_left_origin = e.position
				_dragging = false
			elif _left_down:
				var was_drag := _dragging
				_end_drag()
				if not was_drag: pick_at(e.position)
		elif e.pressed and WHEEL_BUTTONS.has(e.button_index) and Data.WHEEL_THROTTLE:
			wheel_throttle = clampf(wheel_throttle + Data.WHEEL_STEP * WHEEL_BUTTONS[e.button_index], -1.0, 1.0)
		elif e.pressed:
			_discrete(e)
		return
	if e is InputEventKey and e.pressed and not e.echo:
		var f := get_viewport().gui_get_focus_owner() if get_viewport() else null
		if f is LineEdit: return   # typing in the comms box
		_discrete(e)

const WHEEL_BUTTONS := {MOUSE_BUTTON_WHEEL_UP: 1.0, MOUSE_BUTTON_WHEEL_DOWN: -1.0}

func _discrete(e: InputEvent) -> void:
	for id in action_ids():
		if id in HELD: continue
		if blocked and id != "settings": continue
		if InputMap.has_action(id) and e.is_action_pressed(id, false, true):
			if parse_binding(binding(id)) is InputEventMouseButton and not is_kbm(): continue
			if id == "mouse_flight":
				if not is_kbm(): continue
				toggle_mouse_flight()
			action.emit(id)
			get_viewport().set_input_as_handled()
			return
	# Throttle keys take over from the wheel setting
	if e is InputEventKey and (e.is_action_pressed("forward") or e.is_action_pressed("back")): wheel_throttle = 0.0

func _end_drag() -> void:
	_left_down = false
	_dragging = false
	drag_vec = Vector2.ZERO

## Left-click: select the nearest targetable thing drawn within MOUSE_PICK_PX of the cursor.
func pick_at(p: Vector2) -> Node3D:
	var sp = space_ref.call()
	if sp == null or not is_instance_valid(sp) or not is_instance_valid(sp.cam): return null
	var best: Node3D = null
	var bd: float = Data.MOUSE_PICK_PX
	for n in sp.targetables():
		if n == null or not is_instance_valid(n): continue
		if sp.cam.is_position_behind(n.global_position): continue
		var d: float = sp.cam.unproject_position(n.global_position).distance_to(p)
		if d < bd:
			bd = d
			best = n
	if best != null:
		sp.target = best
		sp.message.emit("Target: %s" % best.name)
	return best

# ---------------------------------------------------------------- rebinding ("Press a key…")
func begin_capture(id: String) -> bool:
	var d := action_def(id)
	if d.is_empty() or not d["rebind"]: return false
	capturing = id
	last_note = ""
	return true

func cancel_capture() -> void:
	var id := capturing
	capturing = ""
	last_note = "Cancelled."
	capture_done.emit(id, false, last_note)

func _capture_input(e: InputEvent) -> void:
	var b := ""
	if e is InputEventKey and e.pressed and not e.echo: b = binding_of(e)
	elif e is InputEventMouseButton and e.pressed and not WHEEL_BUTTONS.has(e.button_index) and e.button_index != MOUSE_BUTTON_LEFT: b = binding_of(e)   # left click stays free for the Settings buttons (Cancel etc.)
	else: return
	if get_viewport(): get_viewport().set_input_as_handled()
	if b == "": return   # a lone modifier: keep waiting for the real key
	finish_capture(b)

## Apply a captured key (also used by the tests). Escape cancels.
func finish_capture(b: String) -> String:
	if capturing == "": return "Not waiting for a key."
	if b == Data.KBM_CANCEL_KEY:
		cancel_capture()
		return last_note
	var id := capturing
	var note := rebind(id, b)
	if note == "":
		capturing = ""
		last_note = ""
		capture_done.emit(id, true, "")
	else:
		last_note = note   # duplicate / reserved: stay in "Press a key…" so the player can pick another
		capture_done.emit(id, false, note)
	return note
