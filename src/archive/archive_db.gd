extends Node
## Loads in-game document texts from res://assets/data/archive/*.json
## (CLAUDE.md, section 4). Logic lives here; texts live only in JSON.
## Format: see assets/data/archive/README.md.

const ARCHIVE_DIR := "res://assets/data/archive"

var _documents: Dictionary = {}  # id -> Dictionary


func _ready() -> void:
	_load_all()


func get_document(id: String) -> Dictionary:
	return _documents.get(id, {})


func has_document(id: String) -> bool:
	return _documents.has(id)


func _load_all() -> void:
	var dir := DirAccess.open(ARCHIVE_DIR)
	if dir == null:
		push_warning("ArchiveDB: folder not found: %s" % ARCHIVE_DIR)
		return
	for file_name in dir.get_files():
		if file_name.get_extension() == "json":
			_load_file(ARCHIVE_DIR.path_join(file_name))


func _load_file(path: String) -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_ARRAY:
		push_error("ArchiveDB: %s must contain a JSON array" % path)
		return
	for entry in data:
		if typeof(entry) != TYPE_DICTIONARY or not entry.has("id"):
			push_error("ArchiveDB: entry without id in %s" % path)
			continue
		if entry.get("sources", []).is_empty():
			push_warning("ArchiveDB: %s has no sources [НЕ ПОДТВЕРЖДЕНО]" % entry.id)
		_documents[entry.id] = entry
