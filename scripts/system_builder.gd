class_name SystemBuilder
extends RefCounted
## Builds every star system the game does not have by hand from the galaxy map tables (GalaxyData, generated from
## docs/galaxy). One generator, no copy-paste: each system gets a star, one station, one planet, an asteroid field, a
## nebula, patrols, and one gate per link on the map. Hand-made systems (Data.CORE_SYSTEMS) are kept as they are and
## only receive the extra gates the map gives them. Pure data: nothing here loads art.

# faction: star colour, sky tint, ambient light, station colour, enemy type
const FACTIONS := {
	"Unity": [Color(0.95, 0.97, 1.0), Color(0.04, 0.08, 0.14), Color(0.42, 0.47, 0.58), Color(0.78, 0.9, 0.96), "raider"],
	"Elyza": [Color(0.75, 0.85, 1.0), Color(0.03, 0.06, 0.16), Color(0.38, 0.44, 0.6), Color(0.45, 0.6, 0.95), "raider"],
	"Solarion": [Color(1.0, 0.82, 0.5), Color(0.12, 0.08, 0.04), Color(0.52, 0.46, 0.38), Color(0.95, 0.72, 0.3), "raider"],
	"Imperium": [Color(1.0, 0.6, 0.5), Color(0.13, 0.04, 0.05), Color(0.5, 0.38, 0.38), Color(0.75, 0.25, 0.28), "corsair"],
	"Covenant": [Color(0.85, 0.7, 1.0), Color(0.09, 0.04, 0.14), Color(0.46, 0.4, 0.56), Color(0.6, 0.4, 0.85), "corsair"],
	"Orion": [Color(0.7, 1.0, 0.75), Color(0.03, 0.11, 0.07), Color(0.38, 0.5, 0.42), Color(0.25, 0.7, 0.45), "corsair"],
	"Savagers": [Color(1.0, 0.7, 0.45), Color(0.13, 0.07, 0.03), Color(0.5, 0.42, 0.36), Color(0.78, 0.42, 0.2), "raider"],
	"Liberator": [Color(0.7, 1.0, 0.95), Color(0.03, 0.11, 0.11), Color(0.38, 0.5, 0.5), Color(0.3, 0.75, 0.72), "raider"],
	"Enemy": [Color(1.0, 0.45, 0.4), Color(0.06, 0.03, 0.05), Color(0.34, 0.32, 0.38), Color(0.3, 0.3, 0.34), "corsair"],
	"Neutral": [Color(1.0, 0.9, 0.75), Color(0.08, 0.07, 0.07), Color(0.44, 0.43, 0.44), Color(0.72, 0.66, 0.54), "raider"],
	"Hidden": [Color(0.9, 0.8, 1.0), Color(0.05, 0.03, 0.09), Color(0.4, 0.38, 0.5), Color(0.4, 0.35, 0.55), "corsair"],
	"Void": [Color(0.75, 0.8, 0.95), Color(0.02, 0.02, 0.04), Color(0.26, 0.28, 0.36), Color(0.35, 0.38, 0.45), "raider"],
	"Heart": [Color(1.0, 0.95, 0.75), Color(0.1, 0.06, 0.12), Color(0.5, 0.46, 0.52), Color(0.95, 0.88, 0.6), "raider"],
}
# gate kind: name on the gate, portal colour, distance from the system centre
const GATE_KINDS := {
	"jump": ["Jump Gate", Color(0.35, 0.95, 0.5), 3400.0],
	"warp": ["Warp Gate", Color(0.35, 0.65, 1.0), 4200.0],
	"rift": ["Rift Gate", Color(0.8, 0.4, 1.0), 4900.0],
}
const CENTRE := Vector3(0, 0, -1200)

static func all(core: Dictionary) -> Dictionary:
	var out: Dictionary = core.duplicate(true)
	var rows := {}
	for t in GalaxyData.TILES:
		rows[t[0]] = t
		if not out.has(t[0]): out[t[0]] = _system(t)
		out[t[0]]["tile"] = t[2]
		out[t[0]]["faction"] = t[5]
	for id in out:
		if not out[id].has("gates"): out[id]["gates"] = [out[id]["gate"]] if out[id].has("gate") else []
		for g in out[id]["gates"]:
			if not g.has("gkind"): g["gkind"] = "jump"
	for g in GalaxyData.GATES:
		_link(out, rows, g[0], g[1], g[2])
		_link(out, rows, g[0], g[2], g[1])
	for id in out:
		if not out[id].has("gate"): out[id]["gate"] = out[id]["gates"][0]
	return out

