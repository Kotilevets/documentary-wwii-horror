extends SceneTree
## Writes the engine's own license and third-party copyright notices, as the
## running Godot binary reports them, to the file given after `--`.
## tools/make_playtest_build.py runs it to put the Godot license next to the
## game exe (the exe is the official Godot binary, renamed).


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		printerr("usage: godot --headless --script tools/godot_license.gd -- <out file>")
		quit(2)
		return
	var path: String = args[0]
	var lines: PackedStringArray = []
	lines.append("Godot Engine " + Engine.get_version_info().string)
	lines.append("")
	lines.append(Engine.get_license_text().strip_edges())
	lines.append("")
	lines.append("")
	lines.append("Third-party components (Engine.get_copyright_info())")
	lines.append("====================================================")
	for comp: Dictionary in Engine.get_copyright_info():
		lines.append("")
		lines.append(str(comp["name"]))
		for part: Dictionary in comp["parts"]:
			var files: PackedStringArray = part["files"]
			if not files.is_empty():
				lines.append("  Files: " + ", ".join(files))
			for c: String in part["copyright"]:
				lines.append("  Copyright: " + c)
			lines.append("  License: " + str(part["license"]))
	lines.append("")
	lines.append("")
	lines.append("License texts (Engine.get_license_info())")
	lines.append("=========================================")
	var info: Dictionary = Engine.get_license_info()
	var names := info.keys()
	names.sort()
	for n: String in names:
		lines.append("")
		lines.append("License: " + n)
		lines.append("")
		lines.append(str(info[n]).strip_edges())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		printerr("cannot write ", path, ": ", error_string(FileAccess.get_open_error()))
		quit(1)
		return
	f.store_string("\n".join(lines) + "\n")
	f.close()
	print("license lines: ", lines.size())
	quit(0)
