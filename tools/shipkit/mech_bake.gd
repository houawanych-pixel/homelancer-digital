extends SceneTree
## mech_bake.gd -- res://a.glb [res://b.glb ...]   (run with --path <repo>, after the GLBs are imported)
## v1.9i: cuts each rigged mech into its three parts ONCE, here, so the game never cuts at runtime: writes
## <same folder>/<name>.scn with the skinned mesh replaced by Part_arms / Part_core / Part_legs (same skin, same
## skeleton). The game loads the .scn; a mech wearing another's arms just swaps those nodes.
const MP = preload("res://scripts/mech_parts.gd")

func _initialize() -> void:
	for path in OS.get_cmdline_user_args():
		var t0 := Time.get_ticks_msec()
		var scene: PackedScene = load(path)
		if scene == null:
			print("BAKE cannot load ", path)
			continue
		var root: Node = scene.instantiate()
		var skel := MP.find_skeleton(root)
		var tris := {"arms": 0, "core": 0, "legs": 0}
		for mi: MeshInstance3D in MP.skinned_meshes(root):
			var parts: Dictionary = MP.split(mi, skel)
			var parent: Node = mi.get_parent()
			for p in MP.PARTS:
				if parts[p] == null: continue
				var n := MeshInstance3D.new()
				n.name = "Part_" + p
				n.mesh = parts[p]
				n.skin = mi.skin
				n.transform = mi.transform
				parent.add_child(n)
				n.skeleton = n.get_path_to(skel)
				for s in (parts[p] as ArrayMesh).get_surface_count():
					tris[p] += (parts[p] as ArrayMesh).surface_get_array_index_len(s) / 3
			parent.remove_child(mi)
			mi.free()
		_own(root, root)
		var ps := PackedScene.new()
		ps.pack(root)
		var out := path.get_basename() + ".scn"
		var err := ResourceSaver.save(ps, out, ResourceSaver.FLAG_COMPRESS)
		print("BAKE ", out, " err ", err, " tris ", tris, " ", Time.get_ticks_msec() - t0, " ms")
		root.free()
	quit()

func _own(n: Node, root: Node) -> void:
	for c in n.get_children():
		c.owner = root
		_own(c, root)
