@tool
extends EditorExportPlugin
## After a game export, writes one .pck per content pack into "<export dir>/packs/".
## A pack holds its source folders' import remaps (*.import) and the imported files they point to, exactly as the
## main pck would, so ResourceLoader finds them once the game calls ProjectSettings.load_resource_pack().
## The main export leaves these folders out (export_presets.cfg exclude_filter), so they are not downloaded at start.

var _dir := ""

func _get_name() -> String:
	return "HomelancerContentPacks"

func _export_begin(_features: PackedStringArray, _is_debug: bool, path: String, _flags: int) -> void:
	_dir = path.get_base_dir()

func _export_end() -> void:
	if _dir == "": return
	var packs: Dictionary = load("res://scripts/packs.gd").PACKS
	DirAccess.make_dir_recursive_absolute(_dir.path_join("packs"))
	for name in packs:
		var out := _dir.path_join("packs/%s.pck" % name)
		var pk := PCKPacker.new()
		pk.pck_start(out)
		var n := 0
		for folder: String in packs[name]["folders"]:
			n += _add_folder(pk, folder, packs[name].get("match", ""))
		pk.flush()
		print("[packs] %s: %d files -> %s (%d bytes)" % [name, n, out, FileAccess.get_file_as_bytes(out).size()])

func _add_folder(pk: PCKPacker, folder: String, match: String) -> int:
	var n := 0
	var d := DirAccess.open(folder)
	if d == null: return 0
	for f in d.get_files():
		if not f.ends_with(".import"): continue
		if match != "" and not f.begins_with(match): continue
		var remap := folder.path_join(f)
		pk.add_file(remap, ProjectSettings.globalize_path(remap))
		n += 1
		var cf := ConfigFile.new()
		if cf.load(remap) != OK: continue
		for dest in cf.get_value("deps", "dest_files", []):
			pk.add_file(dest, ProjectSettings.globalize_path(dest))
			n += 1
	# plain resources in the folder (shaders etc.) that are not imported
	for f in d.get_files():
		if f.ends_with(".import") or (match != "" and not f.begins_with(match)): continue
		if FileAccess.file_exists(folder.path_join(f + ".import")): continue
		pk.add_file(folder.path_join(f), ProjectSettings.globalize_path(folder.path_join(f)))
		n += 1
	return n
