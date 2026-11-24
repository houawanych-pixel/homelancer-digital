class_name Gestures
extends RefCounted
## v13.288 (owner: "universal on every map and viewer: one finger rotates, two fingers move, pinch to zoom"): one
## touch / mouse gesture reader shared by every map and model viewer. Feed it the events a Control gets; it reports
##   rotate (Vector2 px dragged with one finger, or the left mouse button),
##   pan (Vector2 px the middle of two fingers moved, or the right / middle mouse button),
##   zoom (a factor: the two fingers' spread now / before, or the mouse wheel),
## and whether the touch that ended was a tap (no drag), so a viewer can still pick things.

var rotate := Vector2.ZERO
var pan := Vector2.ZERO
var zoom := 1.0
var tap := false
var tap_at := Vector2.ZERO
var _touch := {}        # index -> position
var _moved := false
var _spread := 0.0

## Read one event. Returns true if it moved the view (rotate / pan / zoom are set until the next call).
func feed(e: InputEvent) -> bool:
	rotate = Vector2.ZERO
	pan = Vector2.ZERO
	zoom = 1.0
	tap = false
	if e is InputEventScreenTouch:
		var st := e as InputEventScreenTouch
		if st.pressed:
			_touch[st.index] = st.position
			if _touch.size() == 1: _moved = false
			_spread = _spread_now()
		else:
			_touch.erase(st.index)
			if _touch.is_empty() and not _moved:
				tap = true
				tap_at = st.position
			_spread = _spread_now()
		return false
	if e is InputEventScreenDrag:
		var sd := e as InputEventScreenDrag
		var before := _mid()
		_touch[sd.index] = sd.position
		if _touch.size() >= 2:
			var s2 := _spread_now()
			if _spread > 1.0 and s2 > 1.0: zoom = s2 / _spread
			_spread = s2
			pan = _mid() - before
		else:
			rotate = sd.relative
		if rotate.length() + pan.length() > 0.5 or absf(zoom - 1.0) > 0.002: _moved = true
		return _moved
	if e is InputEventMagnifyGesture:   # (a trackpad pinch)
		zoom = (e as InputEventMagnifyGesture).factor
		return true
	if e is InputEventPanGesture:
		pan = -(e as InputEventPanGesture).delta * 8.0
		return true
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = 1.1
			return true
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = 1.0 / 1.1
			return true
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed: _moved = false
			elif not _moved:
				tap = true
				tap_at = mb.position
		return false
	if e is InputEventMouseMotion:
		var mm := e as InputEventMouseMotion
		if mm.button_mask & (MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE): pan = mm.relative
		elif mm.button_mask & MOUSE_BUTTON_MASK_LEFT: rotate = mm.relative
		if rotate.length() + pan.length() > 0.5: _moved = true
		return rotate != Vector2.ZERO or pan != Vector2.ZERO
	return false

func fingers() -> int: return _touch.size()

func _mid() -> Vector2:
	if _touch.is_empty(): return Vector2.ZERO
	var s := Vector2.ZERO
	for k in _touch: s += _touch[k]
	return s / _touch.size()

func _spread_now() -> float:
	if _touch.size() < 2: return 0.0
	var ks := _touch.keys()
	return (_touch[ks[0]] as Vector2).distance_to(_touch[ks[1]])
