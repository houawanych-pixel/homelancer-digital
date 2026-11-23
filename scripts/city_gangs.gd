class_name CityGangs
extends Node3D
## v13.287 (owner: "gangs and phone missions", GTA style). Every city has two street gangs, each holding some of its
## blocks as turf (the safehouse block is nobody's). Your standing with each gang is kept (GS.gang_rep). Walk or drive
## into the turf of a gang that has it in for you and its enforcers come for you in their gunships. The PHONE (in a
## city, on foot or in a car) rings with a job from one of them:
##   BOOST: take a car of a kind (car / bus / truck) and bring it to their drop point;
##   COURIER: get to a door on their turf in time;
##   HIT: take out a wing of the other gang's enforcers.
## A job done pays and raises your standing with the gang that gave it (a hit costs you with the other one).
## This node draws the drop points and job markers on the city tile; space.gd runs the jobs.

const NAMES := ["Neon Vipers", "Chrome Saints", "Void Jackals", "Ember Kings", "Static Wolves", "Glass Ravens"]
const COLORS := [Color(0.2, 1.0, 0.45), Color(0.85, 0.85, 1.0), Color(0.75, 0.3, 1.0), Color(1.0, 0.45, 0.1), Color(0.3, 0.7, 1.0), Color(1.0, 0.25, 0.55)]

var space: Node
var planet_id := ""
var tile := -1
var _marker: Node3D = null

func setup(sp: Node, pid: String, t: int) -> void:
	space = sp
	planet_id = pid
	tile = t
	name = "CityGangs"

## The city's two gangs: [{name, color, turf: [region]}] (turf may be empty for a one-block city's second gang).
static func gangs(pid: String, tile: int) -> Array:
	var cr := CityPlan.rect(pid, tile)
	if cr.size == Vector2i.ZERO: return []
	var h := absi(hash("%s|%d|gangs" % [pid, tile]))
	var a := h % NAMES.size()
	var b := (a + 1 + (h / 7) % (NAMES.size() - 1)) % NAMES.size()
	var out := [{"name": NAMES[a], "color": COLORS[a], "turf": []}, {"name": NAMES[b], "color": COLORS[b], "turf": []}]
	var safe: Vector2i = CityPlan.safehouse(pid, tile).get("region", Vector2i(-99, -99))
	var k := 0
	for rz in cr.size.y:
		for rx in cr.size.x:
			var r := cr.position + Vector2i(rx, rz)
			if r == safe and cr.size.x * cr.size.y > 1: continue
			(out[k % 2]["turf"] as Array).append(r)
			k += 1
	return out

## Whose turf a tile-local point is on ({} if nobody's).
static func turf_at(pid: String, tile: int, p: Vector2) -> Dictionary:
	var r := Vector2i(int(floor((p.x + Surface.EDGE) / Data.BLOCK_REGION)), int(floor((p.y + Surface.EDGE) / Data.BLOCK_REGION)))
	for g in gangs(pid, tile):
		if (g["turf"] as Array).has(r): return g
	return {}

## A spot on a gang's turf for a job (on the pavement round one of its lots), picked by n.
static func turf_spot(pid: String, tile: int, g: Dictionary, n: int) -> Vector2:
	var turf: Array = g["turf"]
	if turf.is_empty(): return CityPlan.safehouse(pid, tile).get("door", Vector2.ZERO)
	var r: Vector2i = turf[n % turf.size()]
	var lots: Array = CityPlan.block(pid, tile, r)["lots"]
	var lot: Rect2i = lots[(n / turf.size()) % lots.size()]
	var corner: Vector2 = [Vector2(lot.position.x + 1, lot.position.y + 1), Vector2(lot.end.x - 2, lot.position.y + 1), Vector2(lot.end.x - 2, lot.end.y - 2), Vector2(lot.position.x + 1, lot.end.y - 2)][(n / 3) % 4]
	return CityPlan.cell_pos(r, corner)

## Show the job's target (a ring and a tall beam in the gang's colour, with its words), or none.
func show_target(at: Vector2, col: Color, txt: String) -> void:
	clear_target()
	if at == Vector2.INF: return
	var g := CityPlan.ground(planet_id, tile)
	_marker = Node3D.new()
	_marker.name = "JobMarker"
	_marker.position = Vector3(at.x, g, at.y)
	add_child(_marker)
	var ring := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = Data.GANG_DROP_R
	cm.bottom_radius = Data.GANG_DROP_R
	cm.height = 0.3
	ring.mesh = cm
	ring.material_override = _glow(col, 1.5, 0.45)
	ring.position.y = 0.2
	_marker.add_child(ring)
	var beam := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 1.5
	bm.bottom_radius = 3.0
	bm.height = 300.0
	beam.mesh = bm
	beam.material_override = _glow(col, 1.3, 0.2)
	beam.position.y = 150.0
	_marker.add_child(beam)
	var l := Label3D.new()
	l.text = txt
	l.font_size = 80
	l.pixel_size = 0.04
	l.modulate = col
	l.outline_size = 16
	l.outline_modulate = Color(0, 0, 0, 0.8)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position.y = 18.0
	_marker.add_child(l)

func clear_target() -> void:
	if _marker != null and is_instance_valid(_marker): _marker.queue_free()
	_marker = null

func has_target() -> bool: return _marker != null and is_instance_valid(_marker)

func _glow(col: Color, e: float, alpha := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(col.r, col.g, col.b, alpha)
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = e
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m
