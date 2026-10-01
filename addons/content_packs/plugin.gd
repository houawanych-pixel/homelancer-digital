@tool
extends EditorPlugin
## Registers the export step that writes the optional content packs (see scripts/packs.gd).

var _exp: EditorExportPlugin

func _enter_tree() -> void:
	_exp = preload("res://addons/content_packs/export_packs.gd").new()
	add_export_plugin(_exp)

func _exit_tree() -> void:
	remove_export_plugin(_exp)
