class_name PilotScene
extends Control
## v12.91 (owner: "use the whole scene of the anime ... animate ... the bottom pictures"): the Pilot Gear Store and the
## PILOT CREATOR show an anime scene of your pilot instead of the 3D model when its pictures are in. The game's menus stay
## on top; the art has none. Files, per pilot build (male = Hovick's, female = Judy's), in ROOT/<male|female>/:
##   A.(jpg|png|webp)        full body, flight suit (no jacket)       B.*  waist-up, same scene
##   C_<jacket id>.*         waist-up wearing that jacket            D_<jacket id>.*  full body wearing it
##   zoom_in.ogv (A -> B) · zoom_out.ogv (B -> A)
##   alive_<hair|cold|stretch|bored|check>.ogv              little moments on A (no jacket; "cold" only without one)
##   alive_<name>_<jacket id>.ogv                            the same moments on D (wearing that jacket)
##   tryon_<jacket id>.ogv (B -> C)                          putting the jacket on, played when you EQUIP it
## Godot plays Theora video only: tools/pilot_scene/import_clips.py turns the MP4s into .ogv and checks their first and
## last frames against the pictures. A missing clip is skipped (a straight cut to the picture); without A the store
## keeps the 3D model. Credits, ownership and what you wear stay in the game state: this only shows them.

static var root_dir := "res://assets/pilot_scene"   # (tests point it at a sample set)
const ALIVE := ["hair", "cold", "stretch", "bored", "check"]
const NO_JACKET := "up_flight"
const IDLE_GAP := [6.0, 10.0]   # s of the still between two alive moments

var sex := "male"
var focus := "full"     # "full" / "waist"
var jacket := NO_JACKET # the jacket worn (or previewed)
var still: TextureRect
var video: VideoStreamPlayer
var playing := ""       # the clip on now ("" = the still)
var _after := ""        # what to do when the clip ends: "" or a focus to settle on
var _idle_t := 0.0
var _rng := RandomNumberGenerator.new()
var played: Array = []  # (tests) clips started, by name

static func dir_for(body: String) -> String:
	var sx := str(Loadout.PILOT_BODIES.get(body, {}).get("sex", "male"))
	return "%s/%s" % [root_dir, sx]

## a picture by name (any of the usual image types), or "" if it isn't in
static func pic(body: String, nm: String) -> String:
	for ext in ["jpg", "png", "webp", "jpeg"]:
		var p := "%s/%s.%s" % [dir_for(body), nm, ext]
		if ResourceLoader.exists(p): return p
	return ""

static func clip(body: String, nm: String) -> String:
	var p := "%s/%s.ogv" % [dir_for(body), nm]
	return p if ResourceLoader.exists(p) or FileAccess.file_exists(p) else ""

## Is there a scene for this pilot (at least the full-body picture A)?
static func available(body: String) -> bool:
	return pic(body, "A") != ""

var body := "hovick"
func setup(b: String, worn: String, f: String) -> void:
	body = b
	sex = str(Loadout.PILOT_BODIES.get(b, {}).get("sex", "male"))
	jacket = worn if worn != "" else NO_JACKET
	focus = f
	name = "PilotScene"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rng.randomize()
	still = TextureRect.new()
	still.name = "SceneStill"
	still.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	still.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	still.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	still.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(still)
	video = VideoStreamPlayer.new()
	video.name = "SceneClip"
	video.expand = true
	video.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	video.mouse_filter = Control.MOUSE_FILTER_IGNORE
	video.visible = false
	video.finished.connect(_clip_done)
	add_child(video)
	_show_still()
	_idle_t = _rng.randf_range(IDLE_GAP[0], IDLE_GAP[1])

## the picture for the current framing and jacket (C / D for a jacket when they're in, else B / A)
func still_name() -> String:
	if jacket != NO_JACKET:   # (waist-up: C, else its full body D; full: D)
		for j in (["C_" + jacket, "D_" + jacket] if focus == "waist" else ["D_" + jacket]):
			if pic(body, j) != "": return j
	return "B" if focus == "waist" and pic(body, "B") != "" else "A"

func _show_still() -> void:
	var p := pic(body, still_name())
	if p != "": still.texture = load(p)

func _play(nm: String, after: String) -> bool:
	var p := clip(body, nm)
	if p == "": return false
	var st = load(p)
	if st == null: return false
	video.stream = st
	video.visible = true
	video.play()
	playing = nm
	_after = after
	played.append(nm)
	return true

func _clip_done() -> void:
	playing = ""
	if _after != "": focus = _after
	_after = ""
	_show_still()
	video.visible = false
	_idle_t = _rng.randf_range(IDLE_GAP[0], IDLE_GAP[1])

## A category was picked: the torso parts frame the waist (zoom in), the rest the whole pilot (zoom out).
func go(f: String) -> void:
	if f == focus and playing == "": return
	if playing != "":
		video.stop()
		playing = ""
	var clip_name := "zoom_in" if f == "waist" else "zoom_out"
	if jacket != NO_JACKET: clip_name += "_" + jacket   # (in a jacket: its own zoom; none made: a straight cut)
	if not _play(clip_name, f):
		focus = f
		_show_still()

## What's on (or previewed): the picture follows; nothing plays (a preview is a still swap).
func show_outfit(j: String) -> void:
	j = j if j != "" else NO_JACKET
	if j == jacket: return
	jacket = j
	if playing != "":
		video.stop()
		playing = ""
		video.visible = false
	_show_still()

## EQUIP: the try-on clip (B -> C) when it's in; it ends on the waist-up picture in that jacket.
func equipped(j: String) -> void:
	var was := jacket
	jacket = j if j != "" else NO_JACKET
	if jacket != NO_JACKET and _play("tryon_" + jacket, "waist"):
		var p := pic(body, "B")   # (it starts without the jacket)
		if p != "" and was == NO_JACKET: still.texture = load(p)
		return
	_show_still()

## the alive moments while it stands at full body: one every few seconds, those that fit what it wears
func _process(dt: float) -> void:
	if playing != "" or focus != "full" or not is_visible_in_tree(): return
	_idle_t -= dt
	if _idle_t > 0.0: return
	_idle_t = _rng.randf_range(IDLE_GAP[0], IDLE_GAP[1])
	var opts: Array = []
	for a in ALIVE:
		if a == "cold" and jacket != NO_JACKET: continue
		var nm := ("alive_%s" % a) if jacket == NO_JACKET else ("alive_%s_%s" % [a, jacket])
		if clip(body, nm) != "": opts.append(nm)
	if not opts.is_empty(): _play(opts[_rng.randi() % opts.size()], "")
