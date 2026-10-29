extends Node
## tools/handoff: dock, then visit every hub page and save a picture of each with the room it shows.
## env HL_TOOL=res://tools/handoff/room_tour.gd  HL_TOUR_FACTION=liberator  HL_TOUR_OUT=/abs/dir
func _ready() -> void:
	var main: Node = get_tree().root.find_child("Main", true, false)
	if main == null: main = get_tree().current_scene
	main.start_game()
	while main.state != "flight": await get_tree().process_frame
	for i in 30: await get_tree().process_frame
	main.dock(main.space.station)
	while main.state != "hub": await get_tree().process_frame
	var hb = main.hub
	hb.room_override = OS.get_environment("HL_TOUR_FACTION")
	var out := OS.get_environment("HL_TOUR_OUT")
	DirAccess.make_dir_recursive_absolute(out)
	var pages := []
	for c in hb.nav_cats():
		for pg in c[2]: pages.append(pg[0])
	for t in ["weapon", "ammo"]: pages.append("equipment:" + t)
	for pg in pages:
		var p: String = pg
		if p == "map": continue
		if p.begins_with("equipment:"):
			hb.eq_tab = p.get_slice(":", 1)
			p = "equipment"
		hb.show_screen(p)
		hb.close_call("l"); hb.close_call("r")
		for i in 20: await get_tree().process_frame
		print("[tour] ", pg, " -> room ", hb.room_key, " visible ", hb.room_view.visible)
		get_viewport().get_texture().get_image().save_jpg("%s/%s.jpg" % [out, pg.replace(":", "_")], 0.8)
	get_tree().quit()