static func _system(t: Array) -> Dictionary:
	var id: String = t[0]
	var nm: String = t[1]
	var f: Array = FACTIONS[t[5]]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("homelancer:" + id)
	var void_sys: bool = t[5] == "Void"
	var a := rng.randf() * TAU
	var pr := 520.0 if void_sys else rng.randf_range(700.0, 980.0)
	var st_pos := Vector3(rng.randf_range(-500, 500), rng.randf_range(-60, 60), rng.randf_range(-700, -100))
	var pl_pos := CENTRE + Vector3(cos(a) * 1900.0, rng.randf_range(-320, 320), sin(a) * 1900.0)
	var a2 := a + rng.randf_range(1.6, 2.6)
	var a3 := a2 + rng.randf_range(1.4, 2.2)
	var sa := rng.randf() * TAU
	var station := {"id": id + "_station", "name": t[9], "pos": st_pos, "kind": "station", "color": f[3],
		"desc": "Automated beacon. No one lives out here." if void_sys else "%s station in the %s system." % [t[5], nm]}
	if t[6] == "capital": station["model"] = "wheel_station"
	var patrols: Array = []
	for i in 3:
		var pa := rng.randf() * TAU
		patrols.append(CENTRE + Vector3(cos(pa), 0, sin(pa)) * rng.randf_range(700.0, 2300.0) + Vector3(0, rng.randf_range(-80, 120), 0))
	return {
		"name": nm, "star": Color(0.8, 0.85, 1.0) if void_sys else f[0], "sky_tint": f[1], "ambient": f[2],
		"sun_dir": Vector3(cos(sa), -0.32, sin(sa)), "small_sun": void_sys, "role": t[6], "generated": true,
		"station": station,
		"planet": {"id": id + "_planet", "name": t[7], "pos": pl_pos, "radius": pr, "kind": "planet", "palette": t[8],
			"desc": "A dead, frozen world. Too cold to live on." if void_sys else "%s world of the %s system." % [(t[8] as String).capitalize(), nm]},
		"asteroids": {"name": "%s Belt" % nm, "center": CENTRE + Vector3(cos(a2) * 1300.0, 0, sin(a2) * 1300.0), "radius": 380.0,
			"count": 70 if void_sys else 130, "ice": t[8] in ["ice", "dead", "gas"]},
		"nebula": {"name": "%s Veil" % nm, "center": CENTRE + Vector3(cos(a3) * 1700.0, 40, sin(a3) * 1700.0), "radius": 460.0,
			"color": (f[0] as Color).lerp(f[3], 0.6)},
		"enemy": f[4], "patrols": patrols, "traffic": [[id + "_station", id + "_planet"]],
	}

## One gate in system `a` leading to `b`, set in the direction `b` lies on the map (north on the map = -Z in flight).
static func _link(out: Dictionary, rows: Dictionary, kind: String, a: String, b: String) -> void:
	for g in out[a]["gates"]:
		if g["to"] == b: return
	var ta: Array = rows[a]
	var tb: Array = rows[b]
	var dir := Vector3(float(tb[3] - ta[3]), 0, float(tb[4] - ta[4])).normalized()
	var k: Array = GATE_KINDS[kind]
	var n: int = out[a]["gates"].size()
	out[a]["gates"].append({"id": "%s_gate_%s" % [a, b], "name": "%s %s" % [tb[1], k[0]], "pos": CENTRE + dir * float(k[2]) + Vector3(0, 70.0 * n, 0),
		"to": b, "gkind": kind})

## Sun surfaces for every system (one looping tile each), merged into Surface.PLANETS.
static func suns(have: Dictionary) -> Dictionary:
	var out := {}
	for t in GalaxyData.TILES:
		var pid: String = t[0] + "_sun"
		if not have.has(pid): out[pid] = {"name": "%s's Star" % t[1], "system": t[0], "grid": 1, "tiles": ["sun"], "locations": [], "sun": true}
	return out
